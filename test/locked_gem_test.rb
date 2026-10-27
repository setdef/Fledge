# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "test_helper"

class LockedGemTest < Minitest::Test
  def test_names_a_gem_as_rubygems_and_a_person_do
    native = Fledge::LockedGem.new(name: "sqlite3", version: "2.10.2", platform: "x64-mingw-ucrt", remote: "https://rubygems.org/", sha256: "")
    pure = native.with(name: "i18n", version: "1.15.2", platform: "ruby", remote: "https://gems.example.com")

    assert_equal ["sqlite3-2.10.2-x64-mingw-ucrt", "sqlite3-2.10.2-x64-mingw-ucrt.gem", "sqlite3 2.10.2 (x64-mingw-ucrt)"],
      [native.full_name, native.file_name, native.to_s]
    assert_equal "https://rubygems.org/gems/sqlite3-2.10.2-x64-mingw-ucrt.gem", native.url
    assert_equal ["i18n-1.15.2", "i18n 1.15.2", "https://gems.example.com/gems/i18n-1.15.2.gem"], [pure.full_name, pure.to_s, pure.url]
  end
end
