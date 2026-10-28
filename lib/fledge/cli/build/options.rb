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
      # conventions read options: each <tt>--target</tt>, the <tt>--out</tt>
      # folder, and the one PATH, with <tt>--</tt> ending the options.
      Options = Data.define(:targets, :out, :path) do
        # The options +argv+ gives. Raises Fledge::UsageError for an
        # option it does not know, one without its value, or more than one
        # PATH.
        def self.parse(argv)
          targets = [] # : Array[String]
          out = DEFAULT_OUT
          paths = [] # : Array[String]
          arguments = argv.dup
          while (argument = arguments.shift)
            case argument
            when "-t", "--target" then targets << value_of(argument, arguments, "PLATFORM")
            when /\A--target=(.+)\z/ then targets << ::Regexp.last_match(1).to_s
            when "-o", "--out" then out = value_of(argument, arguments, "DIR")
            when /\A--out=(.+)\z/ then out = ::Regexp.last_match(1).to_s
            when "--" then paths.concat(arguments.shift(arguments.size))
            when /\A--(?:target|out)=\z/ then value_of(argument.delete_suffix("="), [], argument.start_with?("--t") ? "PLATFORM" : "DIR")
            when /\A-./ then raise UsageError, "unrecognized option '#{argument}'"
            else paths << argument
            end
          end
          raise UsageError, "takes one PATH, but got #{paths.map { |p| "'#{p}'" }.join(' and ')}" if paths.size > 1

          new(targets:, out:, path: paths.first || ".")
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
