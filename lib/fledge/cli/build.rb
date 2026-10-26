# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "../app"
require_relative "../assembly"
require_relative "../error"
require_relative "../platform"
require_relative "../runtimes"

module Fledge
  class CLI
    # The <tt>fledge build</tt> command.
    #
    # Shipping an app means copying it into a runtime for each platform
    # you want it to run on, and archiving each result (Plan 001). Doing
    # that by hand means knowing where each runtime lives, renaming its
    # launcher, and archiving without losing an executable bit.
    #
    # This command reads <tt>--target</tt>, <tt>--out</tt>, and the app's
    # folder from its arguments, finds each target's runtime through
    # Fledge::Runtimes, builds each with Fledge::Assembly, and prints the
    # path of each archive it wrote, one per line. A failed build becomes
    # one line on the error stream and exit status 1; a mistake in its
    # arguments raises Fledge::UsageError, which Fledge::CLI turns into
    # the usage and exit status 2.
    #
    # Use it through the +fledge+ executable, or through Fledge::CLI.
    #
    # === Examples
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   # From a terminal:
    #   #   $ fledge build -t x86_64-linux examples/hello
    #   #   dist/hello-x86_64-linux.tar.gz
    #
    #   Fledge::CLI::Build.new(out: $stdout, err: $stderr).call(["-t", "x86_64-linux", "examples/hello"]) # => 0
    #--
    # SPDX-SnippetEnd
    #++
    class Build
      # The output folder when you give no <tt>--out</tt>.
      DEFAULT_OUT = "dist"

      # Creates the command.
      #
      # [out] Where results go, such as <tt>$stdout</tt>.
      # [err] Where errors and progress go, such as <tt>$stderr</tt>.
      # [env] The environment Fledge::Runtimes reads (default: +ENV+).
      # [host] The Gem::Platform the default target comes from (default:
      #        Gem::Platform.local).
      def initialize(out:, err:, env: ENV, host: Gem::Platform.local)
        @out = out
        @err = err
        @env = env
        @host = host
      end

      # Runs the command with the arguments after +build+, and returns
      # the exit status: 0 when every target built, 1 otherwise. Raises
      # Fledge::UsageError for arguments it cannot make sense of.
      #
      # === Example
      #
      #--
      # SPDX-SnippetBegin
      # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
      # SPDX-License-Identifier: MIT-0
      #++
      #   Fledge::CLI::Build.new(out: $stdout, err: $stderr).call(["--out", "/tmp/builds", "my_app"]) # => 0
      #--
      # SPDX-SnippetEnd
      #++
      def call(argv)
        targets, out, path = parse(argv)
        platforms = targets.uniq.map { |name| Platform.find(name) }
        app = App.at(path)
        build(app, platforms.empty? ? [Platform.local(@host)] : platforms, out)
        0
      rescue UsageError
        raise
      rescue Error => e
        @err.puts "fledge build: #{e.message}"
        1
      end

      private def build(app, platforms, out)
        out_dir = File.expand_path(out)
        raise Error, "--out can't be the app's own folder, #{out}" if out_dir == app.root

        runtimes = Runtimes.new(env: @env, log: @err)
        platforms.each do |platform|
          assembly = Assembly.new(app:, platform:, runtime: runtimes.archive(platform), out: out_dir)
          archive = assembly.call
          @out.puts File.join(out, File.basename(archive))
        end
      end

      # [targets, out, path] from +argv+.
      private def parse(argv)
        targets = [] # : Array[String]
        out = DEFAULT_OUT
        paths = [] # : Array[String]
        arguments = argv.dup
        while (argument = arguments.shift)
          case argument
          when "-t", "--target" then targets << value_of(argument, arguments, "PLATFORM")
          when /\A--target=(.+)\z/ then targets << ::Regexp.last_match(1).to_s
          when "-o", "--out" then out = value_of(argument, arguments, "DIR")
          when /\A--out=(.+)\z/ then out = ::Regexp.last_match(1).to_s
          when "--" then paths.concat(arguments.shift(arguments.size))
          when /\A--(?:target|out)=\z/ then value_of(argument.delete_suffix("="), [], argument.start_with?("--t") ? "PLATFORM" : "DIR")
          when /\A-./ then raise UsageError, "unrecognized option '#{argument}'"
          else paths << argument
          end
        end
        raise UsageError, "takes one PATH, but got #{paths.map { |p| "'#{p}'" }.join(' and ')}" if paths.size > 1

        [targets, out, paths.first || "."]
      end

      private def value_of(option, arguments, name)
        value = arguments.shift
        raise UsageError, "#{option} needs a #{name}" if value.nil? || value.empty?

        value
      end
    end
  end
end
