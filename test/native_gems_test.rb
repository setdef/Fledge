# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "test_helper"

# The map of what native gems compile in (lib/fledge/compiled_code.yml),
# checked against the real precompiled gems it describes, downloaded from
# RubyGems.org and pinned by SHA-256, as fledge build would fetch them.
# They are kept in tmp/native-gems between runs.
#
# nokogiri's builds for macOS and Windows compile GNU libiconv in
# statically (nokogiri's LICENSE-DEPENDENCIES.md at 1.19.4), which
# decision 8 forbids, so Fledge refuses them and says why; its builds for
# Linux use the C library's iconv and ship. sqlite3's compile in SQLite,
# which is in the public domain, on every platform.
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
  }.freeze

  def audit(full_name)
    path = File.join(CACHE, "#{full_name}.gem")
    Fledge::Download.save("https://rubygems.org/gems/#{full_name}.gem", to: path, sha256: GEMS.fetch(full_name)) unless File.file?(path)
    package = Fledge::GemPackage.new(path)
    Fledge::CompiledCode.new.audit(package.spec.name, package.contents, label: full_name)
  end

  def test_nokogiri_for_macos_and_windows_is_refused_for_its_static_libiconv
    %w[nokogiri-1.19.4-arm64-darwin nokogiri-1.19.4-x64-mingw-ucrt].each do |gem|
      problems = audit(gem).problems

      assert_equal 1, problems.size, gem
      assert_match(%r{\A#{gem} compiles GNU libiconv's code \(LGPL-2\.1-or-later\) into lib/nokogiri/3\.2/nokogiri\.\w+, }, problems.first)
      assert_includes problems.first, "lib/nokogiri/4.0/nokogiri."
      assert_includes problems.first, "Fledge ships LGPL code only as a separate shared library that a person can replace"
      assert_includes problems.first, "nokogiri's builds for x86_64-linux and aarch64-linux use the C library's iconv"
    end
  end

  def test_nokogiri_for_linux_ships_with_what_it_compiles_in
    %w[nokogiri-1.19.4-x86_64-linux-gnu nokogiri-1.19.4-aarch64-linux-gnu].each do |gem|
      result = audit(gem)

      assert_empty result.problems, gem
      assert_equal ["GCC's runtime library (libgcc)", "libgumbo", "libxml2", "libxslt", "zlib"], result.components.map(&:name).sort, gem
      assert_equal %w[3.2 3.3 3.4 4.0].map { |ruby| "lib/nokogiri/#{ruby}/nokogiri.so" },
        result.components.find { |component| component.name == "libxml2" }.files
    end
  end

  def test_sqlite3_ships_with_sqlite_on_every_platform
    GEMS.keys.grep(/\Asqlite3-/).each do |gem|
      result = audit(gem)

      assert_empty result.problems, gem
      sqlite = result.components.find { |component| component.name == "SQLite" }
      assert_equal "blessing", sqlite&.license, gem
    end
  end
end
