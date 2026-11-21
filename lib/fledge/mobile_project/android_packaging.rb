# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

module Fledge
  class MobileProject
    # Whether an Android project's <tt>build.gradle</tt> lets the
    # package installer extract the native libraries that the app's
    # extensions built as files are.
    #
    # An extension an <tt>extconf.rb</tt> builds in C or C++ is one of
    # the app's native libraries, which Ruby loads from the app's native
    # library folder, and the installer fills that folder only when the
    # Android Gradle plugin packs the libraries compressed, which
    # <tt>useLegacyPackaging = true</tt> asks for. A framework's own copy
    # of <tt>build.gradle</tt>, made from Fledge's template before 0.13.0,
    # says <tt>false</tt>, and the app it builds installs, starts, and
    # raises +LoadError+ at the extension's +require+.
    #
    # This class reads the last <tt>useLegacyPackaging</tt> the file sets
    # for native libraries, its comments and its setting for dex files
    # left out, and names each such extension with what to set:
    # a refusal when the file sets +false+, and a warning when it sets
    # nothing, since a project may set it in another file
    # (doc/contributors/design/phone-projects.md, "Host files").
    #
    # Use it from MobileProject::Android, once the host's files are in
    # place.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 setdef <kerrick@setdef.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   packaging = Fledge::MobileProject::AndroidPackaging.new([["adder", "adder/adder"]])
    #   packaging.refusal("useLegacyPackaging = false\n", shown: "host/android/build.gradle")
    #   # => "host/android/build.gradle sets useLegacyPackaging = false, so the package installer ..."
    #--
    # SPDX-SnippetEnd
    #++
    class AndroidPackaging
      # A setting of <tt>useLegacyPackaging</tt> in Groovy's ways: an
      # assignment, a method call, or a call with no parentheses.
      SETTING = /\buseLegacyPackaging\b\s*(?:=|\(|\s)\s*(true|false)\b/

      # Groovy's comments, which may hold an old setting.
      COMMENTS = %r{/\*.*?\*/|//[^\n]*}m

      # The setting of the same name for dex files, in a block or by its
      # path, which says nothing of native libraries: the Android Gradle
      # plugin's DexPackaging has a useLegacyPackaging of its own.
      DEX = /\bdex\s*\{[^{}]*\}|\bdex\s*\.\s*useLegacyPackaging\b[^\n]*/

      # What to set, as Fledge's template sets it.
      FIX = "useLegacyPackaging = true in a packaging { jniLibs { } } block"

      # [extensions] Each extension built as a file: its gem's name and
      #              its feature.
      def initialize(extensions)
        @extensions = extensions
      end

      # Why the app could not ship when +text+, the file a message calls
      # +shown+, sets <tt>useLegacyPackaging</tt> to +false+, or +nil+.
      #
      # === Example
      #
      #--
      # SPDX-SnippetBegin
      # SPDX-SnippetCopyrightText: 2026 setdef <kerrick@setdef.com>
      # SPDX-License-Identifier: MIT-0
      #++
      #   packaging.refusal("useLegacyPackaging true\n", shown: "build.gradle") # => nil
      #--
      # SPDX-SnippetEnd
      #++
      def refusal(text, shown:)
        return unless setting(text) == "false"

        "#{shown} sets useLegacyPackaging = false, so the package installer extracts none of the app's native libraries, " \
          "and #{named}, which Ruby loads from among them, would not load on a phone. Set " \
          "#{FIX.sub(' in a ', ' in its ')}, as Fledge's own build.gradle does."
      end

      # What to say when +text+, the file a message calls +shown+, sets
      # no <tt>useLegacyPackaging</tt>, or +nil+.
      #
      # === Example
      #
      #--
      # SPDX-SnippetBegin
      # SPDX-SnippetCopyrightText: 2026 setdef <kerrick@setdef.com>
      # SPDX-License-Identifier: MIT-0
      #++
      #   packaging.warning("android {\n}\n", shown: "host/android/build.gradle")
      #   # => "host/android/build.gradle sets no useLegacyPackaging for its native libraries, ..."
      #--
      # SPDX-SnippetEnd
      #++
      def warning(text, shown:)
        return if @extensions.empty? || setting(text)

        "#{shown} sets no useLegacyPackaging for its native libraries, and Android's default keeps them stored, so unless " \
          "your project sets it to true elsewhere, #{named} will not load on a phone. Add #{FIX}, as Fledge's own build.gradle " \
          "has it."
      end

      # The value +text+ sets last for native libraries, outside its
      # comments, or +nil+.
      private def setting(text)
        return if @extensions.empty?

        found = nil # : String?
        text.gsub(COMMENTS, "").gsub(DEX, "").scan(SETTING) { found = ::Regexp.last_match(1) }
        found
      end

      private def named
        names = @extensions.map { |gem, feature| "#{gem}'s extension #{feature}" }
        (names.length > 1) ? "#{names.take(names.length - 1).join(', ')} and #{names.last}" : names.first.to_s
      end
    end
  end
end
