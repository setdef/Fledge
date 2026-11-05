# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "test_helper"

class RuntimeGemTest < Minitest::Test
  # What RubyGems calls each computer Fledge builds on: the platform it
  # reports there (Gem::Platform.local) for each Fledge platform.
  LOCAL = {
    "arm64-darwin" => "arm64-darwin-24",
    "x86_64-linux" => "x86_64-linux",
    "aarch64-linux" => "aarch64-linux",
    "x86_64-linux-musl" => "x86_64-linux-musl",
    "aarch64-linux-musl" => "aarch64-linux-musl",
    "x64-mingw-ucrt" => "x64-mingw-ucrt",
    "aarch64-mingw-ucrt" => "aarch64-mingw-ucrt",
  }.freeze

  def test_every_desktop_platform_shares_one_gem_name_and_each_phone_has_its_own
    assert_equal ["fledge-runtime"], Fledge::Platform.names.map { |name| Fledge::RuntimeGem.new(target: name).name }.uniq
    assert_equal %w[fledge-runtime-ios fledge-runtime-android],
      %w[ios android].map { |name| Fledge::RuntimeGem.for(Fledge::MobilePlatform.find(name)).name }
  end

  def test_a_phones_gem_is_for_any_computer
    assert_equal %w[ruby ruby], %w[ios android].map { |name| Fledge::RuntimeGem.new(target: name).platform }
    refute Fledge::RuntimeGem.new(target: "ios").desktop?
  end

  # The reason glibc Linux's gem says -gnu: RubyGems would install a gem
  # for plain x86_64-linux on musl Linux too. Each desktop platform's gem
  # must install on that platform's computers and on no other's.
  def test_rubygems_installs_each_desktop_gem_on_its_own_platform_and_no_other
    LOCAL.each do |target, local|
      gem = Gem::Platform.new(Fledge::RuntimeGem.new(target:).platform)
      LOCAL.each do |other, other_local|
        assert_equal target == other, gem === Gem::Platform.new(other_local),
          "#{gem} on #{other_local} (#{other}), from the gem for #{target}"
      end
      assert_equal target, Fledge::Platform.local(Gem::Platform.new(local)).name
    end
    assert Gem::Platform.new("x86_64-linux") === Gem::Platform.new("x86_64-linux-musl"),
      "RubyGems no longer installs a plain linux gem on musl; the -gnu suffix could go"
  end
end
