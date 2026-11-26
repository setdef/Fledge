# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "test_helper"
require "yaml"

# The workflows that carry the example apps into a release
# (doc/contributors/design/releases.md, "The examples a release
# carries"): ci.yml's jobs stage each platform's examples, release.yml
# checks and attaches them, and installed.yml leaves them out of the
# runtimes' sums.
class WorkflowReleaseExamplesTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  def test_every_desktop_build_job_stages_its_examples_and_uploads_them_by_platform
    builds = jobs("ci.yml").select { |name, _| name.start_with?("build-") }

    assert_equal 7, builds.values.sum { |job| (job.dig("strategy", "matrix", "include") || []).size }
    builds.each do |name, job|
      assert(runs(job).any? { |run| run.include?("release_examples.rb stage-desktop") }, "#{name} stages no examples")
      upload = uploads(job).find { |with| with["name"] == "example-${{ matrix.platform }}" }

      refute_nil upload, "#{name} uploads no example-PLATFORM"
      assert_equal "release-examples", upload["path"]
    end
  end

  # A release carries Focus Timer and Pop (issue 154), so the Build job
  # leaves each in dist, where Delivery and the staging read it, and a
  # Delivery job runs each on every platform that carries it. Focus
  # Timer's x64 Windows app carries Microsoft's Visual C++ runtime, so
  # that build stays outside dist.
  def test_focus_timer_and_pop_are_built_into_dist_and_delivered_on_every_platform_that_carries_them
    steps = jobs("ci.yml").fetch("build-arm64-darwin").fetch("steps").filter_map { |step| step["run"] }.join("\n")

    assert_includes steps, "fledge build -o dist examples/libui_app"
    assert_includes steps, "fledge build -o dist examples/lota_pop"
    refute_match(/libui-example|lota-pop"/, steps)
    windows = jobs("ci.yml").fetch("build-x64-mingw-ucrt").fetch("steps").filter_map { |step| step["run"] }.join("\n")
    assert_includes windows, 'fledge build -o "$(cygpath -w "$probe")" examples/libui_app'

    {
"delivery-games-arm64-darwin" => %w[deliver-focus-timer.sh deliver-pop.sh],
"delivery-games-x86_64-linux" => %w[deliver-focus-timer.sh deliver-pop.sh],
"delivery-games-aarch64-linux" => %w[deliver-focus-timer.sh deliver-pop.sh],
"delivery-windows-x64-mingw-ucrt" => %w[deliver-pop.ps1],
"delivery-windows-aarch64-mingw-ucrt" => %w[deliver-pop.ps1],
}.each do |name, scripts|
      run = runs(jobs("ci.yml").fetch(name)).join("\n")
      scripts.each { |script| assert_includes run, script, "#{name} does not run #{script}" }
    end
  end

  # The runners of Windows have no GPU, and the OpenGL in System32 is 1.1,
  # which Lota's renderer cannot use, so Pop's window was 0x0 and its loop
  # never ran (issue 163). Each Windows Delivery job gathers Mesa's
  # software OpenGL before the Pop step and hands that step its folder.
  def test_the_windows_delivery_jobs_give_pop_mesas_software_opengl_before_its_step
    %w[delivery-windows-x64-mingw-ucrt delivery-windows-aarch64-mingw-ucrt].each do |name|
      steps = jobs("ci.yml").fetch(name).fetch("steps")
      pop = steps.index { |step| step["run"].to_s.include?("deliver-pop.ps1") }
      mesa = steps.index { |step| ["Download Mesa's OpenGL for Pop", "Gather Mesa's OpenGL for Pop"].include?(step["name"]) }

      refute_nil pop, "#{name} runs no Pop step"
      refute_nil mesa, "#{name} gathers no Mesa"
      assert_operator mesa, :<, pop, "#{name} gathers Mesa after Pop's step"
      assert_includes steps[pop]["run"], '-Mesa "$env:RUNNER_TEMP/mesa"'
    end
    download = jobs("ci.yml").fetch("delivery-windows-x64-mingw-ucrt").fetch("steps").find { |step| step["name"] == "Download Mesa's OpenGL for Pop" }

    assert_match(/\A\h{64}\z/, download.dig("env", "MESA_SHA256"))
    assert_includes download["run"], "Get-FileHash"
    msys2 = jobs("ci.yml").fetch("delivery-windows-aarch64-mingw-ucrt").fetch("steps").select { |step| step["uses"].to_s.start_with?("msys2/setup-msys2@") }

    refute_empty msys2
    msys2.each { |step| assert_match(/@\h{40}\z/, step["uses"]) }
  end

  def test_the_musl_jobs_stage_inside_the_container_that_built_them_and_know_their_platform
    job = jobs("ci.yml").fetch("build-musl")
    docker = runs(job).find { |run| run.include?("docker run") }

    assert_includes docker, 'PLATFORM="${{ matrix.platform }}"'
    assert_includes docker, 'ruby tasks/release_examples.rb stage-desktop dist release-examples "$PLATFORM"'
  end

  def test_one_android_job_and_the_ios_job_stage_the_phone_examples
    android = jobs("ci.yml").fetch("mobile-apps-android")
    ios = jobs("ci.yml").fetch("mobile-apps-ios")

    assert(android.fetch("steps").any? { |step| step["run"].to_s.include?("release_examples.rb stage-android tmp/mobile-parity/android/apks") && step["if"] == "matrix.target == 'google_apis'" })
    assert(android.fetch("steps").any? { |step| step.dig("with", "name") == "example-android" && step["if"] == "matrix.target == 'google_apis'" })
    assert(runs(ios).any? { |run| run.include?("release_examples.rb stage-ios tmp/mobile-parity/ios/projects") })
    assert(uploads(ios).any? { |with| with["name"] == "example-ios" })
  end

  # A staged example is uploaded only after the step that runs the app
  # in an emulator or a Simulator passed, so that a release carries what
  # was delivered.
  def test_the_phone_examples_are_staged_after_the_apps_ran
    { "mobile-apps-android" => "mobile_parity.rb android\n", "mobile-apps-ios" => "mobile_parity.rb ios " }.each do |name, ran|
      steps = jobs("ci.yml").fetch(name).fetch("steps")
      ran_at = steps.index { |step| step["run"].to_s.include?(ran) || step.dig("with", "script").to_s.include?(ran) }
      staged_at = steps.index { |step| step["run"].to_s.include?("release_examples.rb") }

      refute_nil ran_at, "#{name} runs no app"
      assert_operator staged_at, :>, ran_at, "#{name} stages before its apps ran"
    end
  end

  def test_release_takes_the_examples_from_the_run_that_built_the_runtimes_and_checks_them
    steps = jobs("release.yml").fetch("check").fetch("steps")
    runtimes = steps.find { |step| step.dig("with", "pattern") == "runtime-*" }
    examples = steps.find { |step| step.dig("with", "pattern") == "example-*" }

    assert_equal runtimes.dig("with", "run-id"), examples.dig("with", "run-id")
    assert_equal true, examples.dig("with", "merge-multiple")
    assert(steps.index(examples) > steps.index(runtimes))
    check = steps.find { |step| step["run"].to_s.include?("ruby tasks/release_examples.rb check release-examples") }

    refute_nil check, "release.yml does not check the examples with the tagged commit's code"
    assert_operator steps.index(check), :>, steps.index(examples)
    assert(steps.any? { |step| step.dig("with", "name") == "release-examples" })
  end

  def test_the_publish_job_attaches_the_examples_beside_the_runtimes
    steps = jobs("release.yml").fetch("release").fetch("steps")
    create = steps.find { |step| step["run"].to_s.include?("gh release create") }.fetch("run")

    assert(steps.any? { |step| step.dig("with", "name") == "release-examples" })
    assert_includes create, "release-examples/fledge-example-*"
    assert_includes create, "release/fledge-runtime-*"
  end

  def test_the_runtimes_sums_check_downloads_runtimes_alone
    download = jobs("installed.yml").fetch("sums").fetch("steps").first.fetch("run")

    assert_includes download, "--pattern 'fledge-runtime-*' --pattern SHA256SUMS"
  end

  private def jobs(file) = YAML.safe_load_file(File.join(ROOT, ".github", "workflows", file), aliases: true).fetch("jobs")

  private def runs(job) = job.fetch("steps").filter_map { |step| step["run"] }

  private def uploads(job)
    job.fetch("steps").select { |step| step["uses"].to_s.start_with?("actions/upload-artifact@") }.map { |step| step.fetch("with") }
  end
end
