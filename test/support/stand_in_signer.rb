# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require "fileutils"
require "tmpdir"

# A stand-in for a developer's signing command (fledge build
# --sign-command, ADR 051), at the seam Fledge::SignCommand crosses: a
# script that records each path it is given, one per line, in SIGNED,
# and appends MARKER to the file, as a signer adds its signature to the
# end of a PE file, so that a test reads back which files were signed,
# in which order, and that what was archived is what was signed. When
# FAIL_ON is set, it refuses any path that holds it, saying so on
# standard error, and exits 3. On Windows it is a .cmd file, which
# cmd.exe runs, as makensis runs the command; elsewhere a shell script.
module StandInSigner
  # What the stand-in appends to each file it signs.
  MARKER = "FLEDGE-STAND-IN-SIGNED"

  SH = <<~SH
    #!/bin/sh
    printf '%s\\n' "$1" >> "$SIGNED"
    if [ -n "$FAIL_ON" ]; then
      case "$1" in *"$FAIL_ON"*) echo "refused $1" >&2; exit 3 ;; esac
    fi
    printf '%s' "#{MARKER}" >> "$1"
  SH

  CMD = <<~CMD.gsub("\n", "\r\n")
    @echo off
    >>"%SIGNED%" echo %~1
    if defined FAIL_ON (
      echo %~1| findstr /L /C:"%FAIL_ON%" >nul && (
        echo refused %~1 1>&2
        exit /b 3
      )
    )
    <nul set /p "=#{MARKER}">>"%~1"
    exit /b 0
  CMD

  # Writes the stand-in into a folder of its own, sets SIGNED and
  # FAIL_ON (+fail_on+) for the block, and yields the stand-in's path and
  # a reader of the paths it was given.
  def self.with(fail_on: nil)
    Dir.mktmpdir("fledge-signer") do |root|
      path = File.join(root, Gem.win_platform? ? "sign.cmd" : "sign")
      File.binwrite(path, Gem.win_platform? ? CMD : SH)
      File.chmod(0o755, path)
      signed = File.join(root, "signed.txt")
      saved = ENV.to_h.slice("SIGNED", "FAIL_ON")
      ENV.update("SIGNED" => signed, "FAIL_ON" => fail_on)
      begin
        yield path, -> { File.file?(signed) ? File.readlines(signed, chomp: true).map(&:strip) : [] }
      ensure
        %w[SIGNED FAIL_ON].each { |key| ENV[key] = saved[key] }
      end
    end
  end
end
