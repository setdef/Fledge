# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "fileutils"
require_relative "../archive"
require_relative "../error"

module Fledge
  class Assembly
    # A runtime archive, unpacked for one app: its one top folder, sorted
    # into what the app holds, its launchers, and the tools only the build
    # uses. It refuses an archive that is not a Fledge
    # runtime, and one whose files the app's own would collide with.
    class RuntimeFolder # :nodoc:
      # Unpacks the runtime archive at +path+ into +work+, for
      # +platform+'s app whose programs are named +app_names+: all of it,
      # or with +only+, those of the names in its top folder that it has,
      # such as its launchers and tools.
      def initialize(path, platform:, app_names:, work:, only: [])
        @path = path
        @platform = platform
        @app_names = app_names
        unpacked = Archive.unpack(path, into: File.join(work, "runtime"), only: members(only))
        tops = Dir.children(unpacked).sort
        raise Error, "#{path} is not a Fledge runtime: it holds both #{tops[0]}/ and #{tops[1]}" if tops.size > 1

        @top = File.join(unpacked, tops.first.to_s)
      end

      # The paths in the archive of the names +only+ in its top folder that
      # it holds.
      private def members(only)
        return [] if only.empty?

        names = Archive.names(@path).map { |name| name.chomp("/") }
        top = names.first.to_s[%r{\A[^/]+}]
        only.map { |name| "#{top}/#{name}" } & names
      end

      # The path of the runtime's launcher named +name+ (before the
      # platform's extension). Raises Fledge::Error when it has none.
      def launcher(name)
        program = @platform.executable(name)
        path = File.join(@top, program)
        File.file?(path) or raise Error, "#{@path} is not a Fledge runtime: it has no #{program}"
        path
      end

      # The runtime's tools folder, or +nil+ when it has none.
      def tools
        path = File.join(@top, TOOLS)
        File.directory?(path) ? path : nil
      end

      # Moves everything the app holds of the runtime, which is all of it
      # but its launchers and tools folder, into +folder+, once
      # nothing of the app's could collide with it.
      def move_into(folder)
        FileUtils.mkdir_p(folder)
        held.each { |name| FileUtils.mv(File.join(@top, name), File.join(folder, name)) }
      end

      private def held
        launchers = [LAUNCHER, WINDOWED_LAUNCHER].map { |name| @platform.executable(name) }
        names = Dir.children(@top).sort - launchers - [TOOLS]
        names.each { |name| check(name) }
      end

      private def check(name)
        raise Error, "#{@path} is not a Fledge runtime: it holds an app folder" if name == "app"
        raise Error, "#{@path} is not a Fledge runtime: it holds a #{CONFIG}" if name == CONFIG
        taken = @app_names.find { |app_name| name.casecmp?(@platform.executable(app_name)) }
        return unless taken

        raise Error, "an app named #{taken} would collide with the runtime's #{name}. Give it another name."
      end
    end
  end
end
