# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "../test_helper"
require_relative "../../tasks/runtime_builder"

# RuntimeBuilder::RubyDescription reading the Ruby of an Android runtime
# out of its AAR, a zip, with the unzip program, as the license audit
# does. The test packs a real AAR with zip, so it needs both programs, which
# the computers that build Android runtimes (Linux and macOS) have, and
# which a Windows computer may not.
class RubyDescriptionAarTest < Minitest::Test
  def test_an_android_runtimes_ruby_description_is_read_from_the_libraries_in_its_aar
    skip "an Android runtime is built on Linux and macOS, which have zip and unzip" if Gem.win_platform?

    preview = "ruby 4.1.0preview1 (2026-10-11 master 2d08b5f42f)"
    Dir.mktmpdir do |stage|
      aar = File.join(stage, "aar")
      { "arm64-v8a" => "aarch64-linux-android", "x86_64" => "x86_64-linux-android" }.each do |abi, platform|
        FileUtils.mkdir_p(File.join(aar, "jni", abi))
        File.binwrite(File.join(aar, "jni", abi, "libfledgeruby.so"), "\x7FELF\0#{preview} [#{platform}]\0".b)
      end
      system("zip", "-q", "-r", File.join(stage, "FledgeRuby.aar"), "jni", chdir: aar, exception: true)
      FileUtils.rm_rf(aar)

      assert_equal preview, RuntimeBuilder::RubyDescription.read(stage)
    end
  end
end
