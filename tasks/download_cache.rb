# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "digest"
require_relative "../lib/fledge/download"

# The folder the build tasks download their pinned inputs into, each
# checked against the SHA-256 runtime/sources.yml pins it to, and kept,
# so a second build downloads nothing it already has.
class DownloadCache
  # A cache in the folder +folder+.
  def initialize(folder)
    @folder = folder
  end

  # The path of +url+'s file in the cache, downloaded and checked against
  # +sha256+ unless a file with that SHA-256 is already there. When +url+
  # fails, each of +mirrors+ is tried in order, every one checked against
  # the same +sha256+, so a mirror can serve the pinned file and nothing
  # else; the file keeps +url+'s name whichever served it. Raises
  # Fledge::Error naming every URL and why it failed when none served it.
  def fetch(url, sha256, mirrors: [])
    path = File.join(@folder, File.basename(url))
    return path if File.file?(path) && Digest::SHA256.file(path).hexdigest == sha256

    errors = [url, *mirrors].map do |source|
      puts "Downloading #{source}"
      return Fledge::Download.save(source, to: path, sha256:)
    rescue Fledge::Error => e
      e.message
    end
    raise Fledge::Error, errors.first if errors.one?

    raise Fledge::Error, "could not download #{File.basename(url)} from any of its #{errors.size} URLs:\n  #{errors.join("\n  ")}"
  end
end
