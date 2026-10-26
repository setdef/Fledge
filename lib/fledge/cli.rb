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
  # message and an exit status, never a backtrace. Spread across an
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
  #   cli.call(["frobnicate"]) # => 1
  #   err.string # => "fledge: 'frobnicate' is not a command. See 'fledge --help'.\n"
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

    # Runs +argv+ and returns the exit status: 0 for success, 1 for an
    # error. Leaves +argv+ unchanged.
    #
    # With no arguments, prints the help to the error stream and fails,
    # since a bare +fledge+ asked for nothing.
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
      when nil then fail_with(help)
      when "--help", "-h" then succeed_with(help)
      when "--version", "-V" then succeed_with("fledge #{VERSION}")
      when /\A-/ then fail_with("fledge: unknown option '#{name}'. See 'fledge --help'.")
      else run(name, arguments)
      end
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
      return fail_with("fledge: '#{name}' is not a command. See 'fledge --help'.") unless command

      command.new(out: @out, err: @err).call(arguments)
    end

    private def succeed_with(text)
      @out.puts text
      0
    end

    private def fail_with(text)
      @err.puts text
      1
    end
  end
end
