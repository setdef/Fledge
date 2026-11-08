# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "../error"

module Fledge
  class Config
    # What a project's <tt>fledge.yml</tt> says under +linux+: the
    # libraries its gems load from the Linux distribution (ADR 030).
    #
    # A gem's compiled files may need only the libraries every Linux
    # distribution has, Fledge's runtime ships, or the gem carries
    # (Fledge::Linkage). A wrapper of a desktop library, such as a
    # webview's of WebKitGTK and GTK, needs libraries a desktop's
    # distribution provides and no gem should carry, as auditwheel's
    # <tt>--exclude</tt> leaves a wheel's to the system and Tauri's
    # <tt>.deb</tt> lists its own as dependencies. Listing one here lets
    # the gems need it: <tt>fledge build</tt> refuses a library listed
    # that no gem's compiled file needs from the system, a
    # <tt>.deb</tt> depends on the packages that provide those listed,
    # and the app's program says which one is missing on a computer that
    # lacks it, before Ruby starts.
    #
    # This class reads the mapping: its +system_libraries+, each a name
    # as a compiled file gives it (its soname, such as
    # <tt>libgtk-3.so.0</tt>), once each.
    #
    # Use it through Fledge::Config#linux.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 setdef <kerrick@setdef.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   # fledge.yml:
    #   #   linux:
    #   #     system_libraries: [libwebkit2gtk-4.1.so.0, libgtk-3.so.0]
    #   Fledge::Config.load("path/to/project").linux.system_libraries # => ["libwebkit2gtk-4.1.so.0", "libgtk-3.so.0"]
    #--
    # SPDX-SnippetEnd
    #++
    class Linux < Data.define(:system_libraries, :deb_changelog)
      ##
      # :attr_reader: system_libraries
      # The names of the libraries the project's gems load from the
      # distribution, as their compiled files give them, or none.

      # The keys the mapping may hold.
      KEYS = %w[system_libraries deb_changelog].freeze

      # A library's name as an ELF file's <tt>DT_NEEDED</tt> gives it: a
      # file name, in letters, digits, and <tt>. _ + -</tt>, that ends in
      # <tt>.so</tt> and any version numbers after it.
      SONAME = /\A[A-Za-z0-9_+-][A-Za-z0-9._+-]*\.so(?:\.[0-9]+)*\z/

      # The mapping at +data+'s +linux+ key in the <tt>fledge.yml</tt> at
      # +file+, or +nil+ when it has none. Raises Fledge::Error, naming the
      # file, when it is not a mapping of KEYS with the values they need.
      #
      # === Example
      #
      #--
      # SPDX-SnippetBegin
      # SPDX-SnippetCopyrightText: 2026 setdef <kerrick@setdef.com>
      # SPDX-License-Identifier: MIT-0
      #++
      #   Fledge::Config::Linux.from({ "linux" => { "system_libraries" => ["libgtk-3.so.0"] } }, "fledge.yml").system_libraries
      #   # => ["libgtk-3.so.0"]
      #--
      # SPDX-SnippetEnd
      #++
      def self.from(data, file)
        item = data["linux"]
        return nil if item.nil?
        unless item.is_a?(Hash)
          raise Error, "#{file}: linux must be a mapping of system_libraries and deb_changelog, such as linux: { system_libraries: [libgtk-3.so.0] }"
        end

        unknown = item.keys - KEYS
        unless unknown.empty?
          raise Error, "#{file}: linux has #{unknown.map { |key| "'#{key}'" }.join(', ')}, which Fledge does not know. " \
            "It knows system_libraries and deb_changelog."
        end

        new(system_libraries: libraries(item["system_libraries"], file), deb_changelog: Config.file(item, "deb_changelog", "#{file}: linux", "CHANGELOG.md"))
      end

      # The list at +system_libraries+, each a SONAME, once each.
      private_class_method def self.libraries(value, file) # :nodoc:
        return [] if value.nil?
        unless value.is_a?(Array) && value.all?(String)
          raise Error, "#{file}: linux: system_libraries must be a list of the names compiled files give libraries, such as [libgtk-3.so.0]"
        end

        wrong = value.find { |name| !name.match?(SONAME) }
        if wrong
          raise Error, "#{file}: linux: system_libraries has #{wrong.inspect}, which is not a library's name: name it as compiled files do, " \
            "such as libgtk-3.so.0, with no folder"
        end

        value.uniq
      end
    end
  end
end
