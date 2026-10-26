# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

module Fledge
  # A problem you can fix: a missing app, an unknown target, a runtime
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
end
