# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
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

  # Only a person publishes to RubyGems.org
  # (doc/contributors/design/releases.md, "Where releases are"); a push
  # host that cannot resolve makes a stray gem push refuse instead.
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
