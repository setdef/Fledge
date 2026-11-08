# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "test_helper"

# Fledge::WindowsResources's strings, which rcedit writes on Windows,
# where assembly_test.rb reads them back with (Get-Item).VersionInfo.
class WindowsResourcesTest < Minitest::Test
  def identity(**about)
    Fledge::Identity.new(name: "My App", kind: "windowed", identifier: "com.example.MyApp", version: "1.2.3", publisher: "Me",
      copyright: nil, icon: nil, description: nil, long_description: nil, homepage: nil, file_associations: [], **about)
  end

  # The description is the Comments string, which Explorer's Properties
  # dialog shows; an app without one has none.
  def test_the_description_is_the_comments_string
    expected = %w[CompanyName FileDescription InternalName OriginalFilename ProductName].zip(["Me", "My App", "My App", "My App.exe", "My App"]).to_h
    assert_equal expected, Fledge::WindowsResources.strings(identity, "My App.exe")
    assert_equal "Says hello", Fledge::WindowsResources.strings(identity(description: "Says hello"), "My App.exe")["Comments"]
  end
end
