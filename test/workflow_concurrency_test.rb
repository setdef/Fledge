# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "test_helper"
require "yaml"

# How CI's runs queue (doc/contributors/design/releases.md, "Runs,
# batches, and the release commit"): a push to trunk never
# cancels a run in progress there, a release or pin commit's run waits
# behind no other run and no push replaces it, and the fast tier runs
# on every push to trunk and judges each alone, its macOS leg in a
# workflow of its own.
class WorkflowConcurrencyTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  # Only a branch other than trunk cancels the run in progress; GitHub
  # names trunk as the repository's default branch.
  BRANCHES_ONLY = "${{ github.ref != format('refs/heads/{0}', github.event.repository.default_branch) }}"

  # The fast tier's workflows: the lint and the Linux and Windows unit
  # tests, and the macOS unit tests.
  FAST_TIER = %w[fast.yml fast-macos.yml].freeze

  def test_ci_cancels_runs_in_progress_on_branches_only
    assert_equal BRANCHES_ONLY, workflow("ci.yml").dig("concurrency", "cancel-in-progress")
  end

  # Every other push to trunk shares one group, so GitHub keeps one run
  # going and one waiting, and a newer push replaces the waiting one.
  # A release or pin commit's run gets a group of its own, named for its
  # commit, so it starts at once and nothing replaces it.
  def test_ci_gives_release_and_pin_commits_a_group_of_their_own
    group = workflow("ci.yml").dig("concurrency", "group")

    assert_includes group, "${{ github.workflow }}-${{ github.ref }}"
    assert_includes group, "startsWith(github.event.head_commit.message, 'chore: release ')"
    assert_includes group, "startsWith(github.event.head_commit.message, 'chore: pin ')"
    assert_includes group, "format('-{0}', github.sha)"
  end

  def test_fast_tier_cancels_on_branches_only_and_gives_each_trunk_push_a_group
    FAST_TIER.each do |name|
      concurrency = workflow(name).fetch("concurrency")

      assert_equal BRANCHES_ONLY, concurrency.fetch("cancel-in-progress"), name
      assert_includes concurrency.fetch("group"), "github.sha", name
      assert_equal [{ "branches" => ["**"] }, nil], workflow(name).fetch(true).values_at("push", "pull_request"), name
    end
  end

  # The macOS leg is a workflow of its own, so its wait for a macOS
  # runner never holds the verdict of the lint, the package check, and
  # the Linux and Windows unit tests. The package check is the one check
  # of the tier that loads Fledge as an installed gem.
  def test_fast_tier_runs_the_lint_the_package_check_and_the_unit_tests_on_linux_and_windows_and_macos_alone
    assert_equal %w[ubuntu-24.04 windows-latest], runners("fast.yml").uniq.sort
    assert_includes commands("fast.yml"), "bundle exec rake lint steep package:check"
    assert_equal 2, commands("fast.yml").count("bundle exec rake test")
    assert_equal %w[macos-26], runners("fast-macos.yml")
    assert_equal ["bundle exec rake test"], commands("fast-macos.yml").grep(/\Abundle exec rake/)
  end

  private def runners(name)
    workflow(name).fetch("jobs").values.flat_map { |job| job.dig("strategy", "matrix", "os") || [job.fetch("runs-on")] }
  end

  private def commands(name)
    workflow(name).fetch("jobs").values.flat_map { |job| job.fetch("steps").filter_map { |step| step["run"] } }
  end

  private def workflow(name)
    YAML.load_file(File.join(ROOT, ".github", "workflows", name), aliases: true)
  end
end
