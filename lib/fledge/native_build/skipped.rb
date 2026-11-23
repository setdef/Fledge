# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "built_files"

module Fledge
  class NativeBuild
    # Says when a gem that lists extensions was installed without one.
    #
    # An +extconf.rb+ may write an empty Makefile and exit 0 when what it
    # needs is missing (ruby2d 1.0.0's, lines 35 to 50, does when its SDL
    # libraries are), and RubyGems takes a build that exits 0 as built.
    # <tt>gem install</tt> and <tt>bundle install</tt> say nothing, and the
    # gem fails when Ruby requires its extension. The app does the same
    # as <tt>bundle exec</tt> would on the developer's computer, so the
    # build does not refuse; it says what it saw, as a warning, because
    # a person who builds the app can then fix the build computer before
    # anyone runs it (doc/contributors/design/gems.md, "A gem whose
    # extension was skipped").
    module Skipped # :nodoc:
      # The warnings about +gem+, whose gemspec lists +extensions+, when
      # none of +entries+, the files its build left that Ruby may load,
      # is a shared library (BuiltFiles::LIBRARY).
      def self.warnings(gem, extensions, entries)
        return [] if extensions.empty?
        return [] if entries.any? { |entry| entry.type == :file && entry.path.match?(BuiltFiles::LIBRARY) && !entry.path.match?(BuiltFiles::DEBUG) }

        message = "#{gem} lists #{extensions.join(', ')} as its extensions, and its build left no shared library, so the app carries " \
          "the gem without its extension and Ruby will fail to load it, as under bundle exec on this computer. Its extconf.rb may " \
          "have skipped the build and exited 0 because a library it needs is missing: read the build's output above, and install " \
          "what it names before building."
        [message]
      end
    end
  end
end
