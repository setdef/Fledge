# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: MIT-0
#++

# The app ADR 025's spike ships to iOS, iPadOS, and Android: Ruby drives
# a frame loop that SDL3 runs, from a gem's C extension. Each frame, Ruby
# picks the background's color, which cycles, and the place of a white
# square, which follows the last touch. It prints the thread it runs on,
# how deep its stack is, the frames it has drawn, and each touch, which
# the Mobile apps jobs read from the system log. It stops a moment after
# the first touch, or after a minute.
require "sdl_demo"

# Each line reaches the log as it is printed, not when the game ends:
# standard output is a pipe on a phone, which Ruby otherwise buffers.
$stdout.sync = true

# How deep Ruby recurses here before SystemStackError, through a C
# method (Array#each) at every level, as most Ruby code does, so that
# the machine stack runs out as well as Ruby's own.
def depth
  level = 0
  dive = lambda do |count|
    level = count
    [count + 1].each { |deeper| dive.call(deeper) }
  end
  begin
    dive.call(0)
  rescue SystemStackError
    level
  end
end

# The background's color at +frame+: a hue that goes round once in four
# seconds at 60 frames a second.
def color(frame)
  hue = (frame % 240) / 40.0
  rising = (255 * (hue % 1)).round
  falling = 255 - rising
  [[255, rising, 0], [falling, 255, 0], [0, 255, rising], [0, falling, 255], [rising, 0, 255], [255, 0, falling]][hue.floor]
end

size, main_thread = SdlDemo.stack
puts "SdlDemo runs Ruby on #{main_thread ? 'the main thread' : 'a thread of its own'} with a stack of " \
  "#{size / 1024} KB, on #{RUBY_PLATFORM} with SDL #{SdlDemo.sdl_version}"
puts "SdlDemo recurses #{depth} levels deep"

point = nil
touched_at = nil
frames = SdlDemo.run(60) do |frame, width, height, touches|
  touches.each do |x, y, kind|
    point = [x, y]
    next unless kind == :down

    touched_at ||= frame
    puts "SdlDemo touch down at #{x.round}, #{y.round} in #{width}x#{height}, frame #{frame}"
  end
  puts "SdlDemo drew #{frame} frames" if frame.positive? && (frame % 60).zero?
  next nil if touched_at && frame > touched_at + 90

  x, y = point || [width / 2.0, height / 2.0]
  [*color(frame), x, y]
end
puts "SdlDemo drew #{frames} frames in all, #{touched_at ? 'after a touch' : 'with no touch'}"
