# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

# Tests .github/workflows/ruby-builds.yml, which builds Fledge's own Ruby
# for glibc Linux on each architecture and can publish it, and the pins
# of .github/scripts/ruby-archive.sh, which it builds with
# (doc/contributors/design/runtimes.md, "Fledge's own Ruby builds").

require_relative "test_helper"
require "yaml"

class WorkflowRubyBuildsTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  SCRIPT = File.join(ROOT, ".github", "scripts", "ruby-archive.sh")

  # Each platform, and the runner of its architecture.
  RUNNERS = { "x86_64-linux" => "ubuntu-24.04", "aarch64-linux" => "ubuntu-24.04-arm" }.freeze

  def workflow
    @workflow ||= YAML.load_file(File.join(ROOT, ".github", "workflows", "ruby-builds.yml"), aliases: true)
  end

  def script
    @script ||= File.read(SCRIPT)
  end

  def test_each_platform_is_built_by_the_script_on_a_runner_of_its_own_architecture
    build = workflow.dig("jobs", "build")
    platforms = build.dig("strategy", "matrix", "include").to_h { |entry| [entry.fetch("platform"), entry.fetch("os")] }
    step = build.fetch("steps").find { |each| each["run"].to_s.include?("ruby-archive.sh") }

    assert_equal RUNNERS, platforms
    assert_equal '.github/scripts/ruby-archive.sh "$PLATFORM"', step.fetch("run")
    assert_equal "${{ matrix.platform }}", step.dig("env", "PLATFORM")
  end

  def test_each_archive_is_kept_as_an_artifact_the_publish_job_takes
    upload = workflow.dig("jobs", "build", "steps").find { |step| step.dig("with", "path").to_s.end_with?(".tar.gz") }
    download = workflow.dig("jobs", "publish", "steps").find { |step| step["uses"].to_s.start_with?("actions/download-artifact@") }
    publish = workflow.dig("jobs", "publish", "steps").find { |step| step["run"].to_s.include?("ruby-archive-publish.sh") }

    assert_equal "tmp/ruby-archive/ruby-*-${{ matrix.platform }}.tar.gz", upload.dig("with", "path")
    assert_equal "error", upload.dig("with", "if-no-files-found")
    assert File.fnmatch(download.dig("with", "pattern"), upload.dig("with", "name").sub("${{ matrix.platform }}", "x86_64-linux"))
    assert download.dig("with", "merge-multiple")
    assert_equal ".github/scripts/ruby-archive-publish.sh #{download.dig('with', 'path')}", publish.fetch("run")
    assert_equal ["build"], Array(workflow.dig("jobs", "publish", "needs"))
  end

  # A push builds and prints what it would publish; only a run by hand,
  # with dry-run turned off, publishes, and only its job can write.
  def test_only_a_run_by_hand_with_dry_run_off_publishes
    publish = workflow.dig("jobs", "publish", "steps").find { |step| step["run"].to_s.include?("ruby-archive-publish.sh") }
    on = workflow.fetch(true)

    assert_equal "${{ (github.event_name != 'workflow_dispatch' || inputs.dry-run) && '1' || '' }}", publish.dig("env", "DRY_RUN")
    assert_equal true, on.dig("workflow_dispatch", "inputs", "dry-run", "default")
    assert_equal %w[push workflow_dispatch], on.keys.sort
    assert_equal({}, workflow.fetch("permissions"))
    assert_equal({ "contents" => "write" }, workflow.dig("jobs", "publish", "permissions"))
    assert_equal({ "contents" => "read" }, workflow.dig("jobs", "build", "permissions"))
  end

  def test_a_push_to_trunk_that_changes_the_recipe_or_its_pins_runs_it
    push = workflow.fetch(true).fetch("push")

    assert_equal ["trunk"], push.fetch("branches")
    %w[tasks/ruby_archive.rb tasks/runtime_builder/ruby_build.rb runtime/sources.yml .github/scripts/ruby-archive.sh].each do |path|
      assert_includes push.fetch("paths"), path
    end
    push.fetch("paths").each { |path| assert File.file?(File.join(ROOT, path)), "#{path} is no file the build reads" }
  end

  def test_the_image_is_pinned_by_digest
    assert_match(/^IMAGE=ubuntu:22\.04@sha256:\h{64}$/, script)
  end

  def test_every_package_apt_installs_is_pinned_by_version
    packages = script[/^PACKAGES=\((.*?)^\)/m, 1].split

    assert_includes packages.map { |package| package.split("=").first }, "gcc-11"
    packages.each { |package| assert_match(/\A[a-z0-9.+-]+=[0-9][\w.:~+-]*\z/, package) }
    assert_includes script, '--no-install-recommends "${PACKAGES[@]}"'
  end

  def test_the_driver_ruby_is_checked_by_sha256_on_each_architecture
    RUNNERS.each_key do |platform|
      arm = script[/^    #{platform}\)\n(.*?);;/m, 1]

      refute_nil arm, "ruby-archive.sh builds no #{platform}"
      assert_match(/driver_sha256=\h{64}$/, arm, platform)
    end
    assert_includes script, 'echo "$driver_sha256  /tmp/driver.tar.gz" | sha256sum --strict -c -'
  end
end
