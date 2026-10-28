# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "test_helper"

# Real precompiled gems, downloaded from RubyGems.org and pinned by
# SHA-256, as fledge build would fetch them, checked as fledge build
# checks every gem an app ships: whether their compiled files would load
# where the app goes (Fledge::Linkage). They are kept in tmp/native-gems
# between runs.
#
# nokogiri's builds for macOS and Windows compile GNU libiconv in
# statically (nokogiri's LICENSE-DEPENDENCIES.md at 1.19.4). Fledge
# refused them for it until the maintainer ruled, on 2026-10-28, that the
# licenses of an app's gems are its developer's to judge, not Fledge's
# (ADR 007). Now they ship like every other build.
class NativeGemsTest < Minitest::Test
  CACHE = File.expand_path("../tmp/native-gems", __dir__)

  GEMS = {
    "nokogiri-1.19.4-arm64-darwin" => "a46db9853286e6597b36ebc6953817d15acf3a299583eb3f89fdc6f91dd63527",
    "nokogiri-1.19.4-x64-mingw-ucrt" => "051da97b8eccfdb5444fed40246a35e10d7298b9efe759b4cd25455ea04c587e",
    "nokogiri-1.19.4-x86_64-linux-gnu" => "379fae440b28915e3f19d752ce2dcf8465ed2b2fbefd2a7ca0dd497bc981a06a",
    "nokogiri-1.19.4-aarch64-linux-gnu" => "1269fb644a6de405057a53dd5c762b1209b43ca7424f839454d3dbc677c31a8f",
    "sqlite3-2.10.2-arm64-darwin" => "5b0d235ea037e6dcd1b8387a19d73be571917db9f93044d35741cf933a21a37d",
    "sqlite3-2.10.2-x64-mingw-ucrt" => "7fe1bf1adfca4fffeaec27371e0a20c1162d9d985681ec9560971a44fc41d198",
    "sqlite3-2.10.2-x86_64-linux-gnu" => "ca92731ab464df9cae503fa1a439a549e2724f6953c8c05a7769b59366e38f15",
    "sqlite3-2.10.2-aarch64-linux-gnu" => "e9aea2c2b3476fc875dd8a89313a9a2862818519c0186bfb5b56d6f57bb08d98",
    "ratatui_ruby-1.5.2-arm64-darwin" => "4f61e09ec6a81c5cc557b9b17fd78a4f99974017562c7275bee06a49af3f5cf6",
    "ratatui_ruby-1.5.2-x64-mingw-ucrt" => "e3279373e2cc02435a4e3a9ecfd9c72f1cf300019d946f67504f7fabbad46612",
  }.freeze

  def problems(full_name, os:, provided: [])
    path = File.join(CACHE, "#{full_name}.gem")
    Fledge::Download.save("https://rubygems.org/gems/#{full_name}.gem", to: path, sha256: GEMS.fetch(full_name)) unless File.file?(path)
    Fledge::Linkage.new(os:, provided:).problems(full_name, Fledge::GemPackage.new(path).contents)
  end

  # What a runtime ships beside Ruby's own DLL on Windows, which a gem's
  # extension may load (runtime/licenses.yml).
  WINDOWS = %w[x64-ucrt-ruby400.dll libwinpthread-1.dll].freeze

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

  # ratatui_ruby's precompiled builds are Rust extensions built for each
  # Ruby from 3.2 to 4.0 (lib/ratatui_ruby/RUBY/); those for older Rubies
  # on Windows need those Rubies' DLLs, which the runtime's Ruby never
  # loads, and the one for Ruby 4.0 loads what the runtime ships.
  def test_ratatui_rubys_builds_ship
    assert_empty problems("ratatui_ruby-1.5.2-arm64-darwin", os: "darwin")
    assert_empty problems("ratatui_ruby-1.5.2-x64-mingw-ucrt", os: "windows", provided: WINDOWS)
  end

  # Judged for another operating system, the same files need libraries it
  # does not have, which shows the check reads the real files.
  def test_a_build_for_another_system_would_not_load
    refute_empty problems("nokogiri-1.19.4-arm64-darwin", os: "linux")
  end
end
