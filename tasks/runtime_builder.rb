# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "digest"
require "fileutils"
require "json"
require "open3"
require "yaml"
require_relative "download_cache"
require_relative "license_audit"
require_relative "release_archive"
require_relative "../lib/fledge/download"
require_relative "../lib/fledge/platform"
require_relative "../lib/fledge/runtimes"
require_relative "../lib/fledge/version"

# Builds a runtime (ADR 001, section 2).
#
# On macOS and Linux, a runtime is the launcher in runtime/launcher/,
# compiled against rv-ruby's static libruby, beside Ruby's own program
# (bin/ruby, built from the same libruby), rv-ruby's standard library,
# default gems, and bundled gems, its CA bundle, and the license notices
# of everything it carries. Those launchers link Ruby itself, so each builds
# on its own platform's runner. On Windows, a runtime is the launcher,
# cross-compiled with llvm-mingw, beside RubyInstaller's Ruby in ruby\,
# with the notices: the Windows launcher loads Ruby's DLL when it runs
# and needs only Ruby's headers to build, so a Linux runner, or a Mac,
# builds it. Then fledge build, on any computer, copies apps into the
# results.
#
# Before it archives a runtime, the builder audits it (LicenseAudit,
# against runtime/licenses.yml) and refuses to archive one that breaks
# Fledge's license policy (ADR 004). The audit's findings become the
# runtime's notices/NOTICES.txt and notices/sbom.spdx.json, and, beside
# the archive, the release assets that go with it: the SBOM, the
# NOTICES, and the source of the runtime's LGPL libraries.
#
# Every input comes from runtime/sources.yml and is checked against its
# SHA-256, and RubyInstaller's archive against its PGP signature too. The
# steps that differ by operating system (unpacking Ruby, compiling,
# stripping, libxcrypt) live in a recipe per OS: Darwin and Linux, which
# share Unix, and Windows. The layout is the one the Unix and Windows
# launcher spikes settled (Plan 001).
#
# What a runtime leaves out follows one rule (ADR 003): an app's Ruby
# code must run as it does under a standard Ruby 4.0.9, so a runtime
# keeps everything such a Ruby installs that running Ruby code can
# reach (every default and bundled gem, its executables, the gem cache,
# the C extensions, RbConfig.ruby) and prunes only what no running Ruby
# code reads: documentation, man pages, headers, static and import
# libraries, and debug information. Size matters less than that rule.
#
# Run it as rake runtime (or rake "runtime[x64-mingw-ucrt]"), or as ruby
# tasks/runtime_builder.rb [PLATFORM] in a container that has a C
# toolchain and any Ruby.
class RuntimeBuilder
  ROOT = File.expand_path("..", __dir__)

  # Compiler warnings the launcher must build without. Ruby's headers are
  # included with -isystem, so these apply to Fledge's code only.
  WARNINGS = %w[
    -Wall
    -Wextra
    -Werror
    -Wpedantic
    -Wshadow
    -Wstrict-prototypes
    -Wmissing-prototypes
    -Wformat=2
    -Wconversion
    -Wsign-conversion
  ].freeze

  attr_reader :platform, :host, :sources

  def initialize(platform: Fledge::Platform.local, host: Fledge::Platform.local, work: File.join(ROOT, "tmp", "runtime"),
    downloads: File.join(ROOT, "tmp", "downloads"), sources: File.join(ROOT, "runtime", "sources.yml")
  )
    @platform = platform
    @host = host
    @work = work
    @downloads = downloads
    @sources = YAML.safe_load_file(sources)
  end

  # Builds the runtime, audits it, and returns the path of its archive,
  # with the release assets that go with it beside it (#assets). Raises
  # LicenseAudit::Failure, and archives nothing, when the runtime breaks
  # the license policy.
  def call
    recipe = recipe_class.new(builder: self, build_dir:)
    hosts = recipe.hosts
    raise "#{platform} runtimes build on #{hosts.join(', ')} only; this is #{host}" unless hosts.include?(host.name)

    FileUtils.rm_rf(build_dir)
    FileUtils.rm_f(assets.values.map { |name| File.join(@work, name) })
    FileUtils.mkdir_p(stage)
    recipe.build(stage)
    license(stage)
    path = archive
    publish(stage)
    write_dev(recipe.tree)
    path
  end

  # The file names of what a release publishes for this platform at
  # +version+: the runtime archive Fledge::Runtimes downloads, its SPDX
  # SBOM and NOTICES (the same files as the archive's notices/), and the
  # source bundle of its LGPL libraries, if it ships any.
  def assets(version: Fledge::VERSION)
    archive = Fledge::Runtimes.file_name(platform, version:)
    base = File.basename(archive, Fledge::Runtimes::EXTENSION)
    {
      runtime: archive,
      sbom: "#{base}.spdx.json",
      notices: "#{base}-NOTICES.txt",
      sources: LicenseAudit::Notices.source_bundle(version, platform.name),
      dev: Fledge::Runtimes.dev_file_name(platform, version:),
    }
  end

  # Every asset a release of +version+ publishes but SHA256SUMS, sorted:
  # each platform's #assets, and its source bundle only where the
  # platform ships an LGPL library, and the makensis of each computer that
  # builds apps (tasks/makensis_builder.rb). release.yml checks the
  # release against it.
  def self.release_assets(version: Fledge::VERSION)
    Fledge::Platform.names.flat_map do |name|
      platform = Fledge::Platform.find(name)
      lgpl = !LicenseAudit::SourceBundle.new(platform: name, version:).components.empty?
      files = new(platform:).assets(version:).filter_map { |kind, file| file if kind != :sources || lgpl }
      files << Fledge::Runtimes.makensis_file_name(platform, version:)
    end.sort
  end

  # Audits the runtime folder +stage+ against runtime/licenses.yml and
  # writes what it found into +stage+/notices: NOTICES.txt, which names
  # every component and its license and holds every license text, and
  # sbom.spdx.json. Raises LicenseAudit::Failure when the runtime breaks
  # the policy or a component's license text is nowhere, so that no such
  # runtime is ever archived. Returns the audit's Report.
  def license(stage)
    audit = LicenseAudit.new(platform: platform.name, tree: stage, fledge_version: Fledge::VERSION)
    report = audit.call
    notices = LicenseAudit::Notices.new(report, version: Fledge::VERSION, map: audit.map)
    problems = LicenseAudit.problems(report, notices)
    raise LicenseAudit::Failure.new(platform.name, problems) unless problems.empty?

    FileUtils.mkdir_p(File.join(stage, "notices"))
    File.write(File.join(stage, "notices", "NOTICES.txt"), notices.text)
    File.write(File.join(stage, "notices", "sbom.spdx.json"), "#{JSON.pretty_generate(LicenseAudit::Spdx.new(report, version: Fledge::VERSION).to_h)}\n")
    puts "#{platform}: #{report.owners.size} files in #{report.present.size} components meet the license policy"
    report
  end

  # Writes the build-only companion (#assets, :dev) from the Ruby tree
  # +tree+, with the runtime's top folder, so it unpacks over the runtime.
  private def write_dev(tree)
    dev = File.join(build_dir, "dev", top)
    FileUtils.rm_rf(File.dirname(dev))
    DevCompanion.copy(tree, dev, windows: platform.windows?)
    ReleaseArchive.pack(dev, File.join(@work, assets.fetch(:dev)), top:)
  end

  # Writes the release assets beside the archive: copies of the SBOM and
  # NOTICES the runtime carries, and the LGPL source bundle.
  private def publish(stage)
    FileUtils.cp(File.join(stage, "notices", "sbom.spdx.json"), File.join(@work, assets.fetch(:sbom)))
    FileUtils.cp(File.join(stage, "notices", "NOTICES.txt"), File.join(@work, assets.fetch(:notices)))
    bundle = LicenseAudit::SourceBundle.new(platform: platform.name, version: Fledge::VERSION, downloads: @downloads).write(@work)
    puts "Wrote #{bundle}" if bundle
  end

  # The folder that becomes the runtime archive's top folder.
  def stage
    File.join(build_dir, "stage", top)
  end

  def top
    File.basename(Fledge::Runtimes.file_name(platform), Fledge::Runtimes::EXTENSION)
  end

  def build_dir
    File.join(@work, platform.name)
  end

  # Downloads +url+ into the download cache, checked against +sha256+,
  # unless a file with that SHA-256 is already there.
  def fetch(url, sha256)
    DownloadCache.new(@downloads).fetch(url, sha256)
  end

  # The first of +tools+ found on PATH, as a full path, or nil.
  def which(*tools)
    directories = ENV.fetch("PATH", "").split(File::PATH_SEPARATOR)
    tools.each do |tool|
      directories.each do |directory|
        path = File.join(directory, tool)
        return path if File.file?(path) && File.executable?(path)
      end
    end
    nil
  end

  # Runs a command, echoing it, and raises when it fails.
  def run(*command, chdir: ROOT, out: $stdout)
    puts "+ #{command.join(' ')}"
    system(*command, chdir:, out:, exception: true)
  end

  # Runs a command and returns its standard output.
  def capture(*command)
    out, status = Open3.capture2(*command)
    raise "#{command.join(' ')} failed" unless status.success?

    out
  end

  # Ruby's bundled gems, as runtime/sources.yml lists them.
  def bundled_gems
    sources.fetch("ruby").fetch("bundled_gems")
  end

  # Puts Fledge's rubygems/defaults/operating_system.rb into the Ruby
  # library at +ruby+ (a lib/ruby folder), replacing any there, such as
  # RubyInstaller's; see the file's own comment.
  def install_rubygems_defaults(ruby)
    version = sources.fetch("ruby").fetch("version").sub(/\.\d+\z/, ".0")
    defaults = File.join(ruby, version, "rubygems", "defaults")
    raise "#{ruby} has no RubyGems at #{version}" unless File.directory?(File.dirname(defaults))

    FileUtils.mkdir_p(defaults)
    FileUtils.cp(File.join(ROOT, "runtime", "rubygems", "operating_system.rb"), defaults)
  end

  private def recipe_class
    if platform.windows?
      Windows
    else
      platform.name.end_with?("-darwin") ? Darwin : Linux
    end
  end

  private def archive
    ReleaseArchive.pack(stage, File.join(@work, Fledge::Runtimes.file_name(platform)), top:)
  end
end

require_relative "runtime_builder/armor"
require_relative "runtime_builder/dev_companion"
require_relative "runtime_builder/gem_repack"
require_relative "runtime_builder/pruning"
require_relative "runtime_builder/recipe"
require_relative "runtime_builder/unix"
require_relative "runtime_builder/darwin"
require_relative "runtime_builder/linux"
require_relative "runtime_builder/app_image_runtime"
require_relative "runtime_builder/windows"

if $PROGRAM_NAME == __FILE__
  platform = ARGV.first ? Fledge::Platform.find(ARGV.first) : Fledge::Platform.local
  puts RuntimeBuilder.new(platform:).call
end
