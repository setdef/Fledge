# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "../lib/fledge/archive"

# How the build tasks pack what a release publishes, a runtime or its
# build-only companion: a .tar.gz, written by the computer's own tar,
# that unpacks into one top folder.
module ReleaseArchive
  # Packs +folder+, whose name must be +top+, as the archive at +path+,
  # says how large it is, and returns +path+.
  def self.pack(folder, path, top:)
    raise ArgumentError, "#{folder} is not named #{top}" unless File.basename(folder) == top

    Fledge::Archive.pack(folder, to: path)
    puts "Built #{path} (#{(File.size(path) / 1_000_000.0).round(1)} MB)"
    path
  end
end
