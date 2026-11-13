# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require "open3"
require_relative "../error"
require_relative "../native_build"

module Fledge
  class MobileExtensions
    # Runs the commands of a phone's extension build: each tool's output
    # goes to the log, line by line, after a line that says what runs,
    # and a tool that fails, or cannot start, raises Fledge::Error.
    #
    # It also knows the environment every such command starts from: the
    # developer's own, less the variables of this computer's toolchain
    # (FOREIGN, and NativeBuild::SCRUBBED), which must not reach a cross
    # compile.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 setdef <kerrick@setdef.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   runner = Fledge::MobileExtensions::Runner.new(log: $stderr, env: ENV)
    #   runner.call(runner.clean_env, "make", "static", what: "compiling adder's extension", chdir: folder)
    #--
    # SPDX-SnippetEnd
    #++
    class Runner
      # Creates the runner.
      #
      # [log] Where the tools' output goes, such as <tt>$stderr</tt>.
      # [env] The developer's environment, which the commands start from.
      def initialize(log:, env:)
        @log = log
        @env = env
      end

      # The variables to remove from the developer's environment for a
      # command of the build, each mapped to +nil+.
      def clean_env
        scrubbed = @env.to_h.keys.grep(NativeBuild::SCRUBBED) + FOREIGN
        scrubbed.to_h { |name| [name, nil] } # : Hash[String, String?]
      end

      # Runs +command+ with +env+ in +chdir+ (default: the current folder),
      # first logging +what+, and raises Fledge::Error, naming +what+, when
      # it fails, or naming the tool when it cannot be run.
      def call(env, *command, what:, chdir: nil)
        @log.puts "#{what[0]&.upcase}#{what[1..]}"
        options = { chdir: chdir || Dir.pwd } # : Hash[Symbol, String]
        status = Open3.popen2e(env, *command, **options) do |_, output, thread| # steep:ignore ArgumentTypeMismatch
          output.each_line { |line| @log.puts line }
          thread.value
        end
        raise Error, "#{what} failed; the tools' output is above" unless status.success?
      rescue SystemCallError => e
        raise Error, "fledge build needs #{File.basename(command.first.to_s)}, which it could not run (#{e.message})"
      end
    end
  end
end
