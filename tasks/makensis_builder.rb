# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "digest"
require "etc"
require "fileutils"
require "open3"
require "yaml"
require_relative "../lib/fledge/download"
require_relative "../lib/fledge/entry"
require_relative "../lib/fledge/platform"
require_relative "../lib/fledge/runtimes"
require_relative "../lib/fledge/archive"
require_relative "../lib/fledge/version"
require_relative "download_cache"
require_relative "release_archive"

# Builds the NSIS compiler, makensis, for one kind of computer that
# builds apps (ADR 009), into the archive Fledge::Runtimes#makensis
# downloads: fledge-makensis-VERSION-HOST.tar.gz.
#
# NSIS publishes makensis only for Windows. Its own documentation
# ("Building on POSIX", Appendix G) builds the compiler alone on macOS
# and Linux with SCons, to use with the stubs and plug-ins of the Windows
# release, which is how Fledge uses it: the Windows runtime carries those
# (RuntimeBuilder::Windows::NSIS), and fledge build points makensis at
# them with NSISDIR. So this builds makensis from NSIS's pinned source,
# with no stubs, plug-ins, or utilities, finding its data by NSISDIR
# rather than by a path compiled in, and, on Linux, with libstdc++ and
# libgcc linked statically, so it needs only glibc and zlib, which every
# Linux computer that builds an app has; on macOS, for macOS 14, the
# runtimes' floor. For Windows computers it repacks the release's own
# makensis.exe and the zlib1.dll it loads. Either way it then compiles a
# script with the release's stubs and checks the version makensis
# reports, and archives it with NSIS's license.
#
# Run it as rake "makensis[HOST]", or ruby tasks/makensis_builder.rb
# [HOST]. It builds for the computer it runs on, but Windows' repack
# runs anywhere.
class MakensisBuilder
  ROOT = File.expand_path("..", __dir__)

  attr_reader :host

  def initialize(host: Fledge::Platform.local, work: File.join(ROOT, "tmp", "makensis"),
    downloads: File.join(ROOT, "tmp", "downloads"), sources: File.join(ROOT, "runtime", "sources.yml")
  )
    @host = host
    @work = work
    @downloads = downloads
    @nsis = YAML.safe_load_file(sources).fetch("nsis")
  end

  # Builds makensis and returns the path of its archive.
  def call
    raise "makensis for #{host} builds on #{host} only" unless host.windows? || host == Fledge::Platform.local

    folder = File.join(build_dir, "stage", top)
    FileUtils.rm_rf(build_dir)
    FileUtils.mkdir_p(folder)
    release = unpack_release
    host.windows? ? repack(release, folder) : compile(folder)
    FileUtils.cp(File.join(release, "COPYING"), File.join(folder, "COPYING"))
    check(File.join(folder, host.executable("makensis")), release) unless host.windows? && !Gem.win_platform?
    archive(folder)
  end

  # The archive's top folder: its name, less the extension.
  def top
    File.basename(Fledge::Runtimes.makensis_file_name(host), Fledge::Runtimes::EXTENSION)
  end

  # The flags SCons builds makensis alone with, as "Building on POSIX"
  # gives them, for +host+.
  def self.scons_flags(host, version:, prefix:)
    flags = %W[SKIPSTUBS=all SKIPPLUGINS=all SKIPUTILS=all SKIPMISC=all NSIS_CONFIG_CONST_DATA_PATH=no VERSION=#{version} PREFIX=#{prefix}]
    case host.os
    when "linux" then flags << "APPEND_LINKFLAGS=-static-libstdc++ -static-libgcc"
    when "darwin" then flags.push("APPEND_CCFLAGS=-mmacosx-version-min=14.0", "APPEND_LINKFLAGS=-mmacosx-version-min=14.0")
    end
    flags << "install-compiler"
  end

  private def build_dir
    File.join(@work, host.name)
  end

  private def fetch(pin)
    DownloadCache.new(@downloads).fetch(pin.fetch("url"), pin.fetch("sha256"))
  end

  private def run(*command, chdir: ROOT)
    puts "+ #{command.join(' ')}"
    system(*command, chdir:, exception: true)
  end

  # NSIS's release for Windows, unpacked: its stubs for the check, its
  # license, and, for Windows computers, its makensis.
  private def unpack_release
    zip = fetch(@nsis.fetch("binary"))
    into = File.join(build_dir, "release")
    FileUtils.mkdir_p(into)
    run("unzip", "-q", zip, "-d", into)
    File.join(into, "nsis-#{@nsis.fetch('version')}")
  end

  private def repack(release, folder)
    %w[makensis.exe zlib1.dll].each { |name| FileUtils.cp(File.join(release, "Bin", name), File.join(folder, name)) }
  end

  private def compile(folder)
    source = File.join(build_dir, "source")
    FileUtils.mkdir_p(source)
    run("tar", "-xjf", fetch(@nsis.fetch("source")), "-C", source, "--strip-components=1")
    scons = install_scons
    prefix = File.join(build_dir, "out")
    run(scons, "-Q", "-j#{Etc.nprocessors}", *MakensisBuilder.scons_flags(host, version: @nsis.fetch("version"), prefix:), chdir: source)
    FileUtils.cp(File.join(prefix, "makensis"), File.join(folder, "makensis"))
    run("strip", File.join(folder, "makensis"))
  end

  # SCons from its pinned wheel, in a virtual environment of this
  # computer's Python 3, with nothing else from PyPI.
  private def install_scons
    pin = @nsis.fetch("scons")
    wheel = fetch(pin)
    venv = File.join(build_dir, "scons")
    run("python3", "-m", "venv", venv)
    run(File.join(venv, "bin", "pip"), "install", "--quiet", "--no-index", "--no-deps", wheel)
    File.join(venv, "bin", "scons")
  end

  # Compiles a small installer with the release's stubs, and checks the
  # version makensis says it is.
  private def check(makensis, release)
    env = { "NSISDIR" => release }
    version, status = Open3.capture2(env, makensis, "-VERSION")
    raise "#{makensis} -VERSION failed" unless status.success?
    raise "#{makensis} is #{version.strip}, not v#{@nsis.fetch('version')}" unless version.strip == "v#{@nsis.fetch('version')}"

    script = File.join(build_dir, "check.nsi")
    File.write(script, "Unicode true\nSetCompressor /SOLID zlib\nOutFile \"#{File.join(build_dir, 'check.exe')}\"\nSection\nSectionEnd\n")
    run(env, makensis, "-V2", "-NOCD", "-NOCONFIG", script)
  end

  private def archive(folder)
    ReleaseArchive.pack(folder, File.join(@work, Fledge::Runtimes.makensis_file_name(host)), top:)
  end
end

if $PROGRAM_NAME == __FILE__
  host = ARGV.first ? Fledge::Platform.find(ARGV.first) : Fledge::Platform.local
  puts MakensisBuilder.new(host:).call
end
