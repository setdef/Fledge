# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

class RubySpec
  # What mspec-run reports, read, and compared between stock Ruby and a
  # built app: every example that fails on one side only, and whether
  # JUSTIFIED explains it.
  module Results
    # One run of mspec-run over +directory+ (core, library, ...):
    # +failures+, each failed or errored example's directory and
    # description mapped to what MSpec printed about it, and +totals+,
    # MSpec's last line ("N files, N examples, ..."), or nil when the run
    # stopped before it printed one.
    class Run < Data.define(:directory, :failures, :totals)
    end

    # An example that fails on one +side+ only (:stock or :app), or a
    # run of +name+ that did not finish there (+stopped+), and the
    # justification that explains it, or nil.
    class Difference < Data.define(:name, :side, :stopped, :detail, :justification)
      SIDES = { stock: "stock Ruby", app: "the built app" }.freeze

      def justified?
        !justification.nil?
      end

      def to_s
        status = justified? ? "justified" : "DIFFERENT"
        return "#{status}: #{name} did not finish in #{SIDES.fetch(side)}" if stopped

        lines = ["#{status}: fails in #{SIDES.fetch(side)} only: #{name}"]
        lines << "    why: #{justification.reason}" if justification
        lines.concat(detail.lines.first(6).map { |line| "    #{line.chomp}" }) unless justified?
        lines.join("\n")
      end
    end

    # The Run that mspec-run's +output+ for +directory+ reports. MSpec's
    # default formatter numbers each failure ("1)"), then prints its
    # description ending in FAILED or ERROR, after "An exception occurred
    # during: HOOK" for an error in a hook, then the message and
    # backtrace, until the next number or "Finished in".
    def self.read(directory, output)
      lines = output.b.gsub("\r\n", "\n").lines
      failures = {}
      lines.each_with_index do |line, index|
        next unless line.match?(/\A\d+\)\n\z/)

        at = index + 1
        at += 1 if lines[at].to_s.start_with?("An exception occurred during:")
        description = lines[at].to_s.chomp[/\A(.*) (?:FAILED|ERROR)\z/, 1] or next
        detail = lines.drop(at + 1).take_while { |rest| !rest.match?(/\A(?:\d+\)|Finished in )/) }.join
        failures["#{directory}: #{description.dup.force_encoding(Encoding::UTF_8).scrub}"] = detail
      end
      totals = lines.grep(/\A\d+ files?, \d+ examples?, /).last&.chomp
      Run.new(directory:, failures:, totals:)
    end

    # The differences between the +stock+ and +app+ runs, Arrays of Run
    # over the same directories, on +platform+.
    def self.compare(stock, app, platform:)
      stopped = { stock:, app: }.flat_map do |side, runs|
        runs.select { |run| run.totals.nil? }.map do |run|
          Difference.new(name: run.directory, side:, stopped: true, detail: "", justification: nil)
        end
      end
      stock_failures = stock.map(&:failures).reduce({}, :merge)
      app_failures = app.map(&:failures).reduce({}, :merge)
      only = { stock: stock_failures.except(*app_failures.keys), app: app_failures.except(*stock_failures.keys) }
      stopped + only.flat_map do |side, failures|
        failures.map do |name, detail|
          justification = JUSTIFIED.find { |candidate| candidate.explains?(name, side, platform) }
          Difference.new(name:, side:, stopped: false, detail:, justification:)
        end
      end
    end
  end

  # An example that may fail on one +side+ only (:stock or :app), on
  # +platforms+ (every platform when nil), when its directory and
  # description match +example+, and why that is right.
  class Justification < Data.define(:example, :side, :platforms, :reason)
    def explains?(name, side_failing, platform)
      side == side_failing && (platforms.nil? || platforms.include?(platform)) && example.match?(name)
    end
  end
end
