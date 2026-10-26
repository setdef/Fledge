# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

lib = File.expand_path("../lib", __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require "fledge"

require "minitest/autorun"
require "tmpdir"

# Builds runtime archives shaped like the ones rake runtime writes, small
# enough for a unit test: a launcher that is a shell script, a library
# file, and a symlink, under one top folder.
module FakeRuntime
  LAUNCHER = "#!/bin/sh\necho launched\n"

  # Writes the runtime for +platform+ into +directory+, named as
  # Fledge::Runtimes expects, and returns its path. +extra+ entries
  # (paths relative to the runtime's top folder) go in after the rest.
  def self.write(directory, platform, extra: [])
    top = File.basename(Fledge::Runtimes.file_name(platform), platform.archive_extension)
    path = File.join(directory, Fledge::Runtimes.file_name(platform))
    Fledge::TarGz.write(path) do |tar|
      tar.add(Fledge::Entry.directory(top))
      [
        Fledge::Entry.file("launcher", LAUNCHER, mode: 0o755),
        Fledge::Entry.directory("lib"),
        Fledge::Entry.directory("lib/ruby"),
        Fledge::Entry.file("lib/ruby/stdlib.rb", "# stdlib\n"),
        Fledge::Entry.symlink("lib/current", "ruby"),
        *extra,
      ].each { |entry| tar.add(entry.with(path: "#{top}/#{entry.path}")) }
    end
    path
  end
end

# Writes a minimal app, a folder with a main.rb, and returns its path.
module FakeApp
  def self.write(directory, name = "hello")
    root = File.join(directory, name)
    FileUtils.mkdir_p(root)
    File.write(File.join(root, "main.rb"), "puts 'hi'\n")
    root
  end
end
