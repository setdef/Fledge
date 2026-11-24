# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT-0
#++

module Lectern
  # Shows lines a screen at a time, as less does, on the terminal's
  # alternate screen so that the shell's own text is there again after
  # q. It is written in Ruby, with nothing but the terminal, so that it
  # works where no less is installed, and on a computer with no Ruby.
  class Pager
    # What it writes to enter the alternate screen and hide the cursor
    # (xterm's control sequences).
    ENTER = "\e[?1049h\e[?25l"
    # What it writes to show the cursor and leave the alternate screen.
    LEAVE = "\e[?25h\e[?1049l"
    # The keys a Windows console sends after a prefix.
    CONSOLE_KEYS = { "H" => :up, "P" => :down, "I" => :page_up, "Q" => :page_down, "G" => :top, "O" => :bottom }.freeze
    # The help the status line gives.
    HELP = "q quit   space, b page   j, k line   g, G ends"

    # A pager of +lines+ on +output+, reading keys from +input+, in a
    # terminal +height+ rows tall.
    def initialize(lines, input:, output:, height:)
      @lines = lines
      @input = input
      @output = output
      @page = [height - 1, 1].max
      @top = 0
    end

    # Shows the first screen and acts on keys until the person quits.
    def run
      @output.write(ENTER)
      raw { show }
    ensure
      @output.write(LEAVE)
    end

    # The key that was pressed, as one of :down, :up, :page_down, :page_up,
    # :top, :bottom, :quit, or nil for a key that does nothing. The end of
    # input quits.
    def key
      char = read
      case char
      when nil, "q", "\u0003" then :quit
      when " ", "f", "\u0006" then :page_down
      when "b", "\u0002" then :page_up
      when "j", "\r", "\n" then :down
      when "k" then :up
      when "g" then :top
      when "G" then :bottom
      when "\e" then escape
      when "\u0000", "\u00E0" then extended
      end
    end

    private def show
      loop do
        draw
        case key
        when :quit then break
        when :down then scroll(1)
        when :up then scroll(-1)
        when :page_down then scroll(@page)
        when :page_up then scroll(-@page)
        when :top then @top = 0
        when :bottom then @top = last_top
        end
      end
    end

    private def scroll(rows)
      @top = (@top + rows).clamp(0, last_top)
    end

    private def last_top
      [@lines.size - @page, 0].max
    end

    private def draw
      visible = @lines[@top, @page] || []
      rows = visible + ([""] * (@page - visible.size))
      @output.write("\e[H#{rows.map { |line| "\e[2K#{line}" }.join("\r\n")}\r\n")
      last = [@top + @page, @lines.size].min
      status = " lines #{@top + 1}-#{last} of #{@lines.size}   #{HELP}"
      @output.write("\e[2K\e[7m#{status}\e[0m")
    end

    private def raw(&)
      if @input.respond_to?(:raw) && @input.tty?
        @input.raw(&)
      else
        yield
      end
    end

    private def read
      @input.respond_to?(:getch) ? @input.getch : @input.getc
    end

    # An escape: a lone one quits; a sequence is an arrow or a page key.
    private def escape
      return :quit unless pending?

      return nil unless read == "["

      case read
      when "A" then :up
      when "B" then :down
      when "H" then :top
      when "F" then :bottom
      when "5" then (read == "~") ? :page_up : nil
      when "6" then (read == "~") ? :page_down : nil
      end
    end

    # What a Windows console sends for a function key: a prefix, then a code.
    private def extended
      CONSOLE_KEYS[read]
    end

    # Whether more of an escape sequence is waiting: a key that is only
    # the escape key sends nothing after it.
    private def pending?
      @input.respond_to?(:wait_readable) ? @input.wait_readable(0.05) : true
    end
  end
end
