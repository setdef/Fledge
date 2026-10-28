# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "test_helper"

class IdentityTest < Minitest::Test
  def config(**values)
    Fledge::Config.none.with(**values)
  end

  def gemspec(homepage: nil)
    Gem::Specification.new do |spec|
      spec.name = "my_cool_app"
      spec.version = "0.4.1"
      spec.authors = ["Ada", "Grace"]
      spec.homepage = homepage
    end
  end

  def test_a_project_with_nothing_to_say_is_a_console_app_at_version_0_0_0
    identity = Fledge::Identity.from(config:, gemspec: nil, name: "Hello", root: "/x/hello")
    assert_equal Fledge::Identity.new(name: "Hello", kind: "console", identifier: nil, version: "0.0.0", publisher: nil,
      copyright: nil, icon: nil), identity
    refute_predicate identity, :windowed?
  end

  def test_the_gemspec_gives_the_version_and_publisher_unless_fledge_yml_does
    from_gemspec = Fledge::Identity.from(config:, gemspec:, name: "MyCoolApp", root: "/x")
    assert_equal ["0.4.1", "Ada, Grace"], [from_gemspec.version, from_gemspec.publisher]

    configured = Fledge::Identity.from(config: config(version: "2.0", publisher: "Example, Inc.", copyright: "© Example"),
      gemspec:, name: "MyCoolApp", root: "/x")
    assert_equal ["2.0", "Example, Inc.", "© Example"], [configured.version, configured.publisher, configured.copyright]
  end

  # Tauri, Briefcase, and Flatpak require an identifier; a windowed app
  # does too, and the message suggests Flathub's for a GitHub project.
  def test_a_windowed_app_needs_an_identifier
    error = assert_raises(Fledge::Error) { Fledge::Identity.from(config: config(kind: "windowed"), gemspec: nil, name: "Hello Window", root: "/x") }
    assert_equal "/x/fledge.yml: a windowed app needs an identifier, which macOS and Windows know it by: a reverse-DNS name " \
      "of a domain you control, such as identifier: com.example.HelloWindow", error.message

    error = assert_raises(Fledge::Error) do
      Fledge::Identity.from(config: config(kind: "windowed"), gemspec: gemspec(homepage: "https://github.com/setdef/my_cool_app"),
        name: "MyCoolApp", root: "/x")
    end
    assert_match(/such as identifier: io\.github\.setdef\.MyCoolApp\z/, error.message)

    windowed = Fledge::Identity.from(config: config(kind: "windowed", identifier: "com.example.Hi"), gemspec: nil, name: "Hi", root: "/x")
    assert_predicate windowed, :windowed?
  end

  # The icon names its files without an extension, from the project's
  # root, as Briefcase's does; each platform's build takes its own file,
  # and one that is missing says how to make it.
  def test_the_icon_names_each_systems_file_from_the_projects_root
    Dir.mktmpdir do |dir|
      FakeRuntime.icons(File.join(dir, "art").tap { |art| FileUtils.mkdir_p(art) })
      icon = Fledge::Identity.from(config: config(icon: "art/icon"), gemspec: nil, name: "Hi", root: dir).icon
      assert_equal File.join(dir, "art/icon.icns"), icon.file("icns")
      assert_equal File.join(dir, "art/icon.ico"), icon.file("ico")
      assert_equal File.join(dir, "art/icon-512.png"), icon.png(512)

      missing = Fledge::Identity.from(config: config(icon: "missing"), gemspec: nil, name: "Hi", root: dir).icon
      error = assert_raises(Fledge::Error) { missing.file("icns") }
      assert_equal "the icon missing.icns does not exist. fledge.yml's icon names the icon's files without an extension, as Briefcase's " \
        "does. Make it from PNGs with iconutil -c icns, as a Mac app's icon is made.", error.message
      assert_includes assert_raises(Fledge::Error) { missing.png(16) }.message, "Linux apps take one PNG of each size, -16, -32, -64,"
    end
  end
end
