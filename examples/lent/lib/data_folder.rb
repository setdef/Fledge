# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT-0
#++

# Where a desktop app keeps what it writes: the person's own data folder,
# as each system names it, never the app's folder, which an update
# replaces and which may be read-only.
module DataFolder
  # The folder for the app +name+ on +platform+ (a RUBY_PLATFORM), from
  # +env+ and +home+: ~/Library/Application Support/NAME on macOS,
  # %APPDATA%\NAME on Windows, and $XDG_DATA_HOME/name, or
  # ~/.local/share/name, on Linux. The XDG Base Directory Specification
  # (0.8) says an empty XDG_DATA_HOME means ~/.local/share, and a relative
  # one is invalid and is ignored.
  #
  #   DataFolder.for("Lent") # => "/home/ada/.local/share/lent"
  def self.for(name, platform: RUBY_PLATFORM, env: ENV, home: Dir.home)
    case platform
    when /darwin/ then File.join(home, "Library", "Application Support", name)
    when /mingw|mswin/ then File.join(env.fetch("APPDATA"), name)
    else
      base = env["XDG_DATA_HOME"].to_s
      base = File.join(home, ".local", "share") unless base.start_with?("/")
      File.join(base, name.downcase)
    end
  end
end
