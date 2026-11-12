# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "test_helper"
require_relative "support/short_path"

# A path named by its folders' long names, which fledge build makes its
# work folder in, where Windows' TMP names a user folder by its 8.3 name.
class LongPathTest < Minitest::Test
  def setup
    @dir = Dir.mktmpdir
  end

  def teardown
    FileUtils.rm_rf(@dir)
  end

  # A short name anywhere in the path, not only in its last part, which
  # is all File.expand_path makes long.
  def test_every_folder_of_a_short_path_gets_its_long_name
    long = File.join(@dir, "longfoldername", "child")
    FileUtils.mkdir_p(long)
    short = ShortPath.of(File.dirname(long))
    skip "no 8.3 names here: off Windows, or 8.3 names are turned off on #{@dir}'s volume" unless short

    assert_equal File.join(Fledge::LongPath.of(@dir), "longfoldername", "child"), Fledge::LongPath.of(File.join(short, "child"))
  end

  def test_a_path_with_long_names_already_is_the_same_path
    path = File.join(Fledge::LongPath.of(@dir), "app", "missing")
    FileUtils.mkdir_p(File.dirname(path))

    assert_equal path, Fledge::LongPath.of(path)
    assert_equal File.absolute_path("/"), Fledge::LongPath.of("/")
  end

  # A folder whose name begins with a tilde is that folder, not a home.
  def test_a_tilde_is_a_name
    path = File.join(Fledge::LongPath.of(@dir), "~build")

    assert_equal path, Fledge::LongPath.of(path)
  end
end
