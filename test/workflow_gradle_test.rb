# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "test_helper"
require "yaml"

# Maven Central refuses some of GitHub's runners for minutes at a time,
# and Gradle's own retries give up after three seconds, so every CI job
# that runs Gradle first makes it patient, with
# .github/scripts/gradle-patience.sh (doc/contributors/design/
# phone-projects.md, "Gradle's downloads in CI"). The jobs that run
# Gradle are the jobs that restore its dependency cache.
class WorkflowGradleTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  WORKFLOWS = %w[ci.yml ruby-spec.yml installed.yml].freeze
  SCRIPT = File.join(ROOT, ".github", "scripts", "gradle-patience.sh")
  CACHE = "~/.gradle/caches/modules-2"

  def test_every_job_that_restores_gradles_cache_makes_gradle_patient_first
    refute_empty gradle_jobs, "no job restores #{CACHE}"
    gradle_jobs.each do |name, steps|
      restore = steps.index { |step| step.dig("with", "path").to_s.include?(CACHE) }
      patience = steps.index { |step| step["run"].to_s.strip.end_with?(".github/scripts/gradle-patience.sh") }

      refute_nil patience, "#{name} runs Gradle and never runs gradle-patience.sh"
      assert_operator patience, :<, restore, "#{name} makes Gradle patient only after it restores Gradle's cache"
      assert steps[restore]["if"] == steps[patience]["if"], "#{name} makes Gradle patient under another condition than it runs Gradle"
    end
  end

  def test_the_script_raises_gradles_own_retry_settings
    assert_equal 7, setting("max.tentatives")
    assert_equal 10_000, setting("initial.backoff")
  end

  def test_gradles_whole_wait_for_one_download_fits_in_each_gradle_jobs_time_limit
    tries = setting("max.tentatives")
    wait = (0...(tries - 1)).sum { |each| setting("initial.backoff") * (2 ** each) } / 1000

    assert_equal 630, wait
    gradle_jobs.each_key do |name|
      minutes = jobs.fetch(name)["timeout-minutes"] or next

      assert_operator wait * 2, :<=, minutes * 60, "#{name}'s #{minutes} minutes leave too little room for Gradle's #{wait} seconds of waiting"
    end
  end

  private def setting(name)
    line = File.read(SCRIPT)[/systemProp\.org\.gradle\.internal\.repository\.#{Regexp.escape(name)}=(\d+)/, 1]
    Integer(line || flunk("gradle-patience.sh sets no #{name}"))
  end

  private def gradle_jobs
    jobs.filter_map do |name, job|
      steps = job["steps"] or next
      [name, steps] if steps.any? { |step| step.dig("with", "path").to_s.include?(CACHE) }
    end.to_h
  end

  private def jobs
    @jobs ||= WORKFLOWS.to_h do |file|
      [file, YAML.safe_load_file(File.join(ROOT, ".github", "workflows", file), aliases: true).fetch("jobs")]
    end.flat_map { |file, each| each.map { |name, job| ["#{file} #{name}", job] } }.to_h
  end
end
