# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

# The short 8.3 path Windows gives a folder, as TMP names a user folder
# whose name is no 8.3 name (C:/Users/RUNNER~1 for runneradmin), for the
# tests of Fledge::LongPath. cmd.exe prints it: the +s+ modifier of a
# FOR variable expands it to its short path (<tt>help for</tt>).
module ShortPath
  # The short path of the folder +path+, with forward slashes, or +nil+
  # where no short name differs from its long one: off Windows, or on a
  # volume whose 8.3 names are turned off (<tt>fsutil 8dot3name</tt>),
  # where a folder's only name is its long one.
  def self.of(path)
    return nil unless Gem.win_platform?

    native = File.absolute_path(path).tr("/", "\\")
    short = IO.popen(%(cmd /c for %I in ("#{native}") do @echo %~sI), &:read).strip.tr("\\", "/")
    short unless short.empty? || short.casecmp?(native.tr("\\", "/"))
  end
end
