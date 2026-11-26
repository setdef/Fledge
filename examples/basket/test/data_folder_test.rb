# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT-0
#++

# Minitest's tests of where Basket keeps its list: bundle exec ruby
# test/data_folder_test.rb on your computer, and inside the app on a
# phone, where test/phone.rb runs it, so that the phone's folder is the
# one it checks.

require "minitest/autorun"
require "fileutils"
require "tmpdir"
require_relative "../lib/basket/data_folder"
require_relative "../lib/basket/list"

# The tests of Basket::DataFolder.
class DataFolderTest < Minitest::Test
  # The folder each system keeps an app's data in, from that system's
  # documentation and not from Etcetera: Apple's File System Programming
  # Guide ("The Library Directory Stores App-Specific Files": Application
  # Support), Microsoft's Known Folders (FOLDERID_RoamingAppData, which
  # %APPDATA% holds), and the XDG Base Directory Specification
  # ($XDG_DATA_HOME, or $HOME/.local/share when it is empty or not
  # absolute).
  def expected_folder
    if Gem.win_platform?
      File.join(ENV.fetch("APPDATA"), "setdef", "Basket", "data")
    elsif RUBY_PLATFORM.include?("darwin")
      File.join(Dir.home, "Library", "Application Support", "com.setdef.Basket")
    else
      home = ENV["XDG_DATA_HOME"].to_s
      File.join(home.start_with?("/") ? home : File.join(Dir.home, ".local", "share"), "basket")
    end
  end

  # The list's file is basket.json in the system's folder for app data.
  def test_the_list_is_kept_where_the_system_keeps_an_apps_data
    assert_equal File.join(expected_folder, "basket.json"), File.expand_path(Basket::DataFolder.list_path)
  end

  # A system makes none of that folder for an app, so the first item makes
  # it, as an iOS app's Library/Application Support is not there at first.
  def test_a_list_makes_its_folder_when_it_first_saves
    dir = Dir.mktmpdir
    path = File.join(dir, "Library", "Application Support", "basket.json")
    Basket::List.new(path).add("Milk")

    assert_equal ["Milk"], Basket::List.new(path).items
  ensure
    FileUtils.rm_rf(dir)
  end
end
