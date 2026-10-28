# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "../../error"

module Fledge
  class CLI
    class Build
      # What <tt>fledge build</tt>'s arguments ask for, read as GNU's
      # conventions read options: the <tt>--out</tt> folder and the one
      # PATH, with <tt>--</tt> ending the options. There is no target to
      # choose: a build is for the computer it runs on (ADR 010).
      Options = Data.define(:out, :path) do
        # The options +argv+ gives. Raises Fledge::UsageError for an
        # option it does not know, one without its value, or more than one
        # PATH, and for the <tt>--target</tt> Fledge 0.0.1.pre.7 and earlier
        # took, saying why it went.
        def self.parse(argv)
          out = DEFAULT_OUT
          paths = [] # : Array[String]
          arguments = argv.dup
          while (argument = arguments.shift)
            case argument
            when "-o", "--out" then out = value_of(argument, arguments, "DIR")
            when /\A--out=(.+)\z/ then out = ::Regexp.last_match(1).to_s
            when "--" then paths.concat(arguments.shift(arguments.size))
            when "--out=" then value_of("--out", [], "DIR")
            when "-t", "--target", /\A--target=/ then raise UsageError, "#{argument[/\A[^=]+/]} is gone: a build is for this computer. Build each platform's app on that platform."
            when /\A-./ then raise UsageError, "unrecognized option '#{argument}'"
            else paths << argument
            end
          end
          raise UsageError, "takes one PATH, but got #{paths.map { |p| "'#{p}'" }.join(' and ')}" if paths.size > 1

          new(out:, path: paths.first || ".")
        end

        # The value after +option+ in +arguments+, which names a +name+.
        private_class_method def self.value_of(option, arguments, name)
          value = arguments.shift
          raise UsageError, "#{option} needs a #{name}" if value.nil? || value.empty?

          value
        end
      end
    end
  end
end
