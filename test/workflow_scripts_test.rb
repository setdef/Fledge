# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "test_helper"

# A workflow that runs one of .github/scripts by its path, not through sh
# or bash, needs git to keep it executable: on a runner, a checkout sets
# a file's mode from the tree, and a script without its x bit stops the
# step with "Permission denied", which only CI would show.
class WorkflowScriptsTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  def test_every_script_a_workflow_runs_by_its_path_is_executable_in_git
    run = Dir[File.join(ROOT, ".github/workflows/*.yml")].flat_map { |file| commands(File.read(file)) }.uniq

    refute_empty run
    assert_includes run, ".github/scripts/deliver.sh"
    assert_empty run.reject { |path| modes.fetch(path, "missing") == "100755" }, "not tracked as 100755"
  end

  private def commands(text)
    text.each_line.reject { |line| line.lstrip.start_with?("#") }
      .flat_map { |line| line.scan(%r{(?<![\w/.-])(?<!sh |bash )(\.github/scripts/[\w.-]+\.sh)\b}).flatten }
  end

  private def modes
    @modes ||= IO.popen(["git", "ls-files", "-s", "-z", "--", ".github/scripts"], chdir: ROOT, &:read).split("\0")
      .to_h { |entry| entry.split("\t").then { |meta, path| [path, meta.split.first] } }
  end
end
