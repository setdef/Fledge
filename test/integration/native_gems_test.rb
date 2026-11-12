# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "../test_helper"

# Real precompiled gems, downloaded from RubyGems.org and pinned by
# SHA-256, as fledge build would fetch them, checked as fledge build
# checks every gem an app ships: whether their compiled files would load
# where the app goes (Fledge::Linkage). They are kept in tmp/native-gems
# between runs.
#
# nokogiri's and sqlite3's builds hold extensions for Rubies up to 4.0.
# Their Linux and macOS files name no Ruby, so each is judged; their
# Windows files each name their Ruby's DLL, which a runtime of Ruby 4.1
# never loads, so none is. libusb's Windows builds need no Ruby at all,
# so they fit Ruby 4.1 and are judged.
#
# nokogiri's builds for macOS and Windows compile GNU libiconv in
# statically (nokogiri's LICENSE-DEPENDENCIES.md at 1.19.4). Fledge
# refused them for it until the maintainer ruled, on 2026-10-28, that the
# licenses of an app's gems are its developer's to judge, not Fledge's
# (ADR 007). Now they ship like every other build.
class NativeGemsTest < Minitest::Test
  CACHE = File.expand_path("../../tmp/native-gems", __dir__)

  GEMS = {
    "nokogiri-1.19.4-arm64-darwin" => "a46db9853286e6597b36ebc6953817d15acf3a299583eb3f89fdc6f91dd63527",
    "nokogiri-1.19.4-x64-mingw-ucrt" => "051da97b8eccfdb5444fed40246a35e10d7298b9efe759b4cd25455ea04c587e",
    "nokogiri-1.19.4-x86_64-linux-gnu" => "379fae440b28915e3f19d752ce2dcf8465ed2b2fbefd2a7ca0dd497bc981a06a",
    "nokogiri-1.19.4-aarch64-linux-gnu" => "1269fb644a6de405057a53dd5c762b1209b43ca7424f839454d3dbc677c31a8f",
    "sqlite3-2.10.2-arm64-darwin" => "5b0d235ea037e6dcd1b8387a19d73be571917db9f93044d35741cf933a21a37d",
    "sqlite3-2.10.2-x64-mingw-ucrt" => "7fe1bf1adfca4fffeaec27371e0a20c1162d9d985681ec9560971a44fc41d198",
    "sqlite3-2.10.2-x86_64-linux-gnu" => "ca92731ab464df9cae503fa1a439a549e2724f6953c8c05a7769b59366e38f15",
    "sqlite3-2.10.2-aarch64-linux-gnu" => "e9aea2c2b3476fc875dd8a89313a9a2862818519c0186bfb5b56d6f57bb08d98",
    "libusb-0.8.0-x64-mingw-ucrt" => "216ad4b95bc2cf9446c8c49ccb8b1ed92af2069caf2888cbb4a1f7792a1ba7ef",
    "libusb-0.8.0-aarch64-mingw-ucrt" => "727af569f7764c9ab2ac9f76cd43b2469373f0d73243bffcef4e505f8a4046fe",
  }.freeze

  def contents(full_name)
    path = File.join(CACHE, "#{full_name}.gem")
    Fledge::Download.save("https://rubygems.org/gems/#{full_name}.gem", to: path, sha256: GEMS.fetch(full_name)) unless File.file?(path)
    Fledge::GemPackage.new(path).contents
  end

  def problems(full_name, os:, provided: [])
    Fledge::Linkage.new(os:, provided:, readers: TestReaders.all).problems(full_name, contents(full_name))
  end

  # Skips unless a tool here reads every format these gems hold.
  def setup
    TestReaders.need(self, :elf, :macho, :pe)
  end

  # What a runtime ships beside Ruby's own DLL on Windows, which a gem's
  # extension may load (runtime/licenses.yml).
  WINDOWS = %w[x64-ucrt-ruby410.dll libwinpthread-1.dll].freeze

  def os_of(full_name)
    case full_name
    when /darwin\z/ then "darwin"
    when /mingw-ucrt\z/ then "windows"
    else "linux"
    end
  end

  def test_nokogiris_builds_ship_on_every_platform_libiconv_and_all
    GEMS.keys.grep(/\Anokogiri-/).each do |gem|
      os = os_of(gem)

      assert_empty problems(gem, os:, provided: (os == "windows") ? WINDOWS : []), gem
    end
  end

  def test_sqlite3s_builds_ship_on_every_platform
    GEMS.keys.grep(/\Asqlite3-/).each do |gem|
      os = os_of(gem)

      assert_empty problems(gem, os:, provided: (os == "windows") ? WINDOWS : []), gem
    end
  end

  # libusb's Windows builds carry libusb-1.0.dll, which ffi loads and
  # which needs no Ruby, so they fit Ruby 4.1, and examples/native_app
  # ships the x64 one. Every file in them is judged, and each needs only
  # what Windows provides.
  def test_libusbs_windows_builds_ship_and_need_nothing_from_the_runtime
    GEMS.keys.grep(/\Alibusb-/).each do |gem|
      assert_empty problems(gem, os: "windows"), gem
    end
  end

  # sqlite3's Windows build holds one extension for each Ruby from 3.2 to
  # 4.0 (lib/sqlite3/RUBY/), each naming its Ruby's DLL, and those for 3.2
  # to 3.4 also need MinGW's libwinpthread-1.dll. A runtime of Ruby 4.1
  # loads none of them, so none is judged; a runtime of Ruby 3.4 that
  # carried no libwinpthread-1.dll would load the one for 3.4, which could
  # not find it.
  def test_a_windows_build_is_judged_only_for_the_runtimes_own_ruby
    assert_empty problems("sqlite3-2.10.2-x64-mingw-ucrt", os: "windows", provided: WINDOWS)

    found = problems("sqlite3-2.10.2-x64-mingw-ucrt", os: "windows", provided: %w[x64-ucrt-ruby340.dll])

    assert_equal 1, found.size, found.inspect
    assert_match %r{lib/sqlite3/3\.4/sqlite3_native\.so needs libwinpthread-1\.dll}, found.first
  end

  # The check reads the real files: each Ruby's build of nokogiri for
  # Linux links glibc, and for macOS libSystem, and for Windows names the
  # Ruby DLL it was built for.
  def test_the_real_files_are_read
    linux = Fledge::Binary.parse(contents("nokogiri-1.19.4-x86_64-linux-gnu"), readers: TestReaders.all).values
    macos = Fledge::Binary.parse(contents("nokogiri-1.19.4-arm64-darwin"), readers: TestReaders.all).values
    windows = Fledge::Binary.parse(contents("nokogiri-1.19.4-x64-mingw-ucrt"), readers: TestReaders.all).values

    refute_empty linux
    assert(linux.all? { |binary| binary.needed.include?("libc.so.6") && binary.glibc_minimum })
    assert(macos.all? { |binary| binary.needed.include?("/usr/lib/libSystem.B.dylib") && binary.macos_minimum })
    assert(windows.all? { |binary| binary.needed.any? { |library| library.match?(Fledge::Linkage::RUBY_DLL) } })
  end
end
