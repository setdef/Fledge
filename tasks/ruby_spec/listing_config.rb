# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

# MSpec's configuration for listing the examples a ruby/spec run ran,
# which mspec-run loads with -B on the desktop, and which
# phone_config.rb requires on a phone, in the app and in stock Ruby
# alike (RubySpec::Listing reads what it prints).
#
# Comparing failures alone misses an example that ran on one side only:
# one a guard of ruby/spec's left out on one side, or one in a file or
# describe whose error kept it from running there. So when the run
# finishes, after MSpec's totals, the formatter prints every example
# MSpec counted, as TallyAction counts them (each :example event, and
# each :tagged one, for an example a filter such as -E left out, so the
# count matches the totals' "N examples"), under the spec file it ran
# in: the guards that enclosed it where it was defined, the file and
# line of its block, and its description. Then every guard that left
# its block out, each by the file and line of its block and what MSpec
# names it in its reports (SpecGuard#report_key):
#
#   ruby/spec listing: begin
#   @ core/array/each_spec.rb
#   = core/array/each_spec.rb:12 Array#each yields each element to the block
#   =core/process/groups_spec.rb:3,core/process/groups_spec.rb:5 core/process/groups_spec.rb:6 Process.groups gets an Array
#   - core/process/groups_spec.rb:5 platform_is_not android
#   ruby/spec listing: 32681 examples
#
# The block's line, not the description, is what the comparison matches
# the two sides' examples by: a description holds what the spec
# inspected as it loaded, which the locale changes, as String#inspect
# escapes a character the default external encoding cannot show.
#
# A guard is MSpec's: a SpecGuard's run_if or run_unless with a block,
# as platform_is and ruby_version_is call them, or the guard and
# guard_not helpers. An example defined in a shared describe is
# enclosed by the guards around it in the shared file and those around
# the it_behaves_like that copied it (ExampleState#initialize_copy). It
# reads MSpec's own state and changes nothing an example sees; it wraps
# guard and guard_not on Object as phone_config.rb wraps ruby_exe,
# adding no module to Object's ancestors.

require "mspec/runner/formatters/dotted"

module RubySpecListing
  # Where mspec-run runs, ruby/spec's folder, as it is named and as it
  # is resolved, in lower case, since Windows names a drive either way.
  SPEC = [Dir.pwd, File.realpath(Dir.pwd)].map { |folder| "#{folder.tr('\\', '/').downcase}/" }.uniq.freeze

  # Where to write the listing, when RUBY_SPEC_LISTING names a file, as
  # main.rb has it on a phone, whose log drops lines when a process
  # writes tens of thousands at once; the formatter then prints only
  # "ruby/spec listing: in PATH". Read as MSpec starts, before any
  # example changes ENV.
  FILE = ENV.fetch("RUBY_SPEC_LISTING", nil)

  # ruby/spec's own folders, which a path inside it begins with.
  FOLDERS = %w[language core library command_line security shared fixtures optional].freeze

  @guards = []
  @denied = {}

  class << self
    # The guards that enclose the code being loaded, outermost first.
    attr_reader :guards

    # Each guard that left its block out, by location, with its name.
    attr_reader :denied

    # +path+ inside ruby/spec, as stock Ruby and the app, which run it
    # from different folders, both name it.
    def relative(path)
      inside(path) || path.to_s
    end

    # +path+ inside ruby/spec, or nil when it is not, as for a block
    # MSpec's own helpers define.
    def inside(path)
      path = path.to_s.tr("\\", "/")
      folder = SPEC.find { |spec| path.downcase.start_with?(spec) }
      return path.byteslice(folder.bytesize, path.bytesize) if folder

      path[%r{/spec/((?:#{FOLDERS.join('|')})/.+)\z}, 1]
    end

    # Runs the guard whose +block+ the given block passes on to it,
    # wrapped to stand among #guards while it runs, and records it in
    # #denied, named by +name+'s result, when the guard leaves it out.
    def guarded(block, name)
      return yield(nil) unless block

      location = "#{relative(block.source_location[0])}:#{block.source_location[1]}"
      ran = false
      result = yield(proc do |*arguments|
        ran = true
        @guards.push(location)
        begin
          block.call(*arguments)
        ensure
          @guards.pop
        end
      end)
      @denied[location] ||= name.call unless ran
      result
    end

    # Wraps MSpec's guards and the copying of a shared example, once,
    # before the first spec file loads.
    def install
      return if @installed

      @installed = true
      SpecGuard.prepend(Guard)
      ExampleState.prepend(Copy)
      Object.class_eval do
        alias_method :ruby_spec_listing_guard, :guard
        alias_method :ruby_spec_listing_guard_not, :guard_not
        private def guard(condition, &block)
          RubySpecListing.guarded(block, -> { "guard" }) { |inner| ruby_spec_listing_guard(condition, &inner) }
        end
        private def guard_not(condition, &block)
          RubySpecListing.guarded(block, -> { "guard_not" }) { |inner| ruby_spec_listing_guard_not(condition, &inner) }
        end
      end
    end
  end

  # A SpecGuard that records its block among the guards.
  module Guard
    def run_if(name, &block)
      RubySpecListing.guarded(block, -> { report_key.strip }) { |inner| super(name, &inner) }
    end

    def run_unless(name, &block)
      RubySpecListing.guarded(block, -> { report_key.strip }) { |inner| super(name, &inner) }
    end
  end

  # An example copied into a describe by it_behaves_like, enclosed by
  # the guards around that call too.
  module Copy
    def initialize_copy(other)
      super
      @ruby_spec_guards = RubySpecListing.guards + (other.instance_variable_get(:@ruby_spec_guards) || [])
    end
  end

  def register
    super
    MSpec.register :load, self
    MSpec.register :add, self
    MSpec.register :example, self
    MSpec.register :tagged, self
    @ran = []
  end

  # Before each spec file loads.
  def load
    RubySpecListing.install
  end

  # As each example is defined.
  def add(example)
    example.instance_variable_set(:@ruby_spec_guards, RubySpecListing.guards.dup)
  end

  # As each example has run.
  def example(state, _block)
    guards = state.instance_variable_get(:@ruby_spec_guards) || []
    block = state.example&.source_location
    inside = block && RubySpecListing.inside(block[0])
    location = inside ? "#{inside}:#{block[1]}" : "-"
    @ran << [RubySpecListing.relative(MSpec.file), guards.join(","), location, state.description.gsub("\n", "\\n")]
  end

  # As each example a filter left out is counted.
  def tagged(state)
    example(state, nil)
  end

  def finish
    super
    file = nil
    lines = ["ruby/spec listing: begin\n"]
    @ran.each do |path, guards, location, description|
      lines << "@ #{path}\n" unless path == file
      file = path
      lines << "=#{guards} #{location} #{description}\n"
    end
    RubySpecListing.denied.each { |location, name| lines << "- #{location} #{name}\n" }
    lines << "ruby/spec listing: #{@ran.size} examples\n"
    if RubySpecListing::FILE
      File.binwrite(RubySpecListing::FILE, lines.join)
      print "ruby/spec listing: in #{RubySpecListing::FILE}\n"
    else
      print(*lines)
    end
  end
end

# MSpec's dotted formatter, which mspec-run takes for a run of a few
# folders, with the listing.
class RubySpecListingFormatter < DottedFormatter
  include RubySpecListing
end

MSpecScript.set :formatter, RubySpecListingFormatter
