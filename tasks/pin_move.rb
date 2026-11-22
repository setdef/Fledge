# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require "fileutils"
require_relative "pin_watch"

# Moves the pins the watch found behind to upstream's newer release
# (doc/contributors/design/runtimes.md, "Keeping the pins current").
#
# A pin is a version, the URL of each file, and each file's SHA-256, and
# its version is named again in a few files beside runtime/sources.yml:
# runtime/licenses.yml's entries for what the pin builds, a file a tool
# reads (mise.toml, the Gradle wrapper's properties), and CHANGELOG.md.
# A move rewrites all of them as text, so every comment stays, and takes
# each new SHA-256 from upstream's own record of it: GitHub's digest of a
# release asset, or the .sha256 file beside a download. Only where the
# upstream records none does it download the file and compute it.
#
# An upstream runtime/upstreams.yml marks with hold is never moved: its
# reason says what a person has to do instead.
#
#   move = PinMove.load(".", PinWatch::Fetch.new)
#   move.call(finding)   # => {"runtime/sources.yml" => "...", ...}
class PinMove
  # Something about a pin, or about what its upstream answers, that a
  # move cannot take as it is.
  class Error < StandardError; end

  # The keys of a mapping whose URL moves that the move knows how to
  # write: anything else in it, such as the SHA-256 of a file inside the
  # download, it would leave false.
  MOVED = %w[url sha256].freeze

  attr_reader :texts

  # The move of the checkout at +root+, asking +fetch+ for upstreams'
  # records.
  def self.load(root, fetch)
    entries = YAML.safe_load_file(File.join(root, "runtime/upstreams.yml")).fetch("watched")
    new(root, entries, fetch)
  end

  def initialize(root, entries, fetch)
    @root = root
    @entries = entries
    @fetch = fetch
    @texts = {}
  end

  # Why the upstream named +name+ is moved by a person, or nil.
  def hold(name)
    @entries.fetch(name)["hold"]
  end

  # The names of the upstreams a move may change.
  def movable
    @entries.keys.reject { |name| hold(name) }
  end

  # Moves the pins of +finding+, a PinWatch::Finding or its report's
  # hash, from its current version to its newer one, in the texts this
  # move holds, and returns the files it changed.
  def call(finding)
    finding = finding.to_h
    name = finding.fetch("name")
    raise Error, "#{name} is held: #{hold(name)}" if hold(name)

    entry = @entries.fetch(name)
    upstream = PinWatch::Upstream.from(name, entry)
    from = finding.fetch("current")
    to = finding.fetch("newer")
    before = @texts.dup
    changed = {}
    swaps = move_sources(upstream, entry, from, to, changed)
    entry.fetch("licenses", []).each { |id| write("runtime/licenses.yml", license(read("runtime/licenses.yml"), id, from, to), changed) }
    entry.fetch("also", {}).each { |path, patterns| write(path, also(read(path), path, patterns, swaps, from, to), changed) }
    write("CHANGELOG.md", changelog(read("CHANGELOG.md"), title(name), from, to), changed) if entry.fetch("ships", true)
    changed
  rescue Error, PinWatch::Error
    @texts = before if before
    raise
  end

  # The text of +path+ as this move has it.
  def read(path)
    @texts[path] ||= File.read(File.join(@root, path))
  end

  # The words CHANGELOG.md and messages name the upstream +name+ by.
  def title(name)
    Array(@entries.fetch(name)["names"]).first || name
  end

  # The commit message of the moves of +findings+, as the workflow that
  # proves them commits it: a subject in Conventional Commits' form, a
  # body that says what moved and why, wrapped at 72, and the trailer
  # every commit of Fledge's carries (AGENTS.md, "Committing").
  def message(findings)
    moves = findings.map(&:to_h).map { |finding| "#{title(finding.fetch('name'))} #{finding.fetch('current')} to #{finding.fetch('newer')}" }
    subject = if findings.one?
      finding = findings.first.to_h
      "chore: move #{title(finding.fetch('name'))} to #{finding.fetch('newer')}"
    else
      "chore: move #{findings.size} pins to their upstreams' newest releases"
    end
    list = (moves.size > 1) ? "#{moves[0..-2].join(', ')}, and #{moves.last}" : moves.first
    body = "The pin watch found #{findings.one? ? 'this pin' : 'these pins'} behind upstream, and the " \
      "workflow that keeps the pins current moved #{findings.one? ? 'it' : 'them'} with tasks/pin_move.rb, " \
      "taking each SHA-256 from upstream's own record of it, and proved the move with a full run of CI " \
      "before it reached trunk (doc/contributors/design/runtimes.md, \"Keeping the pins current\"): #{list}."
    "#{subject}\n\n#{body.gsub(/(.{1,72})(?:\s+|\z)/, "\\1\n")}\nProvenance: requested\n"
  end

  # Writes every text this move changed into the checkout, or into the
  # folder +root+ instead, at the same paths, so it can be compared.
  def save(root = @root)
    @texts.each do |path, text|
      FileUtils.mkdir_p(File.dirname(File.join(root, path)))
      File.write(File.join(root, path), text)
    end
  end

  private def write(path, text, changed)
    return if text == read(path)

    @texts[path] = text
    changed[path] = text
  end

  private def move_sources(upstream, entry, from, to, changed)
    text = read("runtime/sources.yml")
    sources = YAML.safe_load(text)
    swaps = {}
    upstream.pins.each do |pin|
      text = rename(text, pin.split("."), upstream, from, to)
      urls(sources.dig(*pin.split("."))).each { |mapping| swaps.merge!(swap(mapping, entry, upstream, from, to)) }
    end
    text = swaps.reduce(text) { |result, (old, new)| result.gsub(old, new) }
    check(text, upstream, to)
    write("runtime/sources.yml", text, changed)
    swaps
  end

  # Every mapping under +node+ with a URL.
  private def urls(node)
    return [] unless node.is_a?(Hash)

    (node.key?("url") ? [node] : []) + node.values.flat_map { |value| urls(value) }
  end

  # The URL and SHA-256 that replace +mapping+'s, when its URL names the
  # version.
  private def swap(mapping, entry, upstream, from, to)
    url = mapping.fetch("url")
    return {} unless url.include?(from)

    stray = mapping.keys - MOVED - [upstream.field, "version"] - entry.fetch("keep", [])
    raise Error, "#{url} stands beside #{stray.join(', ')}, which a move cannot know" unless stray.empty?

    new_url = url.gsub(from, to)
    { url => new_url, mapping.fetch("sha256") => sha256(new_url, entry, upstream) }
  end

  # The SHA-256 of +url+, from upstream's record where it keeps one.
  private def sha256(url, entry, upstream)
    case entry.fetch("checksum", upstream.github? ? "github" : "download")
    when "github" then digest(url, upstream) || @fetch.sha256(url)
    when "beside" then @fetch.call("#{url}.sha256")[/\A\h{64}\b/] || raise(Error, "#{url}.sha256 holds no SHA-256")
    else @fetch.sha256(url)
    end
  end

  private def digest(url, upstream)
    asset = JSON.parse(@fetch.call(upstream.url)).flat_map { |release| release.fetch("assets") }
      .find { |candidate| candidate.fetch("browser_download_url") == url }
    raise Error, "#{upstream.url} lists no asset #{url}" unless asset

    asset["digest"]&.delete_prefix("sha256:")
  end

  # +text+ with the version of the pin at +path+ moved: its line in the
  # pin's own block, so another pin that holds the same version is left.
  private def rename(text, path, upstream, from, to)
    lines = text.lines
    range = block(lines, path)
    key = Regexp.union(upstream.field, path.last)
    found = false
    range.each do |index|
      lines[index] = lines[index].sub(/\A(\s*(?:#{key}): (["']?))(\S*?)\2$/) do
        head, quote, value = Regexp.last_match.captures
        found = true if value.include?(from)
        "#{head}#{value.sub(from, to)}#{quote}"
      end
    end
    raise Error, "runtime/sources.yml's #{path.join('.')} has no #{upstream.field} that names #{from}" unless found

    lines.join
  end

  # The lines of +path+'s block: from its key to the next line, not a
  # comment, indented no deeper than that key.
  private def block(lines, path)
    from = 0
    to = lines.size
    path.each_with_index do |key, depth|
      indent = "  " * depth
      start = (from...to).find { |index| lines[index].start_with?("#{indent}#{key}:") }
      raise Error, "runtime/sources.yml has no #{path.join('.')}" unless start

      stop = ((start + 1)...to).find { |index| lines[index] !~ /\A\s*(?:#|$)/ && lines[index][/\A */].size <= indent.size }
      from = start
      to = stop || to
    end
    from...to
  end

  # Raises unless the pins of +upstream+ in +text+ hold +to+.
  private def check(text, upstream, to)
    watch = PinWatch.new(sources: YAML.safe_load(text), upstreams: [upstream], unwatched: {})
    moved = watch.current(upstream)
    raise Error, "the move left #{upstream.pins.join(', ')} at #{moved}, not #{to}" unless moved == to
  rescue PinWatch::Error => e
    raise Error, e.message
  end

  # +text+, runtime/licenses.yml, with the version moved in each entry
  # +id+ that names it: its version, its download, and the evidence its
  # files hold. An entry of that id that names another version records
  # another build, and is left.
  private def license(text, id, from, to)
    entries = text.split(/(?=^  - id: )/)
    moved = entries.map { |entry| (entry.start_with?("  - id: #{id}\n") && entry.include?(from)) ? entry.gsub(from, to) : entry }
    raise Error, "runtime/licenses.yml has no entry #{id} that names #{from}" if moved == entries

    moved.join
  end

  # +text+ of +path+ with each URL and SHA-256 the move replaced, and the
  # version each of +patterns+ captures.
  private def also(text, path, patterns, swaps, from, to)
    text = swaps.reduce(text) { |result, (old, new)| result.gsub(old, new) }
    patterns.reduce(text) do |result, pattern|
      raise Error, "#{path} has nothing #{pattern} matches with #{from}" unless result.match(Regexp.new(pattern))&.[](:version) == from

      result.sub(Regexp.new(pattern)) { |match| match.sub(from, to) }
    end
  end

  # +text+, CHANGELOG.md, with the move under the unreleased changes:
  # a line already there for +title+ keeps the version it moved from,
  # since the next release's readers never had the one between.
  private def changelog(text, title, from, to)
    head = text.index("## [Unreleased]\n") or raise Error, "CHANGELOG.md has no [Unreleased] section"
    stop = text.index(/^## \[/, head + 1) || text.size
    section = text[head...stop]
    line = /^- #{Regexp.escape(title)} \S+, from (\S+)\.\n/
    section = if (earlier = section[line, 1]) then section.sub(line, entry(title, earlier, to))
    elsif section.include?("### Changed\n\n") then section.sub(/^### Changed\n\n(?:- .*\n)*/) { |list| list + entry(title, from, to) }
    else
      at = section.index(/^### (?:Deprecated|Removed|Fixed|Security)\n/) || section.size
      section.dup.insert(at, "### Changed\n\n#{entry(title, from, to)}\n")
    end
    text[0...head] + section + text[stop..].to_s
  end

  private def entry(title, from, to)
    "- #{title} #{to}, from #{from}.\n"
  end
end

# ruby tasks/pin_move.rb REPORT [--only NAME] [--into DIR] [--message FILE]
# moves every pin the watch's REPORT found behind, or only the one named,
# prints each move, and writes the files it changed into the checkout,
# or, with --into, into DIR at the same paths, for a run that must change
# nothing to compare them with the checkout's. With --message, it writes
# the commit message of what it moved into FILE. It exits 1
# when a pin behind could not be moved. A pin held for a person is not
# in the report as behind, but as held, and is left.
if $PROGRAM_NAME == __FILE__
  args = ARGV.dup
  into = (index = args.index("--into")) && args.slice!(index, 2).last
  only = (index = args.index("--only")) && args.slice!(index, 2).last
  message = (index = args.index("--message")) && args.slice!(index, 2).last
  findings = JSON.parse(File.read(args.fetch(0))).select { |finding| finding["status"] == "newer" }
  findings.select! { |finding| finding["name"] == only } if only
  move = PinMove.load(File.expand_path("..", __dir__), PinWatch::Fetch.new(token: ENV.fetch("GITHUB_TOKEN", nil)))
  failed = findings.reject do |finding|
    changed = move.call(finding)
    puts "moved    #{finding['name']} #{finding['current']} -> #{finding['newer']}: #{changed.keys.join(', ')}"
    true
  rescue PinMove::Error, PinWatch::Error => e
    puts "failed   #{finding['name']} #{finding['current']} -> #{finding['newer']}: #{e.message}"
    false
  end
  into ? move.save(into) : move.save
  moved = findings - failed
  File.write(message, move.message(moved)) if message && moved.any?
  exit(failed.empty? ? 0 : 1)
end
