# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "../error"

module Fledge
  class Config
    # One of the programs a project's <tt>fledge.yml</tt> names under
    # +programs+ (ADR 024).
    #
    # A project can have several ways in that share one codebase: a
    # command-line game, a terminal UI, and a GUI that all open the same
    # save. Each is a program of its own, with a kind and a name, but they
    # ship as one folder with one runtime, one copy of the project, and
    # one set of gems.
    #
    # This class reads one entry of the list: its +path+, which it needs,
    # and its +name+, +kind+, +identifier+, and +icon+, which mean for the
    # program what they mean for an app (ADR 008). It refuses a key it
    # does not know, and a path that leaves the project.
    #
    # Use it through Fledge::Config#programs.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   # fledge.yml:
    #   #   programs:
    #   #     - path: gui/main.rb
    #   #       kind: windowed
    #   #       identifier: com.example.MyGame
    #   #     - path: bin/cli
    #   program = Fledge::Config.load("path/to/project").programs.last
    #   program.path # => "bin/cli"
    #   program.name # => "cli"
    #   program.kind # => nil
    #--
    # SPDX-SnippetEnd
    #++
    class Program < Data.define(:path, :name, :kind, :identifier, :icon)
      ##
      # :attr_reader: path
      # The program's file, relative to the project's root, with
      # <tt>/</tt> between folders.

      ##
      # :attr_reader: name
      # The program's name: the one <tt>fledge.yml</tt> gives, or else
      # its file's name without the extension.

      ##
      # :attr_reader: kind
      # One of Config::KINDS, or +nil+ for +console+.

      ##
      # :attr_reader: identifier
      # The program's reverse-DNS identifier, or +nil+ for none.

      ##
      # :attr_reader: icon
      # The path of the program's icon files without their extension, or
      # +nil+ for none (Config#icon).

      # The keys a program may hold.
      KEYS = %w[path name kind identifier icon].freeze

      # KEYS, as a sentence lists them.
      KNOWN = "path, name, kind, identifier, and icon"

      # The program that +item+, the +number+th entry of +programs+ in the
      # <tt>fledge.yml</tt> at +file+, describes. Raises Fledge::Error,
      # naming the file and the program, when it is not a mapping of KEYS
      # with the values they need.
      #
      # === Example
      #
      #--
      # SPDX-SnippetBegin
      # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
      # SPDX-License-Identifier: MIT-0
      #++
      #   Fledge::Config::Program.from({ "path" => "bin/cli" }, 1, "fledge.yml").name # => "cli"
      #--
      # SPDX-SnippetEnd
      #++
      def self.from(item, number, file)
        unless item.is_a?(Hash)
          raise Error, "#{file}: program #{number} must be a mapping of #{KNOWN}, such as - path: bin/cli"
        end

        path = path(item, number, file)
        where = "#{file}: the program #{path}"
        unknown = item.keys - KEYS
        raise Error, "#{where} has #{unknown.map { |key| "'#{key}'" }.join(', ')}, which Fledge does not know. A program knows #{KNOWN}." unless unknown.empty?

        new(
          path:,
          name: Config.text(item, "name", where, "MyCoolApp") || File.basename(path, ".*"),
          kind: Config.kind(item, where),
          identifier: Config.identifier(item, where),
          icon: Config.icon(item, where)
        )
      end

      # The program's path: text, relative to the project's root, with
      # <tt>/</tt> between folders, none of them empty, <tt>.</tt>, or
      # <tt>..</tt>, and no space or line break at either end, which
      # <tt>fledge.cfg</tt> could not hold.
      private_class_method def self.path(item, number, file) # :nodoc:
        value = item["path"]
        fix = "such as path: bin/cli"
        raise Error, "#{file}: program #{number} has no path, the program's file in the project, #{fix}" if value.nil?

        value = Config.text(item, "path", "#{file}: program #{number}", "bin/cli").to_s
        segments = value.split("/", -1)
        if value != value.strip || value.match?(/[\r\n\\]/) || segments.any? { |segment| ["", ".", ".."].include?(segment) }
          raise Error, "#{file}: program #{number}'s path, #{value.inspect}, must name a file in the project, with / between folders, #{fix}"
        end

        value
      end

      # Whether the program opens its own windows.
      #
      # === Example
      #
      #--
      # SPDX-SnippetBegin
      # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
      # SPDX-License-Identifier: MIT-0
      #++
      #   Fledge::Config::Program.from({ "path" => "bin/cli" }, 1, "fledge.yml").windowed? # => false
      #--
      # SPDX-SnippetEnd
      #++
      def windowed?
        kind == "windowed"
      end
    end
  end
end
