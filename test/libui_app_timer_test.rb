# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "test_helper"
require_relative "../examples/libui_app/timer"

# examples/libui_app's clock, apart from its window, which no test can
# watch: what the window shows and what its settings change.
class LibuiAppTimerTest < Minitest::Test
  def test_a_new_timer_waits_at_the_whole_focus_stretch
    timer = Timer.new(focus: 25, rest: 5)

    assert_equal [:focus, 1500, false, "25:00 left", 0], [timer.phase, timer.left, timer.running?, timer.clock, timer.progress]
  end

  def test_a_stopped_timer_does_not_count_down
    timer = Timer.new(focus: 1, rest: 1)

    assert_nil timer.tick
    assert_equal 60, timer.left
  end

  def test_a_running_timer_counts_down_a_second_each_tick
    timer = Timer.new(focus: 1, rest: 1)
    timer.toggle
    15.times { timer.tick }

    assert_equal ["00:45 left", 25], [timer.clock, timer.progress]
  end

  def test_the_end_of_focus_begins_the_break_and_stops
    timer = Timer.new(focus: 1, rest: 2)
    timer.toggle
    ended = Array.new(60) { timer.tick }.compact

    assert_equal [[:focus], :rest, 120, false], [ended, timer.phase, timer.left, timer.running?]
  end

  def test_onward_runs_the_next_stretch_by_itself
    timer = Timer.new(focus: 1, rest: 1, onward: true)
    timer.toggle
    ended = Array.new(120) { timer.tick }.compact

    assert_equal [[:focus, :rest], :focus, true], [ended, timer.phase, timer.running?]
  end

  def test_reset_stops_and_starts_the_stretch_over
    timer = Timer.new(focus: 1, rest: 1)
    timer.toggle
    10.times { timer.tick }
    timer.reset

    assert_equal [60, false], [timer.left, timer.running?]
  end

  def test_a_stretch_not_begun_takes_its_new_length
    timer = Timer.new(focus: 25, rest: 5)
    timer.configure(focus: 50, rest: 10, onward: true)

    assert_equal [3000, 50, 10, true], [timer.left, timer.focus, timer.rest, timer.onward]
  end

  def test_a_stretch_under_way_keeps_its_time_unless_it_is_now_too_long
    timer = Timer.new(focus: 2, rest: 1)
    timer.toggle
    10.times { timer.tick }
    timer.configure(focus: 3, rest: 1, onward: false)

    assert_equal 110, timer.left
    timer.configure(focus: 1, rest: 1, onward: false)

    assert_equal 60, timer.left
  end
end
