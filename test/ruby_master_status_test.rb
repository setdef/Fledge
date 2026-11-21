# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "test_helper"
require_relative "../tasks/ruby_master_status"

# The one place the nightly run against Ruby's master reports to: an
# issue whose body says the newest master Fledge passed on and what has
# failed since, and a run that fails only on the night something new
# breaks (doc/contributors/design/runtimes.md, "Testing against Ruby's
# master").
class RubyMasterStatusTest < Minitest::Test
  RUN = "https://github.com/setdef/Fledge/actions/runs/1"

  def night(revision, date, failed, run: RUN)
    RubyMasterStatus::Night.new(revision:, date:, failed:, run:)
  end

  def test_a_first_night_that_passes_records_it_and_passes
    status = RubyMasterStatus.read("").record(night("21ee43fb1e", "2026-11-20", []))

    assert_equal({ "revision" => "21ee43fb1e", "date" => "2026-11-20", "run" => RUN }, status.passed)
    assert_nil status.failing
    refute status.news?
    assert_includes status.body, "passed on Ruby's master of 2026-11-20, 21ee43fb1e"
  end

  def test_a_break_is_news_once_and_its_range_starts_after_the_last_pass
    passed = RubyMasterStatus.read("").record(night("aaaaaaaaaa", "2026-11-20", [])).body
    broken = RubyMasterStatus.read(passed).record(night("bbbbbbbbbb", "2026-11-21", ["Runtime (android)"]))
    again = RubyMasterStatus.read(broken.body).record(night("cccccccccc", "2026-11-22", ["Runtime (android)"]))

    assert broken.news?
    refute again.news?, "the same job failing again is not news"
    assert_equal({ "revision" => "bbbbbbbbbb", "date" => "2026-11-21", "jobs" => ["Runtime (android)"], "run" => RUN }, again.failing)
    assert_includes again.body, "https://github.com/ruby/ruby/compare/aaaaaaaaaa...bbbbbbbbbb"
    assert_includes again.body, "Runtime (android)"
    assert_includes again.body, "aaaaaaaaaa"
  end

  def test_another_job_breaking_while_one_is_broken_is_news
    broken = RubyMasterStatus.read("").record(night("bbbbbbbbbb", "2026-11-21", ["Runtime (android)"]))
    more = RubyMasterStatus.read(broken.body).record(night("cccccccccc", "2026-11-22", ["Runtime (android)", "Runtime (ios)"]))

    assert more.news?
    assert_equal %w[Runtime\ (android) Runtime\ (ios)], more.failing.fetch("jobs")
    assert_equal "bbbbbbbbbb", more.failing.fetch("revision"), "the range still starts at the first broken night"
  end

  def test_a_pass_after_a_break_clears_it
    broken = RubyMasterStatus.read("").record(night("bbbbbbbbbb", "2026-11-21", ["Runtime (ios)"]))
    fixed = RubyMasterStatus.read(broken.body).record(night("cccccccccc", "2026-11-22", []))

    assert_nil fixed.failing
    assert_equal "cccccccccc", fixed.passed.fetch("revision")
    refute fixed.news?
  end

  def test_a_body_a_person_edited_keeps_its_state_or_starts_afresh
    assert_nil RubyMasterStatus.read("Notes someone wrote").passed
    assert_nil RubyMasterStatus.read("<!-- ruby-master-state: not json -->").passed
  end
end
