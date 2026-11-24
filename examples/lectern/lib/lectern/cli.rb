# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT-0
#++

require "io/console"
require "optparse"
require_relative "renderer"
require_relative "pager"

module Lectern
  # The command: reads Markdown files (or the standard input), renders
  # them for the terminal, and shows the result, through a pager when it
  # is longer than the screen. Every stream is a parameter, so that a
  # test runs it with the ones it makes.
  class Cli
    # The usage line.
    USAGE = "usage: lectern [OPTION]... [FILE]...    (FILE - or none reads the standard input)"
    # sysexits.h's EX_USAGE, for a command line that is wrong,
    EX_USAGE = 64
    # and EX_NOINPUT, for a file that cannot be read.
    EX_NOINPUT = 66
    # The width a terminal is cut to: lines longer than this are hard to
    # follow, however wide the window.
    MAXIMUM_WIDTH = 100
    # The width of output that is no terminal's.
    DEFAULT_WIDTH = 80
    # The size assumed when a terminal cannot say.
    DEFAULT_ROWS = 24

    # A command run with +argv+, on the given streams and +env+. +console+
    # is the terminal to read keys from when the standard input is a pipe.
    def initialize(argv, stdin: $stdin, stdout: $stdout, stderr: $stderr, env: ENV, console: nil)
      @argv = argv.dup
      @stdin = stdin
      @stdout = stdout
      @stderr = stderr
      @env = env
      @console = console
    end

    # Runs it, and returns the exit status.
    def run
      options = parse
      return 0 if options.nil?

      text = options.fetch(:inputs).map { |name| render(name, options) }.join("\n")
      show(text, options)
      0
    rescue OptionParser::ParseError, ArgumentError => e
      @stderr.puts "lectern: #{e.message}\n#{USAGE}"
      EX_USAGE
    rescue Errno::EPIPE
      0
    rescue SystemCallError => e
      @stderr.puts "lectern: #{reason(e)}"
      EX_NOINPUT
    end

    private def parse
      options = { pager: nil, color: "auto", width: nil }
      parser = OptionParser.new do |o|
        o.banner = USAGE
        o.on("-w", "--width=COLUMNS", Integer, "wrap at COLUMNS (default: the terminal's width, at most #{MAXIMUM_WIDTH}; #{DEFAULT_WIDTH} off a terminal)") { |n| options[:width] = n }
        o.on("--color=WHEN", %w[auto always never], "color the output: auto, always, or never (default auto; NO_COLOR is honored)") { |w| options[:color] = w }
        o.on("-p", "--pager", "page the output on a terminal, even when it is short") { options[:pager] = true }
        o.on("-P", "--no-pager", "never page") { options[:pager] = false }
        o.on("-h", "--help", "print this help") { options[:help] = true }
      end
      files = parser.parse(@argv)
      if options[:help]
        @stdout.puts parser.help
        return nil
      end
      raise ArgumentError, "width must be at least 1" if options[:width]&.< 1

      files = ["-"] if files.empty?
      raise ArgumentError, "no file given, and the standard input is a terminal" if files == ["-"] && @stdin.tty?

      options.merge(inputs: files)
    end

    private def render(name, options)
      markdown = (name == "-") ? @stdin.read : File.read(name, encoding: "bom|utf-8")
      markdown = markdown.dup.force_encoding(Encoding::UTF_8).scrub
      Renderer.new(width: width(options), style: style(options)).render(markdown)
    end

    private def width(options)
      return options[:width] if options[:width]

      @stdout.tty? ? [size.last, MAXIMUM_WIDTH].min : DEFAULT_WIDTH
    end

    private def style(options)
      Style.choose(options[:color], terminal: @stdout.tty?, env: @env)
    end

    private def size
      @stdout.winsize
    rescue NoMethodError, SystemCallError
      [DEFAULT_ROWS, DEFAULT_WIDTH]
    end

    private def show(text, options)
      lines = text.lines(chomp: true)
      keys = @stdin.tty? ? @stdin : (@console || IO.console)
      if @stdout.tty? && keys && options[:pager] != false && (options[:pager] || lines.size >= size.first)
        Pager.new(lines, input: keys, output: @stdout, height: size.first).run
      else
        @stdout.write(text)
      end
    end

    # What +error+, from opening a file, says, as cat says it: the file,
    # then what is wrong ("notes.md: No such file or directory").
    private def reason(error)
      what, file = error.message.split(/ @ \w+ - /, 2)
      file ? "#{file}: #{what}" : what
    end
  end
end
