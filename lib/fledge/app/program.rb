# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

module Fledge
  class App
    # One program of an app: what the person runs, and what it runs.
    #
    # An app ships one program, or, when its <tt>fledge.yml</tt> lists
    # +programs+, several that share its runtime, project, and gems (ADR
    # 024). Each is a copy of the runtime's launcher with a name of its
    # own, an entry point in the project, and an identity: a console
    # program in a terminal, or the one windowed program with its own
    # identifier and icon.
    #
    # Use it through Fledge::App#programs.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 setdef <kerrick@setdef.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   program = Fledge::App.at("examples/hello").programs.first
    #   program.name  # => "Hello"
    #   program.entry # => "main.rb"
    #--
    # SPDX-SnippetEnd
    #++
    class Program < Data.define(:name, :entry, :identity)
      ##
      # :attr_reader: name
      # The program's file name in the built folder, before the
      # platform's extension, and the name people see.

      ##
      # :attr_reader: entry
      # The file the program runs, relative to the project's root, with
      # <tt>/</tt> between folders.

      ##
      # :attr_reader: identity
      # The program's Fledge::Identity.
    end
  end
end
