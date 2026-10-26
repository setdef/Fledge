# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "fileutils"
require_relative "entry"
require_relative "error"
require_relative "tar_gz"

module Fledge
  # Puts one app into one platform's runtime: a folder and its archive.
  #
  # A runtime archive holds a launcher named +launcher+ beside the Ruby
  # it embeds. A built app is that runtime with the launcher renamed to
  # the app's name and the app copied into its +app+ folder, written
  # twice: as <tt>OUT/NAME-PLATFORM/</tt>, to try, and as
  # <tt>OUT/NAME-PLATFORM.tar.gz</tt>, to ship. Unpacking the runtime and
  # packing the folder again would lose the launcher's executable bit on
  # a disk that has none.
  #
  # This class streams each runtime entry, and then each of the app's,
  # into the folder and the archive at once, so the archive keeps the
  # permissions and symlinks the runtime was built with. It replaces a
  # previous build of the same app and platform, and removes what it
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
  #   # => "/path/to/dist/hello-x86_64-linux.tar.gz"
  #--
  # SPDX-SnippetEnd
  #++
  class Assembly
    # The launcher's name inside a runtime archive, before the platform
    # adds an extension.
    LAUNCHER = "launcher"

    # Creates the assembly.
    #
    # [app] The Fledge::App to ship.
    # [platform] The Fledge::Platform the runtime is for.
    # [runtime] The path of the runtime archive.
    # [out] The folder builds go to, as an absolute path.
    def initialize(app:, platform:, runtime:, out:)
      @app = app
      @platform = platform
      @runtime = runtime
      @out = out
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
    #   assembly.base_name # => "hello-x86_64-linux"
    #--
    # SPDX-SnippetEnd
    #++
    def base_name
      "#{@app.name}-#{@platform}"
    end

    # Writes the built app's folder and archive, and returns the
    # archive's path. Raises Fledge::Error when the runtime is not a
    # Fledge runtime or the app's name collides with a file in it.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   assembly.call # => "/path/to/dist/hello-x86_64-linux.tar.gz"
    #--
    # SPDX-SnippetEnd
    #++
    def call
      if @platform.executable(@app.name).casecmp?("app")
        raise Error, "an app named #{@app.name} would collide with its own app folder. Rename the app's folder."
      end

      build
    end

    private def build
      remove_output
      FileUtils.mkdir_p(folder)
      TarGz.write(archive) do |tar|
        tar.add(Entry.directory(base_name))
        copy_runtime(tar)
        place(tar, Entry.directory("app"))
        @app.entries(skip: [@out]).each { |entry| place(tar, entry.with(path: "app/#{entry.path}")) }
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

    private def copy_runtime(tar)
      launcher = @platform.executable(LAUNCHER)
      top = nil # : String?
      found = false
      TarGz.each_entry(@runtime) do |entry|
        first, rest = entry.path.split("/", 2)
        top ||= first
        raise Error, "#{@runtime} is not a Fledge runtime: it holds both #{top}/ and #{first}" unless first == top
        next unless rest

        found ||= rest == launcher
        place(tar, entry.with(path: runtime_path(rest, launcher)))
      end
      raise Error, "#{@runtime} is not a Fledge runtime: it has no #{launcher}" unless found
    end

    private def runtime_path(path, launcher)
      executable = @platform.executable(@app.name)
      return executable if path == launcher

      first = path.split("/", 2).first.to_s
      raise Error, "#{@runtime} is not a Fledge runtime: it holds an app folder" if first == "app"
      if first.casecmp?(executable)
        raise Error, "an app named #{@app.name} would collide with the runtime's #{first}. Rename the app's folder."
      end

      path
    end

    private def place(tar, entry)
      entry.write_into(folder)
      tar.add(entry.with(path: "#{base_name}/#{entry.path}"))
    end
  end
end
