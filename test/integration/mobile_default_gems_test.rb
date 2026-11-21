# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "../test_helper"
require_relative "../../tasks/runtime_builder"
require_relative "../support/android"
require_relative "../support/ios"

# The default gems of the phone runtimes rake runtime[ios] and
# runtime[android] built (ADR 079), read from the archives they wrote;
# test/mobile_runtime_test.rb checks the parts that need no runtime.
# Without a phone's runtime, its test fails instead of skipping where
# FLEDGE_REQUIRE_ANDROID or FLEDGE_REQUIRE_IOS is set (AndroidRequired,
# IOSRequired).
class MobileDefaultGemsTest < Minitest::Test
  include AndroidRequired
  include IOSRequired

  def mobile(name)
    RuntimeBuilder.platform(name)
  end

  # A phone's Ruby is built in its source folder, as rv-ruby builds a
  # desktop's, so that its default gems' specifications list the files a
  # desktop's do (doc/contributors/design/phone-runtimes.md, "Building
  # Ruby for a phone"). Built beside its source, tool/rbinstall.rb put
  # lib/ before each extconf.rb a gemspec lists, and RubyGems'
  # register_default_spec then took io-nonblock for a gem whose files sit
  # under lib/ and left out io/nonblock.bundle, so require "io/nonblock"
  # did not activate the gem; bundler's listed none of its manual pages.
  # These read the runtimes rake runtime[ios] and runtime[android] write,
  # and skip without them.
  def test_an_ios_runtimes_default_gems_list_their_files_as_a_desktops_do
    assert_default_gems_list_their_files_as_a_desktops_do("ios", rubies: mobile("ios").targets.size)
  end

  # An Android runtime holds one lib/ruby, which both ABIs share
  # (doc/contributors/design/phone-runtimes.md, "What a phone runtime
  # holds"), where an iOS one holds a Ruby for each slice.
  def test_an_android_runtimes_default_gems_list_their_files_as_a_desktops_do
    assert_default_gems_list_their_files_as_a_desktops_do("android", rubies: 1)
  end

  def assert_default_gems_list_their_files_as_a_desktops_do(name, rubies:)
    slices = default_specifications(name)
    assert_equal rubies, slices.size, slices.keys.inspect
    slices.each do |slice, specs|
      nonblock = specs.fetch("io-nonblock").files
      assert_includes nonblock, "ext/io/nonblock/extconf.rb", slice
      assert_empty nonblock.grep(%r{\Alib/}), slice
      assert nonblock.any? { |file| file.match?(%r{\Aio/nonblock\.(?:bundle|so)\z}) }, "#{slice}: #{nonblock.inspect}"
      assert_includes specs.fetch("bundler").files, "lib/bundler/man/bundle.1", slice
      specs.each { |gem, spec| assert_empty spec.files.grep(%r{\Alib/ext/}), "#{slice}: #{gem}" }
    end
  end

  # The default gems' specifications in the phone runtime +name+ that
  # tmp/runtime (or FLEDGE_RUNTIME_DIR) holds, by gem name, for each
  # folder of the runtime that holds a Ruby.
  def default_specifications(name)
    dir = ENV.fetch("FLEDGE_RUNTIME_DIR", File.expand_path("../../tmp/runtime", __dir__))
    archive = File.join(dir, Fledge::Runtimes.file_name(Fledge::MobilePlatform.find(name)))
    unless File.file?(archive)
      message = "no #{File.basename(archive)} in #{dir}; run bundle exec rake runtime[#{name}]"
      (name == "android") ? android_missing(message) : ios_missing(message)
    end

    # Read with the computer's tar, as Fledge reads a runtime
    # (Fledge::Archive): GNU tar writes a name longer than 100 bytes as a
    # ././@LongLink entry, which Gem::Package::TarReader does not read.
    specifications = Fledge::Archive.names(archive).grep(%r{/lib/ruby/gems/[^/]+/specifications/default/[^/]+\.gemspec\z})
    slices = Hash.new { |hash, key| hash[key] = {} }
    Dir.mktmpdir do |work|
      Fledge::Archive.unpack(archive, into: work, only: specifications)
      specifications.each do |inside|
        spec = Gem::Specification.load(File.join(work, inside)) or flunk "#{inside} is no gemspec"
        slices[inside[%r{\A(.*)/lib/ruby/gems/}, 1]][spec.name] = spec
      end
    end
    slices
  end
end
