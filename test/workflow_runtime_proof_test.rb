# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "test_helper"
require "yaml"

# The runtime's commit stage, runtime-proof.yml:
# on a push to trunk that changes what the proof reads, it runs the very
# task bin/check --runtime runs before the push, and its paths cover
# every file of the repository the proof's code loads or names.
class WorkflowRuntimeProofTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  COMMAND = 'bundle exec rake "runtime:prove[x86_64-linux]"'

  def test_it_runs_the_task_bin_check_runs_before_the_push
    commands = workflow.fetch("jobs").values.flat_map { |job| job.fetch("steps").filter_map { |step| step["run"] } }

    assert_includes commands, COMMAND
    assert_includes File.read(File.join(ROOT, "bin", "check")), "\"runtime:prove[\#{platform}]\""
    assert_equal %w[ubuntu-24.04], workflow.fetch("jobs").values.map { |job| job.fetch("runs-on") }
  end

  # Each push to trunk is judged alone, as the fast tier judges it, and
  # only a push to trunk starts it.
  def test_it_runs_on_a_push_to_trunk_each_in_a_group_of_its_own
    on = workflow.fetch(true)

    assert_equal %w[push workflow_dispatch], on.keys.sort
    assert_equal ["trunk"], on.dig("push", "branches")
    assert_includes workflow.dig("concurrency", "group"), "github.sha"
  end

  def test_its_paths_cover_every_file_the_proof_loads_or_names
    uncovered = proof_inputs.reject { |path| paths.any? { |glob| covers?(glob, path) } }

    assert_operator proof_inputs.size, :>=, 20
    assert_empty uncovered, "runtime-proof.yml's paths miss what the proof reads"
  end

  # A glob that matched nothing would hide a renamed folder.
  def test_every_path_names_something_in_the_repository
    files = Dir.glob("**/*", File::FNM_DOTMATCH, base: ROOT).reject { |path| path.start_with?(".git/") }

    paths.each { |glob| assert files.any? { |path| covers?(glob, path) }, "#{glob} matches nothing" }
  end

  def test_the_coverage_check_fails_for_a_file_outside_the_paths
    refute paths.any? { |glob| covers?(glob, "CONTRIBUTING.md") }
    assert paths.any? { |glob| covers?(glob, "tasks/runtime_proof.rb") }
  end

  private def paths = workflow.dig(true, "push", "paths")

  # GitHub's filter patterns: ** matches across folders, * within one;
  # a folder a proof names, as File.join(ROOT, "lib"), is covered by its "folder/**".
  private def covers?(glob, path)
    return true if glob == "#{path}/**"

    File.fnmatch?(glob.sub(%r{/\*\*\z}, "/**/*"), path, File::FNM_PATHNAME | File::FNM_DOTMATCH)
  end

  # The Ruby files tasks/runtime_proof.rb loads by require_relative, and
  # every path of the repository they name as a string, as
  # ".github/scripts/deliver.sh" or File.join(ROOT, "test", "fixtures",
  # "parity").
  private def proof_inputs
    @proof_inputs ||= begin
      loaded = closure(File.join(ROOT, "tasks", "runtime_proof.rb"))
      named = loaded.flat_map { |file| named_paths(File.read(file)) }
      (loaded.map { |file| file.delete_prefix("#{ROOT}/") } + named).uniq.select { |path| tracked?(path) }
    end
  end

  # What the repository holds, not what the computer has made in it: a
  # kept workspace has tmp/proof and tmp/runtime from earlier runs, which
  # git ignores and no push can change, so no path need cover them.
  private def tracked?(path)
    tracked_files.any? { |file| file == path || file.start_with?("#{path}/") }
  end

  private def tracked_files
    @tracked_files ||= IO.popen(["git", "-C", ROOT, "ls-files"], &:read).split("\n")
  end

  private def closure(file, seen = [])
    return seen if seen.include?(file)

    seen << file
    File.read(file).scan(/^\s*require_relative "([^"]+)"/).flatten.each do |name|
      required = File.expand_path("#{name}.rb", File.dirname(file))
      closure(required, seen) if File.exist?(required)
    end
    seen
  end

  private def named_paths(source)
    literals = source.scan(%r{"((?:\.github|bin|examples|test|runtime|lib|tasks|exe)/[\w./-]+)"}).flatten
    joined = source.scan(/File\.join\(ROOT((?:, "[^"]+")+)\)/).flatten.map { |args| args.scan(/"([^"]+)"/).flatten.join("/") }
    literals + joined
  end

  private def workflow
    @workflow ||= YAML.load_file(File.join(ROOT, ".github", "workflows", "runtime-proof.yml"))
  end
end
