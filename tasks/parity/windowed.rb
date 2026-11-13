# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require "fileutils"
require "json"
require "open3"

class Parity
  # The windowed check (doc/contributors/design/parity.md, "The windowed
  # check"): the probe built as a windowed app, and ruby main.rb, each
  # started as the desktop starts an app, with what the desktop gives it
  # in place of a terminal's. The probe writes its report to a file
  # (parity report FILE), since a windowed app has no terminal.
  #
  # - macOS: open -n -W, through Launch Services, as Finder starts an
  #   app. The reference is an .app of the same name and identifier whose
  #   executable execs the reference ruby with main.rb's path, as a
  #   script's .app runs its interpreter.
  # - Windows: cmd's start, which starts a program with ShellExecuteEx, as
  #   Explorer does, in the program's folder, with no console and no
  #   standard handles. The reference is the reference Ruby's rubyw.exe,
  #   the GUI-subsystem ruby RubyInstaller ships for windowed scripts.
  # - Linux: gio launch, GLib's own launcher of desktop entries, which
  #   GNOME's shell starts apps with, from the home folder. The app's entry
  #   is the one fledge build wrote, with the program's full path in Exec,
  #   as a person installs it; the reference's is the same entry with ruby
  #   and main.rb's path in Exec.
  #
  # Both get the same arguments: report and the same file.
  class Windowed
    NAME = "ParityWindow"
    IDENTIFIER = "com.setdef.fledge.ParityWindow"

    # How long a start may take, until its report is written.
    TIMEOUT = 300

    # The variables a desktop gives each start a value of its own, which
    # no two starts share: the process ID gio launch records
    # (gdesktopappinfo.c, child_setup, at GLib 2.80).
    PER_START = %w[GIO_LAUNCHED_DESKTOP_FILE_PID].freeze

    # +parity+ builds the app (Parity#build_app); +ruby+ is the reference
    # ruby, and +script+ the main.rb it runs; +work+ the check's folder.
    def initialize(parity, ruby:, script:, work:)
      @parity = parity
      @platform = parity.platform
      @ruby = ruby
      @script = script
      @work = File.join(work, "windowed")
      @report = File.join(@work, "report")
    end

    # The reports of ruby main.rb and of the windowed app, each started as
    # the desktop starts one, with +env+, each with PER_START's values
    # made one.
    def reports(env)
      FileUtils.mkdir_p(@work)
      @program = @parity.build_app(project, NAME)
      [start(reference(env), env), start(app(env), env)]
    end

    # +report+ with the value of each of PER_START's variables in ENV and a
    # child's ENV as <per start>.
    def self.per_start(report)
      ["ENV", "child ENV"].each_with_object(report.dup) do |fact, made|
        variables = made[fact]
        next unless variables.is_a?(Hash)

        made[fact] = variables.to_h { |name, value| [name, PER_START.include?(name) ? "<per start>" : value] }
      end
    end

    # The probe as a windowed app's project, with no installers.
    private def project
      folder = File.join(@work, "project")
      FileUtils.mkdir_p(folder)
      FileUtils.cp(@script, folder)
      File.write(File.join(folder, "fledge.yml"), "name: #{NAME}\nkind: windowed\nidentifier: #{IDENTIFIER}\ninstallers: []\n")
      folder
    end

    # How to start ruby main.rb as the desktop starts an app: a command
    # and the folder to run it from.
    private def reference(env)
      case @platform.os
      when "darwin" then launch_services(reference_bundle, env)
      when "windows" then shell_start(File.join(File.dirname(@ruby), "rubyw.exe"), [@script])
      else gio_launch(env, Fledge::DesktopEntry.exec(@ruby), Fledge::DesktopEntry.exec(@script))
      end
    end

    # How to start the built app as the desktop starts it.
    private def app(env)
      case @platform.os
      when "darwin" then launch_services(built_bundle, env)
      when "windows" then shell_start(@program, [])
      else gio_launch(env, Fledge::DesktopEntry.exec(@program))
      end
    end

    private def built_bundle = File.join(File.dirname(@program), "#{NAME}.app")

    # The reference's .app: the built app's Info.plist, so that Launch
    # Services knows both by the same name and identifier, and an
    # executable that execs the reference ruby with main.rb's path and
    # the arguments it was given, as a script's .app runs its interpreter.
    # It is compiled rather than a shell script, since a shell would add
    # its own variables (PWD, SHLVL, _) to what ruby sees.
    private def reference_bundle
      bundle = File.join(@work, "reference", "#{NAME}.app")
      executable = File.join(bundle, "Contents", "MacOS", NAME)
      FileUtils.mkdir_p(File.dirname(executable))
      FileUtils.cp(File.join(built_bundle, "Contents", "Info.plist"), File.join(bundle, "Contents", "Info.plist"))
      source = <<~C
        #include <unistd.h>
        int main(int argc, char **argv) {
          char *arguments[argc + 2];
          arguments[0] = #{JSON.generate(@ruby)};
          arguments[1] = #{JSON.generate(@script)};
          for (int i = 1; i <= argc; i++) arguments[i + 1] = argv[i];
          execv(arguments[0], arguments);
          return 127;
        }
      C
      out, status = Open3.capture2e("cc", "-x", "c", "-o", executable, "-", stdin_data: source)
      raise "cc could not compile the reference's executable:\n#{out}" unless status.success?

      bundle
    end

    # open's command for +bundle+, which Launch Services starts with the
    # environment of the person's session, not open's own, so the
    # person's variables of +env+ are given to it (open --env), as a
    # person's session would hold them.
    private def launch_services(bundle, env)
      given = env.slice("HOME", *PERSON).flat_map { |name, value| ["--env", "#{name}=#{value}"] }
      [["open", "-n", "-W", "-g", *given, bundle, "--args", "report", @report], @work]
    end

    # cmd's command that starts +program+ with +arguments+, then report
    # and the report's path, with ShellExecuteEx, from the program's
    # folder, and waits for it. One string, since cmd reads its own
    # command line, not the C runtime's arguments.
    private def shell_start(program, arguments)
      quoted = [program, *arguments, "report", @report].map { |argument| "\"#{argument.tr('/', '\\')}\"" }
      folder = File.dirname(program).tr("/", "\\")
      [%(cmd.exe /d /c start "" /D "#{folder}" /wait #{quoted.join(' ')}), @work]
    end

    # gio's command that launches a desktop entry whose Exec is
    # +programs+, then report and the report's path, from the home folder
    # of +env+: the built app's entry, as fledge build wrote it, with that
    # Exec in place of its own.
    private def gio_launch(env, *programs)
      exec = [*programs, "report", Fledge::DesktopEntry.exec(@report)].join(" ")
      built = File.read(File.join(File.dirname(@program), "#{IDENTIFIER}.desktop"))
      entry = File.join(@work, "applications", "#{IDENTIFIER}.desktop")
      FileUtils.mkdir_p(File.dirname(entry))
      File.write(entry, built.sub(/^Exec=.*$/) { "Exec=#{Fledge::DesktopEntry.string(exec)}" })
      [["gio", "launch", entry], env.fetch("HOME")]
    end

    # Runs +command+ from +folder+ with +env+ alone, waits for it and then
    # for the report it starts, and returns the report, with PER_START's
    # values made one.
    private def start((command, folder), env)
      FileUtils.rm_f(@report)
      log = File.join(@work, "start.log")
      deadline = Time.now + TIMEOUT
      pid = Process.spawn(env, *command, :chdir => folder, :unsetenv_others => true, :in => File::NULL, %i[out err] => log)
      status = wait(pid, deadline)
      raise "#{Array(command).join(' ')} failed (#{status}):\n#{File.read(log)}" unless status.success?

      sleep 0.2 until File.exist?(@report) || Time.now > deadline
      raise "#{Array(command).join(' ')} wrote no report in #{TIMEOUT} seconds:\n#{File.read(log)}" unless File.exist?(@report)

      Windowed.per_start(Reports.report(File.read(@report)))
    end

    # The status of the process +pid+, which is stopped if it has not
    # ended by +deadline+.
    private def wait(pid, deadline)
      loop do
        _, status = Process.wait2(pid, Process::WNOHANG)
        return status if status

        if Time.now > deadline
          Process.kill(:KILL, pid)
          return Process.wait2(pid).last
        end
        sleep 0.2
      end
    end
  end
end
