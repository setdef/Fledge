# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "test_helper"
require "yaml"

# What CI's artifacts are named (doc/contributors/design/releases.md,
# "The pins"): rake runtime:pin, the pin commit's check, and release.yml
# each download every artifact of a run named runtime-*, and refuse
# anything among them that is not a release asset. So an artifact named
# so holds release assets and nothing else, whatever else a job keeps.
class WorkflowArtifactsTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  # Where a runtime job leaves its release assets.
  ASSETS = "tmp/runtime/fledge-runtime-"

  def test_an_artifact_named_as_a_runtime_holds_only_release_assets
    named = uploads("ci.yml").select { |upload| upload.fetch("name").start_with?("runtime-") }

    refute_empty named
    named.each do |upload|
      assert upload.fetch("path").start_with?(ASSETS),
        "#{upload.fetch('name')} uploads #{upload.fetch('path')}, which is no release asset; name it otherwise, " \
          "or the pin and the release take it for one"
    end
  end

  # A runtime job that fails keeps its build's logs, under a name the
  # pin and the release do not download: a job that fails once and
  # passes when run again leaves them in the run for good.
  def test_a_runtime_jobs_logs_are_kept_under_a_name_of_their_own
    logs = uploads("ci.yml").select { |upload| upload.fetch("path").end_with?("/logs") }

    refute_empty logs
    logs.each { |upload| assert_match(/\Alogs-runtime-/, upload.fetch("name")) }
  end

  # release.yml downloads every artifact named example-* into one folder
  # and expects only what tasks/release_examples.rb staged
  # (doc/contributors/design/releases.md, "The examples a release
  # carries"), so an artifact so named holds that folder and nothing else.
  def test_an_artifact_named_as_an_example_holds_only_the_staged_folder
    named = uploads("ci.yml").select { |upload| upload.fetch("name").start_with?("example-") }

    refute_empty named
    named.each { |upload| assert_equal "release-examples", upload.fetch("path"), "#{upload.fetch('name')} uploads #{upload.fetch('path')}" }
  end

  private def uploads(name)
    workflow = YAML.load_file(File.join(ROOT, ".github", "workflows", name), aliases: true)
    workflow.fetch("jobs").values.flat_map do |job|
      job.fetch("steps", []).select { |step| step["uses"].to_s.start_with?("actions/upload-artifact@") }.map { |step| step.fetch("with") }
    end
  end
end
