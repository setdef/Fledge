# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "../error"

module Fledge
  class Config
    # What a project's <tt>fledge.yml</tt> says under +macos+: the build
    # number of its macOS app.
    #
    # A macOS app has two versions in its <tt>Info.plist</tt>:
    # +CFBundleShortVersionString+, the one people see, and
    # +CFBundleVersion+, the build, which the App Store and an updater
    # such as Sparkle compare to tell one upload or download from the
    # next. Fledge derives both from the app's +version+ (Fledge::MacBundle),
    # so two builds of one version cannot differ; +build+ sets the second,
    # as Tauri's <tt>bundleVersion</tt> and Briefcase's +build+ do; the
    # reserved <tt>ios: build</tt> takes the same shape
    # (doc/contributors/design/public-interface.md, "Reserved names").
    #
    # This class reads the mapping: its +build+, one to three whole
    # numbers between periods, Apple's rule for +CFBundleVersion+.
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
    #   Fledge::Config.load("path/to/project").macos.build # => "1.2.3"
    #--
    # SPDX-SnippetEnd
    #++
    class Macos < Data.define(:build)
      ##
      # :attr_reader: build
      # The app's +CFBundleVersion+, or +nil+ for the one Fledge derives
      # from its version.

      # The keys the mapping may hold.
      KEYS = %w[build].freeze

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
      #--
      # SPDX-SnippetEnd
      #++
      def self.from(data, file)
        item = data["macos"]
        return nil if item.nil?
        raise Error, "#{file}: macos must be a mapping of build, such as macos: { build: \"42\" }" unless item.is_a?(Hash)

        unknown = item.keys - KEYS
        raise Error, "#{file}: macos has #{unknown.map { |key| "'#{key}'" }.join(', ')}, which Fledge does not know. It knows build." unless unknown.empty?

        new(build: build(item["build"], file))
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
