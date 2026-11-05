# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "../../error"
require_relative "../../mobile_platform"

module Fledge
  class CLI
    class Build
      # What <tt>fledge build</tt>'s arguments ask for, read as GNU's
      # conventions read options: the <tt>--out</tt> folder, the phone to
      # build a project for, if any, the identity <tt>--sign</tt> signs a
      # desktop app with (ADR 016), the app <tt>--from</tt> builds from
      # (ADR 032), and the one PATH, with <tt>--</tt> ending the options. A desktop build is for the computer it runs on
      # (ADR 010); a phone's, which no phone builds, is named first, as
      # Briefcase's <tt>briefcase create iOS</tt> and Flutter's
      # <tt>flutter build ios</tt> name it (ADR 012).
      Options = Data.define(:out, :path, :phone, :sign, :from) do
        # The options +argv+ gives. A first operand that names a phone
        # (Fledge::MobilePlatform.names) is the phone; a folder of that
        # name is <tt>./ios</tt>, or follows <tt>--</tt>. A platform added
        # later takes its word here too, which the help reserves (ADR 029,
        # section 5). Raises
        # Fledge::UsageError for an option it does not know, one without
        # its value, or more than one PATH, and for the <tt>--target</tt>
        # Fledge 0.0.1.pre.7 and earlier took, saying why it went.
        def self.parse(argv)
          out = DEFAULT_OUT
          paths = [] # : Array[String]
          phone = nil # : String?
          sign = nil # : String?
          from = nil # : String?
          arguments = argv.dup
          while (argument = arguments.shift)
            case argument
            when "-o", "--out" then out = value_of(argument, arguments, "DIR")
            when /\A--out=(.+)\z/ then out = ::Regexp.last_match(1).to_s
            when "--sign" then sign = value_of(argument, arguments, "IDENTITY")
            when /\A--sign=(.+)\z/ then sign = ::Regexp.last_match(1).to_s
            when "--sign=" then value_of("--sign", [], "IDENTITY")
            when "--from" then from = value_of(argument, arguments, "APP")
            when /\A--from=(.+)\z/ then from = ::Regexp.last_match(1).to_s
            when "--from=" then value_of("--from", [], "APP")
            when *MobilePlatform.names
              if phone || !paths.empty? then paths << argument
              else phone = argument
              end
            when "--" then paths.concat(arguments.shift(arguments.size))
            when "--out=" then value_of("--out", [], "DIR")
            when "-t", "--target", /\A--target=/ then raise UsageError, "#{argument[/\A[^=]+/]} is gone: a build is for this computer. Build each platform's app on that platform."
            when /\A-./ then raise UsageError, "unrecognized option '#{argument}'"
            else paths << argument
            end
          end
          raise UsageError, "takes one PATH, but got #{paths.map { |p| "'#{p}'" }.join(' and ')}" if paths.size > 1

          raise UsageError, "--sign signs desktop apps; sign a phone's app with Xcode or Gradle" if sign && phone
          raise UsageError, "--from builds for this computer; a phone's project is written with fledge build ios or android" if from && phone

          new(out:, path: paths.first || ".", phone:, sign:, from:)
        end

        # The value after +option+ in +arguments+, which names a +name+.
        private_class_method def self.value_of(option, arguments, name)
          value = arguments.shift
          raise UsageError, "#{option} needs #{name.match?(/\A[AEIOU]/) ? 'an' : 'a'} #{name}" if value.nil? || value.empty?

          value
        end
      end
    end
  end
end
