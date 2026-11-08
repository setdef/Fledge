# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "test_helper"
require "open3"

# What the built .gem holds, which is only what the gemspec's file list
# packs. A git checkout has every file, so installing from a tag cannot
# show a file the list forgot; a gem from RubyGems.org can (Plan 003,
# "Fledge on RubyGems.org"). rake package:check installs the gem and
# runs it; this names what the code reads beside itself.
class GemContentsTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  PACKED = Gem::Specification.load(File.join(ROOT, "fledge.gemspec")).files.freeze

  # Each file the code reads from beside itself, by the constant that
  # holds its path, and for a folder every file git tracks in it.
  READ_BESIDE_THE_CODE = [
    Fledge::Runtimes::PINS,
    Fledge::MacSigning::ENTITLEMENTS,
    Fledge::MobileProject::TEMPLATES,
    File.join(ROOT, "lib", "fledge", "config.schema.json"),
  ].freeze

  def tracked(*paths)
    out, status = Open3.capture2("git", "ls-files", "-z", "--", *paths, chdir: ROOT)
    assert_predicate status, :success?
    out.split("\0")
  end

  def relative(path)
    File.realpath(path).delete_prefix("#{File.realpath(ROOT)}/")
  end

  def test_the_gem_packs_every_file_of_lib_and_exe
    assert_empty tracked("lib", "exe") - PACKED
  end

  def test_the_gem_packs_each_file_the_code_reads_beside_itself
    READ_BESIDE_THE_CODE.map { |path| relative(path) }.each do |path|
      files = File.directory?(File.join(ROOT, path)) ? tracked(path) : [path]

      refute_empty files, "#{path} holds no file git tracks"
      assert_empty files - PACKED, "the gem does not pack what #{path} needs"
    end
  end

  def test_the_gem_packs_both_phones_templates_and_the_gradle_wrapper
    expected = %w[
      lib/fledge/templates/ios/project.yml
      lib/fledge/templates/android/build.gradle
      lib/fledge/templates/android/gradlew
      lib/fledge/templates/android/gradle/wrapper/gradle-wrapper.jar
    ]

    assert_empty expected - PACKED
  end

  # A new file read from beside the code joins READ_BESIDE_THE_CODE, or
  # nothing here would notice the gem not packing it.
  def test_the_code_reads_beside_itself_only_through_those_constants
    readers = tracked("lib").grep(/\.rb\z/).flat_map do |file|
      File.readlines(File.join(ROOT, file)).grep(/\A[^#]*(?:File\.dirname\(__FILE__\)|__dir__)/).map { |line| "#{file}: #{line.strip}" }
    end

    assert_equal [
      %(lib/fledge/mac_signing.rb: ENTITLEMENTS = File.join(File.dirname(__FILE__), "templates", "macos", "entitlements.plist")),
      %(lib/fledge/mobile_project.rb: TEMPLATES = File.join(File.dirname(__FILE__), "templates")),
      %(lib/fledge/runtimes.rb: PINS = File.join(File.dirname(__FILE__), "SHA256SUMS")),
    ], readers.sort
  end
end
