# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "../error"

module Fledge
  class Config
    # What a project's <tt>fledge.yml</tt> says under +ios+ or +android+
    # about the project <tt>fledge build ios</tt> or <tt>fledge build
    # android</tt> writes (ADR 025, section 5).
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
    # project whose files Fledge copies over the project it writes. It
    # refuses a key it does not know, and a path that leaves the project.
    # Whether the folder exists is for that phone's build to check, so a
    # desktop build, which ignores these keys, never needs it.
    #
    # Use it through Fledge::Config#ios and Fledge::Config#android.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   # fledge.yml:
    #   #   ios:
    #   #     host: host/ios
    #   Fledge::Config.load("path/to/project").ios.host # => "host/ios"
    #--
    # SPDX-SnippetEnd
    #++
    class Phone < Data.define(:host)
      ##
      # :attr_reader: host
      # The folder of the project's own files for the phone's project,
      # relative to the project's root, with <tt>/</tt> between folders,
      # or +nil+ for none.

      # The keys a phone's mapping may hold.
      KEYS = %w[host].freeze

      # The phone's mapping at +data+'s +phone+ key, +ios+ or +android+, in
      # the <tt>fledge.yml</tt> at +file+, or +nil+ when it has none.
      # Raises Fledge::Error, naming the file and the phone, when it is not
      # a mapping of KEYS with the values they need.
      #
      # === Example
      #
      #--
      # SPDX-SnippetBegin
      # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
      # SPDX-License-Identifier: MIT-0
      #++
      #   Fledge::Config::Phone.from({ "ios" => { "host" => "host/ios" } }, "ios", "fledge.yml").host # => "host/ios"
      #--
      # SPDX-SnippetEnd
      #++
      def self.from(data, phone, file)
        item = data[phone]
        return nil if item.nil?
        raise Error, "#{file}: #{phone} must be a mapping of host, such as #{phone}: { host: host/#{phone} }" unless item.is_a?(Hash)

        unknown = item.keys - KEYS
        raise Error, "#{file}: #{phone} has #{unknown.map { |key| "'#{key}'" }.join(', ')}, which Fledge does not know. It knows host." unless unknown.empty?

        new(host: host(item, phone, file))
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
