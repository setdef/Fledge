# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "../lib/fledge/entry"
require_relative "../lib/fledge/tar_gz"

# How the build tasks pack what a release publishes, a runtime, its
# build-only companion, or a makensis: a .tar.gz that unpacks into one
# top folder, every entry dated SOURCE_DATE_EPOCH when it is set, so a
# rebuild from the same inputs writes the same archive.
module ReleaseArchive
  # Packs +folder+ as the archive at +path+, under the top folder +top+,
  # says how large it is, and returns +path+.
  def self.pack(folder, path, top:)
    Fledge::TarGz.write(path, mtime: Integer(ENV.fetch("SOURCE_DATE_EPOCH", Time.now.to_i.to_s))) do |tar|
      tar.add(Fledge::Entry.directory(top))
      Fledge::Entry.walk(folder).each { |entry| tar.add(entry.with(path: "#{top}/#{entry.path}")) }
    end
    puts "Built #{path} (#{(File.size(path) / 1_000_000.0).round(1)} MB)"
    path
  end
end
