# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "test_helper"
require "yaml"

# A Delivery job checks out only the paths its sparse checkout lists, so
# a step that names any other file of the repository finds nothing there,
# and only CI would show it: on 2026-11-22 three Delivery jobs passed
# examples/markdown_preview/welcome.md to deliver-markdown.sh with no
# examples/ in their checkout. Every path of the repository that a job's
# steps name must be under one its sparse checkouts list. A job with a
# whole checkout is left out; one with several sparse checkouts, each in
# a folder of its own (installed.yml's tag and its checks), is read as
# their union, which is enough to catch a path no checkout lists.
class WorkflowSparseCheckoutTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  TRACKED = IO.popen(["git", "ls-files", "-z"], chdir: ROOT, &:read).split("\0")
  TOP = TRACKED.filter_map { |path| path[%r{\A[^/]+(?=/)}] }.uniq
  PATH = %r{(?<![\w/.$-])((?:#{TOP.map { |name| Regexp.escape(name) }.join('|')})/[\w./-]*[\w-])}

  def test_every_repository_path_a_sparse_job_names_is_in_its_checkout
    jobs = sparse_jobs
    assert_includes jobs.keys, "delivery-musl"
    assert_includes named(jobs.fetch("delivery-musl").fetch(:steps)), ".github/scripts/deliver.sh"

    missing = jobs.flat_map do |name, job|
      named(job.fetch(:steps)).reject { |path| job.fetch(:listed).any? { |listed| covers?(listed, path) } }
        .map { |path| "#{name}: #{path}" }
    end
    assert_empty missing.uniq, "named by a step, missing from the job's sparse-checkout"
  end

  private def sparse_jobs
    Dir[File.join(ROOT, ".github/workflows/*.yml")].each_with_object({}) do |file, jobs|
      YAML.load_file(file, aliases: true).fetch("jobs").each do |name, job|
        steps = job.fetch("steps", [])
        checkouts = steps.select { |step| step["uses"].to_s.start_with?("actions/checkout@") }
        lists = checkouts.map { |step| step.dig("with", "sparse-checkout") }
        next if lists.empty? || lists.include?(nil)

        jobs[name] = { steps:, listed: lists.flat_map { |list| list.split("\n").map(&:strip).reject(&:empty?) } }
      end
    end
  end

  private def named(steps)
    steps.filter_map { |step| step["run"] }
      .flat_map { |text| text.each_line.reject { |line| line.lstrip.start_with?("#") } }
      .flat_map { |line| line.scan(PATH).flatten }
      .select { |path| TRACKED.any? { |file| covers?(path, file) } }
      .uniq
  end

  private def covers?(listed, path)
    path == listed || path.start_with?("#{listed.chomp('/')}/")
  end
end
