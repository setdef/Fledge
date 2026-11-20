# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "test_helper"
require "yaml"

# What CI's bundle caches are keyed by. A bundle's compiled extensions
# target the macOS they were compiled on, and the fast tier's macOS leg
# runs on macos-26 while ci.yml's Test (arm64-darwin) runs on macos-15
# (doc/contributors/design/releases.md, "Runs, batches, and the release
# commit"), so a key without the runner's image would hand macos-15 a
# bundle built for macOS 26.
class WorkflowCachesTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  # The step output every bundle cache's key names: the runner's ImageOS.
  IMAGE = "${{ steps.paths.outputs.image }}"

  def test_a_bundle_cache_a_mac_restores_names_the_runners_image
    keys = Dir[File.join(ROOT, ".github", "workflows", "*.yml")].flat_map { |path| mac_bundle_keys(path) }

    assert_operator keys.size, :>=, 2
    keys.each { |where, key| assert_includes key, IMAGE, "#{where}'s bundle cache is keyed without the runner's image" }
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
