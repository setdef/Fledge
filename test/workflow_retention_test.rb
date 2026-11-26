# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "test_helper"
require "yaml"

# How long ci.yml keeps what a run uploads (doc/contributors/design/releases.md,
# "How long a run keeps what it made"). What a later workflow reads from a
# run is kept longer than what only the run's own jobs read, which is
# kept three days, long enough to run a failed job again over a weekend.
# What release.yml publishes, the runtimes and the examples it attaches,
# is kept ninety days, the longest a public repository's setting allows,
# so that a release can be tagged long after its run. The licensing page
# the pin proof takes, and a failed runtime build's logs, are kept two
# weeks.
class WorkflowRetentionTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  # What release.yml downloads from a ci.yml run. The examples
  # (tasks/release_examples.rb) are read from the same run as the runtimes.
  EXAMPLES = "example-"
  RELEASED = { "runtime-" => ".github/workflows/release.yml", EXAMPLES => ".github/workflows/release.yml" }.freeze

  # What the pin proof downloads from a ci.yml run.
  READ_LATER = { "licensing-page" => ".github/scripts/pin-prove.sh" }.freeze

  # A failed runtime build's logs, which a person reads, perhaps days on.
  LOGS = "logs-runtime-"

  def test_what_the_pin_proof_reads_and_the_runtime_logs_are_kept_two_weeks
    READ_LATER.each do |name, reader|
      assert_includes File.read(File.join(ROOT, reader)), name, "#{reader} no longer reads #{name}: move it to three days"
    end
    later = uploads.select { |name, _| [*READ_LATER.keys, LOGS].any? { |prefix| name.start_with?(prefix) } }

    refute_empty later
    later.each { |name, days| assert_equal 14, days, "#{name} is kept #{days.inspect} days" }
  end

  def test_what_a_release_publishes_is_kept_ninety_days
    RELEASED.each do |name, reader|
      assert_includes File.read(File.join(ROOT, reader)), "#{name}*", "#{reader} no longer reads #{name}: move it to three days"
    end
    released = uploads.select { |name, _| RELEASED.keys.any? { |prefix| name.start_with?(prefix) } }

    assert_equal %w[example-${{ example-android example-ios runtime-${{].sort, released.map(&:first).map { |name| name.sub(/\$\{\{.*\z/, "${{") }.uniq.sort
    released.each { |name, days| assert_equal 90, days, "#{name}, which release.yml reads, is kept #{days.inspect} days" }
  end

  def test_what_only_the_run_reads_is_kept_three_days
    own = uploads.reject { |name, _| read_later?(name) }

    assert_operator own.size, :>=, 6, "fewer uploads than ci.yml had"
    own.each { |name, days| assert_equal 3, days, "#{name}, which only its own run reads, is kept #{days.inspect} days" }
  end

  def test_no_other_workflow_or_script_reads_what_the_run_keeps_three_days
    readers = Dir.glob(".github/{workflows,scripts}/*", base: ROOT).reject { |path| path.end_with?("/ci.yml") }
    texts = readers.to_h { |path| [path, File.read(File.join(ROOT, path))] }
    uploads.reject { |name, _| read_later?(name) }.map(&:first).uniq.each do |name|
      stem = name.sub(/\$\{\{.*\z/, "")
      asked = /\b(?:name|pattern):?\s+["']?#{Regexp.escape(stem)}/
      texts.each { |path, text| refute asked.match?(text), "#{path} reads #{name}, which ci.yml keeps three days" }
    end
  end

  private def read_later?(name) = [*RELEASED.keys, *READ_LATER.keys, LOGS].any? { |prefix| name.start_with?(prefix) }

  # Each upload in ci.yml, by artifact name, with its retention-days.
  private def uploads
    workflow = YAML.load_file(File.join(ROOT, ".github", "workflows", "ci.yml"), aliases: true)
    workflow.fetch("jobs").values.flat_map { |job| job.fetch("steps", []) }
      .select { |step| step["uses"].to_s.start_with?("actions/upload-artifact@") }
      .map { |step| [step.dig("with", "name"), step.dig("with", "retention-days")] }
  end
end
