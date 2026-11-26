# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT-0
#++

# Dots appear one after another, up to five at a time. Click or tap a
# dot to pop it, and the score counts the clicks that popped one. That
# is all.
#
# POP_QUIT_AFTER=SECONDS makes the game print its score and quit after
# that many seconds, so that a check can run it with nobody at the
# screen.
#
# Each dot that appears is also reported on standard error, as "Pop: 3
# dots, 0 popped". A phone gives an app no environment variable to set,
# so there the line is how anyone reading the system log sees that the
# game is running and drawing. It goes to standard error so that the
# score on standard output stays the one line a desktop check reads.

# The radius of a dot, in pixels.
RADIUS = 36

# The most dots on the screen at once.
MOST = 5

# Pop's callbacks, which Lota calls.
module Lota
  # Starts a game with no dots and no score.
  def self.load
    @dots = []
    @score = 0
    @elapsed = 0.0
    @since = 1.0
    @quit_after = ENV["POP_QUIT_AFTER"]&.to_f
  end

  # Adds a dot each second while there are fewer than MOST, and quits
  # when POP_QUIT_AFTER seconds have passed.
  def self.update(dt)
    @elapsed += dt
    @since += dt
    if @since >= 1.0 && @dots.size < MOST
      @since = 0.0
      width, height = Lota::Graphics.dimensions
      @dots << [rand(RADIUS..(width - RADIUS)), rand((RADIUS + 40)..(height - RADIUS))]
      warn "Pop: #{@dots.size} #{(@dots.size == 1) ? 'dot' : 'dots'}, #{@score} popped"
    end
    return unless @quit_after && @elapsed >= @quit_after

    puts "Pop: #{@score} popped"
    Lota::Event.quit
  end

  # Draws the score and the dots.
  def self.draw
    Lota::Graphics.print("Score: #{@score}", 16, 12)
    @dots.each { |x, y| Lota::Graphics.circle(:fill, x, y, RADIUS) }
  end

  # Pops the dots under a click, and a tap on a phone arrives here too, as
  # LÖVE sends it. The score counts a click that popped any.
  def self.mousepressed(x, y, _button, _touch, _presses)
    popped = @dots.reject! { |dot_x, dot_y| ::Math.hypot(x - dot_x, y - dot_y) <= RADIUS }
    @score += 1 if popped
  end
end
