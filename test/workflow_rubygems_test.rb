# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "test_helper"
require "yaml"

# The one job that may publish Fledge on RubyGems.org, release.yml's
# last, which runs only once the maintainer has set RubyGems.org to trust
# the workflow, only from 1.0.0, and only after the release is installed
# and delivered from on every platform.
class WorkflowRubygemsTest < Minitest::Test
  WORKFLOWS = File.expand_path("../.github/workflows", __dir__)

  def jobs(file) = YAML.safe_load_file(File.join(WORKFLOWS, file), aliases: true).fetch("jobs")

  def pushes?(job) = job.fetch("steps", []).any? { |step| step["run"].to_s.match?(/\bgem push\b/) }

  def test_only_release_yml_pushes_the_gem_and_only_after_every_platform_installed_it
    pushing = Dir.children(WORKFLOWS).sort.flat_map { |file| jobs(file).select { |_, job| pushes?(job) }.keys.map { |name| "#{file} #{name}" } }
    job = jobs("release.yml").fetch("rubygems")

    assert_equal ["release.yml rubygems"], pushing
    assert_equal %w[check installed], job.fetch("needs")
    assert_equal "fledge-gem", job.fetch("steps").first.dig("with", "name"), "the .gem installed.yml built from the tag and installed everywhere"
  end

  def test_the_push_waits_for_the_maintainers_trust_and_for_1_0_0
    job = jobs("release.yml").fetch("rubygems")
    condition = job.fetch("if")

    assert_includes condition, "vars.RUBYGEMS_TRUSTED_PUBLISHING == 'true'"
    assert_includes condition, "!startsWith(needs.check.outputs.version, '0.')"
    assert_includes condition, "(github.event_name == 'push' || inputs.publish)"
    assert_equal({ "contents" => "read", "id-token" => "write" }, job.fetch("permissions"))
    assert_equal "release", job.fetch("environment"), "the environment RubyGems.org's trusted publisher names"
  end
end
