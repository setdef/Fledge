# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "../test_helper"
require "fileutils"
require "open3"
require "tmpdir"

# .github/scripts/ruby-master-result.sh and ruby-master-report.sh, which
# ruby-master.yml's jobs and its report run (doc/contributors/design/
# runtimes.md, "Testing against Ruby's master"), night after night,
# against a gh of the test's own that keeps the one issue's body in a
# file: the first night opens the issue, a new break fails the run once,
# the same break the next night does not, and a job that recorded
# nothing counts as failed.
class RubyMasterReportTest < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)
  JOBS = ["Runtime (ios)", "Runtime (android)"].freeze

  FAKE_GH = <<~SH
    #!/bin/sh
    echo "$*" >> "$FAKE/log"
    case "$1 $2" in
      "issue list") cat "$FAKE/number" 2>/dev/null || true ;;
      "issue view") cat "$FAKE/body" ;;
      "issue create") cp "$8" "$FAKE/body"; echo 7 > "$FAKE/number" ;;
      "issue edit") cp "$7" "$FAKE/body" ;;
    esac
  SH

  def setup
    @work = Dir.mktmpdir
    @fake = File.join(@work, "fake")
    FileUtils.mkdir_p(@fake)
    File.write(File.join(@fake, "gh"), FAKE_GH)
    File.chmod(0o755, File.join(@fake, "gh"))
    FileUtils.mkdir_p(File.join(@work, "tasks"))
    FileUtils.cp(File.join(ROOT, "tasks", "ruby_master_status.rb"), File.join(@work, "tasks"))
  end

  def teardown
    FileUtils.rm_rf(@work)
  end

  def night(revision, date, outcomes)
    FileUtils.rm_rf(File.join(@work, "tmp"))
    outcomes.each do |job, outcome|
      _, status = Open3.capture2e("sh", File.join(ROOT, ".github", "scripts", "ruby-master-result.sh"), job, outcome, chdir: @work)
      assert status.success?
    end
    FileUtils.mv(File.join(@work, "tmp", "ruby-master-result"), File.join(@work, "tmp", "results")) if outcomes.any?
    env = {
      "PATH" => "#{@fake}#{File::PATH_SEPARATOR}#{ENV.fetch('PATH')}",
      "FAKE" => @fake,
      "GITHUB_REPOSITORY" => "setdef/Fledge",
      "REVISION" => revision,
      "DATE" => date,
      "RUN" => "https://example.test/runs/#{revision}",
      "GITHUB_STEP_SUMMARY" => File.join(@work, "summary"),
    }
    output, status = Open3.capture2e(env, "bash", File.join(ROOT, ".github", "scripts", "ruby-master-report.sh"), *JOBS, chdir: @work)
    [status.exitstatus, output]
  end

  def body
    File.read(File.join(@fake, "body"))
  end

  def log
    File.readlines(File.join(@fake, "log"), chomp: true)
  end

  def test_opens_the_issue_once_and_fails_only_the_night_something_breaks
    status, output = night("aaaaaaaaaa", "2026-11-20", JOBS.to_h { [it, "success"] })
    assert_equal 0, status, output
    assert_includes body, "Fledge last passed on Ruby's master of 2026-11-20, aaaaaaaaaa"
    assert_equal 1, log.grep(/\Aissue create /).size

    status, output = night("bbbbbbbbbb", "2026-11-21", { "Runtime (ios)" => "failure", "Runtime (android)" => "success" })
    assert_equal 1, status, output
    assert_includes output, "::error::A job failed on Ruby's master that had not been failing: Runtime (ios)"
    assert_includes body, "https://github.com/ruby/ruby/compare/aaaaaaaaaa...bbbbbbbbbb"

    status, output = night("cccccccccc", "2026-11-22", { "Runtime (ios)" => "failure", "Runtime (android)" => "success" })
    assert_equal 0, status, output
    assert_includes body, "Failing since Ruby's master of 2026-11-21, bbbbbbbbbb"
    assert_equal 1, log.grep(/\Aissue create /).size
    assert_equal 2, log.grep(/\Aissue edit 7 /).size
  end

  def test_a_job_that_recorded_nothing_counts_as_failed
    status, output = night("aaaaaaaaaa", "2026-11-20", { "Runtime (ios)" => "success" })

    assert_equal 1, status, output
    assert_includes body, "Runtime (android)"
  end
end
