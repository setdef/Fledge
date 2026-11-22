# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

# Writes a release commit's changes, for a release made with nobody in
# it (doc/contributors/design/releases.md, "How a release is made"):
# the next version, chosen from what CHANGELOG.md has under
# [Unreleased] by releases.md's rule, written wherever a release names
# it, and the CHANGELOG's unreleased entries moved under the release.
# doc/licensing.md, which names the version too, is regenerated after it
# by rake licensing.
#
# The same change, given what was released, records the release on a
# trunk that has moved on since the commit it was made from: the
# entries that were released move under it, and those that landed
# after stay unreleased.
#
#   ruby tasks/release_commit.rb next
#   ruby tasks/release_commit.rb write VERSION [--date DATE] [--released FILE]
#
# +next+ prints the next version. +write+ writes VERSION, dated DATE
# (today, in UTC, by default); with --released, FILE holds a CHANGELOG
# as it stood at the commit the release was made from, and only its
# unreleased entries move.
class ReleaseCommit
  # A release that cannot be written as asked.
  class Error < StandardError; end

  # The files that name the version, as the release commits of every
  # release so far changed them, besides CHANGELOG.md and
  # doc/licensing.md.
  FILES = %w[lib/fledge/version.rb Gemfile.lock README.md README.rdoc lib/fledge/config.rb lib/fledge/config.schema.json].freeze

  # The CHANGELOG's unreleased section, between its heading and the
  # next, of +text+.
  def self.unreleased(text)
    start = text.index("## [Unreleased]\n") or raise Error, "CHANGELOG.md has no [Unreleased] section"
    body = text[(start + "## [Unreleased]\n".length)..]
    body[0, body.index(/^## \[/) || body.index(/^\[Unreleased\]:/) || body.length]
  end

  def initialize(root:)
    @root = root
  end

  # The version Fledge::VERSION holds.
  def current
    read("lib/fledge/version.rb")[/VERSION = "([^"]+)"/, 1] or raise Error, "lib/fledge/version.rb names no VERSION"
  end

  # The next version, by releases.md's rule, "Versions": before 1.0, a
  # change that can break a build (an entry that starts "Breaking", or a
  # removal) moves the middle number, and anything else the last; from
  # 1.0, a break moves the first, an addition or a deprecation the
  # middle, and anything else the last. A release candidate, and 1.0.0
  # itself, are a person's to name.
  def next_version
    body = ReleaseCommit.unreleased(changelog)
    raise Error, "CHANGELOG.md has nothing under [Unreleased]: there is nothing to release" unless body.match?(/^- /)

    major, minor, patch = numbers
    breaking = body.match?(/^- (\*\*)?Breaking:/) || body.match?(/^### Removed$/)
    if major.zero?
      breaking ? "0.#{minor + 1}.0" : "0.#{minor}.#{patch + 1}"
    elsif breaking
      "#{major + 1}.0.0"
    else
      body.match?(/^### (Added|Deprecated)$/) ? "#{major}.#{minor + 1}.0" : "#{major}.#{minor}.#{patch + 1}"
    end
  end

  # Writes +version+ in place of the current one in every file of FILES,
  # and moves the CHANGELOG's +released+ entries, by default all that
  # are unreleased, under a section for +version+ dated +date+.
  def write(version, date:, released: nil)
    old = current
    pattern = /(?<![\d.])#{Regexp.escape(old)}(?![\d.])/
    FILES.each do |file|
      text = read(file)
      raise Error, "#{file} names no #{old}: the release would leave it behind" unless text.match?(pattern)

      File.write(path(file), text.gsub(pattern, version))
    end
    File.write(path("CHANGELOG.md"), dated(changelog, old, version, date, released || ReleaseCommit.unreleased(changelog)))
  end

  # +text+ with +released+'s entries under a section for +version+, and
  # what else was unreleased left there, and the comparison links moved.
  private def dated(text, old, version, date, released)
    body = ReleaseCommit.unreleased(text)
    gone = released.lines.grep(/^- /)
    left = sections(body).filter_map do |heading, entries|
      entries -= gone
      "#{heading}\n#{entries.join}\n" unless entries.empty?
    end
    text = text.sub("## [Unreleased]\n#{body}", "## [Unreleased]\n\n#{left.join}## [#{version}] - #{date}\n#{released.rstrip}\n\n")
    link = "[Unreleased]: https://github.com/setdef/Fledge/compare/v#{old}...HEAD\n"
    raise Error, "CHANGELOG.md has no link #{link.strip}" unless text.include?(link)

    text.sub(link, "[Unreleased]: https://github.com/setdef/Fledge/compare/v#{version}...HEAD\n" \
      "[#{version}]: https://github.com/setdef/Fledge/compare/v#{old}...v#{version}\n")
  end

  # Each "### Heading" of an unreleased +body+, with its entries.
  private def sections(body)
    body.split(/^(?=### )/).filter_map do |part|
      heading = part[/\A### .*/] or next
      ["#{heading}\n", part.lines.grep(/^- /)]
    end
  end

  private def numbers
    parts = current.split(".")
    raise Error, "#{current} is not MAJOR.MINOR.PATCH" unless parts.size == 3 && parts.all?(/\A\d+\z/)

    parts.map(&:to_i)
  end

  private def changelog = read("CHANGELOG.md")
  private def read(file) = File.read(path(file))
  private def path(file) = File.join(@root, file)
end

if $PROGRAM_NAME == __FILE__
  release = ReleaseCommit.new(root: Dir.pwd)
  begin
    case ARGV.shift
    when "next" then puts release.next_version
    when "write"
      version = ARGV.shift or abort "usage: ruby tasks/release_commit.rb write VERSION [--date DATE] [--released FILE]"
      date = ARGV.include?("--date") ? ARGV[ARGV.index("--date") + 1] : Time.now.utc.strftime("%Y-%m-%d")
      released = ReleaseCommit.unreleased(File.read(ARGV[ARGV.index("--released") + 1])) if ARGV.include?("--released")
      release.write(version, date:, released:)
    else abort "usage: ruby tasks/release_commit.rb next | write VERSION [--date DATE] [--released FILE]"
    end
  rescue ReleaseCommit::Error => e
    abort "#{'::error::' if ENV['GITHUB_ACTIONS']}#{e.message}"
  end
end
