# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

module Fledge
  # Keeps what a developer's Gemfile or gemspec prints out of standard
  # output, which <tt>fledge build</tt> keeps for the paths it prints.
  #
  # A Gemfile and a gemspec are Ruby, and Fledge evaluates them in its
  # own process, as <tt>bundle install</tt> does
  # (doc/contributors/design/gems.md, "Reading the Gemfile and
  # lockfile"). A +puts+ in one, or a program it starts with +system+,
  # would write among the paths a wrapper reads from standard output
  # (doc/contributors/design/public-interface.md, "The command's
  # conventions"). So the evaluation runs with file descriptor 1 pointed
  # at descriptor 2, which a child process inherits too.
  #
  # Use it around each evaluation of the developer's code in
  # <tt>fledge build</tt>'s process.
  module Evaluation
    # The value of the block, which runs with standard output going to
    # standard error. Standard output is restored when the block ends,
    # however it ends.
    def self.to_stderr
      STDOUT.flush
      saved = STDOUT.dup
      begin
        STDOUT.reopen(STDERR)
        yield
      ensure
        STDOUT.flush
        STDOUT.reopen(saved)
        saved.close
      end
    end
  end
end
