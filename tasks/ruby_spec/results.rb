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
    # description mapped to what MSpec printed about it, +totals+,
    # MSpec's last line ("N files, N examples, ..."), or nil when the run
    # stopped before it printed one, and +listing+, the examples it ran
    # (RubySpec::Listing), or nil when it printed none.
    class Run < Data.define(:directory, :failures, :totals, :listing)
      def initialize(directory:, failures:, totals:, listing: nil)
        super
      end

      # How many examples the totals count, or nil.
      def examples
        totals.to_s[/(\d+) examples?,/, 1]&.to_i
      end
    end

    # A difference between the two sides, of a +kind+: an example that
    # fails on one +side+ only (:stock or :app) (:fails), an example that
    # runs on one side only (:runs), a run of +name+ that did not finish
    # there (:stopped), or one whose list of the examples it ran is
    # missing or does not add up to its totals (:listing); with what
    # MSpec printed about it, and the justification that explains it, or
    # nil.
    class Difference < Data.define(:name, :side, :kind, :detail, :justification)
      SIDES = { stock: "stock Ruby", app: "the built app" }.freeze

      def justified?
        !justification.nil?
      end

      def to_s
        status = justified? ? "justified" : "DIFFERENT"
        where = SIDES.fetch(side)
        lines = [
          case kind
          when :stopped then "#{status}: #{name} did not finish in #{where}"
          when :listing then "#{status}: #{name} in #{where} listed no examples, or not as many as its totals count"
          when :runs then "#{status}: runs in #{where} only: #{name}"
          when :unused then "#{status}: a justification for #{where} explains no difference of this run: #{name}"
          else "#{status}: fails in #{where} only: #{name}"
          end,
        ]
        lines << "    why: #{justification.reason}" if justification
        lines.concat(detail.lines.first(6).map { |line| "    #{line.chomp}" }) unless justified? && kind != :runs
        lines.join("\n")
      end
    end

    # The Run that mspec-run's +output+ for +directory+ reports. MSpec's
    # default formatter numbers each failure ("1)"), then prints its
    # description ending in FAILED or ERROR, after "An exception occurred
    # during: HOOK" for an error in a hook, then the message and
    # backtrace, until the next number or "Finished in". A run of several
    # directories in one process, as on a phone, names each failure's
    # directory itself (RubySpecPhoneFormatter), and is read with
    # +directory+ nil.
    #
    # An error outside any example has no description of an example, so
    # MSpec prints its one line, "An exception occurred during: WHERE
    # ERROR" (ExceptionState#initialize, mspec/runner/exception.rb, lines
    # 11 to 19 at MSpec 521207f, with no state): WHERE is "loading PATH"
    # for a spec file that fails to load, a hook ("before :all", "after
    # :all") for an error in one that runs before or after a describe's
    # examples, or the describe's own name for an error in its body. A
    # file that fails to load is named by PATH inside ruby/spec, since
    # stock Ruby and the app load ruby/spec from different folders; the
    # rest by the spec file being loaded when it happened, the backtrace's
    # frame of "<top (required)>", and the line of that file the error
    # came through (Results.outside).
    def self.read(directory, output)
      lines = output.b.gsub("\r\n", "\n").lines
      failures = {}
      lines.each_with_index do |line, index|
        next unless line.match?(/\A\d+\)\n\z/)

        at = index + 1
        first = lines[at].to_s.chomp
        during = first[/\AAn exception occurred during: (.+) (?:FAILED|ERROR)\z/, 1]
        at += 1 if during.nil? && first.start_with?("An exception occurred during:")
        detail = lines.drop(at + 1).take_while { |rest| !rest.match?(/\A(?:\d+\)|Finished in )/) }.join
        description = during ? outside(directory, during, detail) : lines[at].to_s.chomp[/\A(.*) (?:FAILED|ERROR)\z/, 1]
        next unless description

        failures[[directory, description.dup.force_encoding(Encoding::UTF_8).scrub].compact.join(": ")] = detail
      end
      totals = lines.grep(/\A\d+ files?, \d+ examples?, /).last&.chomp
      Run.new(directory:, failures:, totals:, listing: Listing.read(directory, lines))
    end

    # The name of an error outside any example, in +during+ (WHERE, as
    # Results.read describes it) with +detail+ its message and backtrace:
    # "loading PATH", or "An exception occurred during: WHERE, at
    # FILE:LINE", with FILE the spec file being loaded and LINE the line
    # of it nearest the error, or without them when the backtrace names
    # no spec file. Each PATH and FILE is from where ruby/spec's
    # +directory+ begins; with +directory+ nil, the directory is FILE's
    # own, named before it as a run of one directory names it.
    def self.outside(directory, during, detail)
      if (path = during[/\Aloading (.+)\z/, 1])
        inside = inside(directory, path) or return "loading #{path}"
        return directory ? "loading #{inside}" : "#{inside.split('/').first}: loading #{inside}"
      end

      frames = detail.lines.filter_map { |frame| frame.chomp.match(/\A(.+?):(\d+):in /) }
      file = frames.reverse_each.find { |frame| frame.post_match.include?("<top (required)>") && inside(directory, frame[1]) }
      return "An exception occurred during: #{during}" unless file

      line = frames.find { |frame| frame[1] == file[1] }[2]
      inside = inside(directory, file[1])
      named = "An exception occurred during: #{during}, at #{inside}:#{line}"
      directory ? named : "#{inside.split('/').first}: #{named}"
    end

    # +path+ from where ruby/spec's +directory+, or any of DIRECTORIES
    # when nil, begins, or nil when it is not inside one.
    def self.inside(directory, path)
      path[%r{/spec/((?:#{directory ? Regexp.escape(directory) : DIRECTORIES.join('|')})/.+)\z}, 1]
    end

    # The differences between the +stock+ and +app+ runs, Arrays of Run
    # over the same directories in the same order, on +platform+: each
    # run that did not finish, each example that fails on one side only,
    # and each that runs on one side only (Listing.compare).
    def self.compare(stock, app, platform:)
      stopped = { stock:, app: }.flat_map do |side, runs|
        runs.select { |run| run.totals.nil? }.map do |run|
          Difference.new(name: run.directory, side:, kind: :stopped, detail: "", justification: nil)
        end
      end
      stock_failures = stock.map(&:failures).reduce({}, :merge)
      app_failures = app.map(&:failures).reduce({}, :merge)
      only = { stock: stock_failures.except(*app_failures.keys), app: app_failures.except(*stock_failures.keys) }
      failing = only.flat_map do |side, failures|
        failures.map do |name, detail|
          justification = JUSTIFIED.find { |candidate| candidate.explains?(name, side, platform) }
          Difference.new(name:, side:, kind: :fails, detail:, justification:)
        end
      end
      differences = stopped + failing + stock.zip(app).flat_map { |pair| Listing.compare(*pair, failing:, platform:) }
      differences + Justification.unused(JUSTIFIED, differences, platform)
    end
  end

  # Examples that may fail, or with +outcome+ :runs run, on one +side+
  # only (:stock or :app), on +platforms+ (every platform when nil), and
  # why that is right: each of +examples+ is an example's directory and
  # description, or a Regexp for a family of them, as a directory's
  # files that fail to load, and each must explain a difference in every
  # run on its platforms (Justification.unused), so none outlives the
  # differences it was written for or explains more than they.
  class Justification < Data.define(:examples, :side, :platforms, :reason, :outcome)
    def initialize(examples:, side:, platforms:, reason:, outcome: :fails)
      super
    end

    def applies?(platform)
      platforms.nil? || platforms.include?(platform)
    end

    def explains?(name, side_differing, platform, outcome_differing = :fails)
      side == side_differing && outcome == outcome_differing && applies?(platform) &&
        examples.any? { |example| Justification.names?(example, name) }
    end

    # Whether +example+, a name or a Regexp, names +name+.
    def self.names?(example, name)
      example.is_a?(Regexp) ? example.match?(name) : example == name
    end

    # A difference for each of the examples of each of +justifications+
    # on +platform+ that explains none of +differences+.
    def self.unused(justifications, differences, platform)
      justifications.select { |justification| justification.applies?(platform) }.flat_map do |justification|
        explained = differences.select { |difference| difference.justification.equal?(justification) }.map(&:name)
        justification.examples.reject { |example| explained.any? { |name| names?(example, name) } }.map do |example|
          Results::Difference.new(name: example.is_a?(Regexp) ? example.inspect : example, side: justification.side, kind: :unused,
            detail: "", justification: nil)
        end
      end
    end
  end
end
