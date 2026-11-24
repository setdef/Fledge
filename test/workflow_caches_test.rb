# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "test_helper"
require "yaml"

# What CI's caches are keyed by, and what each falls back to. A
# bundle's compiled extensions target the Ruby, the system, and the
# runner image they were compiled on, so its key names all three, and a
# bundle compiled on one image (ubuntu-latest's, macos-26's) is never
# restored on another (doc/contributors/design/releases.md, "Installed
# gems in CI"). A set of pinned downloads is keyed by the files it
# holds, and a Gradle set falls back no further than the plugin's pin.
class WorkflowCachesTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  # The step output every installed-gems key names: the runner's ImageOS.
  IMAGE = "${{ steps.paths.outputs.image }}"

  # What decides an installed bundle, each of which its cache's key
  # names: the system and its processor, the runner's image, the Ruby
  # (its version, its revision, which tells one preview from the next,
  # and its platform), and the lockfile.
  BUNDLE = ["${{ runner.os }}", "${{ runner.arch }}", IMAGE, "${{ steps.paths.outputs.ruby }}", "hashFiles('Gemfile.lock'"].freeze

  def test_an_installed_gems_key_names_everything_the_bundle_was_compiled_for
    caches = gems_caches

    assert_operator caches.size, :>=, 8
    caches.each do |where, job, step|
      key = step.dig("with", "key")
      BUNDLE.each { |part| assert_includes key, part, "#{where}'s installed gems are keyed without #{part}" }
      paths = job.fetch("steps").find { |each| each["id"] == "paths" }.fetch("run")

      assert_includes paths, "image=${ImageOS:?", where
      assert_includes paths, "RUBY_REVISION", "#{where} keys its gems by a Ruby that names no revision"
    end
  end

  # On Windows mise.toml pins the RubyInstaller build and the MSYS2 that
  # compiles the bundle's extensions, which RUBY_VERSION does not name.
  def test_installed_gems_on_windows_are_keyed_by_the_tools_mise_pins
    windows = gems_caches.select { |_, job| runners(job).all? { |label| label.start_with?("windows-") } }

    assert_operator windows.size, :>=, 2
    windows.each { |where, _, step| assert_includes step.dig("with", "key"), "'mise.toml'", where }
  end

  def test_jobs_on_different_runners_share_installed_gems_only_by_a_key_that_names_the_image
    gems_caches.group_by { |_, _, step| step.dig("with", "key") }.each do |key, caches|
      next if caches.map { |_, job| runners(job).sort }.uniq.size == 1

      assert_includes key, IMAGE, "#{caches.map(&:first).join(', ')} share installed gems across runners"
    end
  end

  # A job that only restores the bundle restores what a job on its own
  # runner saves under the same key.
  def test_a_job_that_only_restores_installed_gems_restores_a_key_saved_on_its_runner
    caches = gems_caches
    restorers = caches.select { |_, _, step| step["uses"].start_with?("actions/cache/restore@") }

    assert_operator restorers.size, :>=, 1
    restorers.each do |where, job, step|
      saved = caches.any? do |_, saver, save|
        save["uses"].start_with?("actions/cache@") && save.dig("with", "key") == step.dig("with", "key") && (runners(job) - runners(saver)).empty?
      end

      assert saved, "#{where} restores installed gems that no job on its runner saves"
    end
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

  # A Gradle build that failed on a refused download has still fetched
  # most of the set, and Gradle keeps what it fetched, so the job saves
  # it, under a key of its own run that restore-keys reaches, and never
  # under the exact key, which a complete set takes (doc/contributors/
  # design/phone-projects.md, "Gradle's downloads in CI"). A save that
  # waited for success left a trunk run after a pin move to fetch the
  # whole classpath again, run after run, while Maven Central refused it
  # (issue 88).
  def test_a_gradle_set_is_saved_after_a_failed_build_under_a_key_of_its_own_run
    saves = workflows.flat_map do |name, workflow|
      workflow.fetch("jobs").flat_map do |id, job|
        job.fetch("steps", []).select { |step| step.dig("with", "path").to_s.include?("modules-2") && step["uses"].start_with?("actions/cache/save@") }.map { |step| ["#{name} #{id}", step] }
      end
    end

    assert_operator saves.size, :>=, 3
    saves.each do |where, step|
      assert_includes step["if"], "!cancelled()", "#{where} saves Gradle's set only when everything before it passed"
      assert_includes step["if"], "cache-primary-key != ''", "#{where} saves a set when its restore step never ran"
      assert_includes step["if"], "cache-hit != 'true'", where
      key = step.dig("with", "key")

      assert_includes key, "job.status == 'success' && steps.gradle-cache.outputs.cache-primary-key", "#{where} saves a complete set under the exact key only"
      assert_includes key, "-partial-{1}-{2}', steps.gradle-cache.outputs.cache-primary-key, github.run_id, github.run_attempt", "#{where} saves a failed build's set under a key of its run"
    end
  end

  # A run restores only what its own branch or trunk saved, so what the
  # proof of a pin move on pin-move, a release's runs on release-next, or
  # a pull request saves is read by no run of trunk and only fills the
  # repository's 10 GB (doc/contributors/design/runtimes.md, "Caches only
  # trunk saves"; issue 90).
  ON_TRUNK = "github.ref == 'refs/heads/trunk'"

  def test_a_step_that_saves_a_cache_runs_only_on_trunk
    saves = workflow_steps.select { |_, step| step["uses"].to_s.start_with?("actions/cache/save@") }

    assert_operator saves.size, :>=, 12
    saves.each { |where, step| assert_includes step["if"].to_s, ON_TRUNK, "#{where} saves a cache on a branch trunk cannot read it from" }
  end

  def test_mise_action_saves_its_cache_only_on_trunk
    mises = workflow_steps.select { |_, step| step["uses"].to_s.start_with?("jdx/mise-action@") && step.dig("with", "cache").to_s != "false" }

    assert_operator mises.size, :>=, 30
    mises.each { |where, step| assert_equal "${{ #{ON_TRUNK} }}", step.dig("with", "cache_save"), "#{where} saves mise's tools on a branch trunk cannot read them from" }
  end

  private def workflow_steps
    workflows.flat_map do |name, workflow|
      workflow.fetch("jobs").flat_map do |id, job|
        job.fetch("steps", []).map { |step| ["#{name} #{id}", step] }
      end
    end
  end

  # mise-action's key hashes every mise config file the checkout holds,
  # so a sparse checkout that takes only mise.toml keys the same tools
  # apart from ci.yml's, and keeps a second copy of them.
  def test_a_sparse_checkout_that_takes_mise_config_takes_all_of_it
    checkouts = workflows.flat_map do |name, workflow|
      workflow.fetch("jobs").flat_map do |id, job|
        job.fetch("steps", []).filter_map do |step|
          paths = step.dig("with", "sparse-checkout").to_s.split("\n").map(&:strip)
          ["#{name} #{id}", paths] if paths.any? { |path| path.start_with?("mise") }
        end
      end
    end

    assert_operator checkouts.size, :>=, 4
    checkouts.each { |where, paths| assert_includes paths, "mise*.toml", "#{where} checks out mise.toml without the rest of mise's config" }
  end

  private def workflows
    Dir[File.join(ROOT, ".github", "workflows", "*.yml")].to_h { |path| [File.basename(path), YAML.load_file(path, aliases: true)] }
  end

  # The nightly run against Ruby's master restores trunk's downloads and
  # saves none: its snapshot is a new file every night, so every set it
  # saved would be a new entry of the whole set (doc/contributors/design/
  # runtimes.md, "Testing against Ruby's master").
  RESTORE_ONLY = "ruby-master.yml"

  def test_the_run_against_rubys_master_restores_trunks_downloads_and_saves_none
    steps = YAML.load_file(File.join(ROOT, ".github", "workflows", RESTORE_ONLY), aliases: true).fetch("jobs").values.flat_map do |job|
      job.fetch("steps", []).select { |step| step.dig("with", "path") == "~/.cache/fledge/downloads" }
    end

    refute_empty steps
    steps.each do |step|
      assert step["uses"].start_with?("actions/cache/restore@"), "#{RESTORE_ONLY} saves its downloads"
      assert_match(/\Aruntime-downloads-.*-files-\z/, step.dig("with", "key"))
    end
  end

  private def download_cache_jobs
    workflows.except(RESTORE_ONLY).flat_map do |name, workflow|
      workflow.fetch("jobs").filter_map do |id, job|
        steps = job.fetch("steps", []).select { |step| step.dig("with", "path") == "~/.cache/fledge/downloads" }
        refute steps.any? { |step| step["uses"].start_with?("actions/cache@") }, "#{name} #{id} keeps its downloads with actions/cache, whose post step saves under the restore key"
        ["#{name} #{id}", steps, job] unless steps.empty?
      end
    end
  end

  # Every step that restores or saves installed gems, with its job.
  private def gems_caches
    workflows.flat_map do |name, workflow|
      workflow.fetch("jobs").flat_map do |id, job|
        steps = job.fetch("steps", []).select { |step| step["uses"].to_s.start_with?("actions/cache") && step.dig("with", "key").to_s.start_with?("gems-") }
        steps.map { |step| ["#{name} #{id}", job, step] }
      end
    end
  end

  # The labels a job runs on, its matrix's included.
  private def runners(job)
    matrix = job.dig("strategy", "matrix") || {}
    labels = Array(job["runs-on"]) + Array(matrix["os"]) + Array(matrix["include"]).filter_map { |entry| entry["os"] }
    labels.grep_v(/\$\{\{/)
  end
end
