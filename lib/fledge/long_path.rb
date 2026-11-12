# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

module Fledge
  # A path with every folder in it named by its long name, where Windows
  # gives a file a short 8.3 name too (+RUNNER~1+ for +runneradmin+).
  #
  # Windows writes +TMP+ and +TEMP+ with the short name of a user folder
  # whose name is no 8.3 name, and Dir.tmpdir takes them as they are:
  # its File.expand_path gives the long name of the last folder only
  # (+replace_to_long_name+, "Replace the last part of the path to long
  # name", in Ruby's <tt>win32/file.c</tt>, lines 145 to 150 and 563 to
  # 567). A short name breaks a tool that escapes a path for a shell, as
  # mini_portile2 does for cmd.exe, where Shellwords' <tt>\~</tt> names
  # no file, and differs from the path Dir.glob prints, which names each
  # folder it walks by its long name (+replace_real_basename+ in
  # <tt>dir.c</tt>, lines 2473 to 2492 and 3236 to 3241).
  #
  # Ruby has no call for Windows' +GetLongPathNameW+, so the path is
  # rebuilt one folder at a time from its root with File.absolute_path,
  # which names the last part of what it returns by its long name, as
  # File.expand_path does (<tt>file.c</tt>, lines 5415 to 5419), and
  # reads no <tt>~</tt> as a home folder. Elsewhere it changes nothing.
  #
  # === Example
  #
  #--
  # SPDX-SnippetBegin
  # SPDX-SnippetCopyrightText: 2026 setdef <kerrick@setdef.com>
  # SPDX-License-Identifier: MIT-0
  #++
  #   Fledge::LongPath.of("C:/Users/RUNNER~1/AppData/Local/Temp") # => "C:/Users/runneradmin/AppData/Local/Temp"
  #--
  # SPDX-SnippetEnd
  #++
  module LongPath
    # The absolute path +path+, with each folder that exists named by its
    # long name.
    def self.of(path)
      path = File.absolute_path(path)
      parent = File.dirname(path)
      return path if parent == path

      File.absolute_path(File.basename(path), of(parent))
    end
  end
end
