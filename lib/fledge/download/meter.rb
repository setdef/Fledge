# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require "uri"

module Fledge
  module Download
    # One try of a download, measured as its body arrives: it raises
    # Stalled when the body comes slower than its Pace allows, and says on
    # the log how far it got, every so often, when it takes long enough
    # that a person or a CI log would otherwise see nothing for minutes.
    class Meter # :nodoc:
      # A meter for the body of +url+, of +total+ bytes (or +nil+ when the
      # server did not say), held to +pace+, and reporting on +log+.
      def initialize(url, pace, total, log)
        @url = url
        @pace = pace
        @total = total
        @log = log
        @name = File.basename(URI(url).path.to_s)
        @started = @window = @reported = now
        @bytes = @window_bytes = 0
      end

      # Counts +size+ more bytes of the body.
      def add(size)
        @bytes += size
        @window_bytes += size
        time = now
        check(time)
        report(time)
      end

      # Raises Stalled when the window that ends at +time+ is over and
      # brought too little, and otherwise starts the next one.
      private def check(time)
        elapsed = time - @window
        return if elapsed < @pace.seconds
        if @window_bytes < @pace.bytes * elapsed
          raise Stalled, "could not download #{@url}: less than #{@pace.bytes} bytes a second for #{@pace.seconds} seconds"
        end

        @window = time
        @window_bytes = 0
      end

      private def report(time)
        log = @log
        return unless log && time - @reported >= @pace.report

        @reported = time
        log.puts "#{@name}: #{megabytes(@bytes)}#{of_total}, #{megabytes(@bytes / (time - @started))}/s"
      end

      private def of_total
        total = @total
        return "" unless total&.positive?

        " of #{megabytes(total)} (#{@bytes * 100 / total}%)"
      end

      private def megabytes(bytes)
        format("%.1f MB", bytes / 1_000_000.0)
      end

      private def now
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end
    end
  end
end
