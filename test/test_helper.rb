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
require_relative "support/binaries"

# Builds runtime archives shaped like the ones rake runtime writes, small
# enough for a unit test: a launcher that is a shell script (on Windows,
# the smallest console program and, as launcherw.exe, windowed one that
# Fledge can put resources into, from test/support/binaries.rb), a library
# file, Ruby's rbconfig.rb and a default gem's specification where a real
# runtime keeps them, and, except on Windows, whose runtimes hold none, a
# symlink, under one top folder.
module FakeRuntime
  LAUNCHER = "#!/bin/sh\necho launched\n"
  WINDOWS_CONSOLE = Programs.windows(subsystem: 3)
  WINDOWS_GUI = Programs.windows(subsystem: 2)

  # Each runtime's Ruby's architecture, as its rbconfig.rb records it:
  # rv-ruby's macOS build is for macOS 14 (Darwin 23).
  ARCH = {
"arm64-darwin" => "arm64-darwin23",
"x86_64-linux" => "x86_64-linux",
"aarch64-linux" => "aarch64-linux",
"x64-mingw-ucrt" => "x64-mingw-ucrt",
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

  # The launchers of +platform+'s runtime: +launcher+, and on Windows the
  # console and windowed programs.
  def self.launchers(platform, launcher)
    return [Fledge::Entry.file("launcher", launcher, mode: 0o755)] unless platform.windows?

    [Fledge::Entry.file("launcher.exe", WINDOWS_CONSOLE, mode: 0o755), Fledge::Entry.file("launcherw.exe", WINDOWS_GUI, mode: 0o755)]
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
