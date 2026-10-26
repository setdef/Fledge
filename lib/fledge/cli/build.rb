# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

module Fledge
  class CLI
    # The <tt>fledge build</tt> command.
    #
    # Shipping an app means copying it into a runtime for each platform
    # and archiving each result (Plan 001). Until that pipeline exists,
    # a build that pretended to succeed would hand you a folder that
    # does not run.
    #
    # This command holds the name +build+ in Fledge::CLI::COMMANDS and
    # fails plainly, with exit status 1, so a script that calls it today
    # stops instead of shipping nothing.
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
    #   #   $ fledge build
    #   #   fledge build: not yet implemented
    #
    #   Fledge::CLI::Build.new(out: $stdout, err: $stderr).call([]) # => 1
    #--
    # SPDX-SnippetEnd
    #++
    class Build
      # Creates the command.
      #
      # [out] Where results go, such as <tt>$stdout</tt>.
      # [err] Where errors go, such as <tt>$stderr</tt>.
      def initialize(out:, err:)
        @out = out
        @err = err
      end

      # Runs the command with the arguments after +build+, and returns
      # the exit status: always 1, for now.
      #
      # === Example
      #
      #--
      # SPDX-SnippetBegin
      # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
      # SPDX-License-Identifier: MIT-0
      #++
      #   Fledge::CLI::Build.new(out: $stdout, err: $stderr).call(["examples/hello"]) # => 1
      #--
      # SPDX-SnippetEnd
      #++
      def call(_argv)
        @err.puts "fledge build: not yet implemented"
        1
      end
    end
  end
end
