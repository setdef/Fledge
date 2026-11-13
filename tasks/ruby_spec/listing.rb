# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

class RubySpec
  # The examples a run of mspec-run counted, as listing_config.rb prints
  # them after the totals, and the comparison of two runs' lists: each
  # example that ran on one side only, and what explains it.
  #
  # +examples+ holds each example as it ran (Ran), in order. +denied+
  # maps the location of each guard that left its block out to its name,
  # as "platform_is_not android". +count+ is the number the list ends
  # with, or nil when it never ended, or held a line it should not, as
  # when a log loses or splits a line.
  class Listing < Data.define(:examples, :denied, :count)
    BEGIN_LINE = "ruby/spec listing: begin\n"
    END_LINE = %r{\Aruby/spec listing: (\d+) examples\n\z}

    # An example as it ran: its +name+, its directory and description as
    # Results names a failure, the spec +file+ it ran in, the +location+
    # of its block inside ruby/spec, and the locations of the +guards+
    # that enclosed it.
    class Ran < Data.define(:name, :file, :location, :guards)
      # What the two sides' examples are matched by: the block's file
      # and line, which hold for both sides where a description may not,
      # or, for a block outside ruby/spec ("-", or a path of its own, as
      # MSpec's evaluate helper defines one block for many examples), the
      # name.
      def key
        [file, location.match?(%r{\A(?:-|/|[A-Za-z]:)}) ? name : location]
      end
    end

    # The listing in +lines+, mspec-run's output for +directory+ (nil
    # for a phone's run of every directory), or nil when it has none.
    def self.read(directory, lines)
      start = lines.rindex(BEGIN_LINE) or return
      examples = []
      denied = {}
      file = nil
      lines.drop(start + 1).each do |line|
        line = line.chomp.dup.force_encoding(Encoding::UTF_8).scrub
        if (ended = "#{line}\n"[END_LINE, 1])
          return new(examples:, denied:, count: ended.to_i)
        elsif line.start_with?("@ ")
          file = line.delete_prefix("@ ")
        elsif line.start_with?("=") && file
          guards, location, description = line.delete_prefix("=").split(/ /, 3)
          examples << Ran.new(name: "#{directory || file.split('/').first}: #{description}", file:, location:,
            guards: guards.split(","))
        elsif (denial = line.match(/\A- (\S+) (.+)\z/))
          denied[denial[1]] = denial[2]
        else
          break
        end
      end
      new(examples:, denied:, count: nil)
    end

    # Whether the list ended, and holds as many examples as it says and
    # as the +run+'s totals count.
    def complete?(run)
      !count.nil? && examples.size == count && run.examples == count
    end

    # The differences between the examples the +stock+ and +app+ Runs of
    # one directory ran, on +platform+, given the +failing+ differences
    # of every run, as Results.compare finds them. Nothing, when either
    # run stopped, which is a difference already; a :listing difference
    # for a run whose listing is missing or incomplete; and otherwise,
    # for each example that ran on one side only, one of:
    #
    # - nothing, when it failed on the other side, as an error in a
    #   before :each hook does, or a difference of :fails on the other
    #   side names its file, a file that failed to load or an error
    #   outside any example, since that difference is reported, justified
    #   or not, and these are what it kept from running;
    # - a justified difference for each guard of MSpec's platform_is or
    #   platform_is_not that enclosed it on the side that ran it and left
    #   it out on the other, since ruby/spec says by it that the example
    #   is not for that platform, as a phone's run against stock Ruby on
    #   the computer that runs its simulator meets;
    # - a difference that RubySpec::JUSTIFIED explains with +outcome+
    #   :runs, or an unjustified one, naming the other guards that left
    #   it out there, if any.
    def self.compare(stock, app, failing:, platform:)
      return [] if stock.totals.nil? || app.totals.nil?

      incomplete = { stock:, app: }.reject { |_, run| run.listing&.complete?(run) }
      unless incomplete.empty?
        return incomplete.map do |side, run|
          Results::Difference.new(name: run.directory, side:, kind: :listing, detail: "", justification: nil)
        end
      end

      { stock: [stock, app], app: [app, stock] }.flat_map do |side, (ran, other)|
        ran.listing.only(other.listing).filter_map do |occurrence|
          other.listing.explain(occurrence, other, side, failing:, platform:)
        end
      end.then { |differences| group(differences) }
    end

    # The examples this listing ran that +other+ did not: for each
    # example's block, those beyond as many as +other+ ran, matched first
    # by name and then by guards.
    def only(other)
      theirs = other.examples.group_by(&:key)
      examples.group_by(&:key).flat_map do |key, mine|
        missing = mine.dup
        theirs.fetch(key, []).each do |occurrence|
          index = missing.index { |ran| ran.name == occurrence.name } || missing.index { |ran| ran.guards == occurrence.guards } ||
            (missing.size - 1)
          missing.delete_at(index) unless index.negative?
        end
        missing
      end
    end

    # The difference, if any, that +occurrence+, which ran on +side+ and
    # not in +run+, this listing's run, is.
    def explain(occurrence, run, side, failing:, platform:)
      name = occurrence.name
      other_side = (side == :stock) ? :app : :stock
      return if run.failures.key?(name)
      return if failing.any? { |difference| difference.side == other_side && Listing.file(difference.name) == occurrence.file }

      left_out = occurrence.guards.select { |location| denied.key?(location) }
      platform_guard = left_out.find { |location| denied.fetch(location).start_with?("platform_is") }
      if platform_guard
        return Results::Difference.new(name:, side:, kind: :runs, detail: "#{denied.fetch(platform_guard)} at #{platform_guard}",
          justification: :guard)
      end

      detail = left_out.map { |location| "left out by #{denied.fetch(location)} at #{location} in #{Results::Difference::SIDES.fetch(other_side)}\n" }
      justification = JUSTIFIED.find { |candidate| candidate.explains?(name, side, platform, :runs) }
      Results::Difference.new(name:, side:, kind: :runs, detail: "at #{occurrence.location} in #{occurrence.file}\n#{detail.join}", justification:)
    end

    # The spec file a difference of :fails names when it is a file that
    # failed to load or an error outside any example, or nil.
    def self.file(name)
      name[/(?:: |\A)loading (\S+)\z/, 1] || name[/, at (\S+):\d+\z/, 1]
    end

    # +differences+, with those a platform guard explains, marked
    # +:guard+, made one for each guard and side, naming how many
    # examples it left out.
    def self.group(differences)
      guarded, rest = differences.partition { |difference| difference.justification == :guard }
      guarded.group_by { |difference| [difference.side, difference.detail] }.map do |(side, guard), each|
        other = Results::Difference::SIDES.fetch((side == :stock) ? :app : :stock)
        reason = "ruby/spec's own #{guard} leaves #{(each.size == 1) ? 'it' : 'them'} out on #{other}'s platform, which " \
          "ruby/spec says #{(each.size == 1) ? 'it is' : 'they are'} not for."
        Results::Difference.new(name: "#{each.size} example#{'s' unless each.size == 1} under #{guard}", side:, kind: :runs,
          detail: each.map { |difference| "#{difference.name}\n" }.join, justification: Guarded.new(reason:))
      end + rest
    end

    # Why ruby/spec's own guard explains a difference.
    class Guarded < Data.define(:reason)
    end
  end
end
