# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

# Starts a program as Explorer starts one a person double-clicks: with
# ShellExecuteExW, from the program's own folder, then waits for it and
# exits with its status. The windowed parity check
# (tasks/parity/windowed.rb) runs it on Windows as
#
#   ruby shell_execute.rb PROGRAM [ARGUMENT...]
#
# in the environment the program is to have, since ShellExecuteExW
# starts a program with its caller's environment. A GUI program it
# starts has no console and no standard handles.
#
# It passes SEE_MASK_NOCLOSEPROCESS to wait on the process,
# SEE_MASK_NOASYNC since it exits as soon as the program does, and
# SEE_MASK_FLAG_NO_UI so that a failure is a status rather than a dialog
# no one answers (Microsoft Learn, SHELLEXECUTEINFOW).

require "fiddle/import"

# ShellExecuteExW and what waiting on its process takes.
module ShellExecute
  extend Fiddle::Importer

  dlload "shell32.dll", "kernel32.dll"

  Info = struct([
    "unsigned long cbSize",
    "unsigned long fMask",
    "void *hwnd",
    "void *lpVerb",
    "void *lpFile",
    "void *lpParameters",
    "void *lpDirectory",
    "int nShow",
    "void *hInstApp",
    "void *lpIDList",
    "void *lpClass",
    "void *hkeyClass",
    "unsigned long dwHotKey",
    "void *hIcon",
    "void *hProcess",
  ])

  extern "int ShellExecuteExW(void *)"
  extern "unsigned long WaitForSingleObject(void *, unsigned long)"
  extern "int GetExitCodeProcess(void *, void *)"
  extern "int CloseHandle(void *)"

  SEE_MASK_NOCLOSEPROCESS = 0x40
  SEE_MASK_NOASYNC = 0x100
  SEE_MASK_FLAG_NO_UI = 0x400
  SW_SHOWNORMAL = 1
  INFINITE = 0xFFFFFFFF

  # +string+ as a NUL-terminated UTF-16LE string Windows reads.
  def self.wide(string) = Fiddle::Pointer["#{string}\0".encode("UTF-16LE")]

  # A command line's argument as CommandLineToArgvW reads it back
  # (Microsoft Learn, "Parsing C command-line arguments"): in quotes,
  # with each quote escaped and the backslashes before it doubled.
  def self.quote(argument) = %("#{argument.gsub(/(\\*)"/) { "#{$1}#{$1}\\\"" }.sub(/(\\+)\z/) { $1 * 2 }}")

  # Starts +program+ with +arguments+ from its folder, waits for it, and
  # returns its exit status.
  def self.start(program, arguments)
    windows = -> (path) { path.tr("/", "\\") }
    parameters = arguments.map { |argument| quote(windows.(argument)) }.join(" ")
    strings = [windows.(program), parameters, windows.(File.dirname(program))].map { |string| wide(string) }
    info = Info.malloc
    info.to_ptr[0, Info.size] = "\0" * Info.size
    info.cbSize = Info.size
    info.fMask = SEE_MASK_NOCLOSEPROCESS | SEE_MASK_NOASYNC | SEE_MASK_FLAG_NO_UI
    info.lpFile, info.lpParameters, info.lpDirectory = strings
    info.nShow = SW_SHOWNORMAL
    raise "ShellExecuteExW could not start #{program}: #{Fiddle.win32_last_error}" if ShellExecuteExW(info).zero?

    WaitForSingleObject(info.hProcess, INFINITE)
    status = [0].pack("L")
    GetExitCodeProcess(info.hProcess, status)
    CloseHandle(info.hProcess)
    status.unpack1("L")
  end
end

exit ShellExecute.start(ARGV.fetch(0), ARGV.drop(1)) if $PROGRAM_NAME == __FILE__
