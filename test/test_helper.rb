# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

lib = File.expand_path("../lib", __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require "fledge"

require "minitest/autorun"
require "fileutils"
require "tmpdir"

# Builds runtime archives shaped like the ones rake runtime writes, small
# enough for a unit test: a launcher that is a shell script (on Windows,
# the real Windows runtime's launchers and rcedit when they are at hand,
# FakeRuntime.windows), a library file, Ruby's rbconfig.rb and a default
# gem's specification where a real runtime keeps them, and, except on
# Windows, whose runtimes hold none, a symlink, under one top folder.
module FakeRuntime
  LAUNCHER = "#!/bin/sh\necho launched\n"
  # Windows launchers where no real Windows runtime is at hand
  # (FakeRuntime.windows): only Windows' own tools read a program, and
  # only on Windows.
  WINDOWS_CONSOLE = "MZ console"
  WINDOWS_GUI = "MZ gui"

  # Each runtime's Ruby's architecture, as its rbconfig.rb records it:
  # rv-ruby's macOS build is for macOS 14 (Darwin 23).
  ARCH = {
"arm64-darwin" => "arm64-darwin23",
"x86_64-linux" => "x86_64-linux",
"aarch64-linux" => "aarch64-linux",
"x64-mingw-ucrt" => "x64-mingw-ucrt",
"ios" => "arm64-darwin",
"android" => "aarch64-linux-android",
}.freeze

  # Ruby's rbconfig.rb for +platform+'s runtime, with what Fledge reads.
  def self.rbconfig(platform)
    "module RbConfig\n  CONFIG = {}\n  CONFIG[\"MAJOR\"] = \"4\"\n  CONFIG[\"MINOR\"] = \"0\"\n  CONFIG[\"TEENY\"] = \"9\"\n" \
      "  CONFIG[\"arch\"] = \"#{ARCH.fetch(platform.name)}\"\nend\n"
  end

  # Writes the runtime for +platform+ into +directory+, named as
  # Fledge::Runtimes expects, and returns its path. +extra+ entries
  # (paths relative to the runtime's top folder) go in after the rest.
  def self.write(directory, platform, extra: [], launcher: LAUNCHER)
    top = File.basename(Fledge::Runtimes.file_name(platform), Fledge::Runtimes::EXTENSION)
    path = File.join(directory, Fledge::Runtimes.file_name(platform))
    pack(path, top, [
      *launchers(platform, launcher),
      *ruby(platform.windows? ? "ruby/lib/ruby" : "lib/ruby", platform),
      *((platform.windows? || Gem.win_platform?) ? [] : [Fledge::Entry.symlink("lib/current", "ruby")]),
      *extra,
    ])
  end

  # Writes +entries+ under the folder +top+ into the archive +path+, with
  # the computer's tar, as rake runtime packs a runtime, and returns
  # +path+.
  def self.pack(path, top, entries)
    Dir.mktmpdir("fake-runtime") do |stage|
      folder = File.join(stage, top)
      FileUtils.mkdir_p(folder)
      entries.each { |entry| entry.write_into(folder) }
      Fledge::Archive.pack(folder, to: path)
    end
  end

  # Writes the runtime for the phone +phone+ (a Fledge::MobilePlatform)
  # into +directory+, shaped as ADR 011 describes it, and returns its
  # path: for iOS, an XCFramework whose two slices each hold a Ruby; for
  # Android, an AAR beside one Ruby; each with its CA certificates and
  # notices.
  def self.write_mobile(directory, phone)
    top = File.basename(Fledge::Runtimes.file_name(phone), Fledge::Runtimes::EXTENSION)
    path = File.join(directory, Fledge::Runtimes.file_name(phone))
    rubies = (phone.name == "ios") ? %w[ios-arm64 ios-arm64-simulator].map { |slice| "FledgeRuby.xcframework/#{slice}/" } : [""]
    library = (phone.name == "ios") ? Fledge::Entry.file("FledgeRuby.xcframework/Info.plist", "<plist/>\n") : Fledge::Entry.file("FledgeRuby.aar", "PK aar")
    pack(path, top, [
      library,
      *rubies.flat_map { |prefix| [*ruby("#{prefix}lib/ruby", phone), Fledge::Entry.file("#{prefix}libexec/cert.pem", "certificates\n")] },
      Fledge::Entry.file("notices/NOTICES.txt", "Fledge's runtime for #{phone}\n"),
    ])
  end

  # The launchers of +platform+'s runtime: +launcher+, and on Windows the
  # console and windowed programs, with the rcedit a Windows runtime
  # carries: the real runtime's (FakeRuntime.windows) where there is one,
  # since only real programs and rcedit show what Windows makes of them.
  def self.launchers(platform, launcher)
    return [Fledge::Entry.file("launcher", launcher, mode: 0o755)] unless platform.windows?

    windows || [Fledge::Entry.file("launcher.exe", WINDOWS_CONSOLE, mode: 0o755), Fledge::Entry.file("launcherw.exe", WINDOWS_GUI, mode: 0o755)]
  end

  # The launchers and rcedit of the real Windows runtime, in
  # FLEDGE_RUNTIME_DIR or tmp/runtime, on Windows, where they run; or nil.
  def self.windows
    return nil unless Gem.win_platform?
    return @windows if defined?(@windows)

    runtimes = ENV.fetch("FLEDGE_RUNTIME_DIR", File.expand_path("../tmp/runtime", __dir__))
    archive = File.join(runtimes, Fledge::Runtimes.file_name(Fledge::Platform.find("x64-mingw-ucrt")))
    @windows = File.file?(archive) ? unpack_windows(archive) : nil
  end

  private_class_method def self.unpack_windows(archive)
    Dir.mktmpdir("windows-runtime") do |dir|
      Fledge::Archive.unpack(archive, into: dir)
      top = Dir.glob(File.join(dir, "*")).first.to_s
      %w[launcher.exe launcherw.exe tools/rcedit.exe].map { |path| Fledge::Entry.file(path, File.binread(File.join(top, path)), mode: 0o755) }
    end
  end

  # The icon files of examples/windowed_app, named as Fledge::Icon names
  # them, written into +root+ under +base+.
  def self.icons(root, base = "icon")
    source = File.expand_path("../examples/windowed_app/icons", __dir__)
    Dir.children(source).each { |name| FileUtils.cp(File.join(source, name), File.join(root, name.sub("icon", base))) }
  end

  # Ruby's library folder at +lib+: a library file, +platform+'s
  # rbconfig.rb, and a default gem, json 2.18.0, and a bundled gem, csv
  # 3.3.5.
  def self.ruby(lib, platform)
    gems = "#{lib}/gems/4.0.0"
    [
      Fledge::Entry.file("#{lib}/stdlib.rb", "# stdlib\n"),
      Fledge::Entry.file("#{lib}/4.0.0/fake-arch/rbconfig.rb", rbconfig(platform)),
      Fledge::Entry.file("#{gems}/specifications/default/json-2.18.0.gemspec", "# json\n"),
      Fledge::Entry.file("#{gems}/specifications/csv-3.3.5.gemspec", "# csv\n"),
    ]
  end
end

# Writes a minimal app, a folder with a main.rb, and returns its path. Its
# .git folder, which never ships, keeps a search for its project's root
# from going above it.
module FakeApp
  def self.write(directory, name = "hello")
    root = File.join(directory, name)
    FileUtils.mkdir_p(File.join(root, ".git"))
    File.write(File.join(root, "main.rb"), "puts 'hi'\n")
    root
  end
end
