# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

module Fledge
  # A problem you can fix: a missing app, a computer with no runtime, a runtime
  # that will not download.
  #
  # A build fails for reasons that are yours to fix, and for bugs that
  # are Fledge's. Treating both alike either buries your mistake in a
  # backtrace or hides Fledge's bug behind a polite sentence.
  #
  # Fledge raises this error, with a message written for you, for the
  # first kind only. The command line prints its message and exits with
  # status 1; anything else is a bug and keeps its backtrace.
  #
  # Use it to tell a mistake from a bug when you call Fledge from Ruby.
  #
  # === Example
  #
  #--
  # SPDX-SnippetBegin
  # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
  # SPDX-License-Identifier: MIT-0
  #++
  #   begin
  #     Fledge::Platform.find("sparc-solaris")
  #   rescue Fledge::Error => error
  #     warn error.message
  #   end
  #--
  # SPDX-SnippetEnd
  #++
  class Error < StandardError
  end

  # A command line Fledge cannot make sense of: an unrecognized option, a
  # missing value, an unknown platform.
  #
  # A mistake in how +fledge+ was called needs a different answer from
  # a build that failed. The person needs to see how to call it, and a
  # script needs to tell "you called me wrong" from "I tried and failed."
  # GNU tools and the BSDs answer both with exit status 2 and a short
  # usage on standard error.
  #
  # Fledge::CLI catches this error, prints its message, the usage, and
  # <tt>Try 'fledge --help'.</tt>, and exits with status 2. A command
  # raises it from its argument parsing.
  #
  # Use it in a command for any mistake the help text would have
  # prevented.
  #
  # === Example
  #
  #--
  # SPDX-SnippetBegin
  # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
  # SPDX-License-Identifier: MIT-0
  #++
  #   raise Fledge::UsageError, "unrecognized option '--frobnicate'"
  #--
  # SPDX-SnippetEnd
  #++
  class UsageError < Error
  end
end
