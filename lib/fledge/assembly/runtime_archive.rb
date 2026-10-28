# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "../entry"
require_relative "../error"
require_relative "../tar_gz"

module Fledge
  class Assembly
    # A runtime archive, read for one app: every entry under its one top
    # folder, with that folder taken off, sorted into what the app holds,
    # its launchers, and the installer files only installers use. It
    # refuses an archive that is not a Fledge runtime, and one whose
    # files the app's own would collide with.
    class RuntimeArchive # :nodoc:
      # The runtime archive at +path+, for +platform+'s app named
      # +app_name+.
      def initialize(path, platform:, app_name:)
        @path = path
        @platform = platform
        @app_name = app_name
      end

      # Yields each entry the app holds, puts each installer file in +kit+
      # by its path inside the installer folder, and returns the launcher
      # named +launcher_name+.
      def copy(launcher_name, kit)
        launcher = @platform.executable(launcher_name)
        launchers = [launcher, @platform.executable(LAUNCHER), @platform.executable(WINDOWED_LAUNCHER)]
        found = nil # : Entry?
        each_entry do |entry, path|
          found = entry if path == launcher
          next if launchers.include?(path)
          next kit[path.delete_prefix("#{INSTALLER}/")] = entry if path.start_with?("#{INSTALLER}/") && entry.type == :file
          next if path == INSTALLER || path.start_with?("#{INSTALLER}/")

          yield entry.with(path: app_path(path))
        end
        found or raise Error, "#{@path} is not a Fledge runtime: it has no #{launcher}"
      end

      # Yields each entry below the archive's top folder, and its path
      # there.
      private def each_entry
        top = nil # : String?
        TarGz.each_entry(@path) do |entry|
          first, rest = entry.path.split("/", 2)
          top ||= first
          raise Error, "#{@path} is not a Fledge runtime: it holds both #{top}/ and #{first}" unless first == top

          yield entry, rest if rest
        end
      end

      # +path+, which the runtime holds, as the app holds it, once nothing
      # of the app's could collide with it.
      private def app_path(path)
        executable = @platform.executable(@app_name)
        first = path.split("/", 2).first.to_s
        raise Error, "#{@path} is not a Fledge runtime: it holds an app folder" if first == "app"
        raise Error, "#{@path} is not a Fledge runtime: it holds a #{CONFIG}" if first == CONFIG
        if first.casecmp?(executable)
          raise Error, "an app named #{@app_name} would collide with the runtime's #{first}. Give it another name."
        end

        path
      end
    end
  end
end
