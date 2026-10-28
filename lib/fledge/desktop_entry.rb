# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "entry"
require_relative "icon"

module Fledge
  # A windowed app on Linux: its desktop entry and icons.
  #
  # Linux desktops (GNOME, KDE, and the rest) show an app's name and icon
  # in their menus, docks, and window switchers from a desktop entry, a
  # <tt>.desktop</tt> file, and from icons in the hicolor icon theme's
  # folders (decision 18). A folder with only a program in it shows a
  # generic icon and a file name.
  #
  # This class writes them into the built app's folder, as the
  # freedesktop.org Desktop Entry Specification (version 1.5) and Icon
  # Theme Specification describe them, and as an AppImage's AppDir holds
  # them: <tt>ID.desktop</tt> at the top, named by the app's reverse-DNS
  # identifier as the specification recommends, whose +Exec+ names the
  # program beside it and whose +Icon+ names the identifier, and a PNG of
  # each of Fledge::Icon::LINUX's sizes at
  # <tt>share/icons/hicolor/SIZExSIZE/apps/ID.png</tt>, the layout of
  # <tt>$XDG_DATA_HOME</tt>, so installing the app is copying +share+
  # into <tt>~/.local/share</tt> and the desktop entry into its
  # +applications+ with the program's full path. Fledge installs nothing;
  # an AppImage is a later story (Plan 002, "Windowed apps").
  #
  # Use it through Fledge::Assembly.
  #
  # === Example
  #
  #--
  # SPDX-SnippetBegin
  # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
  # SPDX-License-Identifier: MIT-0
  #++
  #   Fledge::DesktopEntry.new(Fledge::App.at("my_app").identity).entries.map(&:path)
  #   # => ["com.example.MyApp.desktop", "share/icons/hicolor/16x16/apps/com.example.MyApp.png", ...]
  #--
  # SPDX-SnippetEnd
  #++
  class DesktopEntry
    # Creates the desktop entry of the app whose Fledge::Identity is
    # +identity+.
    #
    # [identity] The app's identity, with an identifier.
    def initialize(identity)
      @identity = identity
    end

    # The desktop entry and icons, with paths in the built app's folder.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   desktop.entries.first.content.lines.first # => "[Desktop Entry]\n"
    #--
    # SPDX-SnippetEnd
    #++
    def entries
      id = @identity.identifier.to_s
      icon = @identity.icon
      icons = icon ? Icon::LINUX.map { |size| Entry.file("share/icons/hicolor/#{size}x#{size}/apps/#{id}.png", icon.png(size)) } : [] # : Array[Entry]
      [Entry.file("#{id}.desktop", text), *icons]
    end

    # The desktop entry's text.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   desktop.text.include?("Type=Application\n") # => true
    #--
    # SPDX-SnippetEnd
    #++
    def text
      lines = [
        "[Desktop Entry]",
        "Type=Application",
        "Version=1.5",
        "Name=#{DesktopEntry.string(@identity.name)}",
        "Exec=#{DesktopEntry.string(DesktopEntry.exec(@identity.name))}",
      ]
      lines << "Icon=#{@identity.identifier}" if @identity.icon
      lines << "Terminal=false"
      "#{lines.join("\n")}\n"
    end

    # +value+ escaped as a desktop entry's string values are: a backslash
    # before a backslash, and <tt>\n</tt>, <tt>\t</tt>, <tt>\r</tt>, and
    # <tt>\s</tt> for a line break, a tab, a carriage return, and a leading
    # space (the specification's "Possible value types").
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   Fledge::DesktopEntry.string("a\\b") # => "a\\\\b"
    #--
    # SPDX-SnippetEnd
    #++
    def self.string(value)
      escaped = value.gsub(/[\\\n\t\r]/, "\\" => "\\\\", "\n" => "\\n", "\t" => "\\t", "\r" => "\\r")
      escaped.start_with?(" ") ? "\\s#{escaped[1..]}" : escaped
    end

    # +program+ as the first argument of an +Exec+ key: quoted when it
    # holds a character the specification reserves, with a backslash
    # before each of <tt>"</tt>, <tt>`</tt>, <tt>$</tt>, and <tt>\\</tt>
    # inside the quotes, and every <tt>%</tt> doubled, since a single one
    # begins a field code.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   Fledge::DesktopEntry.exec("MyApp")    # => "MyApp"
    #   Fledge::DesktopEntry.exec("My App")   # => "\"My App\""
    #--
    # SPDX-SnippetEnd
    #++
    def self.exec(program)
      argument = program.gsub("%", "%%")
      return argument unless argument.match?(/[ \t\n"'\\><~|&;$*?#()`=]/)

      "\"#{argument.gsub(/["`$\\]/) { |character| "\\#{character}" }}\""
    end
  end
end
