# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "test_helper"
require_relative "../examples/lent/lib/data_folder"

# examples/lent keeps its database, log, and secret in the person's own
# data folder, as doc/desktop_apps.md says a desktop app does: never in
# the app's folder, which an update replaces and which may be read-only.
class LentDataFolderTest < Minitest::Test
  def test_on_macos_it_is_in_application_support
    assert_equal "/Users/ada/Library/Application Support/Lent",
      DataFolder.for("Lent", platform: "arm64-darwin24", env: {}, home: "/Users/ada")
  end

  def test_on_windows_it_is_in_appdata
    assert_equal 'C:\Users\ada\AppData\Roaming/Lent',
      DataFolder.for("Lent", platform: "x64-mingw-ucrt", env: { "APPDATA" => 'C:\Users\ada\AppData\Roaming' }, home: "C:/Users/ada")
  end

  def test_on_linux_it_is_in_xdg_data_home_in_lower_case
    assert_equal "/data/ada/lent",
      DataFolder.for("Lent", platform: "x86_64-linux", env: { "XDG_DATA_HOME" => "/data/ada" }, home: "/home/ada")
  end

  def test_on_linux_without_xdg_data_home_it_is_in_local_share
    assert_equal "/home/ada/.local/share/lent", DataFolder.for("Lent", platform: "x86_64-linux", env: {}, home: "/home/ada")
  end

  # The XDG Base Directory Specification (0.8): an empty XDG_DATA_HOME
  # means its default, and a relative one is invalid and is ignored.
  def test_on_linux_an_empty_or_relative_xdg_data_home_is_ignored
    ["", "data"].each do |value|
      assert_equal "/home/ada/.local/share/lent",
        DataFolder.for("Lent", platform: "x86_64-linux", env: { "XDG_DATA_HOME" => value }, home: "/home/ada")
    end
  end
end
