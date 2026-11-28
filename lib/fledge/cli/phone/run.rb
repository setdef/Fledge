# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require "stringio"
require_relative "../../app"
require_relative "../../command"
require_relative "../../error"
require_relative "../../mobile_platform"
require_relative "../../phone_run"
require_relative "../build"

module Fledge
  class CLI
    class Phone
      # The <tt>fledge ios run</tt> and <tt>fledge android run</tt>
      # commands: run a program inside a phone's app, on an iOS Simulator
      # or an Android emulator or device, and report its result to the
      # terminal.
      #
      # Logic a developer tests with Minitest on their own computer, but
      # the code that drives a phone's own widgets runs only inside the
      # app Fledge builds, so it is tested only there. As Briefcase's
      # <tt>briefcase run iOS --test</tt> builds the app with a test entry
      # point in place of its own and reads the suite's result from the
      # app's log, this command writes the phone's project with the
      # program PATH in place of the app's program, as <tt>fledge ios
      # project PATH</tt> writes it, builds it with Xcode or Gradle, runs
      # it on the booted Simulator or adb's device with Fledge::PhoneRun,
      # prints what the program prints, standard error's to the error
      # stream, and returns the program's exit status, as a shell returns
      # <tt>ruby PATH</tt>'s. A failed build or run becomes lines
      # beginning <tt>fledge PHONE run:</tt> on the error stream and
      # status 1; a mistake in its arguments raises Fledge::UsageError.
      #
      # === Examples
      #
      #--
      # SPDX-SnippetBegin
      # SPDX-SnippetCopyrightText: 2026 setdef <kerrick@setdef.com>
      # SPDX-License-Identifier: MIT-0
      #++
      #   # From a terminal, in examples/basket, with a Simulator booted:
      #   #   $ fledge ios run test/phone.rb
      #   #   ...
      #   #   12 runs, 20 assertions, 0 failures, 0 errors, 0 skips
      #
      #   android = Fledge::MobilePlatform.new(name: "android")
      #   Fledge::CLI::Phone::Run.new(out: $stdout, err: $stderr, phone: android).call(["test/phone.rb"]) # => 0
      #--
      # SPDX-SnippetEnd
      #++
      class Run
        # The output folder when you give no <tt>--out</tt>: beside a
        # build's, so that the run's project never replaces the app's.
        DEFAULT_OUT = File.join(Build::DEFAULT_OUT, "test")

        # What the command's arguments ask for: the program PATH, the
        # <tt>--out</tt> folder, and the device <tt>--device</tt> names,
        # if any.
        class Options < Data.define(:path, :out, :device)
          # The options +argv+ gives: at most one PATH, <tt>.</tt> when
          # there is none, with <tt>-o DIR</tt> or <tt>--out DIR</tt> and
          # <tt>-d ID</tt> or <tt>--device ID</tt> anywhere, and
          # <tt>--</tt> ending the options. Raises Fledge::UsageError for
          # anything else.
          def self.parse(argv)
            arguments = argv.dup
            paths = [] # : Array[String]
            out = DEFAULT_OUT
            device = nil # : String?
            while (argument = arguments.shift)
              case argument
              when "-o", "--out" then out = value(argument, arguments, "a DIR")
              when /\A--out=(.+)\z/m then out = ::Regexp.last_match(1).to_s
              when "-d", "--device" then device = value(argument, arguments, "an ID")
              when /\A--device=(.+)\z/m then device = ::Regexp.last_match(1).to_s
              when "--" then paths.concat(arguments.shift(arguments.size))
              when /\A-./ then raise UsageError, "unrecognized option '#{argument}'"
              else paths << argument
              end
            end
            raise UsageError, "takes one PATH, but got #{paths.map { |p| "'#{p}'" }.join(' and ')}" if paths.size > 1

            new(path: paths.first || ".", out:, device:)
          end

          # The value after +option+ in +arguments+, which names +what+.
          private_class_method def self.value(option, arguments, what)
            value = arguments.shift
            raise UsageError, "#{option} needs #{what}" if value.nil? || value.empty?

            value
          end
        end

        # Creates the command for +phone+, which builds as
        # Fledge::CLI::Build does with +env+, and runs the app with +run+,
        # a Fledge::PhoneRun's +follow+ by default.
        #
        # [out] Where the program's standard output goes.
        # [err] Where its standard error, errors, and progress go.
        # [phone] The Fledge::MobilePlatform to run on.
        # [env] The environment Fledge::Runtimes and the Android SDK are
        #       found in (default: +ENV+).
        # [name] The command each line of an error begins with (default:
        #        <tt>fledge PHONE run</tt>).
        # [build] Writes the project, given the arguments of <tt>fledge
        #         PHONE project</tt> and where it prints (default: a
        #         Fledge::CLI::Build's +call+).
        # [run] Builds, installs, and follows the app, given the phone,
        #       the Fledge::App, the project's folder, and the device
        #       <tt>--device</tt> names or +nil+, and returns the program's
        #       status (default: #run).
        def initialize(out:, err:, phone:, env: ENV, name: nil, build: nil, run: nil)
          @out = out
          @err = err
          @phone = phone
          @env = env
          @name = name || "fledge #{phone.name} run"
          @build = build || -> (arguments, printed) { Build.new(out: printed, err:, env:, phone:, name: @name).call(arguments) }
          @run = run || method(:run)
        end

        # Runs the command with the arguments after +run+, and returns the
        # program's exit status, or 1 when the app could not be built or
        # run. Raises Fledge::UsageError for arguments it cannot make
        # sense of.
        def call(argv)
          options = Options.parse(argv)
          app = App.at(options.path)
          printed = StringIO.new
          built = @build.call(["--out", options.out, "--", options.path], printed)
          return built unless built.zero?

          status = @run.call(@phone, app, File.expand_path(printed.string.strip), options.device)
          status.between?(0, 255) ? status : 1
        rescue UsageError
          raise
        rescue Error => e
          e.message.each_line { |line| @err.puts "#{@name}: #{line.chomp}" }
          1
        end

        # Builds the project at +project+ for +phone+ with the system's
        # own tools, runs it on +device+, a Simulator's UDID or adb's
        # serial, or else on the one booted Simulator or adb's device, and
        # returns the status of +app+'s program.
        private def run(phone, app, project, device)
          name = app.name
          identifier = app.identity.identifier.to_s
          follower = PhoneRun.new(out: @out, err: @err)
          if phone.name == "ios"
            @err.puts "Building #{name} for the iOS Simulator with xcodebuild"
            bundle = PhoneRun::IOS.build(project, name)
            udid = device || PhoneRun::IOS.booted(Fledge::Command.run("xcrun", "simctl", "list", "devices", "booted", "-j", install: PhoneRun::IOS::INSTALL))
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
end
