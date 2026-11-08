# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "../../error"
require_relative "../../mobile_platform"

module Fledge
  class CLI
    class Build
      # What <tt>fledge build</tt>'s arguments ask for, read as GNU's
      # conventions read options: the <tt>--out</tt> folder, the phone to
      # build a project for, if any, the identity <tt>--sign</tt> signs a
      # desktop app with (ADR 016), or the developer's own command
      # <tt>--sign-command</tt> signs a Windows app with, the keychain
      # profile <tt>--notarize</tt> has Apple notarize a signed macOS app
      # with (ADR 033), the app <tt>--from</tt> builds from (ADR 032), and
      # the one PATH, with <tt>--</tt> ending the options. A desktop build
      # is for the computer it runs on (ADR 010); a phone's, which no phone
      # builds, is named first, as Briefcase's <tt>briefcase create
      # iOS</tt> and Flutter's <tt>flutter build ios</tt> name it (ADR 012).
      class Options < Data.define(:out, :path, :phone, :sign, :from, :sign_command, :notarize)
        # The options +argv+ gives. A first operand that names a phone
        # (Fledge::MobilePlatform.names) is the phone; a folder of that
        # name is <tt>./ios</tt>, or follows <tt>--</tt>. A platform added
        # later takes its word here too, which the help reserves (ADR 029,
        # section 5). Raises
        # Fledge::UsageError for an option it does not know, one without
        # its value, or more than one PATH, and for the <tt>--target</tt>
        # Fledge 0.0.1.pre.7 and earlier took, saying why it went.
        def self.parse(argv)
          values = {} # : Hash[String, String]
          paths = [] # : Array[String]
          phone = nil # : String?
          arguments = argv.dup
          while (argument = arguments.shift)
            case argument
            when "-o" then values["--out"] = value_of(argument, arguments, "DIR")
            when *VALUES.keys then values[argument] = value_of(argument, arguments, VALUES.fetch(argument))
            when /\A(--[a-z-]+)=(.*)\z/m
              option = ::Regexp.last_match(1).to_s
              raise UsageError, "#{option} is gone: a build is for this computer. Build each platform's app on that platform." if option == "--target"
              raise UsageError, "unrecognized option '#{argument}'" unless VALUES.key?(option)

              values[option] = value_of(option, [::Regexp.last_match(2).to_s], VALUES.fetch(option))
            when *MobilePlatform.names
              if phone || !paths.empty? then paths << argument
              else phone = argument
              end
            when "--" then paths.concat(arguments.shift(arguments.size))
            when "-t", "--target" then raise UsageError, "#{argument} is gone: a build is for this computer. Build each platform's app on that platform."
            when /\A-./ then raise UsageError, "unrecognized option '#{argument}'"
            else paths << argument
            end
          end
          raise UsageError, "takes one PATH, but got #{paths.map { |p| "'#{p}'" }.join(' and ')}" if paths.size > 1

          check(values, phone)
          new(out: values.fetch("--out", DEFAULT_OUT), path: paths.first || ".", phone:, sign: values["--sign"], from: values["--from"],
            sign_command: values["--sign-command"], notarize: values["--notarize"])
        end

        # Each option that takes a value, and the name of that value.
        VALUES = { "--out" => "DIR", "--sign" => "IDENTITY", "--from" => "APP", "--sign-command" => "COMMAND", "--notarize" => "PROFILE" }.freeze

        # Raises Fledge::UsageError for options +values+ that cannot go
        # together, or with the phone +phone+.
        private_class_method def self.check(values, phone)
          raise UsageError, "--sign and --sign-command each sign the app; give one of them" if values["--sign"] && values["--sign-command"]
          raise UsageError, "--notarize needs --sign IDENTITY, the Developer ID Application identity Apple notarizes" if values["--notarize"] && !values["--sign"]
          return unless phone

          signing = %w[--sign --sign-command].find { |option| values.key?(option) }
          raise UsageError, "#{signing} signs desktop apps; sign a phone's app with Xcode or Gradle" if signing
          raise UsageError, "--from builds for this computer; a phone's project is written with fledge build ios or android" if values["--from"]
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
