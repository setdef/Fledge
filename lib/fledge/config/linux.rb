# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "../error"

module Fledge
  class Config
    # What a project's <tt>fledge.yml</tt> says under +linux+: the
    # libraries and the GObject introspection data its gems load from the
    # Linux distribution, and the packages its <tt>.deb</tt> depends on
    # for what its own Ruby opens.
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
    # A gem over GObject introspection, as each of ruby-gnome's is, also
    # loads a typelib, a file of data that describes a library's
    # interface, by its namespace and version while the app runs.
    # Nothing in a compiled file names it, and a distribution may package
    # it apart from the library, so Fledge cannot find it for itself.
    # Listing one here has the app's program say which one is missing on
    # a computer that lacks it, before Ruby starts, rather than Ruby's
    # error from inside the gem.
    #
    # An app whose Ruby opens a library by itself, with Fiddle or ffi, as
    # Basket opens GTK 4, has no compiled file that names it, so
    # +system_libraries+ cannot list it. Its +deb_depends+ lists the
    # packages a <tt>.deb</tt> depends on for it, as Debian Policy 7.1
    # writes a relationship, such as <tt>libgtk-4-1</tt>. Only a
    # <tt>.deb</tt> reads it.
    #
    # This class reads the mapping: its +system_libraries+, each a name
    # as a compiled file gives it (its soname, such as
    # <tt>libgtk-3.so.0</tt>), its +system_typelibs+, each a
    # namespace and its version as libgirepository names a typelib
    # (such as <tt>Gtk-4.0</tt>), and its +deb_depends+, each a package
    # and, if it has them, its version and alternatives, once each.
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
    #   #     system_typelibs: [Gtk-4.0]
    #   #     deb_depends: [libgtk-4-1, libadwaita-1-0]
    #   linux = Fledge::Config.load("path/to/project").linux
    #   linux.system_libraries # => ["libwebkit2gtk-4.1.so.0", "libgtk-3.so.0"]
    #   linux.system_typelibs  # => ["Gtk-4.0"]
    #   linux.deb_depends      # => ["libgtk-4-1", "libadwaita-1-0"]
    #--
    # SPDX-SnippetEnd
    #++
    class Linux < Data.define(:system_libraries, :system_typelibs, :deb_depends, :deb_changelog)
      ##
      # :attr_reader: system_libraries
      # The names of the libraries the project's gems load from the
      # distribution, as their compiled files give them, or none.

      ##
      # :attr_reader: system_typelibs
      # The typelibs the project's gems load from the distribution, each
      # a namespace and its version, such as <tt>Gtk-4.0</tt>, or none.

      ##
      # :attr_reader: deb_depends
      # The relationships a <tt>.deb</tt> adds to its +Depends+, each a
      # package, as Debian Policy 7.1 writes one, or none.

      # The keys the mapping may hold.
      KEYS = %w[system_libraries system_typelibs deb_depends deb_changelog].freeze

      # A library's name as an ELF file's <tt>DT_NEEDED</tt> gives it: a
      # file name, in letters, digits, and <tt>. _ + -</tt>, that ends in
      # <tt>.so</tt> and any version numbers after it.
      SONAME = /\A[A-Za-z0-9_+-][A-Za-z0-9._+-]*\.so(?:\.[0-9]+)*\z/

      # A typelib as libgirepository names one, and its file is named less
      # <tt>.typelib</tt>: a namespace, which begins with a letter or
      # <tt>_</tt> and holds letters, digits, and <tt>_</tt>, a hyphen,
      # and the version, two numbers between a period
      # (<tt>girepository.c</tt>, <tt>load_dependencies_recurse</tt>, splits
      # a dependency at its last hyphen).
      TYPELIB = /\A[A-Za-z_][A-Za-z0-9_]*-[0-9]+\.[0-9]+\z/

      # A package name as Debian Policy 5.6.7 writes one, which begins with
      # a letter or digit and holds lower case letters, digits, and
      # <tt>+ - .</tt>, in at least two characters, with an
      # architecture qualifier (<tt>:any</tt>) if it has one, and not a
      # soname, which is a library's name and not a package's.
      DEB_PACKAGE = "(?![a-z0-9+.-]*\\.so(?:\\.[0-9]+)*(?![a-z0-9+.-]))[a-z0-9][a-z0-9+.-]+(?::[a-z][a-z0-9-]*)?"

      # A relationship as Debian Policy 7.1 writes one: a package, a
      # version bound if it has one in parentheses (<tt><<</tt>,
      # <tt><=</tt>, <tt>=</tt>, <tt>>=</tt>, or <tt>>></tt> and a
      # version), and alternatives after <tt>|</tt>. An entry is one
      # relationship, so a comma, which Depends separates them with, is not
      # in one.
      DEB_RELATIONSHIP = "#{DEB_PACKAGE}(?: ?\\((?:<<|<=|=|>=|>>) ?[0-9][A-Za-z0-9.+:~-]*\\))?"

      # An entry of +deb_depends+: DEB_RELATIONSHIP, or several joined by
      # <tt>|</tt>.
      DEB_DEPENDENCY = /\A#{DEB_RELATIONSHIP}(?: ?\| ?#{DEB_RELATIONSHIP})*\z/

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
          raise Error, "#{file}: linux must be a mapping of system_libraries, system_typelibs, deb_depends, and deb_changelog, such as linux: { system_libraries: [libgtk-3.so.0] }"
        end

        unknown = item.keys - KEYS
        unless unknown.empty?
          raise Error, "#{file}: linux has #{unknown.map { |key| "'#{key}'" }.join(', ')}, which Fledge does not know. " \
            "It knows system_libraries, system_typelibs, deb_depends, and deb_changelog."
        end

        new(system_libraries: libraries(item["system_libraries"], file), system_typelibs: typelibs(item["system_typelibs"], file),
          deb_depends: dependencies(item["deb_depends"], file), deb_changelog: Config.file(item, "deb_changelog", "#{file}: linux", "CHANGELOG.md"))
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

      # The list at +system_typelibs+, each a TYPELIB, once each.
      private_class_method def self.typelibs(value, file) # :nodoc:
        return [] if value.nil?
        unless value.is_a?(Array) && value.all?(String)
          raise Error, "#{file}: linux: system_typelibs must be a list of GObject introspection namespaces and their versions, such as [Gtk-4.0]"
        end

        wrong = value.find { |name| !name.match?(TYPELIB) }
        if wrong
          raise Error, "#{file}: linux: system_typelibs has #{wrong.inspect}, which is not a namespace and its version: name it as its typelib file " \
            "is named, less .typelib, such as Gtk-4.0"
        end

        value.uniq
      end

      # The list at +deb_depends+, each a DEB_DEPENDENCY, once each.
      private_class_method def self.dependencies(value, file) # :nodoc:
        return [] if value.nil?
        unless value.is_a?(Array) && value.all?(String)
          raise Error, "#{file}: linux: deb_depends must be a list of the packages a .deb depends on, such as [libgtk-4-1]"
        end

        wrong = value.find { |name| !name.match?(DEB_DEPENDENCY) }
        raise Error, wrong_dependency(wrong, file) if wrong

        value.uniq
      end

      # The message for +wrong+, an entry of +deb_depends+ that is not a
      # DEB_DEPENDENCY: one that holds a soname gets the cure for that
      # mistake, the other the form it takes.
      private_class_method def self.wrong_dependency(wrong, file) # :nodoc:
        if wrong.split("|").any? { |part| part.strip.match?(SONAME) }
          return "#{file}: linux: deb_depends has #{wrong.inspect}, which is a library's soname and not a package: name the package that provides it, " \
            "such as libgtk-4-1 for libgtk-4.so.1"
        end

        "#{file}: linux: deb_depends has #{wrong.inspect}, which is not a package and, if it has one, its version: name it as Debian Policy 7.1 does, " \
          "such as \"libgtk-4-1 (>= 4.6)\" or \"libfoo1t64 | libfoo1\""
      end
    end
  end
end
