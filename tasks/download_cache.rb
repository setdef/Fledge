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
  # +sha256+ unless a file with that SHA-256 is already there.
  def fetch(url, sha256)
    path = File.join(@folder, File.basename(url))
    return path if File.file?(path) && Digest::SHA256.file(path).hexdigest == sha256

    puts "Downloading #{url}"
    Fledge::Download.save(url, to: path, sha256:)
  end
end
