# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "test_helper"
require "yaml"

# Every GitHub Release carries the .gem built from its tag, for a developer
# to install when RubyGems.org is down (doc/contributors/design/releases.md,
# "release.yml").
class WorkflowReleaseGemTest < Minitest::Test
  WORKFLOW = File.expand_path("../.github/workflows/release.yml", __dir__)

  def jobs = YAML.safe_load_file(WORKFLOW, aliases: true).fetch("jobs")

  def test_the_check_job_builds_the_gem_and_keeps_it_apart_from_the_runtimes
    steps = jobs.fetch("check").fetch("steps")

    assert(steps.any? { |step| step["run"].to_s.include?("gem build fledge.gemspec") })
    upload = steps.find { |step| step.dig("with", "name") == "release-gem" }

    refute_nil upload
  end

  def test_the_publish_job_attaches_the_gem_named_for_the_version
    steps = jobs.fetch("release").fetch("steps")
    create = steps.find { |step| step["run"].to_s.include?("gh release create") }

    assert(steps.any? { |step| step.dig("with", "name") == "release-gem" })
    assert_includes create.fetch("run"), "gem/fledge-$VERSION.gem"
    assert(steps.any? { |step| step["run"].to_s.include?('"fledge-$VERSION.gem"') })
  end
end
