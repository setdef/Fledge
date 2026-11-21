# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "entry"

module Fledge
  # The file types a windowed app defines, as a Linux desktop learns them.
  #
  # A Linux desktop knows a file by its MIME type, and finds that type
  # from the file's name in the shared MIME-info database, which
  # +update-mime-database+ compiles from the definitions each program
  # installs in <tt>mime/packages</tt> (the freedesktop.org Shared
  # MIME-info Database specification, "Directory layout" and
  # "Recommended checking order"). A desktop entry's +MimeType+ says
  # which types the app opens, and so matches no file of a type the
  # database lacks: a game saved as <tt>level.lota</tt> stays
  # <tt>application/octet-stream</tt>, and the app is not offered for it.
  #
  # This class writes the app's one definition file, as LÖVE ships
  # <tt>love.xml</tt> and electron-builder writes one for its
  # +fileAssociations+: a +mime-type+ for each file association that
  # says <tt>defines_type: true</tt>, with the association's name as its
  # +comment+ and a +glob+ for each extension, lowercased once each,
  # since the database matches globs whatever their case. A type the app
  # only opens gets nothing: the database keeps the last +comment+ it
  # reads for a type, so an app's would rename a type such as
  # <tt>application/zip</tt> on the whole computer. The file goes at
  # <tt>share/mime/packages/ID.xml</tt>, named for the app as the
  # specification asks, beside the icons in <tt>share</tt>, which a
  # <tt>.deb</tt> installs in <tt>/usr/share</tt>, where the trigger
  # shared-mime-info registers compiles it.
  #
  # Use it through Fledge::DesktopEntry.
  #
  # === Example
  #
  #--
  # SPDX-SnippetBegin
  # SPDX-SnippetCopyrightText: 2026 setdef <kerrick@setdef.com>
  # SPDX-License-Identifier: MIT-0
  #++
  #   Fledge::SharedMimeInfo.new(Fledge::App.at("my_game").identity).entries.map(&:path)
  #   # => ["share/mime/packages/com.example.MyGame.xml"]
  #--
  # SPDX-SnippetEnd
  #++
  class SharedMimeInfo
    # The namespace of every element of a definition file.
    NAMESPACE = "http://www.freedesktop.org/standards/shared-mime-info"

    # Creates the definitions of the app whose Fledge::Identity is
    # +identity+.
    #
    # [identity] The app's identity, with an identifier.
    def initialize(identity)
      @identity = identity
    end

    # The definition file, with its path in the built app's folder, or
    # nothing when the app defines no type.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 setdef <kerrick@setdef.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   Fledge::SharedMimeInfo.new(identity).entries.first.path
    #   # => "share/mime/packages/com.example.MyGame.xml"
    #--
    # SPDX-SnippetEnd
    #++
    def entries
      types = @identity.file_associations.select(&:defines_type)
      return [] if types.empty?

      [Entry.file("share/mime/packages/#{@identity.identifier}.xml", text(types))]
    end

    private def text(types) # :nodoc:
      definitions = types.map do |association|
        globs = association.extensions.map(&:downcase).uniq.map { |extension| %(    <glob pattern="*.#{extension}"/>\n) }
        %(  <mime-type type="#{association.mime_types.first}">\n    <comment>#{SharedMimeInfo.escape(association.name)}</comment>\n) \
          "#{globs.join}  </mime-type>\n"
      end
      %(<?xml version="1.0" encoding="UTF-8"?>\n<mime-info xmlns="#{NAMESPACE}">\n#{definitions.join}</mime-info>\n)
    end

    # +text+ escaped for an XML element's text.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 setdef <kerrick@setdef.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   Fledge::SharedMimeInfo.escape("Tom & Jerry") # => "Tom &amp; Jerry"
    #--
    # SPDX-SnippetEnd
    #++
    def self.escape(text)
      text.gsub(/[&<>]/, "&" => "&amp;", "<" => "&lt;", ">" => "&gt;")
    end
  end
end
