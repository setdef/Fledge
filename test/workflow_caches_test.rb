# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "test_helper"
require "yaml"

# What CI's caches are keyed by, and what each falls back to. A
# bundle's compiled extensions target the macOS they were compiled on,
# and the fast tier's macOS leg runs on macos-26 while ci.yml's Test
# (arm64-darwin) runs on macos-15 (doc/contributors/design/releases.md,
# "Which macOS each job runs on"), so a key without the runner's image
# would hand macos-15 a bundle built for macOS 26. A set of pinned
# downloads is keyed by the files it holds, and a Gradle set falls back
# no further than the plugin's pin.
class WorkflowCachesTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  # The step output every bundle cache's key names: the runner's ImageOS.
  IMAGE = "${{ steps.paths.outputs.image }}"

  def test_a_bundle_cache_a_mac_restores_names_the_runners_image
    keys = Dir[File.join(ROOT, ".github", "workflows", "*.yml")].flat_map { |path| mac_bundle_keys(path) }

    assert_operator keys.size, :>=, 2
    keys.each { |where, key| assert_includes key, IMAGE, "#{where}'s bundle cache is keyed without the runner's image" }
  end

  # The digest of the files a job's download folder holds, which every
  # saved set of pinned downloads is keyed by.
  FILES = "${{ steps.downloads-key.outputs.files }}"

  # A set of pinned downloads is restored by its job's prefix, the newest
  # set saved under it, and saved under that prefix and the digest of the
  # files it holds, only when that is not the key restored
  # (doc/contributors/design/runtimes.md, "Pinned downloads in CI").
  def test_pinned_downloads_are_restored_by_prefix_and_saved_under_what_they_hold
    jobs = download_cache_jobs

    assert_operator jobs.size, :>=, 8
    jobs.each do |where, steps|
      restores = steps.select { |step| step["uses"].start_with?("actions/cache/restore@") }
      saves = steps.select { |step| step["uses"].start_with?("actions/cache/save@") }

      assert_equal [1, 1], [restores.size, saves.size], "#{where} restores and saves its downloads once each"
      prefix = restores.first.dig("with", "key")

      assert_match(/-files-\z/, prefix, "#{where} restores by a prefix that ends -files-")
      assert_equal "downloads", restores.first["id"], where
      assert_equal "#{prefix}#{FILES}", saves.first.dig("with", "key"), "#{where} saves under its prefix and the digest"
      assert_includes saves.first["if"], "steps.downloads.outputs.cache-matched-key !=", where
      assert_includes saves.first["if"], "steps.downloads-key.outputs.files != ''", where
    end
  end

  def test_every_job_that_restores_pinned_downloads_keys_them_with_the_script
    download_cache_jobs.each do |where, _steps, job|
      keyer = job.fetch("steps").find { |step| step["id"] == "downloads-key" }

      assert keyer, "#{where} has a downloads-key step"
      assert_includes keyer.fetch("run"), "ruby .github/scripts/download_cache_key.rb", where
    end
  end

  # A Gradle set whose exact key the cache lacks falls back to the newest
  # set for the same system and plugin, never past the plugin's pin
  # (doc/contributors/design/phone-projects.md, "Gradle's downloads in
  # CI").
  def test_a_gradle_restore_falls_back_to_its_key_up_to_the_plugins_pin
    restores = workflows.flat_map do |name, workflow|
      workflow.fetch("jobs").flat_map do |id, job|
        job.fetch("steps", []).select { |step| step.dig("with", "path").to_s.include?("modules-2") && step["uses"].start_with?("actions/cache/restore@") }.map { |step| ["#{name} #{id}", step] }
      end
    end

    assert_operator restores.size, :>=, 5
    restores.each do |where, step|
      key, fallback = step.fetch("with").values_at("key", "restore-keys")

      assert_match(/outputs\.(agp|pins) \}\}-\z/, fallback.to_s, "#{where} falls back to the plugin's pin")
      assert key.start_with?(fallback), "#{where}'s restore-keys is its key's prefix"
    end
  end

  private def workflows
    Dir[File.join(ROOT, ".github", "workflows", "*.yml")].to_h { |path| [File.basename(path), YAML.load_file(path, aliases: true)] }
  end

  private def download_cache_jobs
    workflows.flat_map do |name, workflow|
      workflow.fetch("jobs").filter_map do |id, job|
        steps = job.fetch("steps", []).select { |step| step.dig("with", "path") == "~/.cache/fledge/downloads" }
        refute steps.any? { |step| step["uses"].start_with?("actions/cache@") }, "#{name} #{id} keeps its downloads with actions/cache, whose post step saves under the restore key"
        ["#{name} #{id}", steps, job] unless steps.empty?
      end
    end
  end

  private def mac_bundle_keys(path)
    workflow = YAML.load_file(path, aliases: true)
    workflow.fetch("jobs").filter_map do |id, job|
      next unless runners(job).any? { |label| label.start_with?("macos-") }

      job.fetch("steps", []).filter_map do |step|
        key = step.dig("with", "key").to_s
        ["#{File.basename(path)} #{id}", key] if step["uses"].to_s.start_with?("actions/cache@") && key.start_with?("gems-")
      end
    end.flatten(1)
  end

  private def runners(job)
    matrix = job.dig("strategy", "matrix") || {}
    Array(job["runs-on"]) + Array(matrix["os"]) + Array(matrix["include"]).filter_map { |entry| entry["os"] }
  end
end
