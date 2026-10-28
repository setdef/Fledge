# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-FileComment: Adapted from tasks/license_audit.rb on Fledge's
#   spike/permissive branch (58edf27d27912d062ccfa5c4960533a220c9eb24).
require "digest"
require "find"
require "rubygems"
require "rubygems/package"
require "stringio"
require "yaml"
require "zlib"
require_relative "../lib/fledge/license_policy"

# Accounts for everything in a runtime tree and checks it against
# Fledge's license policy (Fledge::LicensePolicy) and the map of what
# ships (runtime/licenses.yml).
#
# A Fledge runtime is copied whole into every app built with it, so
# whatever it carries, the app's developer distributes. The audit derives
# the inventory from the tree itself rather than from what the build
# meant to put there: it walks every file, reads every compiled file's
# links (LicenseAudit::Binary), reads every gem's license from the
# specification the tree holds, and matches the rest against the
# checked-in map. Components that cannot be seen in a file's links, such
# as OpenSSL compiled into openssl.so or Rust's standard library in YJIT,
# come from the map, which names a string that proves each is still
# there at the version it names, so the map cannot quietly go stale.
#
# Then it writes what the runtime ships with: an SPDX 2.3 SBOM
# (LicenseAudit::Spdx) and a NOTICES file (LicenseAudit::Notices), and,
# for the LGPL libraries, a source bundle (LicenseAudit::SourceBundle).
#
# Run it as
#   ruby tasks/license_audit.rb --platform x86_64-linux --tree DIR
# against an unpacked runtime, or rv-ruby's or RubyInstaller's whole
# tree. It exits 1 when the tree breaks the policy.
class LicenseAudit
  ROOT = File.expand_path("..", __dir__)
  MAP = File.join(ROOT, "runtime", "licenses.yml")
  SOURCES = File.join(ROOT, "runtime", "sources.yml")

  # Words that name a copyleft license in a text file.
  COPYLEFT_WORDS = /GNU (?:Lesser |Library |Affero )?General Public License|\b(?:[AL]?GPL)(?:-?v?[123](?:\.[01])?)?\b|Eclipse Public License|Mozilla Public License|European Union Public Licen[cs]e|Common Development and Distribution License/

  COPYLEFT_BYTES = Regexp.new(COPYLEFT_WORDS.source.b, Regexp::NOENCODING)

  # The largest file whose words the audit reads.
  TEXT_LIMIT = 4_000_000

  attr_reader :platform, :tree, :map

  def initialize(platform:, tree:, map: MAP, sources: SOURCES, fledge_version: nil)
    @platform = platform
    @tree = File.expand_path(tree)
    @map = YAML.safe_load_file(map)
    @sources = YAML.safe_load_file(sources)
    @fledge_version = fledge_version || fledge_version_from_source
    @facts = @map.fetch("platforms").fetch(platform) { raise ArgumentError, "no platform #{platform} in #{map}" }
    @violations = []
  end

  # Audits the tree and returns the Report.
  def call
    files = walk
    inventory = Inventory.new(self)
    components = inventory.map_components
    gems = inventory.gem_components
    ordered = components.reject(&:fallback) + gems + components.select(&:fallback)
    owners = assign(files, ordered)
    binaries = read_binaries(files)
    links = check_links(binaries, files)
    embeds = check_embedded(components, files)
    check_binary_ownership(binaries, owners)
    check_signatures(binaries, owners, embeds)
    check_pins(components, files)
    texts = CopyleftText.new(self, method(:violate))
    texts.check_files(files, owners, binaries)
    texts.check_gem_archives(files, owners)
    report = Report.new(platform:, tree:, components: ordered, owners:, binaries:, links:, embeds:, violations: @violations)
    policy = Policy.new(@sources, method(:violate))
    report.present.each { |component| policy.check(component, report) }
    report
  end

  # Everything that keeps the audited tree from shipping, as lines: each
  # of +report+'s violations, and each component whose license text
  # +notices+ cannot find, which NOTICES.txt could not carry.
  def self.problems(report, notices)
    report.violations.map(&:to_s) + notices.missing.map { |id| "missing-notice: #{id} has no license text in runtime/notices/ or its gem" }
  end

  # The license policy's verdict on an SPDX license expression
  # (Fledge::LicensePolicy): one of :notice_only, :first_party,
  # :file_level, :shared_library, or :forbidden.
  def self.category(expression, first_party: false)
    Fledge::LicensePolicy.category(expression, first_party:)
  end

  # Where Ruby's own tree starts: ruby/ in a Windows runtime.
  def prefix
    @prefix ||= File.directory?(File.join(tree, "ruby", "lib", "ruby")) ? "ruby/" : ""
  end

  def expand(pattern)
    tokens = {
      "prefix" => prefix,
      "arch" => @facts.fetch("arch"),
      "gem_arch" => @facts.fetch("gem_arch"),
      "so" => @facts.fetch("so"),
      "fledge_version" => @fledge_version,
    }
    expanded = pattern.gsub(/\{(prefix|arch|gem_arch|so|fledge_version)\}/) { tokens.fetch(Regexp.last_match(1)) }
    expanded.end_with?("/**") ? "#{expanded}/*" : expanded
  end

  def matches?(pattern, path)
    File.fnmatch(expand(pattern), path, File::FNM_PATHNAME | File::FNM_EXTGLOB | File::FNM_DOTMATCH)
  end

  private def fledge_version_from_source
    File.read(File.join(ROOT, "lib", "fledge", "version.rb"))[/VERSION = "([^"]+)"/, 1].to_s
  end

  # Every file and symlink in the tree, relative to it, except the
  # notices this audit writes.
  private def walk
    paths = []
    Find.find(tree) do |path|
      relative = path.delete_prefix("#{tree}/")
      next if path == tree

      Find.prune if relative == "notices"
      paths << relative if File.file?(path) || File.symlink?(path)
    end
    paths.sort
  end

  # Gives each file to the first component whose files match it, and
  # records a violation for each file no component owns.
  private def assign(files, components)
    owners = {}
    files.each do |path|
      owner = components.find { |component| owns?(component, path) }
      if owner
        owners[path] = owner
      else
        violate("unaccounted", path, "belongs to no component in runtime/licenses.yml and to no gem")
      end
    end
    owners
  end

  private def owns?(component, path)
    component.files.any? do |pattern|
      next matches?(pattern, path) unless pattern.is_a?(Hash)

      matches?(pattern.fetch("glob"), path) && File.read(File.join(tree, path)).include?(pattern.fetch("contains"))
    end
  end

  private def read_binaries(files)
    files.each_with_object({}) do |path, binaries|
      binary = Binary.read(File.join(tree, path))
      binaries[path] = binary if binary
    end
  end

  # Checks that every shared library a compiled file needs is either the
  # operating system's or a file in the tree, and returns, for each
  # compiled file, what it needs and where each comes from.
  private def check_links(binaries, files)
    system = @map.fetch("system_libraries").fetch(@facts.fetch("os")).map { |source| regexp(source) }
    by_name = files.group_by { |path| fold(File.basename(path)) }
    binaries.to_h do |path, binary|
      resolved = binary.needed.to_h do |library|
        next [library, :system] if system.any? { |pattern| pattern.match?(library) }

        local = by_name[fold(File.basename(library.sub(%r{\A@(?:rpath|loader_path|executable_path)/}, "")))]
        violate("unresolved", path, "needs #{library}, which neither the operating system nor the runtime provides") unless local
        [library, local&.first]
      end
      check_assemblies(path, binary, files)
      [path, resolved]
    end
  end

  private def check_assemblies(path, binary, files)
    binary.assemblies.each do |assembly|
      directory = File.dirname(path)
      manifest = ["#{directory}/#{assembly}/#{assembly}.manifest", "#{directory}/#{assembly}.manifest"].map { |candidate| candidate.delete_prefix("./") }
      violate("unresolved", path, "names the side-by-side assembly #{assembly}, whose manifest is not in the runtime") if (manifest & files).empty?
    end
  end

  private def fold(name)
    (@facts.fetch("os") == "windows") ? name.downcase : name
  end

  private def regexp(source)
    body, flags = source.match(%r{\A/(.*)/([a-z]*)\z}m).captures
    Regexp.new(body, flags.include?("i") ? Regexp::IGNORECASE : 0)
  end

  # Checks that every component the map says is compiled into a file is
  # still there, by its evidence string, and returns, for each file, the
  # components compiled into it. A file the tree lacks is skipped: a
  # runtime leaves things out that a whole tree holds.
  private def check_embedded(components, files)
    embeds = Hash.new { |hash, key| hash[key] = [] }
    components.each do |component|
      component.embedded.each do |entry|
        files.select { |path| entry.fetch("files").any? { |pattern| matches?(pattern, path) } }.each do |path|
          evidence = entry["evidence"]
          if evidence && !File.binread(File.join(tree, path)).include?(evidence.b)
            violate("stale", path, "should hold #{component.name} #{component.version}, but #{evidence.inspect} is not in it")
          else
            embeds[path] << component.id
          end
        end
      end
    end
    embeds
  end

  # A compiled file must be one its owner names as a binary, so that a
  # library nobody reviewed cannot ride in under a broad pattern.
  private def check_binary_ownership(binaries, owners)
    binaries.each_key do |path|
      owner = owners[path] or next
      next if owner.binaries.any? { |pattern| matches?(pattern, path) }

      violate("unlisted-binary", path, "is compiled code (#{binaries[path].format}) that #{owner.id} does not list among its binaries")
    end
  end

  # A copyleft library's code may appear only in its own shared library,
  # or in a file the map says it is linked into (its embedded files),
  # which the policy then judges (LicenseAudit::Policy).
  private def check_signatures(binaries, owners, embeds)
    @map.fetch("signatures").each do |signature|
      binaries.each_key do |path|
        bytes = File.binread(File.join(tree, path))
        next unless signature.fetch("bytes").any? { |needle| bytes.include?(needle.b) }

        owner = owners[path]
        next if owner&.id == signature.fetch("component") && owner&.kind == "shared_library"
        next if embeds.fetch(path, []).include?(signature.fetch("component"))

        violate("static-copyleft", path, "holds #{signature.fetch('component')}'s code, which may ship only as its own shared library")
      end
    end
  end

  private def check_pins(components, files)
    components.each do |component|
      component.sha256.each do |pattern, sha256|
        files.select { |path| matches?(pattern, path) }.each do |path|
          actual = Digest::SHA256.file(File.join(tree, path)).hexdigest
          violate("stale", path, "has SHA-256 #{actual}, not the #{sha256} its source pin describes") unless actual == sha256
        end
      end
    end
  end

  private def violate(rule, path, message)
    @violations << Violation.new(rule:, path:, message:)
    nil
  end
end

require_relative "license_audit/binary"
require_relative "license_audit/component"
require_relative "license_audit/copyleft_text"
require_relative "license_audit/failure"
require_relative "license_audit/inventory"
require_relative "license_audit/policy"
require_relative "license_audit/report"
require_relative "license_audit/violation"
require_relative "license_audit/spdx"
require_relative "license_audit/notices"
require_relative "license_audit/source_bundle"
require_relative "license_audit/cli"

exit LicenseAudit::CLI.new(ARGV).call if $PROGRAM_NAME == __FILE__
