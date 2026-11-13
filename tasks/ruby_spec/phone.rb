# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require "fileutils"
require_relative "../mobile_parity"

class RubySpec
  # The ruby/spec comparison on phones (doc/contributors/design/parity.md,
  # "ruby/spec on phones"): ruby/spec, run by MSpec, in a phone app built
  # as a developer builds one, with fledge build ios or android and then
  # Xcode or Gradle, in the iOS Simulator, on an iPhone and an iPad, and
  # on an Android emulator, each run's output read back from the system
  # log as the mobile parity check reads its probe's (MobileParity). It
  # is compared with the same project under ruby main.rb on the stock
  # Ruby of the computer that runs the simulator, the release the
  # desktop runtime is made from, of the same version and revision as
  # the phone runtime, which the check confirms from RUBY_DESCRIPTION.
  #
  # Each side's report is MSpec's standard output alone, where MSpec
  # prints RUBY_DESCRIPTION, each failure, and the totals. A phone's log
  # holds standard output and standard error as two threads forward them,
  # interleaved as those threads happen to run (MobileParity::IOS.messages,
  # MobileParity::Android.messages), so a line of standard error, such as
  # the warning MSpec prints when it exits that its temporary folder is
  # not empty (mspec/helpers/tmp.rb), can land between a failure's number
  # and its description, where the failure would go unread. Stock Ruby's
  # standard error goes to a file of its own, so both sides are read
  # alike; the app's stays in the system log.
  #
  # A phone app takes no arguments and runs Ruby once a launch, so the
  # app runs the desktop's DIRECTORIES in one mspec-run, with the arguments main.rb
  # reads from arguments.txt, and RubySpecPhoneFormatter names the
  # directory of each failure. Stock Ruby runs the same main.rb with the
  # same arguments. What no phone can run is left out of both runs
  # (EXCLUDED), and every example that fails on one side only must be
  # justified in RubySpec::JUSTIFIED for the phone's platform, or the
  # check fails.
  #
  #   ruby tasks/ruby_spec.rb ios RUNTIMES_DIR
  #   ruby tasks/ruby_spec.rb android-build RUNTIMES_DIR
  #   ruby tasks/ruby_spec.rb android
  class Phone < RubySpec
    # What a run that did not finish is called: the one run of all of
    # DIRECTORIES.
    LABEL = "ruby/spec"

    # The app's name and identifier, which iOS and Android know it by.
    NAME = "RubySpec"
    IDENTIFIER = "com.setdef.fledge.RubySpec"

    # How long a phone may take to run the specs, from launch to its
    # status.
    TIMEOUT = 1800

    # What a phone leaves out of both runs, on +phones+ ("ios",
    # "android", or both when nil): +files+, spec files or folders
    # relative to spec/, and +examples+, descriptions (mspec-run -E,
    # which leaves out each example whose description holds one), each
    # for the +reason+ given, but for +keep+, which maps some of +files+
    # to the descriptions of their examples that run, since they start
    # nothing the reason is about.
    class Exclusion < Data.define(:reason, :phones, :files, :examples, :keep)
      def initialize(reason:, phones:, files:, examples:, keep: {})
        super
      end

      def applies?(phone)
        phones.nil? || phones.include?(phone)
      end
    end

    EXCLUDED = [
      Exclusion.new(
        reason: "Every example starts ruby with options or a script, and iOS lets no app start a program " \
          "(doc/contributors/design/phone-projects.md, \"Parity on a phone\"). Android's runtime has a ruby program, " \
          "which RbConfig.ruby names (ADR 083), and runs them.",
        phones: %w[ios], files: ["command_line"], examples: [],
      ),
      Exclusion.new(
        reason: "Each signals a Ruby it starts, through ProcessSpecs::Signalizer, which starts it with MSpec's ruby_exe " \
          "in a thread of its own, or through Process.spawn, and iOS lets no app start a program: Apple's SDK marks " \
          "system() prohibited there, \"On iOS, process spawning is unavailable\" (iPhoneOS27.2.sdk, " \
          "usr/include/_stdlib.h, lines 205 to 208). The rest of core/process/kill_spec.rb runs, among it a signal " \
          "to the app's own process. Android runs them, as it runs command_line.",
        phones: %w[ios], files: [],
        examples: [
          "Process.kill raises Errno::ESRCH if the process does not exist",
          "Process.kill accepts a Symbol as a signal name",
          "Process.kill accepts a String as signal name",
          "Process.kill accepts a signal name without the 'SIG' prefix",
          "Process.kill accepts a signal name with the 'SIG' prefix",
          "Process.kill accepts an Integer as a signal value",
          "Process.kill calls #to_int to coerce the pid to an Integer",
          "Process.kill signals multiple processes",
          "Process.kill returns the number of processes signaled",
          "Process.kill signals the process group if",
        ],
      ),
      Exclusion.new(
        reason: "These are about Ruby's ways to start a program and wait for it, Process.spawn, Kernel#system, " \
          "backquotes, IO.popen, Open3, Process.wait and its kin, and IO#pid, and check each by starting the Ruby " \
          "under test, through RUBY_EXE or ruby_cmd rather than ruby_exe; " \
          "whether such a child that cannot start has ended when an example looks is a race. iOS has no such Ruby, " \
          "since it lets no app start a program (doc/contributors/design/phone-projects.md, \"Parity on a phone\"), " \
          "so RbConfig.ruby names a program that is not there. Android runs them, as it runs command_line. The " \
          "examples kept start nothing: each asks whether a method is public or private, raises before any child " \
          "could be, waits with no child, or asks IO#tty? of a file or a closed stream.",
        phones: %w[ios],
        keep: {
          "core/process/spawn_spec.rb" => [
            "Process.spawn with a single argument raises an ArgumentError if the command includes a null byte",
            "Process.spawn with a single argument raises a TypeError if the argument does not respond to #to_str",
            "Process.spawn with multiple arguments raises an ArgumentError if an argument includes a null byte",
            "Process.spawn with multiple arguments raises a TypeError if an argument does not respond to #to_str",
            "Process.spawn with a command array raises an ArgumentError if the Strings in the Array include a null byte",
            "Process.spawn with a command array raises a TypeError if an element in the Array does not respond to #to_str",
            "Process.spawn raises an ArgumentError if passed no command arguments",
            "Process.spawn raises an ArgumentError if passed env or options but no command arguments",
            "Process.spawn raises an ArgumentError if passed env and options but no command arguments",
          ],
          "core/kernel/spawn_spec.rb" => ["Kernel#spawn is a private method", "Kernel.spawn is a public method"],
          "core/kernel/system_spec.rb" => ["Kernel#system is a private method", "Kernel.system is a public method"],
          "core/process/wait_spec.rb" => ["Process.wait raises an Errno::ECHILD if there are no child processes"],
          "core/process/wait2_spec.rb" => ["Process.wait2 raises a StandardError if no child processes exist"],
          "core/process/waitall_spec.rb" => [
            "Process.waitall returns an empty array when there are no children",
            "Process.waitall takes no arguments",
          ],
          "core/process/status/wait_spec.rb" => ["Process::Status.wait returns a status with pid -1 if there are no child processes"],
          "core/io/tty_spec.rb" => [
            "IO#tty? returns true if this stream is a terminal device (TTY)",
            "IO#tty? returns false if this stream is not a terminal device (TTY)",
            "IO#tty? raises IOError on closed stream",
          ],
        },
        files: %w[
          core/process/spawn_spec.rb
          core/kernel/spawn_spec.rb
          core/kernel/system_spec.rb
          core/kernel/backtick_spec.rb
          core/io/popen_spec.rb
          language/execution_spec.rb
          library/open3
          core/process/wait_spec.rb
          core/process/wait2_spec.rb
          core/process/waitall_spec.rb
          core/process/status/wait_spec.rb
          core/io/pid_spec.rb
          core/io/tty_spec.rb
        ],
        examples: ["IO#close on an IO.popen stream sets $?"],
      ),
      Exclusion.new(
        reason: "Each reads the process's command line from /proc/PID/cmdline, or, where there is no /proc, from ps, " \
          "which it starts, and iOS has no /proc and lets no app start a program. iOS's Ruby sets the title where " \
          "ps reads it (RuntimeBuilder::RubySource.setproctitle_c), and the parity probe reads it there through " \
          "sysctl, which needs no program (\"$0= titles the process\"). Android has /proc, and runs both examples.",
        phones: %w[ios], files: [],
        examples: ["Process.setproctitle should set the process title", "Global variable $0 actually sets the program name"],
      ),
      Exclusion.new(
        reason: "Each example reads the Process::Status of a Ruby that its before :each hook starts with MSpec's " \
          "ruby_exe, which skips on iOS (tasks/ruby_spec/phone_config.rb), since iOS lets no app start a program; a " \
          "skip in a hook leaves the example uncounted, so the app ran 13 fewer examples than stock Ruby in run " \
          "43357360436, which the comparison of examples run found. Android runs them, as it runs command_line.",
        phones: %w[ios],
        files: %w[
          core/process/status/exited_spec.rb
          core/process/status/exitstatus_spec.rb
          core/process/status/pid_spec.rb
          core/process/status/signaled_spec.rb
          core/process/status/success_spec.rb
          core/process/status/termsig_spec.rb
        ],
        examples: [],
      ),
      Exclusion.new(
        reason: "Each starts a program of the system's to check what it tests, which iOS lets no app do, where " \
          "Android has them: IO#close_read's, #close_write's, and #stat's examples open a pipe to cat first, the " \
          "examples start cat, id, or whoami, getgrgid's and struct_group's files start id as they load, and " \
          "getpwuid's and struct_passwd's start id in a before :all hook, whose error leaves out every example of the file.",
        phones: %w[ios],
        files: %w[
          library/etc/getgrgid_spec.rb
          library/etc/getpwuid_spec.rb
          library/etc/struct_group_spec.rb
          library/etc/struct_passwd_spec.rb
          core/io/close_read_spec.rb
          core/io/close_write_spec.rb
          core/io/stat_spec.rb
        ],
        examples: [
          "IO#lineno raises an IOError on a duplexed stream with the read side closed",
          "IO#lineno= raises an IOError on a duplexed stream with the read side closed",
          "Process.gid returns the correct gid for the user executing this process",
          "Process.uid returns the correct uid for the user executing this process",
          "Process.groups gets an Array of the gids of groups in the supplemental group access list",
          "Process.initgroups initializes the supplemental group access list",
          "Etc.getpwnam returns a Etc::Passwd struct instance for the given user",
        ],
      ),
      Exclusion.new(
        reason: "Each forks a child that goes on running Ruby, and whether an iOS device lets an app fork is " \
          "unchecked: Apple's SDK marks fork prohibited only on watchOS and tvOS (usr/include/unistd.h, line 459, " \
          "iOS 27.2 SDK), and that a device's sandbox denies it is others' report, such as CPython's iOS build's " \
          "(\"no fork syscall\", configure.ac, line 7732 at v3.14.0), not Apple's " \
          "(doc/contributors/design/phone-projects.md, \"Parity on a phone\"). The Simulator lets an app fork, as " \
          "the Mac does, so a pass there would claim for iOS what only the Mac showed. Android lets an app fork, " \
          "and runs these.",
        phones: %w[ios],
        files: %w[
          core/kernel/fork_spec.rb
          core/process/_fork_spec.rb
          core/process/fork_spec.rb
          core/process/daemon_spec.rb
          core/process/setpgid_spec.rb
          core/process/setpgrp_spec.rb
          core/thread/fork_spec.rb
        ],
        examples: [
          "IO::Buffer.map is shareable across processes",
          "is not shared across processes",
          "gets data from a fork when passed -",
          "opens a pipe to a fork if the rest is -",
          "starts returns a forked process if the command is -",
          "doesn't block if no child is available when WNOHANG is used",
        ],
      ),
      Exclusion.new(
        reason: "The example gives one descriptor to two Dirs, Dir.for_fd's over Dir.open's, and closes it twice, " \
          "which Android's fdsan exists to stop: bionic's fdopendir tags the descriptor as its DIR's, and finding it " \
          "already another DIR's, aborts the process (libc/bionic/dirent.cpp, lines 69 to 99, and fdsan.cpp, lines " \
          "299 to 330 and 111 to 114, fatal by default, at 731631f), where glibc lets it; MSpec's run would end there.",
        phones: %w[android], files: [],
        examples: ["Dir#close raises an error if the file descriptor is closed with another Dir instance"],
      ),
    ].freeze

    # The arguments of mspec-run for both runs on +phone+, one to a line
    # in arguments.txt: the formatter, the timeout the desktop's run
    # has, the examples EXCLUDED leaves out there, then the desktop's
    # DIRECTORIES less the files it leaves out (MSpecScript#files
    # subtracts a pattern that begins with ^), and a line
    # --ruby-spec-keep=FILE:DESCRIPTION for each example of a file that
    # runs alone of its file's, which main.rb takes out of mspec-run's
    # arguments for phone_config.rb.
    def self.arguments(phone)
      excluded = EXCLUDED.select { |exclusion| exclusion.applies?(phone) }
      kept = excluded.flat_map { |exclusion| exclusion.keep.to_a }
      [
        "-B",
        "../phone_config.rb",
        "--timeout",
        "300",
        *excluded.flat_map(&:examples).flat_map { |example| ["-E", example] },
        *DIRECTORIES,
        *(excluded.flat_map(&:files) - kept.map(&:first)).map { |file| "^#{file}" },
        *kept.flat_map { |file, descriptions| descriptions.map { |description| "--ruby-spec-keep=#{file}:#{description}" } },
      ]
    end

    # The Ruby a RUBY_DESCRIPTION names: its version and revision.
    def self.ruby(output)
      output[/^ruby (\S+) \([^)]*?\b(\h{7,})\)/] or raise "the run printed no RUBY_DESCRIPTION:\n#{output[0, 500]}"
      "#{Regexp.last_match(1)} (revision #{Regexp.last_match(2)})"
    end

    # The output of the app's run from its log +entries+, without the
    # host's line with its status.
    def self.output(entries)
      "#{entries.grep_v(MobileParity::STATUS).join("\n")}\n"
    end

    # +output+, with the listing of the examples it ran in its place: a
    # phone's run writes it to a file, whose path it prints (main.rb,
    # listing_config.rb), since a phone's log drops lines when a process
    # writes tens of thousands at once, as logcat dropped a fifth of the
    # listing on an Android emulator in run 43350707323. The block
    # returns the file's contents, read where the run wrote it.
    def self.listed(output)
      path = output[%r{^ruby/spec listing: in (.+)$}, 1] or return output
      output.b + yield(path.chomp).to_s.b
    end

    def initialize(phone, runtimes: ENV.fetch("FLEDGE_RUNTIME_DIR", File.join(ROOT, "tmp", "runtime")),
      work: File.join(ROOT, "tmp", "ruby-spec-#{phone}-work"), out: ENV.fetch("RUBY_SPEC_OUT", File.join(ROOT, "tmp", "ruby-spec-#{phone}")),
      log: $stdout
    )
      super(platform: Fledge::Platform.local, work:, out:, runtimes:, log:)
      @phone = phone
    end

    # In the iOS Simulator: writes the project, runs stock Ruby, builds
    # the app with fledge build ios and xcodebuild, runs it on a new
    # iPhone and a new iPad, and returns whether every difference on each
    # is justified.
    def ios
      app = prepare
      FileUtils.mkdir_p(File.join(@work, "ios"))
      simulator = MobileParity::IOS.new(runtimes: @runtimes, work: File.join(@work, "ios"), out: @log)
      projects = MobileParity.projects("ios", runtimes: @runtimes, out: File.join(@work, "projects"), apps: [app])
      bundles = projects.to_h { |built, project| [built, simulator.build_app(built, project)] }
      run_stock
      MobileParity::IOS::FAMILIES.map do |family|
        simulator.on_simulator(family, bundles, timeout: TIMEOUT) do |_, logged, device|
          compare(logged.output, MobileParity::IOS::TARGET, device)
        end
      end.all?
    end

    # For an Android emulator, before one runs: writes the project, runs
    # stock Ruby, and builds the app's debug APK with fledge build
    # android and the project's Gradle wrapper, keeping stock Ruby's
    # output and the APK in the output folder for #android.
    def android_build
      app = prepare
      project = MobileParity.projects("android", runtimes: @runtimes, out: File.join(@work, "projects"), apps: [app]).fetch(app)
      gradlew = File.join(project, Gem.win_platform? ? "gradlew.bat" : "gradlew")
      system(gradlew, "--no-daemon", "--quiet", "--project-dir", project, "assembleDebug", exception: true)
      apk = Dir.glob(File.join(project, "build", "outputs", "apk", "debug", "*-debug.apk")).first or raise "Gradle built no debug APK"
      FileUtils.cp(apk, apk_path)
      run_stock
      true
    end

    # On the running Android emulator: installs the APK #android_build
    # built, runs it, and returns whether every difference from stock
    # Ruby's run is justified.
    def android
      emulator = MobileParity::Android.new(work: @work, out: @log)
      system("adb", "logcat", "-G", "16M", exception: true)
      system("adb", "install", "-r", apk_path, exception: true)
      compare(emulator.launch(app, timeout: TIMEOUT).output, emulator.target, emulator.device) do |path|
        # As the app, whose files the shell may not read; a debug APK
        # lets run-as do that.
        IO.popen(["adb", "exec-out", "run-as", IDENTIFIER, "cat", path], "rb", &:read)
      end
    end

    # The project's two copies, one for stock Ruby and one to build, in
    # new folders, and the app to build from the second.
    private def prepare
      FileUtils.rm_rf([@work, @out])
      FileUtils.mkdir_p([@work, @out])
      sources = SOURCES.to_h { |source| [source.name, unpack(source)] }
      project(File.join(@work, "reference", "ruby_spec"), sources)
      app(project(File.join(@work, "build", "ruby_spec"), sources))
    end

    # The app, from the project in +path+.
    private def app(path = File.join(@work, "build", "ruby_spec"))
      MobileParity::App.new(path:, name: NAME, identifier: IDENTIFIER, prints: nil)
    end

    # RubySpec#project, with the phone's identifier in fledge.yml, and
    # the formatter and arguments.txt beside main.rb.
    private def project(into, sources)
      super
      File.write(File.join(into, "fledge.yml"), "name: #{NAME}\nidentifier: #{IDENTIFIER}\n")
      FileUtils.cp(File.join(__dir__, "phone_config.rb"), into)
      File.write(File.join(into, "arguments.txt"), "#{Phone.arguments(@phone).join("\n")}\n")
      into
    end

    # Runs ruby main.rb from the project's copy for stock Ruby, with the
    # Ruby the desktop runtime of this computer is made from, as the
    # desktop's comparison runs it, in its clean environment with a UTF-8
    # locale, as a phone's app has, and keeps its standard output and its
    # standard error apart in the output folder.
    private def run_stock
      parity = File.join(@work, "parity")
      FileUtils.mkdir_p(parity)
      ruby = Parity.new(platform:, work: parity, runtimes: @runtimes, out: @log).unpack_reference
      project = File.join(@work, "reference", "ruby_spec")
      env = environment("stock").merge("LANG" => "en_US.UTF-8", "RUBY_SPEC_LISTING" => File.join(@out, "stock-listing.txt"))
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      pid = Process.spawn(env, ruby, "main.rb", chdir: project, unsetenv_others: true, out: stock_path, err: stock_error_path, in: File::NULL)
      Process.wait(pid)
      seconds = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
      @log.puts format("stock %4.0fs  %s", seconds, read(File.binread(stock_path)).totals || "did not finish")
    end

    # Compares the app's run on +device+, of the platform +target+, from
    # its log +entries+, with stock Ruby's, prints and records the
    # differences, and returns whether every one is justified.
    private def compare(entries, target, device, &app_file)
      output = Phone.listed(Phone.output(entries), &app_file || -> (path) { File.binread(path) })
      File.binwrite(File.join(@out, "#{device.gsub(/[^\w.-]+/, '-')}.out"), output)
      stock_output = Phone.listed(File.binread(stock_path)) { |path| File.binread(path) }
      unless Phone.ruby(output) == Phone.ruby(stock_output)
        raise "the app runs Ruby #{Phone.ruby(output)}, but stock Ruby is #{Phone.ruby(stock_output)}"
      end

      stock = [read(stock_output)]
      built = [read(output)]
      differences = Results.compare(stock, built, platform: target)
      report(stock, built, differences, title: "ruby/spec on #{target} (#{device}), against stock Ruby #{Phone.ruby(output)} on #{platform}")
      differences.all?(&:justified?)
    end

    private def read(output)
      Results.read(nil, output).with(directory: LABEL)
    end

    private def stock_path
      File.join(@out, "stock.out")
    end

    private def stock_error_path
      File.join(@out, "stock.err")
    end

    private def apk_path
      File.join(@out, "#{IDENTIFIER}.apk")
    end
  end
end
