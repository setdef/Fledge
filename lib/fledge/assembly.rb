# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "fileutils"
require_relative "desktop_entry"
require_relative "entry"
require_relative "error"
require_relative "installers"
require_relative "mac_bundle"
require_relative "platform"
require_relative "tar_gz"
require_relative "windows_resources"

module Fledge
  # Puts one app into one platform's runtime: a folder and its archive.
  #
  # A runtime archive holds a launcher named +launcher+ (+launcher.exe+
  # on Windows, beside +launcherw.exe+ for windowed apps) beside the Ruby
  # it embeds. A built app is that runtime with the launcher renamed to
  # the app's name, the app's project copied into its +app+ folder, and a
  # CONFIG beside the launcher that tells it which program in +app+ to run
  # and, for a project with a Gemfile, which Gemfile to set up (ADR 005).
  # The app's identity goes in as each operating system reads it (ADR
  # 008): on Windows, into the program's own resources
  # (Fledge::WindowsResources); for a windowed app on macOS, as an
  # <tt>.app</tt> bundle that holds all of it (Fledge::MacBundle); for a
  # windowed app on Linux, as a desktop entry and icons beside the program
  # (Fledge::DesktopEntry). It is written twice: as
  # <tt>OUT/NAME-PLATFORM/</tt>, to try, and as
  # <tt>OUT/NAME-PLATFORM.tar.gz</tt> (<tt>.zip</tt> for Windows), to
  # ship; and a windowed app's installers (Fledge::Installers) are
  # written beside them, from the same entries, with the installer files
  # the runtime keeps in its +installer+ folder, which no app holds.
  # Unpacking the runtime and packing the folder again would lose the
  # launcher's executable bit on a disk that has none.
  #
  # This class streams each runtime entry, then CONFIG, each of the app's
  # entries, and the files the build adds (the app's gems), into the
  # folder and the archive at once, so the archive keeps the permissions
  # and symlinks the runtime was built with, and the launcher last, once
  # everything it must describe or seal is known. The platform names the
  # archive's format (Fledge::Platform#archive_format).
  # It refuses to let an added file replace one the runtime holds,
  # replaces a previous build of the same app and platform, and removes
  # what it wrote if the build fails.
  #
  # Use it once per target in <tt>fledge build</tt>.
  #
  # === Example
  #
  #--
  # SPDX-SnippetBegin
  # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
  # SPDX-License-Identifier: MIT-0
  #++
  #   platform = Fledge::Platform.find("x86_64-linux")
  #   Fledge::Assembly.new(
  #     app: Fledge::App.at("examples/hello"),
  #     platform:,
  #     runtime: Fledge::Runtimes.new.archive(platform),
  #     out: File.expand_path("dist")
  #   ).call
  #   # => "/path/to/dist/Hello-x86_64-linux.tar.gz"
  #--
  # SPDX-SnippetEnd
  #++
  class Assembly
    # The launcher's name inside a runtime archive, before the platform
    # adds an extension.
    LAUNCHER = "launcher"

    # The windowed launcher's name inside a Windows runtime, before its
    # extension: a GUI-subsystem program, named as RubyInstaller names
    # +rubyw.exe+ beside +ruby.exe+.
    WINDOWED_LAUNCHER = "launcherw"

    # The runtime's folder of what installers need and apps do not: the
    # AppImage runtime in a Linux runtime, and NSIS in a Windows one.
    INSTALLER = "installer"

    # The file beside the launcher that says what it runs. The launcher
    # reads it as Python reads the pyvenv.cfg beside its interpreter (PEP
    # 405): lines of <tt>key = value</tt>.
    CONFIG = "fledge.cfg"

    # Creates the assembly.
    #
    # [app] The Fledge::App to ship.
    # [platform] The Fledge::Platform the runtime is for.
    # [runtime] The path of the runtime archive.
    # [out] The folder builds go to, as an absolute path.
    # [app_files] Contents for files in the app's folder, by path relative
    #             to it, in place of the project's own file at that path or
    #             beside the rest.
    # [files] More entries for the built folder, with paths relative to
    #         it, which may not replace anything the runtime holds.
    # [makensis] The NSIS compiler, for a Windows app's NSIS installer, or
    #            +nil+ when there is none to build.
    def initialize(app:, platform:, runtime:, out:, app_files: {}, files: [], makensis: nil)
      @app = app
      @platform = platform
      @runtime = runtime
      @out = out
      @app_files = app_files
      @files = files
      @makensis = makensis
      @placed = {} # : Hash[String, bool]
      @bundle = nil # : MacBundle?
      @writers = [] # : Array[Dmg | Nsis | AppImage]
      @kit = {} # : Hash[String, Entry]
      @installers = [] # : Array[String]
    end

    # The paths of the installers #call wrote, after it has run, such as
    # <tt>OUT/NAME-PLATFORM.dmg</tt>; empty for an app that has none.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   assembly.call
    #   assembly.installers # => ["/path/to/dist/Hello Window-x86_64-linux.AppImage"]
    #--
    # SPDX-SnippetEnd
    #++
    attr_reader :installers

    # The built app's folder and archive name: <tt>NAME-PLATFORM</tt>.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   assembly.base_name # => "Hello-x86_64-linux"
    #--
    # SPDX-SnippetEnd
    #++
    def base_name
      "#{@app.name}-#{@platform}"
    end

    # Writes the built app's folder and archive, and returns the
    # archive's path. Raises Fledge::Error when the runtime is not a
    # Fledge runtime, the app's name collides with a file in it, or an
    # added file would replace one of the runtime's.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   assembly.call # => "/path/to/dist/Hello-x86_64-linux.tar.gz"
    #--
    # SPDX-SnippetEnd
    #++
    def call
      executable = @platform.executable(@app.name)
      { "app" => "its own app folder", CONFIG => "the file that says what it runs" }.each do |taken, what|
        raise Error, "an app named #{@app.name} would collide with #{what}. Give it another name." if executable.casecmp?(taken)
      end

      build
    end

    # The contents of CONFIG for the app: its entry point, and its
    # Gemfile when it has one, relative to the +app+ folder, and its
    # identifier when it has one, which the Windows launcher makes its
    # AppUserModelID.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   assembly.launch_config.lines.drop(1)
    #   # => ["entry = exe/my_cool_app\n", "gemfile = Gemfile\n"]
    #--
    # SPDX-SnippetEnd
    #++
    def launch_config
      lines = ["entry = #{config_value(@app.entry)}"]
      gemfile = @app.gemfile
      lines << "gemfile = #{config_value(gemfile)}" if gemfile
      identifier = @app.identity.identifier
      lines << "identifier = #{identifier}" if identifier
      "# Written by fledge build: what this app's program runs (ADR 005).\n#{lines.join("\n")}\n"
    end

    private def config_value(path)
      if path.match?(/[\r\n]/) || path != path.strip
        raise Error, "#{path.inspect} can't be an app's program or Gemfile: its name begins or ends with a space, or holds a line break"
      end

      path
    end

    private def build
      remove_output
      FileUtils.mkdir_p(folder)
      mtime = Time.now.to_i
      @bundle = (@platform.os == "darwin" && @app.identity.windowed?) ? MacBundle.new(@app.identity) : nil
      @writers = Installers.formats(@app, @platform).map do |format|
        Installers.writer(format, app: @app, folder:, makensis: @makensis, mtime:)
      end
      path = @platform.archive_format.write(archive, mtime:) do |writer|
        writer.add(Entry.directory(base_name))
        launcher = copy_runtime(writer)
        add(writer, Entry.file(CONFIG, launch_config))
        copy_app(writer)
        @files.each { |entry| add(writer, entry) }
        finish(writer, launcher)
      end
      @installers = @writers.map { |installer| installer.finish(@kit) }
      path
    rescue
      @writers.each(&:abort)
      remove_output
      raise
    end

    # Places the launcher, last, as the app's program: on Windows with the
    # app's resources in it; in a bundle, after the bundle's own files,
    # signed for it; on Linux, after a windowed app's desktop entry.
    private def finish(writer, launcher)
      bundle = @bundle
      if bundle
        bundle.extras.each { |entry| put(writer, entry) }
        bundle.finish(launcher).each { |entry| put(writer, entry) }
        return
      end

      executable = @platform.executable(@app.name)
      content = launcher.content
      content = windows_program(content, executable) if @platform.windows?
      DesktopEntry.new(@app.identity).entries.each { |entry| put(writer, entry) } if @platform.os == "linux" && @app.identity.windowed?
      put(writer, Entry.file(executable, content, mode: launcher.mode))
    end

    private def windows_program(content, executable)
      WindowsResources.apply(content, identity: @app.identity, file_name: executable)
    rescue Error => e
      raise Error, "the runtime's #{@platform.executable(launcher_name)} #{e.message}"
    end

    # The runtime's launcher for this app: the windowed one on Windows for
    # a windowed app, the one launcher elsewhere.
    private def launcher_name
      (@platform.windows? && @app.identity.windowed?) ? WINDOWED_LAUNCHER : LAUNCHER
    end

    private def folder
      File.join(@out, base_name)
    end

    private def archive
      "#{folder}#{@platform.archive_extension}"
    end

    private def remove_output
      FileUtils.rm_rf(folder)
      FileUtils.rm_f(archive)
      FileUtils.rm_f(Installers::SUFFIX.keys.map { |format| Installers.file_name(format, folder) })
    end

    # Copies every entry of the runtime but its launchers and its
    # installer files, which it keeps for the installers, and returns the
    # launcher this app runs.
    private def copy_runtime(writer)
      launcher = @platform.executable(launcher_name)
      launchers = [launcher, @platform.executable(LAUNCHER), @platform.executable(WINDOWED_LAUNCHER)]
      top = nil # : String?
      found = nil # : Entry?
      TarGz.each_entry(@runtime) do |entry|
        first, rest = entry.path.split("/", 2)
        top ||= first
        raise Error, "#{@runtime} is not a Fledge runtime: it holds both #{top}/ and #{first}" unless first == top
        next unless rest

        found = entry if rest == launcher
        next if launchers.include?(rest)
        next @kit[rest.delete_prefix("#{INSTALLER}/")] = entry if rest.start_with?("#{INSTALLER}/") && entry.type == :file
        next if rest == INSTALLER || rest.start_with?("#{INSTALLER}/")

        add(writer, entry.with(path: runtime_path(rest)))
      end
      found or raise Error, "#{@runtime} is not a Fledge runtime: it has no #{launcher}"
    end

    private def runtime_path(path)
      executable = @platform.executable(@app.name)
      first = path.split("/", 2).first.to_s
      raise Error, "#{@runtime} is not a Fledge runtime: it holds an app folder" if first == "app"
      raise Error, "#{@runtime} is not a Fledge runtime: it holds a #{CONFIG}" if first == CONFIG
      if first.casecmp?(executable)
        raise Error, "an app named #{@app.name} would collide with the runtime's #{first}. Give it another name."
      end

      path
    end

    # The project's entries in +app+, with the contents @app_files gives
    # in place of a file's own, then the files of @app_files the project
    # does not have.
    private def copy_app(writer)
      add(writer, Entry.directory("app"))
      remaining = @app_files.dup
      @app.entries(skip: [@out]).each do |entry|
        content = remaining.delete(entry.path)
        entry = entry.with(content:) if content && entry.type == :file
        add(writer, entry.with(path: "app/#{entry.path}"))
      end
      remaining.each { |path, content| add(writer, Entry.file("app/#{path}", content)) }
    end

    # Places an entry of the runtime, the app, or the build, at its place
    # in the built app: where it is, or in a bundle's +Resources+.
    private def add(writer, entry)
      bundle = @bundle
      put(writer, bundle ? entry.with(path: bundle.resource(entry.path)) : entry)
    end

    # Places +entry+, whose path is in the built app's folder, after any
    # folder above it that is not there yet. A folder already there stays;
    # any other entry already there is the runtime's, which nothing the
    # build adds may replace.
    private def put(writer, entry)
      parents = entry.path.split("/")[0...-1] || []
      parents.each_index do |index|
        parent = parents.first(index + 1).join("/")
        place(writer, Entry.directory(parent)) unless @placed.key?(parent)
      end
      return if entry.type == :directory && @placed.key?(entry.path)
      raise Error, "#{entry.path} is in #{@runtime} already, so the build can't add its own" if @placed.key?(entry.path)

      place(writer, entry)
    end

    private def place(writer, entry)
      entry.write_into(folder)
      writer.add(entry.with(path: "#{base_name}/#{entry.path}"))
      @placed[entry.path] = true
      @bundle&.seal(entry)
      @writers.each { |installer| installer.add(entry) }
    end
  end
end
