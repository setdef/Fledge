# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "../error"

module Fledge
  class Config
    # One of the kinds of file or folder a windowed app opens, as its
    # <tt>fledge.yml</tt> lists them under +file_associations+ (ADR 032,
    # section 3).
    #
    # A person opens a document with the app that made it, or drops a
    # folder on the app that shows it. Each system learns which app opens
    # what from the app itself: macOS from the document types in its
    # bundle's <tt>Info.plist</tt>, Windows from registry entries its
    # setup program writes, and a Linux desktop from the MIME types in its
    # desktop entry. Tauri's bundler and electron-builder take the same
    # list (+fileAssociations+, with +ext+, +name+, +role+, +mimeType+,
    # and on macOS content types) and write it in those places.
    #
    # This class reads one entry: its +name+, which it needs and each
    # system shows as the kind of document; its +role+, +viewer+ or
    # +editor+; and what it covers: +extensions+, without the dot, as
    # Windows and macOS know a file; +mime_types+, as a Linux desktop
    # knows one; +content_types+, Apple's uniform type identifiers, such
    # as <tt>public.png</tt>; or <tt>folders: true</tt>, for folders, in
    # an entry of its own.
    #
    # Use it through Fledge::Config#file_associations.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   # fledge.yml:
    #   #   file_associations:
    #   #     - name: Project folder
    #   #       folders: true
    #   #     - name: Project archive
    #   #       extensions: [zip]
    #   #       mime_types: [application/zip]
    #   folder, archive = Fledge::Config.load("path/to/project").file_associations
    #   folder.folders     # => true
    #   archive.extensions # => ["zip"]
    #   archive.role       # => "viewer"
    #--
    # SPDX-SnippetEnd
    #++
    class FileAssociation < Data.define(:name, :role, :extensions, :mime_types, :content_types, :folders)
      ##
      # :attr_reader: name
      # What a person calls these documents, such as <tt>"Project
      # archive"</tt>.

      ##
      # :attr_reader: role
      # One of ROLES: +viewer+, an app that reads them, or +editor+, one
      # that also writes them.

      ##
      # :attr_reader: extensions
      # The files' extensions, without the dot, such as <tt>["zip"]</tt>.

      ##
      # :attr_reader: mime_types
      # The files' MIME types, such as <tt>["application/zip"]</tt>.

      ##
      # :attr_reader: content_types
      # The files' uniform type identifiers on macOS, such as
      # <tt>["public.zip-archive"]</tt>.

      ##
      # :attr_reader: folders
      # Whether the entry is for folders, and not files.

      # The keys an entry may hold.
      KEYS = %w[name role extensions mime_types content_types folders].freeze

      # KEYS, as a sentence lists them.
      KNOWN = "name, role, extensions, mime_types, content_types, and folders"

      # What the app does with these documents, as macOS's
      # CFBundleTypeRole names it: +viewer+, the default, or +editor+.
      ROLES = %w[viewer editor].freeze

      # An extension, without the dot: letters, digits, and <tt>_ + -</tt>.
      EXTENSION = /\A[A-Za-z0-9][A-Za-z0-9_+-]*\z/

      # A MIME type: a type and a subtype of RFC 6838's restricted names.
      MIME_TYPE = %r{\A[A-Za-z0-9][A-Za-z0-9!^_.+-]*/[A-Za-z0-9][A-Za-z0-9!^_.+-]*\z}

      # A uniform type identifier: two or more parts between dots, of
      # letters, digits, and hyphens, as Apple's reverse-DNS names are.
      CONTENT_TYPE = /\A[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+\z/

      # The lists an entry may give, each with its rule and an example.
      LISTS = {
        "extensions" => [EXTENSION, "[zip, txt], without the dot"],
        "mime_types" => [MIME_TYPE, "[application/zip]"],
        "content_types" => [CONTENT_TYPE, "[public.zip-archive]"],
      }.freeze

      # The entries at +data+'s +file_associations+ key in the
      # <tt>fledge.yml</tt> at +file+, or +nil+ when it has none. Raises
      # Fledge::Error, naming the file, when it is not a list of mappings of
      # KEYS with the values they need.
      #
      # === Example
      #
      #--
      # SPDX-SnippetBegin
      # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
      # SPDX-License-Identifier: MIT-0
      #++
      #   data = { "file_associations" => [{ "name" => "Project folder", "folders" => true }] }
      #   Fledge::Config::FileAssociation.list(data, "fledge.yml").first.folders # => true
      #--
      # SPDX-SnippetEnd
      #++
      def self.list(data, file)
        value = data["file_associations"]
        return nil if value.nil?
        unless value.is_a?(Array)
          raise Error, "#{file}: file_associations must be a list of what the app opens, each a mapping such as - name: Project folder"
        end

        value.each_with_index.map { |item, index| from(item, index + 1, file) }
      end

      # The entry +item+, the +number+th of the list in +file+.
      private_class_method def self.from(item, number, file) # :nodoc:
        where = "#{file}: file_associations' entry #{number}"
        raise Error, "#{where} must be a mapping of #{KNOWN}, such as - name: Project folder" unless item.is_a?(Hash)

        unknown = item.keys - KEYS
        raise Error, "#{where} has #{unknown.map { |key| "'#{key}'" }.join(', ')}, which Fledge does not know. It knows #{KNOWN}." unless unknown.empty?

        name = item["name"]
        raise Error, "#{where} needs a name, the kind of document a person sees, such as name: Project archive" unless name.is_a?(String) && !name.strip.empty?

        lists = LISTS.to_h { |key, (rule, example)| [key, list_at(item, key, rule, "#{where}: #{key} must be a list such as #{example}")] }
        new(name:, role: role(item, where), extensions: lists.fetch("extensions"), mime_types: lists.fetch("mime_types"),
          content_types: lists.fetch("content_types"), folders: folders(item, lists, where))
      end

      # The +role+ at +item+, one of ROLES, or +viewer+.
      private_class_method def self.role(item, where) # :nodoc:
        value = item.fetch("role", nil)
        return "viewer" if value.nil?
        known = ROLES.find { |role| role == value }
        return known if known

        raise Error, "#{where}: role must be viewer or editor, not #{value}"
      end

      # Whether +item+ is for folders: +true+ only in an entry that names
      # no files, and an entry names folders or some files.
      private_class_method def self.folders(item, lists, where) # :nodoc:
        value = item.fetch("folders", nil)
        raise Error, "#{where}: folders must be true or false" unless [true, false, nil].include?(value)

        files = lists.values.any?(&:any?)
        raise Error, "#{where} is for folders and files; give the files an entry of their own" if value && files
        raise Error, "#{where} names nothing to open: give it extensions, mime_types, content_types, or folders: true" unless value || files

        value == true
      end

      # The list at +key+ in +item+, each matching +rule+, once each.
      private_class_method def self.list_at(item, key, rule, message) # :nodoc:
        value = item[key]
        return [] if value.nil?
        raise Error, message unless value.is_a?(Array) && value.all? { |each| each.is_a?(String) && each.match?(rule) }

        value.uniq
      end
    end
  end
end
