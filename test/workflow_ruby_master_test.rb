# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "test_helper"
require "yaml"

# ruby-master.yml builds runtimes from the day's snapshot of Ruby's
# master and reports to one issue (doc/contributors/design/runtimes.md,
# "Testing against Ruby's master"). Each build records its result for
# the report instead of failing its job, so a build that recorded
# nothing, or a job the report does not know, would pass unseen; these
# keep the two lists one.
class WorkflowRubyMasterTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  def workflow
    @workflow ||= YAML.load_file(File.join(ROOT, ".github", "workflows", "ruby-master.yml"), aliases: true)
  end

  # Each job that builds, by the name it records, with its steps.
  def builds
    workflow.fetch("jobs").values.select { |job| job.dig("strategy", "matrix", "include") }.flat_map do |job|
      job.dig("strategy", "matrix", "include").map { |entry| [job.fetch("name").sub("${{ matrix.platform }}", entry.fetch("platform")), job.fetch("steps")] }
    end
  end

  def test_the_report_counts_every_job_that_builds
    report = workflow.dig("jobs", "report", "steps").find { |step| step["run"].to_s.include?("ruby-master-report.sh") }
    named = report.fetch("run").scan(/"([^"]+)"/).flatten

    assert_equal builds.map(&:first).sort, named.sort
    building = workflow.fetch("jobs").select { |_id, job| job.dig("strategy", "matrix", "include") }.keys
    assert_equal building.sort, (workflow.dig("jobs", "report", "needs") - ["snapshot"]).sort
  end

  def test_each_build_takes_the_snapshots_pins_records_its_outcome_and_keeps_it
    builds.each do |name, steps|
      take = steps.index { |step| step["run"].to_s.include?("cp tmp/ruby-master/sources.yml tmp/ruby-master/licenses.yml runtime/") }
      build = steps.index { |step| step["id"] == "build" }
      record = steps.find { |step| step["run"].to_s.include?("ruby-master-result.sh") }

      assert take && build && take < build, "#{name} builds before it takes the snapshot's pins"
      assert steps[build]["continue-on-error"], "#{name}'s build fails its job instead of recording its outcome"
      assert_equal "always()", record["if"], name
      assert_includes record["run"], '"${{ steps.build.outcome }}"', name
      assert steps.any? { |step| step.dig("with", "name").to_s.start_with?("result-") && step["if"] == "always()" }, "#{name} keeps no result"
    end
  end

  def test_its_alpine_is_ci_ymls
    ci = YAML.load_file(File.join(ROOT, ".github", "workflows", "ci.yml"), aliases: true)

    assert_equal ci.dig("env", "ALPINE_RUBY"), workflow.dig("env", "ALPINE_RUBY")
  end
end
