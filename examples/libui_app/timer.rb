# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT-0
#++

# Focus Timer's clock, in plain Ruby, apart from its window: a stretch of
# focused work, then a break, then work again, each counted down a
# second at a time while the timer runs.
#
#   timer = Timer.new(focus: 25, rest: 5)
#   timer.clock   # => "25:00 left"
#   timer.toggle  # running
#   timer.tick    # => nil, with 24:59 left
class Timer
  # Which stretch is counting down: +:focus+ or +:rest+.
  attr_reader :phase

  # The seconds left of the stretch.
  attr_reader :left

  # Minutes of focus, minutes of rest, and whether the next stretch
  # starts by itself when one ends.
  attr_reader :focus, :rest, :onward

  def initialize(focus: 25, rest: 5, onward: false) # :nodoc:
    @focus = focus
    @rest = rest
    @onward = onward
    @phase = :focus
    @left = total
    @running = false
  end

  # Whether the clock is counting down.
  def running?
    @running
  end

  # Starts the clock if it is stopped, and stops it if it runs.
  def toggle
    @running = !@running
  end

  # Stops the clock and starts the stretch over.
  def reset
    @running = false
    @left = total
  end

  # One second gone. When the stretch ends, the other begins, and runs
  # only if #onward; returns the phase that ended, or +nil+.
  def tick
    return unless @running

    @left -= 1
    return unless @left.zero?

    ended = @phase
    @phase = (ended == :focus) ? :rest : :focus
    @left = total
    @running = @onward
    ended
  end

  # New lengths, in minutes, and whether stretches run on. A stretch not
  # yet begun takes its new length; one under way keeps what it has
  # left, unless that is now more than the whole.
  def configure(focus:, rest:, onward:)
    fresh = @left == total
    @focus = focus
    @rest = rest
    @onward = onward
    @left = fresh ? total : [@left, total].min
  end

  # The stretch's whole length, in seconds.
  def total
    ((@phase == :focus) ? @focus : @rest) * 60
  end

  # How much of the stretch has gone, from 0 to 100.
  def progress
    100 * (total - @left) / total
  end

  # The time left, as the window shows it.
  def clock
    format("%02d:%02d left", @left / 60, @left % 60)
  end
end
