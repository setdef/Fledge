# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require "stringio"
require_relative "../app"
require_relative "../command"
require_relative "../error"
require_relative "../mobile_platform"
require_relative "../phone_run"
require_relative "build"

module Fledge
  class CLI
    # The <tt>fledge test</tt> command: runs a phone app's tests inside
    # the app, on an iOS Simulator or an Android emulator, and reports
    # their result to the terminal.
    #
    # Logic a developer tests with Minitest on their own computer, but the
    # code that drives a phone's own widgets runs only inside the app
    # Fledge builds, so it is tested only there. As Briefcase's
    # <tt>briefcase run iOS --test</tt> builds the app with a test entry
    # point in place of its own and reads the suite's result from the
    # app's log (doc/contributors/design/phone-projects.md, "Tests in the
    # app"), this command writes the phone's project with the test
    # program PROGRAM in place of the app's program, as <tt>fledge build
    # ios PROGRAM</tt> writes it, builds it with Xcode or Gradle, runs it
    # on the booted Simulator or adb's device with Fledge::PhoneRun,
    # prints what the program prints, standard error's to the error
    # stream, and returns the program's exit status, as a shell returns
    # <tt>ruby PROGRAM</tt>'s. A failed build or run becomes lines
    # beginning <tt>fledge test:</tt> on the error stream and status 1; a
    # mistake in its arguments raises Fledge::UsageError.
    #
    # === Examples
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 setdef <kerrick@setdef.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   # From a terminal, in examples/basket, with a Simulator booted:
    #   #   $ fledge test ios test/phone.rb
    #   #   ...
    #   #   12 runs, 20 assertions, 0 failures, 0 errors, 0 skips
    #
    #   Fledge::CLI::Test.new(out: $stdout, err: $stderr).call(["android", "test/phone.rb"]) # => 0
    #--
    # SPDX-SnippetEnd
    #++
    class Test
      # The output folder when you give no <tt>--out</tt>: beside a
      # build's, so that the test app's project never replaces the app's.
      DEFAULT_OUT = File.join(Build::DEFAULT_OUT, "test")

      # What <tt>fledge test</tt>'s arguments ask for: the phone, the
      # test program, the <tt>--out</tt> folder, and the device
      # <tt>--device</tt> names, if any.
      class Options < Data.define(:phone, :program, :out, :device)
        # The options +argv+ gives: the phone's name first, then the one
        # PROGRAM, with <tt>-o DIR</tt> or <tt>--out DIR</tt> and
        # <tt>-d ID</tt> or <tt>--device ID</tt> anywhere, and <tt>--</tt>
        # ending the options. Raises Fledge::UsageError for
        # anything else.
        def self.parse(argv)
          arguments = argv.dup
          operands = [] # : Array[String]
          out = DEFAULT_OUT
          device = nil # : String?
          while (argument = arguments.shift)
            case argument
            when "-o", "--out" then out = value(argument, arguments, "a DIR")
            when /\A--out=(.+)\z/m then out = ::Regexp.last_match(1).to_s
            when "-d", "--device" then device = value(argument, arguments, "an ID")
            when /\A--device=(.+)\z/m then device = ::Regexp.last_match(1).to_s
            when "--" then operands.concat(arguments.shift(arguments.size))
            when /\A-./ then raise UsageError, "unrecognized option '#{argument}'"
            else operands << argument
            end
          end
          phone, program, *rest = operands
          unless phone && MobilePlatform.names.include?(phone)
            raise UsageError, "names the phone first, #{MobilePlatform.names.join(' or ')}, as fledge build ios does"
          end
          raise UsageError, "needs PROGRAM, the test program to run in the app, such as test/phone.rb" unless program
          raise UsageError, "takes one PROGRAM, but got #{[program, *rest].map { |p| "'#{p}'" }.join(' and ')}" unless rest.empty?

          new(phone:, program:, out:, device:)
        end

        # The value after +option+ in +arguments+, which names +what+.
        private_class_method def self.value(option, arguments, what)
          value = arguments.shift
          raise UsageError, "#{option} needs #{what}" if value.nil? || value.empty?

          value
        end
      end

      # Creates the command, which builds as Fledge::CLI::Build does with
      # +env+, and runs the app with +run+, a Fledge::PhoneRun's +follow+
      # by default.
      #
      # [out] Where the program's standard output goes.
      # [err] Where its standard error, errors, and progress go.
      # [env] The environment Fledge::Runtimes and the Android SDK are
      #       found in (default: +ENV+).
      # [build] Writes the project, given the arguments of
      #         <tt>fledge build</tt> and where it prints (default: a
      #         Fledge::CLI::Build's +call+).
      # [run] Builds, installs, and follows the app, given the phone, the
      #       Fledge::App, the project's folder, and the device
      #       <tt>--device</tt> names or +nil+, and returns the program's
      #       status (default: #run).
      def initialize(out:, err:, env: ENV, build: nil, run: nil)
        @out = out
        @err = err
        @env = env
        @build = build || -> (arguments, printed) { Build.new(out: printed, err:, env:).call(arguments) }
        @run = run || method(:run)
      end

      # Runs the command with the arguments after +test+, and returns the
      # test program's exit status, or 1 when the app could not be built
      # or run. Raises Fledge::UsageError for arguments it cannot make
      # sense of.
      def call(argv)
        options = Options.parse(argv)
        app = App.at(options.program, phone: true)
        printed = StringIO.new
        built = @build.call([options.phone, "--out", options.out, "--", options.program], printed)
        return built unless built.zero?

        phone = MobilePlatform.find(options.phone) || raise(Error, "no phone #{options.phone}")
        status = @run.call(phone, app, File.expand_path(printed.string.strip), options.device)
        status.between?(0, 255) ? status : 1
      rescue UsageError
        raise
      rescue Error => e
        e.message.each_line { |line| @err.puts "fledge test: #{line.chomp}" }
        1
      end

      # Builds the project at +project+ for +phone+ with the system's own
      # tools, runs it on +device+, a Simulator's UDID or adb's serial, or
      # else on the one booted Simulator or adb's device, and returns the
      # status of +app+'s program.
      private def run(phone, app, project, device)
        name = app.name
        identifier = app.identity.identifier.to_s
        follower = PhoneRun.new(out: @out, err: @err)
        if phone.name == "ios"
          @err.puts "Building #{name} for the iOS Simulator with xcodebuild"
          bundle = PhoneRun::IOS.build(project, name)
          udid = device || PhoneRun::IOS.booted(Command.run("xcrun", "simctl", "list", "devices", "booted", "-j", install: PhoneRun::IOS::INSTALL))
          launched = PhoneRun::IOS.new(name:, identifier:, udid:)
          launched.launch(bundle)
        else
          @err.puts "Building #{name}'s debug APK with Gradle"
          apk = PhoneRun::Android.build(project)
          adb = PhoneRun::Android.adb(@env["ANDROID_HOME"] || @env["ANDROID_SDK_ROOT"])
          launched = PhoneRun::Android.new(name:, identifier:, adb:, serial: device)
          launched.launch(apk)
        end
        @err.puts "Running #{name} on the #{(phone.name == 'ios') ? 'Simulator' : 'device'}"
        follower.follow(launched)
      end
    end
  end
end
