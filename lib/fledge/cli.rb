# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "version"
require_relative "cli/build"

module Fledge
  # Runs the +fledge+ command line.
  #
  # A command-line tool answers <tt>--help</tt> and <tt>--version</tt>,
  # hands each command its own arguments, and turns every mistake into a
  # message and an exit status, never a backtrace. GNU's and the BSDs'
  # conventions tell the two kinds of mistake apart: a usage error
  # prints a short usage to standard error and exits with status 2, and a
  # failed operation exits with status 1 (ADR 002). Spread across an
  # executable, that logic is hard to test and easy to let drift from
  # the help text.
  #
  # This class keeps it in one place. It reads its help from the comment
  # header at the top of the executable, between a <tt>####</tt> line and
  # a <tt>###</tt> line, so the help a person reads in the source is the
  # help +fledge+ prints. It writes to the streams you give it and
  # returns an exit status instead of exiting, so a test can run it with
  # StringIO.
  #
  # Use it to run +fledge+ from its executable, or from a test or another
  # tool. Add a command by adding a class to COMMANDS.
  #
  # === Examples
  #
  #--
  # SPDX-SnippetBegin
  # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
  # SPDX-License-Identifier: MIT-0
  #++
  #   # exe/fledge:
  #   exit Fledge::CLI.new(help_path: __FILE__).call(ARGV)
  #
  #   # A test, through real streams:
  #   out = StringIO.new
  #   err = StringIO.new
  #   cli = Fledge::CLI.new(help_path: "exe/fledge", out:, err:)
  #   cli.call(["--version"]) # => 0
  #   out.string              # => "fledge 0.0.0\n"
  #   cli.call(["frobnicate"]) # => 2
  #   err.string.lines.first # => "fledge: 'frobnicate' is not a fledge command\n"
  #--
  # SPDX-SnippetEnd
  #++
  class CLI
    # The commands +fledge+ runs, by name. Each is a class whose +new+
    # takes <tt>out:</tt> and <tt>err:</tt> and whose +call+ takes the
    # arguments after the command's name and returns an exit status.
    COMMANDS = { "build" => Build }.freeze

    # Creates a command line.
    #
    # [help_path] The executable whose comment header is the help text.
    # [out] Where help, the version, and results go (default:
    #       <tt>$stdout</tt>).
    # [err] Where errors go (default: <tt>$stderr</tt>).
    # [commands] The command table (default: COMMANDS).
    def initialize(help_path:, out: $stdout, err: $stderr, commands: COMMANDS)
      @help_path = help_path
      @out = out
      @err = err
      @commands = commands
    end

    # Runs +argv+ and returns the exit status: 0 for success, 1 when a
    # command fails, and 2 for a usage error. Leaves +argv+ unchanged.
    #
    # <tt>-h</tt>, <tt>-?</tt>, and <tt>--help</tt> print the help, and
    # <tt>-v</tt> and <tt>--version</tt> the version, to the output
    # stream. With no arguments, or with arguments it cannot make sense
    # of, it prints the usage and <tt>Try 'fledge --help'.</tt> to the
    # error stream and returns 2, since a bare +fledge+ asked for nothing.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   Fledge::CLI.new(help_path: "exe/fledge").call(["--help"]) # => 0
    #--
    # SPDX-SnippetEnd
    #++
    def call(argv)
      name, *arguments = argv
      case name
      when nil then usage_error(nil)
      when "--help", "-h", "-?" then succeed_with(help)
      when "--version", "-v" then succeed_with("fledge #{VERSION}")
      when /\A-/ then usage_error("fledge: unrecognized option '#{name}'")
      else run(name, arguments)
      end
    end

    # The short usage a usage error prints: the help's SYNOPSIS, with
    # <tt>Usage:</tt> in place of its indentation.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   Fledge::CLI.new(help_path: "exe/fledge").usage.lines.first
    #   # => "Usage: fledge build [OPTIONS] [PATH]\n"
    #--
    # SPDX-SnippetEnd
    #++
    def usage
      synopsis = help[/^SYNOPSIS\n(.*?)\n\n/m, 1] or raise ArgumentError, "#{@help_path}'s help has no SYNOPSIS"
      synopsis.lines.each_with_index.map do |line, index|
        "#{index.zero? ? 'Usage:' : '      '} #{line.strip}\n"
      end.join
    end

    # The help text: the executable's header between its <tt>####</tt>
    # and <tt>###</tt> lines, with each line's leading <tt>#</tt> and one
    # space removed. Raises ArgumentError when the file has no such
    # header.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   Fledge::CLI.new(help_path: "exe/fledge").help.lines[1]
    #   # => "fledge - Ship a Ruby app to people who don't have Ruby\n"
    #--
    # SPDX-SnippetEnd
    #++
    def help
      lines = File.readlines(@help_path)
      start = lines.index { |line| line.chomp == "####" } or raise missing_header
      header = lines.drop(start + 1)
      length = header.index { |line| line.chomp == "###" } or raise missing_header

      header.first(length).map { |line| line.sub(/\A# ?/, "") }.join
    end

    private def missing_header
      ArgumentError.new("#{@help_path} has no help header between #### and ### lines")
    end

    private def run(name, arguments)
      command = @commands[name]
      return usage_error("fledge: '#{name}' is not a fledge command") unless command

      command.new(out: @out, err: @err).call(arguments)
    rescue UsageError => e
      usage_error("fledge #{name}: #{e.message}")
    end

    private def succeed_with(text)
      @out.puts text
      0
    end

    # Prints +message+, when there is one, the usage, and where to read
    # more, and returns 2: the exit status GNU and BSD tools give a
    # usage error.
    private def usage_error(message)
      @err.puts message if message
      @err.puts usage, "Try 'fledge --help'."
      2
    end
  end
end
