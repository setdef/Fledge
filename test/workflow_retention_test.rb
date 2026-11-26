# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "test_helper"
require "yaml"

# How long ci.yml keeps what a run uploads (doc/contributors/design/releases.md,
# "How long a run keeps what it made"). What a later workflow reads from a
# run, the runtimes release.yml publishes and the licensing page the pin
# proof takes, is kept two weeks, as are a failed runtime build's logs;
# what only the run's own jobs read, three days, long enough to run a
# failed job again over a weekend. The examples release.yml attaches are
# read later too, but only a release's run, which cut.yml starts on the
# branch release-next, has them kept two weeks; every other run keeps
# them three days.
class WorkflowRetentionTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  # What a later workflow or script downloads from a ci.yml run.
  READ_LATER = { "runtime-" => ".github/workflows/release.yml", "licensing-page" => ".github/scripts/pin-prove.sh" }.freeze

  # The examples a release attaches (tasks/release_examples.rb), which
  # release.yml reads from the run of the release commit alone, and the
  # retention that keeps them two weeks there and three days elsewhere.
  EXAMPLES = "example-"
  EXAMPLES_RETENTION = "${{ github.ref_name == 'release-next' && 14 || 3 }}"

  # A failed runtime build's logs, which a person reads, perhaps days on.
  LOGS = "logs-runtime-"

  def test_what_a_later_workflow_reads_is_kept_two_weeks
    READ_LATER.each do |name, reader|
      assert_includes File.read(File.join(ROOT, reader)), name, "#{reader} no longer reads #{name}: move it to three days"
    end
    later = uploads.select { |name, _| read_later?(name) }

    refute_empty later
    later.each { |name, days| assert_equal 14, days, "#{name}, which a later workflow reads, is kept #{days.inspect} days" }
  end

  def test_the_examples_a_release_attaches_are_kept_two_weeks_only_on_the_release_branch
    assert File.read(File.join(ROOT, ".github/workflows/release.yml")).include?("#{EXAMPLES}*"), "release.yml no longer reads #{EXAMPLES}: move it to three days"
    examples = uploads.select { |name, _| name.start_with?(EXAMPLES) }

    assert_equal %w[example-${{ example-android example-ios].sort, examples.map(&:first).map { |name| name.sub(/\$\{\{.*\z/, "${{") }.uniq.sort
    examples.each { |name, days| assert_equal EXAMPLES_RETENTION, days, "#{name} is kept #{days.inspect} days" }
  end

  def test_what_only_the_run_reads_is_kept_three_days
    own = uploads.reject { |name, _| read_later?(name) || name.start_with?(EXAMPLES) }

    assert_operator own.size, :>=, 6, "fewer uploads than ci.yml had"
    own.each { |name, days| assert_equal 3, days, "#{name}, which only its own run reads, is kept #{days.inspect} days" }
  end

  def test_no_other_workflow_or_script_reads_what_the_run_keeps_three_days
    readers = Dir.glob(".github/{workflows,scripts}/*", base: ROOT).reject { |path| path.end_with?("/ci.yml") }
    texts = readers.to_h { |path| [path, File.read(File.join(ROOT, path))] }
    uploads.reject { |name, _| read_later?(name) || name.start_with?(EXAMPLES) }.map(&:first).uniq.each do |name|
      stem = name.sub(/\$\{\{.*\z/, "")
      asked = /\b(?:name|pattern):?\s+["']?#{Regexp.escape(stem)}/
      texts.each { |path, text| refute asked.match?(text), "#{path} reads #{name}, which ci.yml keeps three days" }
    end
  end

  private def read_later?(name) = [*READ_LATER.keys, LOGS].any? { |prefix| name.start_with?(prefix) }

  # Each upload in ci.yml, by artifact name, with its retention-days.
  private def uploads
    workflow = YAML.load_file(File.join(ROOT, ".github", "workflows", "ci.yml"), aliases: true)
    workflow.fetch("jobs").values.flat_map { |job| job.fetch("steps", []) }
      .select { |step| step["uses"].to_s.start_with?("actions/upload-artifact@") }
      .map { |step| [step.dig("with", "name"), step.dig("with", "retention-days")] }
  end
end
