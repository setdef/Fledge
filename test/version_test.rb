# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "test_helper"

class VersionTest < Minitest::Test
  def gemspec
    Gem::Specification.load(File.expand_path("../fledge.gemspec", __dir__))
  end

  def test_version_is_a_semantic_version
    assert_match(/\A\d+\.\d+\.\d+(?:\.pre\.\d+)?\z/, Fledge::VERSION)
  end

  def test_gemspec_publishes_the_library_version
    assert_equal Fledge::VERSION, gemspec.version.to_s
  end

  # Fledge never publishes to RubyGems.org (ADR 001); a push host that
  # cannot resolve makes gem push refuse instead.
  def test_gemspec_cannot_be_pushed_to_rubygems
    assert_equal "https://fledge.invalid", gemspec.metadata.fetch("allowed_push_host")
  end

  def test_gemspec_installs_the_fledge_executable
    spec = gemspec

    assert_equal ["fledge"], spec.executables
    assert_includes spec.files, "exe/fledge"
    assert_includes spec.files, "lib/fledge/cli.rb"
  end
end
