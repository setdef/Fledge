# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "test_helper"
require_relative "support/gems"
require "stringio"
require "zlib"

class GemPackageTest < Minitest::Test
  def setup
    @dir = Dir.mktmpdir
  end

  def teardown
    FileUtils.rm_rf(@dir)
  end

  def test_installs_as_gem_install_lays_a_gem_out
    built = FakeGem.build(@dir, "tool", "1.2.0", executables: ["tool"], plugin: true,
      files: { "lib/tool.rb" => "# tool\n", "exe/tool" => "#!/usr/bin/env ruby\n", "LICENSE.txt" => "MIT\n" })
    package = Fledge::GemPackage.new(built.path)

    entries = package.entries("lib/ruby/gems/4.0.0").to_h { |entry| [entry.path, entry] }

    gems = "lib/ruby/gems/4.0.0"
    assert_equal :directory, entries.fetch("#{gems}/gems/tool-1.2.0").type
    assert_equal ["# tool\n", 0o644], entries.fetch("#{gems}/gems/tool-1.2.0/lib/tool.rb").then { |entry| [entry.content, entry.mode] }
    # gem build takes each file's mode from the disk, and a Windows disk
    # keeps no executable bit, so a gem built there has none to keep.
    assert_equal Gem.win_platform? ? 0o644 : 0o755, entries.fetch("#{gems}/gems/tool-1.2.0/exe/tool").mode
    assert_equal File.binread(built.path), entries.fetch("#{gems}/cache/tool-1.2.0.gem").content
    assert_equal "require_relative '../gems/tool-1.2.0/lib/rubygems_plugin.rb'\n", entries.fetch("#{gems}/plugins/tool_plugin.rb").content
    refute(entries.keys.any? { |path| path.include?("/bin/") }, "no executables for a shell")

    spec = eval(entries.fetch("#{gems}/specifications/tool-1.2.0.gemspec").content, binding, "tool.gemspec")
    assert_equal ["tool", "1.2.0", Gem::VERSION], [spec.name, spec.version.to_s, spec.installed_by_version.to_s]
  end

  def test_reads_a_platform_gems_name_and_its_license_files
    built = FakeGem.build(@dir, "native", "2.0.0", platform: "x64-mingw-ucrt",
      files: { "lib/native.rb" => "", "LICENSE" => "BSD\n", "LICENSE-DEPENDENCIES.md" => "SQLite is public domain\n", "docs/LICENSE.md" => "" })
    package = Fledge::GemPackage.new(built.path)

    assert_equal "native-2.0.0-x64-mingw-ucrt", package.spec.full_name
    assert_equal({ "LICENSE" => "BSD\n", "LICENSE-DEPENDENCIES.md" => "SQLite is public domain\n" }, package.license_files)
    assert_equal "ruby/lib/ruby/gems/4.0.0/gems/native-2.0.0-x64-mingw-ucrt/lib/native.rb",
      package.entries("ruby/lib/ruby/gems/4.0.0").map(&:path).grep(/native\.rb\z/).first
  end

  def test_says_what_keeps_a_gem_from_the_target
    compiled = Fledge::GemPackage.new(FakeGem.build(@dir, "c", extensions: ["ext/c/extconf.rb"], files: { "ext/c/extconf.rb" => "" }).path)
    old = Fledge::GemPackage.new(FakeGem.build(@dir, "old", required_ruby_version: [">= 3.1", "< 3.5"]).path)
    fine = Fledge::GemPackage.new(FakeGem.build(@dir, "fine", required_ruby_version: ">= 3.2").path)

    assert_equal [
"c 1.0.0 has a C extension, which would have to be compiled for aarch64-linux, and the lockfile locks no build " \
  "of it precompiled for aarch64-linux. Fledge ships only precompiled native gems for now: choose a version of c with a " \
  "build for aarch64-linux, and run bundle lock --add-platform aarch64-linux.",
], compiled.problems(platform: "aarch64-linux", ruby_version: "4.0.9")
    assert_equal ["old 1.0.0 needs Ruby >= 3.1, < 3.5, and Fledge's runtime is Ruby 4.0.9."], old.problems(platform: "x", ruby_version: "4.0.9")
    assert_empty fine.problems(platform: "x", ruby_version: "4.0.9")
  end

  def test_a_file_that_is_not_a_gem_is_refused
    path = File.join(@dir, "broken.gem")
    File.write(path, "not a gem")

    error = assert_raises(Fledge::Error) { Fledge::GemPackage.new(path) }
    assert_match(/\A#{Regexp.escape(path)} is not a gem RubyGems can install: /, error.message)
  end

  def test_a_gem_whose_contents_were_changed_is_refused
    built = FakeGem.build(@dir, "tampered")
    members = File.open(built.path, "rb") do |io|
      Gem::Package::TarReader.new(io).to_h { |entry| [entry.full_name, entry.read] }
    end
    tar = StringIO.new(+"".b)
    Gem::Package::TarWriter.new(tar) { |writer| writer.add_file("lib/tampered.rb", 0o644) { |file| file.write("raise 'changed'\n") } }
    members["data.tar.gz"] = Zlib.gzip(tar.string)
    File.open(built.path, "wb") do |io|
      Gem::Package::TarWriter.new(io) { |tar| members.each { |name, bytes| tar.add_file(name, 0o444) { |file| file.write(bytes) } } }
    end

    error = assert_raises(Fledge::Error) { Fledge::GemPackage.new(built.path) }
    assert_match(/\A#{Regexp.escape(built.path)} is not a gem RubyGems can install: .*checksum/i, error.message)
  end
end
