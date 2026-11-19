# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "test_helper"
require_relative "../tasks/lint_files"

# The files the gate's lints read in this repository, which the fast
# check narrows to those a change touches, and how both find a tool on
# PATH.
class LintFilesTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  def test_the_shell_scripts_are_the_tracked_ones_that_start_with_a_shells_shebang
    scripts = LintFiles.shell(ROOT)

    assert_includes scripts, "bin/setup"
    assert_includes scripts, ".github/scripts/windows-ruby-env.sh"
    refute_includes scripts, "bin/check"
  end

  def test_the_c_is_the_launchers_and_the_mobile_embedding_apis
    sources = LintFiles.c(ROOT)

    assert_includes sources, "runtime/launcher/unix.c"
    assert_includes sources, "runtime/mobile/mobile.h"
    assert(sources.all? { |path| path.match?(%r{\Aruntime/(?:launcher|mobile)/.*\.[ch]\z}) })
  end

  def test_the_workflows_are_github_actions
    assert_includes LintFiles.workflows(ROOT), ".github/workflows/fast.yml"
  end

  def test_a_tool_is_found_on_path_with_windows_executable_extensions
    Dir.mktmpdir do |dir|
      name = Gem.win_platform? ? "shellcheck.exe" : "shellcheck"
      File.write(File.join(dir, name), "")
      File.chmod(0o755, File.join(dir, name))
      env = { "PATH" => ["/nowhere", dir].join(File::PATH_SEPARATOR), "PATHEXT" => ".com;.exe" }

      assert_equal [File.join(dir, name), nil], [LintFiles.which("shellcheck", env), LintFiles.which("actionlint", env)]
    end
  end
end
