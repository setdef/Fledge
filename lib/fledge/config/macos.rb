# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "../error"

module Fledge
  class Config
    # What a project's <tt>fledge.yml</tt> says under +macos+: the build
    # number of its macOS app, and the libraries from the developer's
    # computer that the app carries.
    #
    # A macOS app has two versions in its <tt>Info.plist</tt>:
    # +CFBundleShortVersionString+, the one people see, and
    # +CFBundleVersion+, the build, which the App Store and an updater
    # such as Sparkle compare to tell one upload or download from the
    # next. Fledge derives both from the app's +version+ (Fledge::MacBundle),
    # so two builds of one version cannot differ; +build+ sets the second,
    # as Tauri's <tt>bundleVersion</tt> and Briefcase's +build+ do; the
    # reserved <tt>ios: build</tt> takes the same shape.
    #
    # A gem's compiled file may link a library the developer installed
    # with a package manager, such as Homebrew's SDL, which no Mac has
    # from Apple. +carried_libraries+ names each library the app is to
    # carry from this computer, by the file name the compiled files give
    # it, as <tt>linux: system_libraries</tt> names the distribution's:
    # the developer chooses every library the app distributes, and its
    # license is the developer's to honor (Fledge::CarriedLibraries).
    #
    # This class reads the mapping: its +build+, one to three whole
    # numbers between periods, Apple's rule for +CFBundleVersion+, and
    # its +carried_libraries+, file names that end in <tt>.dylib</tt>.
    #
    # Use it through Fledge::Config#macos.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 setdef <kerrick@setdef.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   # fledge.yml:
    #   #   macos:
    #   #     build: "1.2.3"
    #   #     carried_libraries: [libSDL3.0.dylib]
    #   Fledge::Config.load("path/to/project").macos.build             # => "1.2.3"
    #   Fledge::Config.load("path/to/project").macos.carried_libraries # => ["libSDL3.0.dylib"]
    #--
    # SPDX-SnippetEnd
    #++
    class Macos < Data.define(:build, :carried_libraries)
      ##
      # :attr_reader: build
      # The app's +CFBundleVersion+, or +nil+ for the one Fledge derives
      # from its version.

      ##
      # :attr_reader: carried_libraries
      # The file names of the libraries the app carries from this
      # computer, or none.

      # The keys the mapping may hold.
      KEYS = %w[build carried_libraries].freeze

      # A library's file name as a Mach-O file names it, less its folder:
      # letters, digits, and <tt>. _ + -</tt>, ending in <tt>.dylib</tt>.
      LIBRARY = /\A[A-Za-z0-9_+-][A-Za-z0-9._+-]*\.dylib\z/

      # A +CFBundleVersion+: one to three whole numbers between periods,
      # as Apple's Information Property List reference requires.
      BUILD = /\A[0-9]+(?:\.[0-9]+){0,2}\z/

      # The mapping at +data+'s +macos+ key in the <tt>fledge.yml</tt> at
      # +file+, or +nil+ when it has none. Raises Fledge::Error, naming the
      # file and the key, when it is not a mapping of KEYS with the values
      # they need.
      #
      # === Example
      #
      #--
      # SPDX-SnippetBegin
      # SPDX-SnippetCopyrightText: 2026 setdef <kerrick@setdef.com>
      # SPDX-License-Identifier: MIT-0
      #++
      #   Fledge::Config::Macos.from({ "macos" => { "build" => "42" } }, "fledge.yml").build # => "42"
      #   Fledge::Config::Macos.from({ "macos" => { "carried_libraries" => ["libSDL3.0.dylib"] } }, "fledge.yml").carried_libraries
      #   # => ["libSDL3.0.dylib"]
      #--
      # SPDX-SnippetEnd
      #++
      def self.from(data, file)
        item = data["macos"]
        return nil if item.nil?
        raise Error, "#{file}: macos must be a mapping of build and carried_libraries, such as macos: { build: \"42\" }" unless item.is_a?(Hash)

        unknown = item.keys - KEYS
        unless unknown.empty?
          raise Error, "#{file}: macos has #{unknown.map { |key| "'#{key}'" }.join(', ')}, which Fledge does not know. It knows build and carried_libraries."
        end

        new(build: build(item["build"], file), carried_libraries: libraries(item["carried_libraries"], file))
      end

      # The list at +carried_libraries+, each a LIBRARY, once each.
      private_class_method def self.libraries(value, file) # :nodoc:
        return [] if value.nil?
        unless value.is_a?(Array) && value.all?(String)
          raise Error, "#{file}: macos: carried_libraries must be a list of the names compiled files give libraries, such as [libSDL3.0.dylib]"
        end

        wrong = value.find { |name| !name.match?(LIBRARY) }
        if wrong
          raise Error, "#{file}: macos: carried_libraries has #{wrong.inspect}, which is not a library's name: name it as compiled files do, " \
            "such as libSDL3.0.dylib, with no folder"
        end

        value.uniq
      end

      # The build at +value+: text of BUILD's form, or +nil+.
      private_class_method def self.build(value, file) # :nodoc:
        return nil if value.nil?
        raise Error, "#{file}: macos: build must be text; quote it, as in build: \"#{value}\"" if value.is_a?(Numeric)
        return value if value.is_a?(String) && value.match?(BUILD)

        raise Error, "#{file}: macos: build must be one to three whole numbers between periods, as Apple's CFBundleVersion is, " \
          "such as \"42\" or \"1.2.3\", not #{value}"
      end
    end
  end
end
