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
  # How many times a URL is tried before the next one is.
  TRIES = 5

  # The seconds before the second try; each later wait doubles.
  FIRST_WAIT = 5

  # The longest wait, in seconds, between two tries.
  LONGEST_WAIT = 60

  # A cache in the folder +folder+. A URL that answers 408, 429, or a 5xx
  # status, or whose connection fails, is tried up to +tries+ times,
  # waiting +first_wait+ seconds, then twice that and so on up to
  # LONGEST_WAIT, by calling +sleeper+ (a hosted runner's download from
  # GitHub or Gradle fails now and then, and passes a minute later). Any
  # other failure, a 4xx or a SHA-256 mismatch, is final at once. These
  # tries replace Fledge::Download.save's own shorter ones, which a
  # developer at a terminal waits for, rather than multiply them.
  def initialize(folder, tries: TRIES, first_wait: FIRST_WAIT, sleeper: Kernel.method(:sleep))
    @folder = folder
    @tries = tries
    @first_wait = first_wait
    @sleeper = sleeper
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
      return save_with_retries(source, path, sha256)
    rescue Fledge::Error => e
      e.message
    end
    raise Fledge::Error, errors.first if errors.one?

    raise Fledge::Error, "could not download #{File.basename(url)} from any of its #{errors.size} URLs:\n  #{errors.join("\n  ")}"
  end
  private def save_with_retries(source, path, sha256)
    tries = 1
    begin
      Fledge::Download.save(source, to: path, sha256:, waits: [])
    rescue Fledge::Download::Unavailable, Fledge::Download::Unreachable => e
      raise if tries >= @tries

      wait = [@first_wait * (2 ** (tries - 1)), LONGEST_WAIT].min
      puts "#{e.message}; try #{tries + 1} of #{@tries} in #{wait} seconds"
      @sleeper.call(wait)
      tries += 1
      retry
    end
  end
end
