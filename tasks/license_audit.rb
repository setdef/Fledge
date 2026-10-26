# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "digest"
require "find"
require "json"
require "optparse"
require "rubygems"
require "yaml"

# Accounts for everything in a runtime tree and checks it against
# Fledge's license policy (runtime/licenses.yml).
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

  # One way the tree breaks the policy.
  class Violation < Data.define(:rule, :path, :message)
    def to_s
      "#{rule}: #{path.empty? ? '' : "#{path}: "}#{message}"
    end
  end

  # Something the tree ships: a component from the map, or a gem.
  class Component < Data.define(:id, :name, :version, :license, :kind, :first_party, :download, :notice, :source, :ships,
    :supplier, :files, :binaries, :embedded, :sha256, :fallback, :gem_dir)
    def self.from_map(entry, expand)
      patterns = -> (key) { Array(entry[key]).map { |pattern| pattern.is_a?(Hash) ? pattern.transform_keys(&:to_s) : pattern } }
      new(id: entry.fetch("id"), name: entry.fetch("name"), version: expand.call(entry.fetch("version").to_s),
        license: entry.fetch("license"), kind: entry.fetch("kind"), first_party: entry.fetch("first_party", false),
        download: entry.fetch("download"), notice: entry["notice"], source: entry["source"], ships: expand.call(entry.fetch("ships")),
        supplier: entry["supplier"], files: patterns.call("files"), binaries: patterns.call("binaries"),
        embedded: Array(entry["embedded"]), sha256: entry.fetch("sha256", {}), fallback: entry.fetch("fallback", false), gem_dir: nil)
    end
  end

  # What the audit found: the components present, which file each
  # component owns, what each compiled file links and has compiled in,
  # and every violation.
  class Report < Data.define(:platform, :tree, :components, :owners, :binaries, :links, :embeds, :violations)
    def owned(component)
      owners.select { |_path, owner| owner.equal?(component) }.keys.sort
    end

    def embedded_in(component)
      embeds.select { |_path, ids| ids.include?(component.id) }.keys.sort
    end

    def present
      components.select { |component| !owned(component).empty? || !embedded_in(component).empty? }
    end
  end

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
    components = map_components
    gems = gem_components
    ordered = components.reject(&:fallback) + gems + components.select(&:fallback)
    owners = assign(files, ordered)
    binaries = read_binaries(files)
    links = check_links(binaries, files)
    embeds = check_embedded(components, files)
    check_binary_ownership(binaries, owners)
    check_signatures(binaries, owners)
    check_pins(components, files)
    check_texts(files, owners, binaries)
    report = Report.new(platform:, tree:, components: ordered, owners:, binaries:, links:, embeds:, violations: @violations)
    report.present.each { |component| check_policy(component, report) }
    report
  end

  # The license policy's verdict on an SPDX license expression: the
  # least restrictive way to take it, as one of :notice_only,
  # :first_party, :file_level, :shared_library, or :forbidden.
  def self.category(expression, policy, first_party: false)
    Expression.new(expression, policy, first_party:).category
  end

  # Parses and judges an SPDX license expression (SPDX 2.3, annex D):
  # OR takes the least restrictive alternative, AND the most
  # restrictive part, and WITH an allowed exception makes the license it
  # follows notice-only.
  class Expression
    RANKS = %i[notice_only first_party file_level shared_library forbidden].freeze

    def initialize(text, policy, first_party: false)
      @tokens = text.to_s.scan(/\(|\)|[A-Za-z0-9.+:-]+/)
      @policy = policy
      @first_party = first_party
    end

    def category
      return :forbidden if @tokens.empty?

      result = disjunction
      @tokens.empty? ? result : :forbidden
    end

    private def disjunction
      categories = [conjunction]
      categories << conjunction while @tokens.first == "OR" && @tokens.shift
      categories.min_by { |category| RANKS.index(category) }
    end

    private def conjunction
      categories = [exception]
      categories << exception while @tokens.first == "AND" && @tokens.shift
      categories.max_by { |category| RANKS.index(category) }
    end

    private def exception
      license = atom
      return license unless @tokens.first == "WITH"

      @tokens.shift
      @policy.fetch("exceptions").include?(@tokens.shift) ? :notice_only : :forbidden
    end

    private def atom
      token = @tokens.shift
      if token == "("
        inner = disjunction
        (@tokens.shift == ")") ? inner : :forbidden
      else
        classify(token.to_s)
      end
    end

    private def classify(id)
      id = @policy.fetch("aliases", {}).fetch(id, id)
      return :notice_only if @policy.fetch("notice_only").include?(id)
      return :first_party if @first_party && id == "AGPL-3.0-or-later"
      return :file_level if @policy.fetch("file_level").include?(id)
      return :shared_library if @policy.fetch("shared_library").include?(id)

      :forbidden
    end
  end

  # The SPDX expression a gem's specification declares, its names
  # mapped through the policy's aliases, alternatives joined by OR.
  def self.gem_license(licenses, aliases)
    return "NOASSERTION" if licenses.empty?

    licenses.map { |license| aliases.fetch(license, license) }.uniq.join(" OR ")
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

  private def map_components
    @map.fetch("components").filter_map do |entry|
      next unless entry.fetch("platforms").include?(platform)

      Component.from_map(entry, method(:expand))
    end
  end

  # A component for each gem specification in the tree, owning the
  # gem's files where RubyGems keeps them.
  private def gem_components
    root = "#{prefix}lib/ruby/gems/4.0.0"
    aliases = @map.fetch("policy").fetch("aliases", {})
    Dir.glob(File.join(tree, root, "specifications", "{,default/}*.gemspec")).map do |path|
      spec = Gem::Specification.load(path) or raise "#{path}: not a gem specification"
      full = spec.full_name
      override = @map.fetch("gems", {}).fetch(spec.name, {})
      default = path.include?("/specifications/default/")
      Component.new(id: "gem-#{full}", name: "#{spec.name} (#{default ? 'default' : 'bundled'} gem)", version: spec.version.to_s,
        license: override.fetch("license") { LicenseAudit.gem_license(spec.licenses, aliases) }, kind: "program",
        first_party: false, download: "https://rubygems.org/gems/#{spec.name}/versions/#{spec.version}", notice: nil, source: nil,
        ships: default ? "Ruby's default gem; its code is in lib/ruby/4.0.0" : "files under lib/ruby/gems/4.0.0/gems/#{full}",
        supplier: nil, files: gem_files(root, spec), binaries: gem_binaries(root, full), embedded: [], sha256: {},
        fallback: false, gem_dir: "#{root}/gems/#{full}")
    end
  end

  private def gem_files(root, spec)
    full = spec.full_name
    [
      "#{root}/gems/#{full}/**/*",
      "#{root}/specifications/#{full}.gemspec",
      "#{root}/specifications/default/#{full}.gemspec",
      "#{root}/extensions/*/*/#{full}/**/*",
      "#{root}/cache/#{full}.gem",
      "#{root}/build_info/#{full}.info",
      "#{root}/doc/#{full}/**/*",
      "#{root}/plugins/#{spec.name}_plugin.rb",
      *spec.executables.map { |executable| "#{root}/bin/#{executable}{,.bat,.cmd}" },
    ]
  end

  private def gem_binaries(root, full)
    [
      "#{root}/gems/#{full}/**/*.{so,bundle,dll}",
      "#{root}/gems/#{full}/ext/**/*.{o,a}",
      "#{root}/extensions/*/*/#{full}/**/*.{so,bundle,dll}",
      "#{root}/extensions/*/*/#{full}/**/*.dSYM/Contents/Resources/DWARF/*",
    ]
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

  # A copyleft library's code may appear only in its own shared library.
  private def check_signatures(binaries, owners)
    @map.fetch("signatures").each do |signature|
      binaries.each_key do |path|
        bytes = File.binread(File.join(tree, path))
        next unless signature.fetch("bytes").any? { |needle| bytes.include?(needle.b) }

        owner = owners[path]
        next if owner&.id == signature.fetch("component") && owner&.kind == "shared_library"

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

  # Text that names a copyleft license must be in a file whose own
  # component carries that license, or in one a person reviewed.
  private def check_texts(files, owners, binaries)
    reviewed = @map.fetch("reviewed", []).flat_map { |entry| entry.fetch("files") }
    files.each do |path|
      next if binaries.key?(path) || File.symlink?(File.join(tree, path))

      owner = owners[path]
      next if owner && LicenseAudit.category(owner.license, @map.fetch("policy"), first_party: owner.first_party) != :notice_only

      full = File.join(tree, path)
      next if File.size(full) > 4_000_000

      text = File.binread(full)
      next if text.byteslice(0, 8192).to_s.include?("\0")
      next unless COPYLEFT_BYTES.match?(text)
      next if reviewed.any? { |pattern| matches?(pattern, path) }

      word = text[COPYLEFT_BYTES]
      violate("copyleft-text", path, "names #{word.inspect}, but #{owner&.id || 'no component'} is #{owner&.license}; review it in runtime/licenses.yml")
    end
  end

  private def check_policy(component, report)
    category = LicenseAudit.category(component.license, @map.fetch("policy"), first_party: component.first_party)
    where = (report.owned(component) + report.embedded_in(component)).first.to_s
    case category
    when :notice_only, :first_party then nil
    when :file_level
      return if component.kind == "files"

      violate("policy", where, "#{component.id} is #{component.license}, allowed only for unmodified files, but ships as #{component.kind}")
    when :shared_library
      check_shared_library(component, report, where)
    else
      violate("policy", where, "#{component.id} is #{component.license}, which the policy does not allow in an app")
    end
  end

  private def check_shared_library(component, report, where)
    unless component.kind == "shared_library"
      return violate("policy", where, "#{component.id} is #{component.license}, allowed only as a separate shared library, but ships as #{component.kind}")
    end

    violate("policy", where, "#{component.id} is #{component.license} and needs a source pin in runtime/sources.yml") unless @sources.key?(component.source.to_s)
    report.owned(component).each do |path|
      format = report.binaries[path]&.format
      violate("policy", path, "#{component.id} is #{component.license}, so this file must be a shared library, not #{format.inspect}") unless %i[elf pe macho].include?(format)
    end
    return if report.embedded_in(component).all? { |path| report.owners[path].equal?(component) }

    violate("policy", where, "#{component.id} is #{component.license} and is compiled into a file it does not own")
  end

  private def violate(rule, path, message)
    @violations << Violation.new(rule:, path:, message:)
    nil
  end
end

require_relative "license_audit/binary"
require_relative "license_audit/spdx"
require_relative "license_audit/notices"
require_relative "license_audit/source_bundle"
require_relative "license_audit/cli"

exit LicenseAudit::CLI.new(ARGV).call if $PROGRAM_NAME == __FILE__
