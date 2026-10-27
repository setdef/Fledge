# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "fileutils"
require_relative "entry"
require_relative "error"
require_relative "platform"
require_relative "tar_gz"

module Fledge
  # Puts one app into one platform's runtime: a folder and its archive.
  #
  # A runtime archive holds a launcher named +launcher+ (+launcher.exe+
  # on Windows) beside the Ruby it embeds. A built app is that runtime
  # with the launcher renamed to the app's name, the app's project copied
  # into its +app+ folder, and a CONFIG beside the launcher that tells it
  # which program in +app+ to run and, for a project with a Gemfile,
  # which Gemfile to set up (ADR 005). It is written twice: as
  # <tt>OUT/NAME-PLATFORM/</tt>, to try, and as
  # <tt>OUT/NAME-PLATFORM.tar.gz</tt> (<tt>.zip</tt> for Windows), to
  # ship. Unpacking the runtime and packing the folder again would lose
  # the launcher's executable bit on a disk that has none.
  #
  # This class streams each runtime entry, then CONFIG, each of the app's
  # entries, and the files the build adds (the app's gems and their
  # notices), into the folder and the archive at once, so the archive
  # keeps the permissions and symlinks the runtime was built with. The
  # platform names the archive's format (Fledge::Platform#archive_format).
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
      @placed = {} # : Hash[String, bool]
    end

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
    # Gemfile when it has one, relative to the +app+ folder.
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
      @platform.archive_format.write(archive) do |writer|
        writer.add(Entry.directory(base_name))
        copy_runtime(writer)
        add(writer, Entry.file(CONFIG, launch_config))
        copy_app(writer)
        @files.each { |entry| add(writer, entry) }
      end
    rescue
      remove_output
      raise
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
    end

    private def copy_runtime(writer)
      launcher = @platform.executable(LAUNCHER)
      top = nil # : String?
      found = false
      TarGz.each_entry(@runtime) do |entry|
        first, rest = entry.path.split("/", 2)
        top ||= first
        raise Error, "#{@runtime} is not a Fledge runtime: it holds both #{top}/ and #{first}" unless first == top
        next unless rest

        found ||= rest == launcher
        place(writer, entry.with(path: runtime_path(rest, launcher)))
      end
      raise Error, "#{@runtime} is not a Fledge runtime: it has no #{launcher}" unless found
    end

    private def runtime_path(path, launcher)
      executable = @platform.executable(@app.name)
      return executable if path == launcher

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

    # Places an entry the build adds, after any folder above it that is
    # not there yet. A folder already there stays; any other entry already
    # there is the runtime's, which nothing the build adds may replace.
    private def add(writer, entry)
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
    end
  end
end
