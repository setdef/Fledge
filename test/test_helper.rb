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
# file, Ruby's rbconfig.rb and a default gem's specification where a real
# runtime keeps them, and, except on Windows, whose runtimes hold none, a
# symlink, under one top folder.
module FakeRuntime
  LAUNCHER = "#!/bin/sh\necho launched\n"
  RBCONFIG = "module RbConfig\n  CONFIG = {}\n  CONFIG[\"MAJOR\"] = \"4\"\n  CONFIG[\"MINOR\"] = \"0\"\n  CONFIG[\"TEENY\"] = \"9\"\nend\n"

  # Writes the runtime for +platform+ into +directory+, named as
  # Fledge::Runtimes expects, and returns its path. +extra+ entries
  # (paths relative to the runtime's top folder) go in after the rest.
  def self.write(directory, platform, extra: [])
    top = File.basename(Fledge::Runtimes.file_name(platform), Fledge::Runtimes::EXTENSION)
    path = File.join(directory, Fledge::Runtimes.file_name(platform))
    Fledge::TarGz.write(path) do |tar|
      tar.add(Fledge::Entry.directory(top))
      with_folders([
        Fledge::Entry.file(platform.executable("launcher"), LAUNCHER, mode: 0o755),
        *ruby(platform.windows? ? "ruby/lib/ruby" : "lib/ruby"),
        *(platform.windows? ? [] : [Fledge::Entry.symlink("lib/current", "ruby")]),
        *extra,
      ]).each { |entry| tar.add(entry.with(path: "#{top}/#{entry.path}")) }
    end
    path
  end

  # +entries+, each after a folder entry for every folder above it, as a
  # runtime archive holds them.
  def self.with_folders(entries)
    seen = {}
    entries.flat_map do |entry|
      parts = entry.path.split("/")[0...-1]
      folders = parts.each_index.map { |index| parts.first(index + 1).join("/") }.reject { |folder| seen[folder] }
      folders.each { |folder| seen[folder] = true }
      [*folders.map { |folder| Fledge::Entry.directory(folder) }, entry]
    end
  end

  # Ruby's library folder at +lib+: a library file, rbconfig.rb, and a
  # default gem, json 2.18.0, and a bundled gem, csv 3.3.5.
  def self.ruby(lib)
    gems = "#{lib}/gems/4.0.0"
    [
      Fledge::Entry.file("#{lib}/stdlib.rb", "# stdlib\n"),
      Fledge::Entry.file("#{lib}/4.0.0/fake-arch/rbconfig.rb", RBCONFIG),
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
