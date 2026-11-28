# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "../error"
require_relative "../mobile_platform"
require_relative "build"
require_relative "phone/run"

module Fledge
  class CLI
    # The <tt>fledge ios</tt> and <tt>fledge android</tt> commands, each
    # with two commands of its own: +project+ writes the phone's project,
    # as Fledge::CLI::Build does, and +run+ runs a program inside the
    # phone's app (Fledge::CLI::Phone::Run).
    #
    # A phone's app is not built on the computer it runs on, so it gets a
    # command of its own, named for the phone, as <tt>flutter build
    # ios</tt> and <tt>briefcase run iOS</tt> name it, in a noun-then-verb
    # order (clig.dev, "Subcommands"), so that <tt>fledge build</tt>
    # reads no word as a phone.
    #
    # Use it through the +fledge+ executable, or through Fledge::CLI,
    # whose COMMANDS table holds a Phone::Command for each phone.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 setdef <kerrick@setdef.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   ios = Fledge::MobilePlatform.new(name: "ios")
    #   Fledge::CLI::Phone.new(out: $stdout, err: $stderr, phone: ios).call(["project", "examples/hello"]) # => 0
    #--
    # SPDX-SnippetEnd
    #++
    class Phone
      # A phone's entry in Fledge::CLI::COMMANDS: it makes that phone's
      # command, as a command class's +new+ does.
      class Command < Data.define(:phone)
        # The command for #phone, which writes to +out+ and +err+.
        def new(out:, err:)
          Phone.new(out:, err:, phone:)
        end
      end

      # The commands a phone's command takes.
      COMMANDS = %w[project run].freeze

      # Creates the command for +phone+, a Fledge::MobilePlatform.
      #
      # [out] Where results, and a program's standard output, go.
      # [err] Where errors and progress go.
      # [env] The environment Fledge::Runtimes and the Android SDK are
      #       found in (default: +ENV+).
      def initialize(out:, err:, phone:, env: ENV)
        @out = out
        @err = err
        @phone = phone
        @env = env
      end

      # Runs the command +argv+ names first, +project+ or +run+, with the
      # arguments after it, and returns its exit status. Raises
      # Fledge::UsageError for a missing or unknown command, and for
      # arguments the command cannot make sense of, naming that command.
      def call(argv)
        name, *arguments = argv
        command = command(name)
        begin
          command.call(arguments)
        rescue UsageError => e
          raise UsageError.new(e.message, command: "fledge #{@phone.name} #{name}")
        end
      end

      # The command called +name+, or a Fledge::UsageError.
      private def command(name)
        case name
        when "project" then Build.new(out: @out, err: @err, env: @env, phone: @phone)
        when "run" then Run.new(out: @out, err: @err, env: @env, phone: @phone)
        when nil then raise UsageError, "needs a command, #{COMMANDS.join(' or ')}, such as fledge #{@phone.name} project"
        else raise UsageError, "'#{name}' is not a fledge #{@phone.name} command: it takes #{COMMANDS.join(' or ')}"
        end
      end
    end
  end
end
