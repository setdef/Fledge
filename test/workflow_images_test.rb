# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "test_helper"
require "yaml"

# Where the workflows take the container images they run in: from
# runtime/sources.yml's images, by .github/scripts/pinned-images.sh, and
# never from a tag or digest written in a workflow, which the pin move
# could not change, since a workflow's own token cannot push a commit
# that changes a workflow file (doc/contributors/design/runtimes.md,
# "Container images"). A job container whose expression names a key
# sources.yml lacks would be empty, and GitHub would run the job on the
# runner itself, so every key named is checked here.
class WorkflowImagesTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  # How a job container names a pinned image.
  FROM_OUTPUT = /\A\$\{\{ fromJSON\(needs\.changes\.outputs\.images\)\[(?:'(?<key>[^']+)'|matrix\.(?<matrix>\w+))\] \}\}\z/

  def images
    YAML.safe_load_file(File.join(ROOT, "runtime/sources.yml")).fetch("images")
  end

  def workflows
    Dir[File.join(ROOT, ".github/workflows/*.yml")].to_h { |path| [File.basename(path), YAML.load_file(path, aliases: true)] }
  end

  def jobs
    workflows.flat_map { |file, workflow| workflow.fetch("jobs").map { |name, job| ["#{file} #{name}", job] } }
  end

  def test_every_pinned_image_is_a_tag_and_the_digest_of_its_index
    images.each do |key, pin|
      assert_match(%r{\A[a-z0-9./-]+:[\w.-]+@sha256:\h{64}\z}, pin.fetch("image"), key)
      assert_kind_of String, pin.fetch("version"), "#{key}'s version is quoted, or YAML reads a date"
    end
  end

  def test_no_workflow_names_an_image_by_tag_or_digest
    workflows.each do |file, workflow|
      text = File.read(File.join(ROOT, ".github/workflows", file))

      assert_empty text.lines.grep(/@sha256:\h{64}/), "#{file} pins an image the move cannot change"
      workflow.fetch("jobs").each do |name, job|
        container = job["container"]
        next unless container

        assert_match FROM_OUTPUT, container.is_a?(Hash) ? container["image"] : container, "#{file} #{name}"
      end
    end
  end

  def test_a_job_container_names_a_pinned_image_from_the_changes_job
    ci = workflows.fetch("ci.yml")

    assert_equal "${{ steps.images.outputs.images }}", ci.dig("jobs", "changes", "outputs", "images")
    found = jobs.filter_map do |name, job|
      match = FROM_OUTPUT.match(job["container"].to_s) or next
      keys = match[:key] ? [match[:key]] : job.dig("strategy", "matrix", match[:matrix])

      assert_includes Array(job["needs"]), "changes", name
      refute_empty Array(keys), name
      Array(keys).each { |key| assert_includes images.keys, key, name }
    end

    refute_empty found
  end

  def test_a_job_that_runs_an_image_by_its_variable_reads_the_pins_first
    variables = images.keys.map { |key| key.upcase.tr("-", "_") }
    used = jobs.select do |name, job|
      steps = job.fetch("steps", [])
      uses = steps.index { |step| variables.any? { |variable| step["run"].to_s.include?("\"$#{variable}\"") } } or next

      reads = steps.index { |step| step["run"].to_s.match?(%r{\A\S*\.github/scripts/pinned-images\.sh env\b.*>> "\$GITHUB_ENV"\z}) }

      assert reads && reads < uses, "#{name} runs a pinned image before it reads the pins"
      assert_equal steps[uses]["if"], steps[reads]["if"], name if steps[reads]["if"]
      true
    end

    assert_operator used.size, :>=, 4
  end
end
