# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "test_helper"

class GitGemTest < Minitest::Test
  REVISION = "21a106d0c0d6c7f822476ab12102f31efcaa17d1"

  def gem(uri, ref: nil)
    Fledge::GitGem.new(name: "ferro-idna", version: "0.1.0.pre.1", uri:, revision: REVISION, glob: "gems/*/*.gemspec", ref:)
  end

  # Bundler's own folder names for a checkout, which a built app's
  # Bundler looks for (Bundler::Source::Git#install_path).
  def test_names_its_checkout_as_bundler_does
    assert_equal "Ferro-21a106d0c0d6", gem("https://github.com/setdef/Ferro").scope
    assert_equal "Ferro-21a106d0c0d6", gem("https://github.com/setdef/Ferro.git").scope
    assert_equal "ferro-21a106d0c0d6", gem("git@github.com:setdef/ferro.git").scope
    assert_equal "repo-21a106d0c0d6", gem("file:///tmp/some/repo").scope
  end

  def test_says_where_it_came_from
    assert_equal "ferro-idna-0.1.0.pre.1", gem("https://github.com/setdef/Ferro").full_name
    assert_equal "ferro-idna 0.1.0.pre.1", gem("https://github.com/setdef/Ferro").to_s
    assert_equal "https://github.com/setdef/Ferro at #{REVISION} (tag ferro-idna/v0.1.0.pre.1)",
      gem("https://github.com/setdef/Ferro", ref: "tag ferro-idna/v0.1.0.pre.1").url
    assert_equal "https://github.com/setdef/Ferro at #{REVISION}", gem("https://github.com/setdef/Ferro").url
  end
end
