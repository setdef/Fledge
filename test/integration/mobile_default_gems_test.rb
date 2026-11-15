# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "../test_helper"
require_relative "../../tasks/runtime_builder"
require "rubygems/package"
require "zlib"

# The default gems of the phone runtimes rake runtime[ios] and
# runtime[android] built (ADR 079), read from the archives they wrote;
# test/mobile_runtime_test.rb checks the parts that need no runtime.
class MobileDefaultGemsTest < Minitest::Test
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
    assert_default_gems_list_their_files_as_a_desktops_do("ios")
  end

  def test_an_android_runtimes_default_gems_list_their_files_as_a_desktops_do
    assert_default_gems_list_their_files_as_a_desktops_do("android")
  end

  def assert_default_gems_list_their_files_as_a_desktops_do(name)
    slices = default_specifications(name)
    assert_equal mobile(name).targets.size, slices.size, slices.keys.inspect
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
    skip "no #{File.basename(archive)} in #{dir}; run bundle exec rake runtime[#{name}]" unless File.file?(archive)

    slices = Hash.new { |hash, key| hash[key] = {} }
    Dir.mktmpdir do |work|
      Zlib::GzipReader.open(archive) do |gzip|
        Gem::Package::TarReader.new(gzip).each.with_index do |entry, index|
          slice, file = entry.full_name.match(%r{\A(.*)/lib/ruby/gems/[^/]+/specifications/default/([^/]+\.gemspec)\z})&.captures
          next unless file

          path = File.join(work, "#{index}-#{file}")
          File.binwrite(path, entry.read)
          spec = Gem::Specification.load(path) or flunk "#{entry.full_name} is no gemspec"
          slices[slice][spec.name] = spec
        end
      end
    end
    slices
  end
end
