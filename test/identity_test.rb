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

  def test_reads_the_icon_from_the_projects_root
    Dir.mktmpdir do |dir|
      File.binwrite(File.join(dir, "icon.png"), Fledge::Png.new(width: 1024, height: 1024, pixels: "\0".b * (1024 * 1024 * 4)).encode)
      identity = Fledge::Identity.from(config: config(icon: "icon.png"), gemspec: nil, name: "Hi", root: dir)
      assert_equal 16, identity.icon.image(16).width

      error = assert_raises(Fledge::Error) { Fledge::Identity.from(config: config(icon: "missing.png"), gemspec: nil, name: "Hi", root: dir) }
      assert_equal "the icon #{File.join(dir, 'missing.png')} does not exist", error.message
    end
  end
end
