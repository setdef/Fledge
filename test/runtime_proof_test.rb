# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "test_helper"
require_relative "../tasks/runtime_proof"

# The proof before a runtime change's push runs CI's own scripts, never
# copies of them (CONTRIBUTING.md, "Before a push").
class RuntimeProofTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  def build_command(name)
    RuntimeProof.build_command(RuntimeBuilder.platform(name))
  end

  # A glibc Linux runtime is built in the image CI's Runtime job builds
  # it in, by the same script; a Mac's and Android's by the builder.
  def test_builds_each_runtime_as_cis_runtime_jobs_do
    assert_equal ["bash", ".github/scripts/glibc-runtime.sh", "x86_64-linux"], build_command("x86_64-linux")
    assert_equal ["bash", ".github/scripts/glibc-runtime.sh", "aarch64-linux"], build_command("aarch64-linux")
    assert_equal [RbConfig.ruby, "tasks/runtime_builder.rb", "arm64-darwin"], build_command("arm64-darwin")
    assert_equal [RbConfig.ruby, "tasks/runtime_builder.rb", "android"], build_command("android")
  end

  # Windows runtimes are built on Linux, and musl ones in CI's Alpine
  # image, so the proof there takes a runtime already built.
  def test_a_runtime_built_elsewhere_is_named_by_its_folder
    %w[x64-mingw-ucrt aarch64-mingw-ucrt x86_64-linux-musl].each do |name|
      error = assert_raises(RuntimeProof::Failed) { build_command(name) }

      assert_includes error.message, "FLEDGE_RUNTIME_DIR", name
    end
  end

  # deliver-from.sh reads the status a refusal exits with from the
  # workflow's env, which the proof takes from ci.yml.
  def test_takes_the_workflows_env_from_ci_yml
    assert_equal "1", RuntimeProof.workflow_env.fetch("FROM_REFUSES_A_BAD_APP_WITH")
  end

  # Each of CI's scripts the proof runs is one ci.yml runs, so the proof
  # and CI cannot drift apart into two copies.
  def test_runs_only_scripts_ci_runs
    proof = File.read(File.join(ROOT, "tasks", "runtime_proof.rb"))
    ci = File.read(File.join(ROOT, ".github", "workflows", "ci.yml"))
    scripts = proof.scan(%r{\.github/scripts/[\w.-]+}).uniq

    assert_operator scripts.size, :>=, 5
    scripts.each do |script|
      assert_path_exists File.join(ROOT, script)
      assert_includes ci, script
    end
  end

  # A proof that records the steps it would run, rather than running them.
  class Recording < RuntimeProof
    def steps = @steps ||= []

    private def step(label, *)
      steps << label
    end

    private def capture(*) = ""
  end

  # The Android runtime's build packs its AAR with Gradle, which needs the
  # SDK that bin/android-sdk lays out, as "Android on Linux" in
  # CONTRIBUTING.md runs it first; after the build, the proof failed on a
  # clean checkout with "SDK location not found".
  def test_the_android_proof_lays_out_the_sdk_before_it_builds_a_runtime
    previous = ENV.fetch("MISE_ENV", nil)
    ENV["MISE_ENV"] = "android"
    proof = Recording.new(platform: "android", runtimes: nil, work: Dir.mktmpdir, out: StringIO.new)
    proof.call

    assert_equal "the Android SDK", proof.steps.first
    assert_includes proof.steps, "the android runtime"
  ensure
    ENV["MISE_ENV"] = previous
  end
end
