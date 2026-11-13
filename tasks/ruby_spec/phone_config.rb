# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

# MSpec's configuration for the phones' ruby/spec run
# (tasks/ruby_spec/phone.rb), which mspec-run loads with -B, in the app
# and in stock Ruby alike.
#
# A phone app runs once per launch and takes no arguments, so a phone
# runs every directory in one mspec-run, where the desktop runs one
# process per directory. RubySpecPhoneFormatter prints what MSpec's
# summary formatter prints, the failures and the totals without a dot
# for each example, and names before each failure's description the
# directory of the spec file it happened in, as the desktop's
# comparison names each failure by its run's directory
# (RubySpec::Results.read), and after the totals lists the examples
# that ran, as listing_config.rb does on the desktop.
#
# iOS lets no app run a program, Ruby least of all
# (doc/contributors/design/phone-projects.md, "Parity on a phone"), so
# there MSpec's ruby_exe helper, which starts the Ruby under test, skips
# its example where that Ruby is not a program, as it skips on WASI,
# which has no processes either (mspec/helpers/ruby_exe.rb). Where it
# is, under stock Ruby, it runs as MSpec's own. It skips as MSpec's
# skip does, by raising SkippedSpecError, since fixtures call it outside
# examples too. ruby_exe is MSpec's, not Ruby's; the examples of Ruby's
# own ways to start a program still run, where a phone can. Android's
# runtime has a ruby program, which RbConfig.ruby names (ADR 069), so
# on Android ruby_exe never skips: a Ruby that is not there fails its
# examples, as it would on a desktop.

require "mspec/runner/formatters/summary"
require_relative "listing_config"

class RubySpecPhoneFormatter < SummaryFormatter
  include RubySpecListing

  # The folder of ruby/spec, which main.rb made the working folder
  # before mspec-run loaded this file.
  SPEC = "#{File.realpath(Dir.pwd)}/".freeze

  # MSpec's filter of the examples to leave out of the spec files of
  # which only some run (RubySpec::Phone::Exclusion's +keep+, which
  # main.rb reads from arguments.txt as RUBY_SPEC_KEEP): every example of
  # such a file but those kept. MSpec asks it, as it asks -E's, while
  # the file is being loaded, so MSpec.file is the example's own.
  class Keep
    def initialize(kept)
      @kept = kept
    end

    def ===(description)
      kept = @kept[RubySpecListing.relative(MSpec.file)] or return false
      !kept.include?(description)
    end
  end

  def register
    super
    MSpec.register :start, self
    MSpec.register :exclude, Keep.new(RUBY_SPEC_KEEP) if defined?(RUBY_SPEC_KEEP) && !RUBY_SPEC_KEEP.empty?
  end

  # When the run starts, MSpec has defined its helpers, ruby_exe among
  # them, on Object; this wraps it, adding no module to Object's
  # ancestors, which examples of Module#ancestors and Marshal read.
  def start
    super
    Object.class_eval do
      alias_method :ruby_spec_phone_ruby_exe, :ruby_exe
      private def ruby_exe(...)
        unless RUBY_PLATFORM.include?("android") || File.executable?(RUBY_EXE.split.first)
          raise SkippedSpecError, "iOS lets no app run a program"
        end
        ruby_spec_phone_ruby_exe(...)
      end
    end
  end

  def exception(exception)
    (@directories ||= []) << MSpec.file.to_s.delete_prefix(SPEC).split("/").first
    super
  end

  # BaseFormatter#print_exception, with the directory before the
  # description, after the hook an error happened in, if any. An error
  # outside any example, as in loading a spec file, has only the hook,
  # which names the file, and is printed as MSpec prints it.
  def print_exception(exception, count)
    lines = exception.description.split("\n")
    lines[-1] = "#{@directories[count - 1]}: #{lines[-1]}" unless exception.it.empty?
    outcome = exception.failure? ? "FAILED" : "ERROR"
    @err.print "\n#{count})\n", *lines[0...-1].map { |line| "#{line}\n" }, "#{lines[-1]} #{outcome}\n"
    @err.print exception.message, "\n"
    @err.print exception.backtrace, "\n"
  end
end

MSpecScript.set :formatter, RubySpecPhoneFormatter
