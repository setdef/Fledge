# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "fileutils"
require "tmpdir"
require_relative "archive"
require_relative "desktop_entry"
require_relative "entry"
require_relative "error"
require_relative "installers"
require_relative "mac_bundle"
require_relative "platform"
require_relative "windows_resources"
require_relative "assembly/runtime_folder"

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
  # written beside them, from the folder, with the installer files the
  # runtime keeps in its +tools+ folder, which no app holds.
  #
  # This class unpacks the runtime with tar (Fledge::Archive), moves it
  # into the folder, adds CONFIG, the app's project, and the files the
  # build adds (the app's gems), and places the launcher last, once
  # everything it must describe or seal is there; then it packs the
  # folder with tar, which keeps the permissions and symlinks the runtime
  # was built with, as the platform names its archive
  # (Fledge::Platform#archive_extension). Each platform is built on its
  # own computer (ADR 010), whose disk keeps what its archive needs. It
  # refuses to let an added file replace one the runtime holds, replaces
  # a previous build of the same app and platform, and removes what it
  # wrote if the build fails.
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

    # The runtime's folder of what fledge build runs or copies and no app
    # holds: the AppImage runtime in a Linux runtime, and rcedit and NSIS
    # in a Windows one.
    TOOLS = "tools"

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
    def initialize(app:, platform:, runtime:, out:, app_files: {}, files: [])
      @app = app
      @platform = platform
      @runtime = runtime
      @out = out
      @app_files = app_files
      @files = files
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
      Assembly.launch_config(@app)
    end

    # The contents of CONFIG for +app+ (#launch_config), which the
    # launcher reads, and on a phone the embedding API's
    # <tt>fledge_ruby_run_app</tt> (ADR 012). Raises Fledge::Error for a
    # program or Gemfile whose name the file cannot hold.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   Fledge::Assembly.launch_config(Fledge::App.at("examples/hello")).lines.last
    #   # => "entry = main.rb\n"
    #--
    # SPDX-SnippetEnd
    #++
    def self.launch_config(app)
      lines = ["entry = #{config_value(app.entry)}"]
      gemfile = app.gemfile
      lines << "gemfile = #{config_value(gemfile)}" if gemfile
      identifier = app.identity.identifier
      lines << "identifier = #{identifier}" if identifier
      "# Written by fledge build: what this app's program runs (ADR 005).\n#{lines.join("\n")}\n"
    end

    private_class_method def self.config_value(path) # :nodoc:
      if path.match?(/[\r\n]/) || path != path.strip
        raise Error, "#{path.inspect} can't be an app's program or Gemfile: its name begins or ends with a space, or holds a line break"
      end

      path
    end

    # The entries of the built app's +app+ folder, with paths relative to
    # the folder that holds it: the folder, +app+'s project (but each
    # absolute path in +skip+), with the contents +app_files+ gives in
    # place of a file's own, and then the files of +app_files+ the project
    # does not have.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   Fledge::Assembly.app_entries(Fledge::App.at("examples/hello"), {}, skip: []).map(&:path)
    #   # => ["app", "app/fledge.yml", "app/main.rb"]
    #--
    # SPDX-SnippetEnd
    #++
    def self.app_entries(app, app_files, skip:)
      remaining = app_files.dup
      entries = app.entries(skip:).map do |entry|
        content = remaining.delete(entry.path)
        entry = entry.with(content:) if content && entry.type == :file
        entry.with(path: "app/#{entry.path}")
      end
      [Entry.directory("app"), *entries, *remaining.map { |path, content| Entry.file("app/#{path}", content) }]
    end

    private def build
      remove_output
      FileUtils.mkdir_p(@out)
      Dir.mktmpdir(".fledge-build-", @out) do |work|
        runtime = RuntimeFolder.new(@runtime, platform: @platform, app_name: @app.name, work:)
        bundle = (@platform.os == "darwin" && @app.identity.windowed?) ? MacBundle.new(@app.identity, folder:) : nil
        contents = bundle ? bundle.resources : folder
        runtime.move_into(contents)
        File.write(File.join(contents, CONFIG), launch_config)
        copy_app(contents)
        @files.each { |entry| add(contents, entry) }
        tools = runtime.tools
        launcher = runtime.launcher(launcher_name)
        bundle ? bundle.finish(launcher) : place_launcher(launcher, tools)
        Archive.pack(folder, to: archive)
        @installers = Installers.formats(@app, @platform).map do |format|
          Installers.write(format, app: @app, folder:, tools:)
        end
      end
      archive
    rescue
      remove_output
      raise
    end

    # Places the launcher as the app's program: on Windows with the app's
    # resources in it, which the rcedit in +tools+ writes; on Linux, after
    # a windowed app's desktop entry.
    private def place_launcher(launcher, tools)
      program = File.join(folder, @platform.executable(@app.name))
      FileUtils.mv(launcher, program)
      WindowsResources.apply(program, identity: @app.identity, tools:) if @platform.windows?
      DesktopEntry.new(@app.identity).entries.each { |entry| add(folder, entry) } if @platform.os == "linux" && @app.identity.windowed?
    end

    # Writes +entry+, whose path is relative to +root+, unless it is a
    # folder already there; any other entry already there is the
    # runtime's, which nothing the build adds may replace.
    private def add(root, entry)
      target = File.join(root, entry.path)
      return if entry.type == :directory && File.directory?(target)
      raise Error, "#{entry.path} is in #{@runtime} already, so the build can't add its own" if File.exist?(target) || File.symlink?(target)
      if entry.type == :symlink && @platform.windows?
        raise Error, "#{base_name}/#{entry.path} is a symbolic link, which a .zip for Windows cannot hold. Replace it with what it points to."
      end

      entry.write_into(root)
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

    # The project's entries in +app+ under +contents+ (Assembly.app_entries).
    private def copy_app(contents)
      Assembly.app_entries(@app, @app_files, skip: [@out]).each { |entry| add(contents, entry) }
    end
  end
end
