# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "fileutils"

module Fledge
  class Assembly
    # The tools an app carries, when its <tt>fledge.yml</tt> sets
    # +build_tools+, so that it can run <tt>fledge build --from</tt> on
    # itself where no runtime is at hand (ADR 032, section 4).
    #
    # <tt>fledge build --from</tt> runs nothing a system lacks on macOS,
    # whose plutil, codesign, ditto, and hdiutil are in /usr/bin, and whose
    # app's program is the runtime's launcher. On Windows it needs a fresh
    # launcher of each kind, since a program keeps its app's resources,
    # and rcedit and NSIS; on Linux, AppImage's runtime, for an AppImage.
    # Those are the runtime's launchers and tools folder, which no app
    # holds otherwise. This class copies them, as the runtime has them,
    # into the app's own TOOLS folder, but llvm-readobj, which reads the
    # DLLs compiled gems import, and <tt>--from</tt> compiles none.
    # Fledge::BuiltApp finds them there.
    class BuildTools # :nodoc:
      # What the app leaves out of the runtime's tools folder.
      LEFT_OUT = %w[llvm-readobj.exe].freeze

      # The tools of +runtime+ (an Assembly::RuntimeFolder, or what
      # Fledge::BuiltApp gives in its place) for an app on +platform+.
      def initialize(runtime, platform:)
        @runtime = runtime
        @platform = platform
      end

      # Copies the tools into <tt>FOLDER/tools</tt>, when the platform
      # needs any.
      def copy_into(folder)
        sources = files
        return if sources.empty?

        target = File.join(folder, TOOLS)
        FileUtils.mkdir_p(target)
        sources.each { |source| FileUtils.cp_r(source, target, preserve: true) }
      end

      # The files and folders to copy: on Windows the launchers, and the
      # tools folder's contents but LEFT_OUT.
      private def files
        tools = @runtime.tools
        held = tools ? (Dir.children(tools).sort - LEFT_OUT).map { |name| File.join(tools, name) } : [] # : Array[String]
        return held unless @platform.windows?

        [LAUNCHER, WINDOWED_LAUNCHER].map { |name| @runtime.launcher(name) } + held
      end
    end
  end
end
