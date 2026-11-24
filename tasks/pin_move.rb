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
# upstream records none does it download the file and compute it. A
# container image, pinned as REPOSITORY:TAG@sha256:DIGEST, moves its tag
# and takes each new digest from the registry's listing of that tag.
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

  # A container image pinned by tag and digest.
  IMAGE = /\A(?<repository>[^\s:@]+):(?<tag>[^\s@]+)@sha256:(?<digest>\h{64})\z/

  attr_reader :texts

  # The move of the checkout at +root+, asking +fetch+ for upstreams'
  # records.
  def self.load(root, fetch)
    entries = YAML.safe_load_file(File.join(root, "runtime/upstreams.yml")).fetch("watched")
    new(root, PinWatch.watched(entries, YAML.safe_load_file(File.join(root, "runtime/sources.yml"))), fetch)
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

  # The names of the upstreams a move may change: those not held, and
  # those whose hold is for a new release alone, whose other builds of
  # the pinned release move (rebuild in runtime/upstreams.yml).
  def movable
    @entries.keys.reject { |name| hold(name) && !@entries.fetch(name)["rebuild"] }
  end

  # Moves the pins of +finding+, a PinWatch::Finding or its report's
  # hash, from its current version to its newer one, in the texts this
  # move holds, and returns the files it changed.
  def call(finding)
    finding = finding.to_h
    name = finding.fetch("name")
    entry = @entries.fetch(name)
    upstream = PinWatch::Upstream.from(name, entry)
    from = finding.fetch("current")
    to = finding.fetch("newer")
    raise Error, "#{name} is held: #{hold(name)}" if hold(name) && !upstream.rebuild?(to, from)
    before = @texts.dup
    changed = {}
    parts(entry, upstream, from, to).each do |part, named, old, new|
      swaps = move_sources(named, part, old, new, changed)
      part.fetch("licenses", []).each { |id| write("runtime/licenses.yml", license(read("runtime/licenses.yml"), id, old, new, swaps), changed) }
      part.fetch("also", {}).each { |path, patterns| write(path, also(read(path), path, patterns, swaps, old, new), changed) }
      from, to = old, new
    end
    write("runtime/licenses.yml", linked(read("runtime/licenses.yml"), entry["linked"], to), changed) if entry["linked"]
    write("CHANGELOG.md", changelog(read("CHANGELOG.md"), title(name), from, to), changed) if entry.fetch("ships", true)
    platforms = entry.fetch("platform", {}).keys | entry.fetch("compiled", {}).keys
    read = platforms.flat_map do |platform|
      archive(upstream, platform, entry.dig("platform", platform), entry.dig("compiled", platform) || {}, changed)
    end
    compiled(name, read, changed)
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
  # every commit of Fledge's carries (CONTRIBUTING.md).
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

  # Moves each of +findings+, the watch's report's hashes, with +move+,
  # printing to +out+ what became of each, and returns those it moved and
  # those it could not, for which a person is needed.
  def self.move_each(move, findings, out:)
    moved = []
    failed = []
    findings.each do |finding|
      moving = "#{finding['name']} #{finding['current']} -> #{finding['newer']}"
      changed = move.call(finding)
      out.puts "moved    #{moving}: #{changed.keys.join(', ')}"
      moved << finding
    rescue Error, PinWatch::Error => e
      out.puts "failed   #{moving}: #{e.message}"
      failed << finding
    end
    [moved, failed]
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

  # What one move rewrites, each part with its entry, its upstream, and
  # the versions it moves from and to: the version the watch compares,
  # and, for an upstream with release, the release name its URLs carry,
  # which the listing gives for the new version. CHANGELOG.md takes the
  # last.
  private def parts(entry, upstream, from, to)
    parts = [[entry, upstream, from, to]]
    release = entry["release"] or return parts

    named = upstream.with(field: release.fetch("field"), current: nil)
    pattern = Regexp.new(release.fetch("pattern").gsub("{version}", Regexp.escape(to)), Regexp::MULTILINE)
    name = @fetch.call(upstream.url)[pattern, "version"] or raise Error, "#{upstream.url} names no release of #{to}"
    sources = YAML.safe_load(read("runtime/sources.yml"))
    old = PinWatch.new(sources:, upstreams: [named], unwatched: {}).current(named)
    parts << [entry.except("release", "licenses", "also").merge(release.slice("licenses", "also")), named, old, name]
  end

  private def move_sources(upstream, entry, from, to, changed)
    text = read("runtime/sources.yml")
    sources = YAML.safe_load(text)
    swaps = {}
    upstream.pins.each do |pin|
      text = rename(text, pin.split("."), upstream, from, to)
      node = sources.dig(*pin.split("."))
      urls(node).each { |mapping| swaps.merge!(swap(mapping, entry, upstream, from, to)) }
      images(node).each { |reference| swaps.merge!(retag(reference, from, to)) }
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

  # Every container image reference under +node+, a string of the form
  # REPOSITORY:TAG@sha256:DIGEST, as a match with those three captures.
  private def images(node)
    return node.values.flat_map { |value| images(value) } if node.is_a?(Hash)

    match = IMAGE.match(node.to_s)
    match ? [match] : []
  end

  # The reference that replaces +reference+: the tag with the version
  # moved where it names the version, and the digest the registry gives
  # that tag now. A tag that names no version, such as debian:trixie-slim,
  # is one the registry moves to a new image under the same name, so the
  # pin's version is the day it was pushed, and its move is the digest
  # alone. An image's digest is the SHA-256 of its manifest, which only
  # the registry holds, so the registry's own record of the tag is asked.
  private def retag(reference, from, to)
    tag = reference[:tag].gsub(from, to)
    moved = "#{reference[:repository]}:#{tag}@#{registry_digest(reference[:repository], tag)}"
    (moved == reference.to_s) ? {} : { reference.to_s => moved }
  end

  # The digest of +repository+'s +tag+, from quay.io's tag API or Docker
  # Hub's, the registries the pins name; another stops the move. A
  # repository named with no host is Docker Hub's, and one with no
  # namespace is an official image, in library/, as Docker reads them.
  private def registry_digest(repository, tag)
    host, path = repository.split("/", 2)
    host, path = "docker.io", repository unless path && host.match?(/[.:]/)
    return quay_digest(path, tag) if host == "quay.io"
    raise Error, "#{repository} is on no registry the move can ask for a digest (quay.io, Docker Hub)" unless host == "docker.io"

    namespace, name = path.include?("/") ? path.split("/", 2) : ["library", path]
    JSON.parse(@fetch.call("https://hub.docker.com/v2/namespaces/#{namespace}/repositories/#{name}/tags/#{tag}")).fetch("digest")
  end

  private def quay_digest(path, tag)
    url = "https://quay.io/api/v1/repository/#{path}/tag/?specificTag=#{tag}&onlyActiveTags=true"
    listed = JSON.parse(@fetch.call(url)).fetch("tags").find { |candidate| candidate.fetch("name") == tag }
    raise Error, "#{url} lists no tag #{tag}" unless listed

    listed.fetch("manifest_digest")
  end

  # The URL and SHA-256 that replace +mapping+'s, when its URL names the
  # version.
  private def swap(mapping, entry, upstream, from, to)
    url = mapping.fetch("url")
    return {} unless url.include?(from)

    member = entry["member"]
    stray = mapping.keys - MOVED - [upstream.field, "version"] - entry.fetch("keep", []) - (member ? [member, "file_sha256"] : [])
    raise Error, "#{url} stands beside #{stray.join(', ')}, which a move cannot know" unless stray.empty?

    new_url = url.gsub(from, to)
    swaps = { url => new_url, mapping.fetch("sha256") => sha256(new_url, entry, upstream) }
    return swaps unless member

    path = mapping.fetch(member).gsub(from, to)
    swaps.merge(mapping.fetch(member) => path, mapping.fetch("file_sha256") => @fetch.member_sha256(new_url, path))
  end

  # The SHA-256 of +url+, from upstream's record where it keeps one.
  private def sha256(url, entry, upstream)
    case entry.fetch("checksum", upstream.github? ? "github" : "download")
    when "github" then digest(url, upstream) || @fetch.sha256(url)
    when "beside" then @fetch.call("#{url}.sha256")[/\A\h{64}\b/] || raise(Error, "#{url}.sha256 holds no SHA-256")
    else @fetch.sha256(url)
    end
  end

  # GitHub's listing escapes an asset's URL (LLVM's clang+llvm as
  # clang%2Bllvm), so URLs are compared as they read unescaped.
  private def digest(url, upstream)
    asset = JSON.parse(upstream.listing { |url| @fetch.call(url) }).flat_map { |release| release.fetch("assets") }
      .find { |candidate| URI.decode_uri_component(candidate.fetch("browser_download_url")) == URI.decode_uri_component(url) }
    raise Error, "#{upstream.url} lists no asset #{url}" unless asset

    asset["digest"]&.delete_prefix("sha256:")
  end

  # +text+ with the version of the pin at +path+ moved: its line in the
  # pin's own block, so another pin that holds the same version is left,
  # and a comment after the value, as YAML reads one, stays.
  private def rename(text, path, upstream, from, to)
    lines = text.lines
    range = block(lines, path)
    key = Regexp.union(upstream.field, path.last)
    found = false
    range.each do |index|
      lines[index] = lines[index].sub(/\A(\s*(?:#{key}): (["']?))(\S*?)\2(\s+#.*)?$/) do
        head, quote, value, comment = Regexp.last_match.captures
        found = true if value.include?(from)
        "#{head}#{value.sub(from, to)}#{quote}#{comment}"
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

  # Reads the new archive of each pin of +upstream+ for +platform+, once,
  # and returns, for each library of +compiled+, its id, its entry there,
  # the archive's URL, and the version its file holds. With a +pattern+,
  # it raises unless the archive holds a file whose path the pattern's
  # arch capture takes a platform name from, and moves
  # runtime/licenses.yml's platform to that name where it differs. A Ruby
  # names its platform (RbConfig's arch, so RUBY_PLATFORM and the RubyGems
  # platform Bundler runs as) for the macOS it was built on, and the
  # license audit, parity, and Delivery read the name there (runtimes.md,
  # "The move").
  private def archive(upstream, platform, pattern, compiled, changed)
    sources = YAML.safe_load(read("runtime/sources.yml"))
    wanted = compiled.empty? ? nil : Regexp.union(compiled.values.map { |library| Regexp.new(library.fetch("file")) })
    upstream.pins.flat_map do |pin|
      url = sources.dig(*pin.split("."), "platforms", platform, "url")
      files = @fetch.members(url, wanted)
      if pattern
        arch = files.each_key.lazy.filter_map { |path| path[Regexp.new(pattern), "arch"] }.first
        raise Error, "#{url} holds no file that names its platform" unless arch

        rename_platform(platform, arch, changed)
      end
      compiled.map { |id, library| [id, library, url, compiled_version(url, files, id, library)] }
    end
  end

  # Moves each entry of runtime/licenses.yml that +read+, from the
  # archives of the upstream +name+, names to the version its files hold,
  # with a line in CHANGELOG.md. An entry read from several platforms'
  # archives describes them all, as jdx/ruby builds each target from one
  # list of libraries, so it moves only when they all hold one version.
  private def compiled(name, read, changed)
    read.group_by(&:first).each do |id, found|
      versions = found.map(&:last).uniq
      unless versions.one?
        each = found.map { |_, _, url, version| "#{version} in #{url}" }
        raise Error, "#{name}'s archives name #{id} as #{each.join(' and ')}, not one version"
      end

      old = YAML.safe_load(read("runtime/licenses.yml")).fetch("components").find { |entry| entry.fetch("id") == id }&.fetch("version")&.to_s
      raise Error, "runtime/licenses.yml has no entry #{id}" unless old
      next if old == versions.first

      write("runtime/licenses.yml", license(read("runtime/licenses.yml"), id, old, versions.first), changed)
      write("CHANGELOG.md", changelog(read("CHANGELOG.md"), found.first[1].fetch("title"), old, versions.first), changed)
    end
  end

  # Moves runtime/licenses.yml's +platform+ to the arch +arch+, and its
  # gem_arch to the name RubyGems gives that arch, with a line in
  # CHANGELOG.md, when they name another.
  private def rename_platform(platform, arch, changed)
    text = read("runtime/licenses.yml")
    named = YAML.safe_load(text).dig("platforms", platform, "arch") or raise Error, "runtime/licenses.yml gives #{platform} no arch"
    return if named == arch

    moved = text.sub(/^  #{Regexp.escape(platform)}: \{.*\}$/) do |line|
      line.sub("arch: #{named},", "arch: #{arch},").sub("gem_arch: #{Gem::Platform.new(named)},", "gem_arch: #{Gem::Platform.new(arch)},")
    end
    raise Error, "runtime/licenses.yml's line for #{platform} gives its arch in no form the move can rewrite" unless YAML.safe_load(moved).dig("platforms", platform, "arch") == arch

    write("runtime/licenses.yml", moved, changed)
    write("CHANGELOG.md", changelog(read("CHANGELOG.md"), "The #{platform} app's RUBY_PLATFORM", named, arch), changed)
  end

  # The version of the library of runtime/licenses.yml's entry +id+ that
  # +library+'s version pattern finds in the bytes of its file among
  # +files+, the new archive at +url+'s.
  private def compiled_version(url, files, id, library)
    path, bytes = files.find { |name, content| content && name.match?(Regexp.new(library.fetch("file"))) }
    raise Error, "#{url} holds no file in which to read #{id}'s version" unless path

    found = bytes.scan(Regexp.new(library.fetch("version").b)).flatten.uniq
    raise Error, "#{url}'s #{File.basename(path)} names no version of #{id}" if found.empty?
    raise Error, "#{url}'s #{File.basename(path)} names #{id} as #{found.join(' and ')}, not one version" unless found.one?

    found.first
  end

  # Raises unless the pins of +upstream+ in +text+ hold +to+.
  private def check(text, upstream, to)
    watch = PinWatch.new(sources: YAML.safe_load(text), upstreams: [upstream], unwatched: {})
    moved = watch.current(upstream)
    raise Error, "the move left #{upstream.pins.join(', ')} at #{moved}, not #{to}" unless moved == to
  rescue PinWatch::Error => e
    raise Error, e.message
  end

  # +text+, runtime/licenses.yml, with the version moved in the entry
  # +id+, which is the only entry of that id (the license audit refuses
  # two): its version, its download, and the evidence its files hold,
  # and each SHA-256 of +swaps+ it records, as of a file the pin is.
  private def license(text, id, from, to, swaps = {})
    entries = text.split(/(?=^  - id: )/)
    moved = entries.map do |entry|
      next entry unless entry.start_with?("  - id: #{id}\n") && entry.include?(from)

      swaps.reduce(entry.gsub(from, to)) { |result, (old, new)| result.gsub(old, new) }
    end
    raise Error, "runtime/licenses.yml has no entry #{id} that names #{from}" if moved == entries

    moved.join
  end

  # +text+, runtime/licenses.yml, with each entry +linked+ names moved to
  # the version of the library its pattern finds in the upstream's build
  # script at +to+.
  private def linked(text, linked, to)
    script = @fetch.call(linked.fetch("url").gsub("{version}", to))
    entries = YAML.safe_load(text).fetch("components")
    linked.except("url").reduce(text) do |result, (id, pattern)|
      found = script[Regexp.new(pattern), "version"] or raise Error, "#{linked.fetch('url')} names no version #{pattern} finds, at #{to}"
      old = entries.find { |entry| entry.fetch("id") == id }&.fetch("version")&.to_s or raise Error, "runtime/licenses.yml has no entry #{id}"
      (old == found) ? result : license(result, id, old, found)
    end
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
  moved, failed = PinMove.move_each(move, findings, out: $stdout)
  into ? move.save(into) : move.save
  File.write(message, move.message(moved)) if message && moved.any?
  exit(failed.empty? ? 0 : 1)
end
