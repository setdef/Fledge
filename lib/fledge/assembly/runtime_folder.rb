# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "fileutils"
require_relative "../archive"
require_relative "../error"

module Fledge
  class Assembly
    # A runtime archive, unpacked for one app: its one top folder, sorted
    # into what the app holds, its launchers, and the installer files
    # only installers use. It refuses an archive that is not a Fledge
    # runtime, and one whose files the app's own would collide with.
    class RuntimeFolder # :nodoc:
      # Unpacks the runtime archive at +path+ into +work+, for
      # +platform+'s app named +app_name+.
      def initialize(path, platform:, app_name:, work:)
        @path = path
        @platform = platform
        @app_name = app_name
        unpacked = Archive.unpack(path, into: File.join(work, "runtime"))
        tops = Dir.children(unpacked).sort
        raise Error, "#{path} is not a Fledge runtime: it holds both #{tops[0]}/ and #{tops[1]}" if tops.size > 1

        @top = File.join(unpacked, tops.first.to_s)
      end

      # The path of the runtime's launcher named +name+ (before the
      # platform's extension). Raises Fledge::Error when it has none.
      def launcher(name)
        program = @platform.executable(name)
        path = File.join(@top, program)
        File.file?(path) or raise Error, "#{@path} is not a Fledge runtime: it has no #{program}"
        path
      end

      # The runtime's installer folder, or +nil+ when it has none.
      def kit
        path = File.join(@top, INSTALLER)
        File.directory?(path) ? path : nil
      end

      # Moves everything the app holds of the runtime, which is all of it
      # but its launchers and installer folder, into +folder+, once
      # nothing of the app's could collide with it.
      def move_into(folder)
        FileUtils.mkdir_p(folder)
        held.each { |name| FileUtils.mv(File.join(@top, name), File.join(folder, name)) }
      end

      private def held
        launchers = [LAUNCHER, WINDOWED_LAUNCHER].map { |name| @platform.executable(name) }
        names = Dir.children(@top).sort - launchers - [INSTALLER]
        names.each { |name| check(name) }
      end

      private def check(name)
        raise Error, "#{@path} is not a Fledge runtime: it holds an app folder" if name == "app"
        raise Error, "#{@path} is not a Fledge runtime: it holds a #{CONFIG}" if name == CONFIG
        return unless name.casecmp?(@platform.executable(@app_name))

        raise Error, "an app named #{@app_name} would collide with the runtime's #{name}. Give it another name."
      end
    end
  end
end
