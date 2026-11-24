# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "test_helper"
require "yaml"

# Every folder under examples/ is built by a job of CI. The workflows
# name each app they build by hand, in lists and single commands, and
# nothing else compared the folders with them: examples/rooibos_console
# and examples/sdl_phone were built by no job for weeks, and
# rooibos_console stopped building when the runtimes moved to Ruby 4.1's
# preview, with nothing red to say so (issues 44, 56, and 57). The
# maintainer's answer (issue 67) was to remove an example that cannot
# be built until it can: rooibos_console is restored from git history
# (plan 003, the story "A framework wrapper ships an app through Fledge").
#
# This test reads what a job runs, the +run+ text of every step of every
# workflow, and the scripts and tasks those steps start (every file under
# .github/scripts and tasks, a slight over-reading that names a folder a
# task mentions but no job runs), leaving out comment lines, and fails
# for a folder none of them names, naming the folder. A folder that
# cannot be built for now goes in LEFT_OUT, with its reason beside it;
# an entry whose folder is built, or is gone, fails too, so the list
# shrinks as examples are fixed.
class WorkflowExamplesTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  # The folders under examples/ that no job builds on purpose, each with
  # why. Only the maintainer's decision adds one (issue 67).
  LEFT_OUT = {}.freeze

  def test_every_folder_under_examples_is_built_by_a_job_or_left_out_with_a_reason
    folders = example_folders
    assert_includes folders, "hello"

    assert_empty unbuilt(folders, job_text) - LEFT_OUT.keys, "folders under examples/ that no workflow, script, or task builds " \
      "(add them to the jobs, or to LEFT_OUT with the reason)"
  end

  def test_a_folder_left_out_is_one_that_exists_and_is_built_by_no_job
    folders = example_folders
    stale = LEFT_OUT.keys - unbuilt(folders, job_text)
    assert_empty stale, "left out of the check, but built by a job or gone: remove it from LEFT_OUT"
    assert(LEFT_OUT.values.all? { |reason| reason.length > 20 }, "each folder left out says why")
  end

  def test_a_folder_named_only_in_a_comment_or_by_a_longer_name_is_not_built
    text = <<~TEXT
      # examples/ghost is built here
      ruby fledge build examples/ghosts
      apps=(examples/hello examples/real test/fixtures/ghost)
    TEXT
    assert_equal %w[ghost], unbuilt(%w[ghost ghosts hello real], text)
  end

  private def example_folders
    Dir.children(File.join(ROOT, "examples")).select { |name| File.directory?(File.join(ROOT, "examples", name)) }.sort
  end

  # The folders that +text+ does not name as examples/NAME (or as the
  # File.join of "examples" and "NAME"), by lines that are not comments.
  private def unbuilt(folders, text)
    lines = text.each_line.reject { |line| line.lstrip.start_with?("#") }.join
    folders.reject do |name|
      lines.match?(%r{examples(?:/|["']\s*,\s*["'])#{Regexp.escape(name)}(?![\w-])})
    end
  end

  private def job_text
    runs = Dir[File.join(ROOT, ".github/workflows/*.yml")].flat_map do |file|
      YAML.load_file(file, aliases: true).fetch("jobs").values.flat_map { |job| job.fetch("steps", []) }
    end.filter_map { |step| step["run"] }
    files = Dir[File.join(ROOT, ".github/scripts/**/*"), File.join(ROOT, "tasks/**/*")].select { |path| File.file?(path) }
    (runs + files.map { |path| File.read(path, encoding: "UTF-8").scrub }).join("\n")
  end
end
