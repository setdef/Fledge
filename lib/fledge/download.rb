# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "digest"
require "fileutils"
require "net/http"
require "openssl"
require "uri"
require_relative "error"

module Fledge
  # Downloads a file and proves it is the file you expected.
  #
  # Everything a built app carries came from somewhere else: Ruby from
  # rv-ruby, runtimes from Fledge's releases. A download that changed on
  # the way, or a release replaced after the fact, would ship to everyone
  # who builds with it. A size or a status code cannot tell.
  #
  # This module streams a download to a temporary file beside its
  # destination, checks its SHA-256 against the one you pinned, and only
  # then moves it into place. A mismatch deletes the file and raises, so
  # a bad download never sits in a cache waiting to be trusted. It
  # follows redirects, as GitHub's release downloads need, but never
  # from HTTPS to plain HTTP.
  #
  # Use it to fetch anything Fledge pins by SHA-256.
  #
  # === Examples
  #
  #--
  # SPDX-SnippetBegin
  # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
  # SPDX-License-Identifier: MIT-0
  #++
  #   Fledge::Download.save(
  #     "https://github.com/spinel-coop/rv-ruby/releases/download/20261023/ruby-4.0.9.arm64_sonoma.tar.gz",
  #     to: "tmp/ruby.tar.gz",
  #     sha256: "38130a97c314e2e44198f37fc6555a66ab9a8011ecc5980d4ae36f2858ed11b5"
  #   )
  #
  #   Fledge::Download.read("https://example.com/SHA256SUMS") # => "abc123...  file\n"
  #--
  # SPDX-SnippetEnd
  #++
  module Download
    # How many redirects a download follows before giving up.
    REDIRECTS = 5

    # The body at +url+, as a String. Raises Fledge::Error when the
    # server does not answer with success.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   Fledge::Download.read("https://github.com/setdef/Fledge/releases/download/v0.1.0/SHA256SUMS")
    #--
    # SPDX-SnippetEnd
    #++
    def self.read(url)
      body = +""
      get(url) { |response| response.read_body { |chunk| body << chunk } }
      body
    end

    # Saves the file at +url+ to the path +to+, creating its folder, and
    # returns +to+. Raises Fledge::Error, and leaves nothing at +to+,
    # when the download fails or its SHA-256 is not +sha256+.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   Fledge::Download.save(url, to: "tmp/file.tar.gz", sha256: pinned)
    #--
    # SPDX-SnippetEnd
    #++
    def self.save(url, to:, sha256:)
      FileUtils.mkdir_p(File.dirname(to))
      partial = "#{to}.part"
      digest = Digest::SHA256.new
      File.open(partial, "wb") do |file|
        get(url) do |response|
          response.read_body do |chunk|
            digest << chunk
            file.write(chunk)
          end
        end
      end
      verify(url, digest.hexdigest, sha256)
      File.rename(partial, to)
      to
    ensure
      FileUtils.rm_f(partial) if partial
    end

    private_class_method def self.verify(url, actual, expected) # :nodoc:
      return if actual == expected.downcase

      raise Error, "#{url} has SHA-256 #{actual}, but #{expected} was expected. " \
        "The file changed since it was pinned, or the download was damaged; nothing was saved."
    end

    private_class_method def self.get(url, redirects = REDIRECTS, &block) # :nodoc:
      uri = URI(url)
      raise Error, "#{url} is not an http or https URL" unless uri.is_a?(URI::HTTP) && uri.host

      Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https") do |http|
        http.request_get(uri.request_uri) do |response|
          case response
          when Net::HTTPSuccess then block.call(response)
          when Net::HTTPRedirection then follow(uri, response["location"].to_s, redirects, &block)
          else raise Error, "could not download #{url}: #{response.code} #{response.message}"
          end
        end
      end
    rescue SystemCallError, IOError, SocketError, Timeout::Error, OpenSSL::SSL::SSLError => e
      raise Error, "could not download #{url}: #{e.message}"
    end

    private_class_method def self.follow(from, location, redirects, &) # :nodoc:
      raise Error, "#{from} redirected more than #{REDIRECTS} times" if redirects.zero?

      to = from.merge(location)
      raise Error, "#{from} redirected from HTTPS to plain HTTP (#{to}); refusing" if from.scheme == "https" && to.scheme != "https"

      get(to.to_s, redirects - 1, &)
    end
  end
end
