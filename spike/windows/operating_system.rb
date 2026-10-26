# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPIKE: a replacement for RubyInstaller's rubygems/defaults/operating_system.rb
# in a shipped app's runtime. RubyInstaller's hook exists for a developer's
# Ruby: it probes the gem directory's writability by writing a file into it,
# creates %ProgramData%\gemrc, searches for MSYS2 (C:\msys64, the registry,
# PATH, then `scoop prefix msys2`) and adds its ucrt64\bin as a DLL
# directory, and installs MSYS2 packages for gems. A shipped app needs none
# of it: RubyInstaller's own DLLs load through their manifests.
#
# What a shipped app does need: only its own runtime's gems. RubyGems'
# default Gem.path starts with Gem.user_dir (~/.local/share/gem/ruby/4.0.0),
# where a person's own Ruby 4.0 installs gems, so this narrows it.
module Gem
  def self.default_path
    [default_dir]
  end
end
