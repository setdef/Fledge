# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require "json"
require "rubygems/package"
require "yaml"
require "zlib"
require_relative "download_cache"
require_relative "../lib/fledge/download"

# A day's snapshot of Ruby's master, as cache.ruby-lang.org publishes it.
#
# Fledge's releases pin one Ruby, and nothing a runtime builds would
# meet a change in Ruby's master until the day the next Ruby is
# released. Ruby's release tooling (tool/make-snapshot) publishes a
# tarball of master every day, in the shape of a release's, beside an
# index that gives its SHA-256.
#
# This moves the pins of the Rubies Fledge builds from source, the musl
# and phone runtimes', to that tarball, and the license audit's evidence
# of Ruby's revision with them, in a checkout that is never committed.
# The SHA-256 is the index's, so the build still checks the download.
#
# Use it in the nightly workflow, or in a scratch clone, before
# <tt>rake runtime</tt>:
#
#   ruby tasks/ruby_snapshot.rb   # rewrites runtime/sources.yml and runtime/licenses.yml
class RubySnapshot < Data.define(:date, :url, :sha256)
  # The index or the tarball is not what this expects.
  class Error < StandardError; end

  # Where the index and the tarballs are.
  BASE = "https://cache.ruby-lang.org/pub/ruby/snapshot/"

  # The index of master's snapshot.
  INDEX = "#{BASE}snapshot-master.json".freeze

  # The keys of runtime/sources.yml whose Ruby Fledge builds from its
  # tarball: the phones', musl's, and the Rubies Fledge publishes for
  # glibc Linux and macOS (ruby-build).
  FROM_SOURCE = %w[mobile musl-ruby ruby-build].freeze

  # The snapshot the index +json+ describes: its date, and its gzip
  # tarball's URL and SHA-256.
  def self.parse(json)
    entry = JSON.parse(json).first or raise Error, "the snapshot index lists no snapshot"
    name = entry.dig("filename", "gz") or raise Error, "the snapshot index names no gzip tarball"
    sha256 = entry.dig("sha256", "gz") or raise Error, "the snapshot index gives no SHA-256 for #{name}"
    new(date: entry.fetch("date"), url: "#{BASE}#{name}", sha256:)
  end

  # Ruby's short revision, as its revision.h at the top of the tarball
  # +path+ defines RUBY_REVISION.
  def self.revision(path)
    Zlib::GzipReader.open(path) do |gz|
      Gem::Package::TarReader.new(gz).each do |entry|
        next unless entry.full_name.match?(%r{\A[^/]+/revision\.h\z})

        return entry.read[/^#define RUBY_REVISION "(\h+)"/, 1] || raise(Error, "#{entry.full_name} defines no RUBY_REVISION")
      end
    end
    raise Error, "#{path} has no revision.h"
  end

  # The text of runtime/licenses.yml +text+ with the evidence of Ruby's
  # revision in the from-source Rubies' component made +revision+.
  def self.evidence(text, revision)
    component = YAML.safe_load(text).fetch("components").find do |entry|
      entry.fetch("id") == "ruby" && entry.fetch("platforms").include?("android")
    end or raise Error, "runtime/licenses.yml has no ruby component for the phones"
    old = component.fetch("embedded").first.fetch("evidence")
    line = %(evidence: "#{old}")
    raise Error, "runtime/licenses.yml has #{line} #{text.scan(line).size} times" unless text.scan(line).one?

    text.sub(line, %(evidence: "#{revision}"))
  end

  # The text of runtime/sources.yml +text+ with each from-source Ruby's
  # url and sha256 this snapshot's, and every other line as it was.
  def pin(text)
    pins = YAML.safe_load(text)
    rubies = FROM_SOURCE.map { |key| pins.fetch(key).fetch("ruby") }
    lines = rubies.flat_map { |ruby| [["url: #{ruby.fetch('url')}", "url: #{url}"], ["sha256: #{ruby.fetch('sha256')}", "sha256: #{sha256}"]] }
    lines.uniq.reduce(text) { |result, (old, new)| replace(result, old, new) }
  end

  private def replace(text, old, new)
    raise Error, "runtime/sources.yml has no #{old}" unless text.include?(old)

    text.gsub(old, new)
  end
end

if $PROGRAM_NAME == __FILE__
  root = File.expand_path("..", __dir__)
  snapshot = RubySnapshot.parse(Fledge::Download.read(RubySnapshot::INDEX))
  revision = RubySnapshot.revision(DownloadCache.new.fetch(snapshot.url, snapshot.sha256))
  sources = File.join(root, "runtime", "sources.yml")
  licenses = File.join(root, "runtime", "licenses.yml")
  File.write(sources, snapshot.pin(File.read(sources)))
  File.write(licenses, RubySnapshot.evidence(File.read(licenses), revision))
  puts "Ruby's master of #{snapshot.date}, #{revision}: #{snapshot.url}, SHA-256 #{snapshot.sha256}"
  if (output = ENV.fetch("GITHUB_OUTPUT", nil))
    File.write(output, "date=#{snapshot.date}\nrevision=#{revision}\nsha256=#{snapshot.sha256}\n", mode: "a")
  end
end
