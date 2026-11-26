# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "test_helper"
require "yaml"

# lib/fledge/linkage/windows.yml lets an ARM64 gem's DLL need opengl32.dll
# and glu32.dll because Windows 11 on ARM64 has both. Test
# (aarch64-mingw-ucrt, 1 of 2) checks that on every run with
# .github/scripts/read-system-opengl.rb, on windows-11-arm, in one step
# that fails the job when it stops being so.
class WorkflowSystemOpenglTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  SCRIPT = ".github/scripts/read-system-opengl.rb"

  def test_one_step_of_the_arm64_windows_test_job_checks_the_reading_and_fails_the_job
    job = YAML.safe_load_file(File.join(ROOT, ".github", "workflows", "ci.yml"), aliases: true).dig("jobs", "test-windows")
    steps = job.fetch("steps").select { |step| step["run"].to_s.include?(SCRIPT) }

    assert_includes job.dig("strategy", "matrix", "include").map { |entry| entry["os"] }, "windows-11-arm"
    assert_equal 1, steps.size
    assert_nil steps.first["continue-on-error"]
    assert_equal "matrix.platform == 'aarch64-mingw-ucrt' && matrix.shard == 1", steps.first["if"]
    assert_equal "ruby #{SCRIPT}", steps.first["run"]
  end

  def test_the_script_names_both_dlls_and_the_tool_the_runtime_carries
    source = File.read(File.join(ROOT, SCRIPT))

    assert_includes source, "%w[opengl32.dll glu32.dll]"
    assert_includes source, "Fledge::AppGems::READOBJ"
    assert_includes source, "--file-headers"
  end
end
