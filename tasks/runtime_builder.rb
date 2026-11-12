# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require "bundler"
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

# Builds a runtime (ADR 034; doc/contributors/design/runtimes.md,
# "What a runtime is").
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
# What a runtime leaves out follows one rule (ADR 039): an app's Ruby
# code must run as it does under a standard Ruby 4.1, so a runtime
# keeps everything such a Ruby installs that running Ruby code can
# reach (every default and bundled gem, its executables, the gem cache,
# the C extensions, RbConfig.ruby) and prunes only what no running Ruby
# code reads: documentation, man pages, the headers of gems' extensions,
# static and import libraries, and debug information. Ruby's own headers
# stay, since require "mkmf" reads them. Size matters less than that
# rule.
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
    LicenseAudit::SourceBundle.new(platform: platform.name, version: Fledge::VERSION, downloads: @downloads).copy_into(stage)
    license(stage, readers: recipe.readers)
    path = archive
    publish(stage)
    write_dev(recipe.tree) unless mobile?
    path
  end

  # The runtime named +name+: a desktop platform's (Fledge::Platform), or
  # a mobile one's (Mobile::PLATFORMS, ADR 011), which fledge build does
  # not build apps for yet. Raises Fledge::UsageError for any other name.
  def self.platform(name)
    Mobile::PLATFORMS.fetch(name) { Fledge::Platform.find(name) }
  end

  # Whether this is a mobile runtime (ADR 011).
  def mobile?
    platform.is_a?(Mobile::Platform)
  end

  # The file names of what a release publishes for this platform at
  # +version+: the runtime archive Fledge::Runtimes downloads, its SPDX
  # SBOM and NOTICES (the same files as the archive's notices/), and the
  # source bundle of its LGPL libraries, if it ships any.
  def assets(version: Fledge::VERSION)
    archive = Fledge::Runtimes.file_name(platform, version:)
    base = File.basename(archive, Fledge::Runtimes::EXTENSION)
    described = { runtime: archive, sbom: "#{base}.spdx.json", notices: "#{base}-NOTICES.txt" }
    return described if mobile?

    described.merge(sources: LicenseAudit::Notices.source_bundle(version, platform.name),
      dev: Fledge::Runtimes.dev_file_name(platform, version:))
  end

  # Every asset a release of +version+ publishes but SHA256SUMS, sorted:
  # each desktop and mobile runtime's #assets, and its source bundle only
  # where the platform ships a component whose source Fledge publishes.
  # release.yml checks the release against it.
  def self.release_assets(version: Fledge::VERSION)
    [*Fledge::Platform.names, *Mobile::PLATFORMS.keys].flat_map do |name|
      lgpl = !LicenseAudit::SourceBundle.new(platform: name, version:).components.empty?
      new(platform: platform(name)).assets(version:).filter_map { |kind, file| file if kind != :sources || lgpl }
    end.sort
  end

  # Audits the runtime folder +stage+ against runtime/licenses.yml and
  # writes what it found into +stage+/notices: NOTICES.txt, which names
  # every component and its license and holds every license text, and
  # sbom.spdx.json, reading compiled files with +readers+
  # (Fledge::Binary::Readers). Raises LicenseAudit::Failure when the runtime breaks
  # the policy or a component's license text is nowhere, so that no such
  # runtime is ever archived. Returns the audit's Report.
  def license(stage, readers: LicenseAudit.readers)
    audit = LicenseAudit.new(platform: platform.name, tree: stage, fledge_version: Fledge::VERSION, readers:)
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
  # unless a file with that SHA-256 is already there, trying each of
  # +mirrors+ in order when +url+ fails (DownloadCache#fetch).
  def fetch(url, sha256, mirrors: [])
    DownloadCache.new(@downloads).fetch(url, sha256, mirrors:)
  end

  # Downloads the file the runtime/sources.yml pin +pin+ names, as #fetch
  # does, from its url or else from each of its mirrors.
  def fetch_pin(pin)
    fetch(pin.fetch("url"), pin.fetch("sha256"), mirrors: pin.fetch("mirrors", []))
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

  # Runs a command, echoing it, and raises when it fails. A Hash before
  # the command sets (or, with nil, unsets) variables of its environment,
  # as for Kernel#system. The command runs outside Bundler: under
  # bundle exec rake, RUBYOPT=-rbundler/setup and the BUNDLE_ variables
  # would reach the miniruby that a cross build runs on the build machine,
  # which loads Bundler before it can find rbconfig.
  def run(*command, chdir: ROOT, out: $stdout, err: $stderr)
    env = command.first.is_a?(Hash) ? command.shift : {}
    puts "+ #{command.join(' ')}"
    unbundled { system(env, *command, chdir:, out:, err:, exception: true) }
  end

  # Runs a command outside Bundler, as #run does, and returns its
  # standard output.
  def capture(*command)
    out, status = unbundled { Open3.capture2(*command) }
    raise "#{command.join(' ')} failed" unless status.success?

    out
  end

  # Runs the block with the environment the person's shell had before
  # bundle exec changed it.
  private def unbundled(&)
    Bundler.with_unbundled_env(&)
  end

  # Ruby's bundled gems, as runtime/sources.yml lists them.
  def bundled_gems
    sources.fetch("ruby").fetch("bundled_gems")
  end

  # The name of the folder the Ruby library at +ruby+ (a lib/ruby folder)
  # keeps its standard library in, and its gems in gems/ under the same
  # name: RbConfig's ruby_version, such as 4.1.0+5, the one folder there
  # named for a version. A release is named MAJOR.MINOR.0, and a preview
  # or a snapshot of Ruby's master adds its ABI version
  # (include/ruby/internal/abi.h), which two snapshots of one minor need
  # not share. The Ruby's own tree says which it is, so nothing here keeps
  # it a second time.
  def self.ruby_abi(ruby)
    found = Dir.glob(ABI_FOLDER, base: ruby)
    raise "#{ruby} holds no one Ruby standard library: #{found.join(', ')}" unless found.size == 1

    found.first.to_s.delete_suffix("/")
  end

  # The glob of a Ruby library's folder named for its version, in lib/ruby.
  ABI_FOLDER = "[0-9]*.*/"

  # Puts Fledge's rubygems/defaults/operating_system.rb into the Ruby
  # library at +ruby+ (a lib/ruby folder), replacing any there, such as
  # RubyInstaller's; see the file's own comment.
  def install_rubygems_defaults(ruby)
    defaults = File.join(ruby, RuntimeBuilder.ruby_abi(ruby), "rubygems", "defaults")
    FileUtils.mkdir_p(defaults)
    FileUtils.cp(File.join(ROOT, "runtime", "rubygems", "operating_system.rb"), defaults)
  end

  private def recipe_class
    if mobile?
      (platform.name == "ios") ? IOS : Android
    elsif platform.windows?
      Windows
    elsif platform.musl?
      Musl
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
require_relative "runtime_builder/musl"
require_relative "runtime_builder/windows"
require_relative "runtime_builder/ruby_source"
require_relative "runtime_builder/bundled_extensions"
require_relative "runtime_builder/mobile"
require_relative "runtime_builder/ios"
require_relative "runtime_builder/android"

if $PROGRAM_NAME == __FILE__
  platform = ARGV.first ? RuntimeBuilder.platform(ARGV.first) : Fledge::Platform.local
  puts RuntimeBuilder.new(platform:).call
end
