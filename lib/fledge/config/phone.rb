# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "../error"

module Fledge
  class Config
    # What a project's <tt>fledge.yml</tt> says under +ios+ or +android+
    # about the project <tt>fledge build ios</tt> or <tt>fledge build
    # android</tt> writes (doc/contributors/design/phone-projects.md, "Host
    # files").
    #
    # Fledge writes each phone's project afresh on every build (ADR 012),
    # so a change made to it by hand lasts until the next build. Some apps
    # need one all the same: a game whose SDL3 owns the main loop needs
    # SDL's <tt>main.m</tt> on iOS and SDL's Activity on Android, which no
    # gem's <tt>extconf.rb</tt> can supply. Vlissides' Generation Gap
    # keeps such files apart from the ones a generator writes, so that
    # writing again loses nothing.
    #
    # This class reads one phone's mapping: its +host+, a folder in the
    # project whose files Fledge copies over the project it writes, and on
    # Android its +host_libraries+, the native libraries the host's own
    # Gradle dependencies add to the app, which a gem's library may need
    # though no file Fledge reads holds them (MobileProject::AndroidLinkage).
    # It refuses a key it does not know, and a path that leaves the project.
    # Whether the folder exists is for that phone's build to check, so a
    # desktop build, which ignores these keys, never needs it.
    #
    # Use it through Fledge::Config#ios and Fledge::Config#android.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 setdef <kerrick@setdef.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   # fledge.yml:
    #   #   ios:
    #   #     host: host/ios
    #   Fledge::Config.load("path/to/project").ios.host # => "host/ios"
    #--
    # SPDX-SnippetEnd
    #++
    class Phone < Data.define(:host, :host_libraries)
      ##
      # :attr_reader: host
      # The folder of the project's own files for the phone's project,
      # relative to the project's root, with <tt>/</tt> between folders,
      # or +nil+ for none.

      ##
      # :attr_reader: host_libraries
      # The file names of the native libraries the app's host adds to an
      # Android app through its own Gradle dependencies, once each: empty
      # on iOS, and when the mapping lists none.

      # The keys each phone's mapping may hold.
      KEYS = { "ios" => %w[host].freeze, "android" => %w[host host_libraries].freeze }.freeze

      # A name Android's package installer extracts from an APK's
      # <tt>lib/ABI/</tt> for an app that is not debuggable: +lib+, the
      # characters it takes in a file name, and <tt>.so</tt>
      # (ValidLibraryPathLastSlash and isFilenameSafe in AOSP's
      # <tt>libs/androidfw/ApkParsing.cpp</tt>, lines 36 to 84). A host's
      # library of any other name never reaches the phone's library
      # folder, so no library of the app could load it there.
      LIBRARY = /\Alib[A-Za-z0-9_+,=.-]*\.so\z/

      # The phone's mapping at +data+'s +phone+ key, +ios+ or +android+, in
      # the <tt>fledge.yml</tt> at +file+, or +nil+ when it has none.
      # Raises Fledge::Error, naming the file and the phone, when it is not
      # a mapping of KEYS with the values they need.
      #
      # === Example
      #
      #--
      # SPDX-SnippetBegin
      # SPDX-SnippetCopyrightText: 2026 setdef <kerrick@setdef.com>
      # SPDX-License-Identifier: MIT-0
      #++
      #   Fledge::Config::Phone.from({ "ios" => { "host" => "host/ios" } }, "ios", "fledge.yml").host # => "host/ios"
      #--
      # SPDX-SnippetEnd
      #++
      def self.from(data, phone, file)
        item = data[phone]
        return nil if item.nil?

        keys = KEYS.fetch(phone)
        known = keys.join(" and ")
        raise Error, "#{file}: #{phone} must be a mapping of #{known}, such as #{phone}: { host: host/#{phone} }" unless item.is_a?(Hash)

        unknown = item.keys - keys
        raise Error, "#{file}: #{phone} has #{unknown.map { |key| "'#{key}'" }.join(', ')}, which Fledge does not know. It knows #{known}." unless unknown.empty?

        new(host: host(item, phone, file), host_libraries: libraries(item["host_libraries"], file))
      end

      # The list at +host_libraries+, each a LIBRARY, once each.
      private_class_method def self.libraries(value, file) # :nodoc:
        return [] if value.nil?
        unless value.is_a?(Array) && value.all?(String)
          raise Error, "#{file}: android: host_libraries must be a list of the names compiled files give libraries, such as [libSDL3.so]"
        end

        wrong = value.find { |name| !name.match?(LIBRARY) }
        if wrong
          raise Error, "#{file}: android: host_libraries has #{wrong.inspect}, which is not a name Android extracts from an APK: " \
            "name a library lib*.so, with no folder, such as libSDL3.so"
        end

        value.uniq
      end

      # The host's folder: text, relative to the project's root, as a
      # program's path is (Config.inside?).
      private_class_method def self.host(item, phone, file) # :nodoc:
        value = Config.text(item, "host", "#{file}: #{phone}", "host/#{phone}")
        return value if value.nil? || Config.inside?(value)

        raise Error, "#{file}: #{phone}'s host, #{value.inspect}, must name a folder in the project, with / between folders, " \
          "such as host: host/#{phone}"
      end
    end
  end
end
