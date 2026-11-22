# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require "date"
require "digest"
require "json"
require "net/http"
require "open3"
require "rubygems"
require "rubygems/package"
require "time"
require "tmpdir"
require "uri"
require "yaml"
require "zlib"

# Finds the pins of runtime/sources.yml that upstream has released a
# newer version of (doc/contributors/design/runtimes.md, "Keeping the
# pins current").
#
# Every input a runtime is built from is pinned, so a security fix
# upstream, in OpenSSL or in Ruby itself, reaches no app until the pin
# moves. Nothing in the pins says when upstream has moved, and a person
# who has to remember to look will not, every day, for every input.
#
# This reads where each pin is released (runtime/upstreams.yml), asks
# each upstream once for what it has released, and says, for each, the
# newest release in the pin's line and the newest beyond it. It changes
# nothing: what it finds is for the scheduled workflow to act on.
#
#   watch = PinWatch.load(".")
#   report = watch.run(PinWatch::Fetch.new(token: ENV["GITHUB_TOKEN"]))
#   report.map(&:status)   # => [:current, :newer, ...]
class PinWatch < Data.define(:sources, :upstreams, :unwatched)
  # Something an upstream's answer or a pin does not hold as expected.
  class Error < StandardError; end

  # How many days a pin held for a person may stay behind before the
  # watch fails, to call that person: longer than the planned move a hold
  # waits for takes (Ruby 4.0.0 to RubyInstaller-4.0.0-1 took three
  # days), and short enough that a fix upstream does not wait a season
  # unseen.
  HELD_DAYS = 30

  # What the watch found for one upstream: the pin's version, the newest
  # release in its line, and the newest beyond the line, or the error
  # that kept it from knowing; and, for a pin held for a person, why, the
  # day the oldest release newer than the pin came out, when the upstream
  # dates its releases, and whether that was more than HELD_DAYS ago.
  class Finding < Data.define(:name, :pins, :ships, :current, :newer, :beyond, :error, :held, :since, :overdue)
    # :error when the upstream could not be read; when it has a release
    # in the pin's line newer than the pin, :overdue when the pin is held
    # and has been behind for longer than HELD_DAYS, :held when it is
    # held, and :newer otherwise; :beyond when its only newer release is
    # in another line, and :current otherwise.
    def status
      if error then :error
      elsif newer && held then overdue ? :overdue : :held
      elsif newer then :newer
      elsif beyond then :beyond
      else :current
      end
    end

    # The finding as JSON's types, for the report file.
    def to_h
      {
"name" => name,
"status" => status.to_s,
"pins" => pins,
"ships" => ships,
"current" => current,
"newer" => newer,
"beyond" => beyond,
"error" => error,
"held" => held,
"since" => since,
}.compact
    end
  end

  # Where one input is released, as runtime/upstreams.yml says.
  class Upstream < Data.define(:name, :pins, :field, :current, :url, :pattern, :line, :ships, :hold)
    # The upstream runtime/upstreams.yml names +name+ with +entry+.
    def self.from(name, entry)
      if (repository = entry["github"])
        url = "https://api.github.com/repos/#{repository}/releases?per_page=100"
        pattern = entry.fetch("tag")
      else
        url = entry.fetch("page")
        pattern = entry.fetch("pattern")
      end
      current = entry["current"] && Regexp.new(entry["current"])
      new(name:, pins: entry.fetch("pins"), field: entry.fetch("field", "version"), current:, url:,
        pattern: Regexp.new(pattern, Regexp::MULTILINE), line: entry["line"], ships: entry.fetch("ships", true), hold: entry["hold"])
    end

    # Whether the versions come from GitHub's list of releases.
    def github?
      url.start_with?("https://api.github.com/")
    end

    # Every version the upstream's answer +body+ lists.
    def versions(body)
      found = github? ? tags(body) : body.scan(pattern).map { |match| match[pattern.names.index("version")] }
      raise Error, "#{url} lists no version that #{pattern.source} matches" if found.empty?

      found.uniq
    end

    # The day each version the answer +body+ lists came out, as GitHub
    # dates a release; a page dates none.
    def dates(body)
      return {} unless github?

      releases(body).to_h { |version, release| [version, release["published_at"]&.slice(0, 10)] }.compact
    end

    private def tags(body)
      releases(body).map(&:first)
    end

    private def releases(body)
      JSON.parse(body).reject { |release| release["draft"] || release["prerelease"] }
        .filter_map { |release| (version = release.fetch("tag_name")[pattern, "version"]) && [version, release] }
    rescue JSON::ParserError => e
      raise Error, "#{url} answered with no JSON: #{e.message}"
    end
  end

  # Fetches an upstream's answer over HTTPS, following redirects, with
  # the token for GitHub's API when there is one (a public listing needs
  # none, but an anonymous caller gets 60 requests an hour).
  class Fetch
    # How many redirects one request follows.
    REDIRECTS = 5

    def initialize(token: nil, timeout: 30)
      @token = token
      @timeout = timeout
    end

    # The body +url+ answers with.
    def call(url)
      get(url, &:body)
    end

    # The SHA-256 of the file at +url+, read as it downloads and never
    # kept, for an upstream that records none of its own.
    def sha256(url)
      get(url) do |response|
        digest = Digest::SHA256.new
        response.read_body { |chunk| digest << chunk }
        digest.hexdigest
      end
    end

    # The SHA-256 of the file +member+ of the Zstandard-compressed
    # tarball at +url+, which is downloaded into a folder of its own and
    # removed. LLVM's archive is compressed with a 2 GB window, which
    # zstd reads only with --long=31, as tasks/runtime_builder/windows.rb
    # unpacks it; where no zstd is, 7-Zip's 7zz, which mise.toml pins.
    def member_sha256(url, member)
      Dir.mktmpdir("pin-move") do |folder|
        archive = File.join(folder, "archive")
        get(url) { |response| File.open(archive, "wb") { |file| response.read_body { |chunk| file.write(chunk) } } }
        digest = Digest::SHA256.new
        Open3.pipeline_r(decompress(archive), ["tar", "-xOf", "-", member]) do |out, threads|
          while (chunk = out.read(1 << 16))
            digest << chunk
          end
          raise Error, "#{url} holds no #{member}" unless threads.map(&:value).all?(&:success?)
        end
        digest.hexdigest
      end
    end

    # The path of every entry in the gzipped tarball at +url+, in the
    # order it holds them, read with RubyGems' tar reader from a copy
    # kept in a folder of its own and removed.
    def members(url)
      Dir.mktmpdir("pin-move") do |folder|
        archive = File.join(folder, "archive")
        get(url) { |response| File.open(archive, "wb") { |file| response.read_body { |chunk| file.write(chunk) } } }
        Zlib::GzipReader.open(archive) { |gzip| Gem::Package::TarReader.new(gzip).map(&:full_name) }
      end
    rescue Zlib::Error, Gem::Package::Error => e
      raise Error, "#{url} is no gzipped tarball: #{e.message}"
    end

    private def get(url, redirects = REDIRECTS, &read)
      uri = URI(url)
      Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: @timeout, read_timeout: @timeout) do |http|
        http.request(request(uri)) do |response|
          return read.call(response) if response.is_a?(Net::HTTPSuccess)
          return get(URI.join(url, response["location"]).to_s, redirects - 1, &read) if response.is_a?(Net::HTTPRedirection) && redirects.positive?

          raise Error, "#{url} answered #{response.code}#{spent(response)}"
        end
      end
    rescue SystemCallError, IOError, Timeout::Error, OpenSSL::SSL::SSLError => e
      raise Error, "#{url} could not be read: #{e.message}"
    end

    # Why GitHub's API refused, when it was its rate limit: a 403 or 429
    # with x-ratelimit-remaining 0 ("Rate limits for the REST API",
    # docs.github.com/en/rest/using-the-rest-api/rate-limits-for-the-rest-api),
    # which is not a missing release, and which a token lifts from the
    # 60 requests an hour an anonymous caller gets.
    private def spent(response)
      return "" unless %w[403 429].include?(response.code) && response["x-ratelimit-remaining"] == "0"

      reset = Time.at(Integer(response["x-ratelimit-reset"], exception: false) || 0).utc.iso8601
      anonymous = ", and it was asked with no token (GITHUB_TOKEN), which GitHub allows 60 requests an hour" unless @token && !@token.empty?
      ": its rate limit for this caller is spent until #{reset}#{anonymous}"
    end

    private def decompress(archive)
      return ["zstd", "-dc", "--long=31", archive] if tool?("zstd")
      return ["7zz", "x", "-so", "-bd", archive] if tool?("7zz")

      raise Error, "unpacking #{archive} needs zstd or 7-Zip's 7zz on PATH"
    end

    private def tool?(name)
      ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).any? { |folder| File.executable?(File.join(folder, name)) }
    end

    private def request(uri)
      request = Net::HTTP::Get.new(uri)
      request["User-Agent"] = "Fledge pin watch (https://github.com/setdef/Fledge)"
      if uri.host == "api.github.com"
        request["Accept"] = "application/vnd.github+json"
        request["Authorization"] = "Bearer #{@token}" if @token && !@token.empty?
      end
      request
    end
  end

  # The watch of the checkout at +root+.
  def self.load(root)
    sources = YAML.safe_load_file(File.join(root, "runtime/sources.yml"))
    file = YAML.safe_load_file(File.join(root, "runtime/upstreams.yml"))
    new(sources:, upstreams: file.fetch("watched").map { |name, entry| Upstream.from(name, entry) }, unwatched: file.fetch("unwatched"))
  end

  # Every component of runtime/sources.yml, as a dotted path: each mapping
  # that has a version, and each plain value that stands beside no
  # version, as mobile.xcode does.
  def components(node = sources, path = [])
    node.flat_map do |key, value|
      here = [*path, key]
      if !value.is_a?(Hash) || value.key?("version") then [here.join(".")]
      else components(value, here)
      end
    end
  end

  # The components that neither a watched upstream nor the unwatched list
  # names.
  def unaccounted
    components - upstreams.flat_map(&:pins) - unwatched.keys
  end

  # The status the watch exits with for +report+: 1 when an upstream
  # could not be read or a held pin is overdue, since a person is needed;
  # else 3 when a pin is behind, for the move; and else 0.
  def self.exit_status(report)
    statuses = report.map(&:status)
    if statuses.intersect?(%i[error overdue]) then 1
    elsif statuses.include?(:newer) then 3
    else 0
    end
  end

  # What each upstream has released, asking +fetch+ once for each URL, as
  # it stands on +today+.
  def run(fetch, today: Date.today)
    answers = Hash.new { |cache, url| cache[url] = fetch.call(url) }
    upstreams.map { |upstream| find(upstream, answers, today) }
  end

  # The version the pins of +upstream+ hold.
  def current(upstream)
    values = upstream.pins.map { |pin| version_of(upstream, pin) }.uniq
    raise Error, "#{upstream.pins.join(', ')} hold different versions: #{values.join(', ')}" unless values.one?

    values.first
  end

  private def find(upstream, answers, today)
    current = current(upstream)
    newer = upstream.versions(answers[upstream.url]).select { |version| newer?(version, current) }
    in_line, beyond = newer.partition { |version| same_line?(upstream, version, current) }
    since = upstream.dates(answers[upstream.url]).values_at(*in_line).compact.min
    overdue = !since.nil? && today - Date.iso8601(since) > HELD_DAYS
    finding(upstream, current:, newer: newest(in_line), beyond: newest(beyond), since:, overdue:)
  rescue Error => e
    finding(upstream, current:, error: e.message)
  end

  private def finding(upstream, current: nil, newer: nil, beyond: nil, error: nil, since: nil, overdue: false)
    Finding.new(name: upstream.name, pins: upstream.pins, ships: upstream.ships, current:, newer:, beyond:, error:,
      held: upstream.hold, since:, overdue:)
  end

  private def version_of(upstream, pin)
    value = sources.dig(*pin.split("."))
    raise Error, "runtime/sources.yml has no #{pin}" if value.nil?

    value = value.fetch(upstream.field) { raise Error, "#{pin} has no #{upstream.field}" } if value.is_a?(Hash)
    return value.to_s unless upstream.current

    value.to_s[upstream.current, "version"] or raise Error, "#{pin}'s #{upstream.field} #{value} does not match #{upstream.current.source}"
  end

  private def newer?(version, current)
    candidate = gem_version(version)
    return false if candidate.prerelease? && !gem_version(current).prerelease?

    candidate > gem_version(current)
  end

  private def same_line?(upstream, version, current)
    return true unless upstream.line

    numbers(version).first(upstream.line) == numbers(current).first(upstream.line)
  end

  private def newest(versions)
    versions.max_by { |version| gem_version(version) }
  end

  private def numbers(version)
    gem_version(version).segments.take_while { |segment| segment.is_a?(Integer) }
  end

  # Dates (2026-03-19) and MSYS2's pkgrel (16.2.0-7) count as numbers,
  # and RubyGems reads 4.1.0.preview1 as the prerelease it is.
  private def gem_version(version)
    Gem::Version.new(version.tr("-", "."))
  rescue ArgumentError
    raise Error, "#{version} is not a version"
  end
end

# ruby tasks/pin_watch.rb [REPORT]
# asks every upstream, prints what it found, writes it to REPORT as
# JSON, and exits as PinWatch.exit_status says: 0 when no pin is behind
# but those held in time, 3 when an upstream has a newer release in the
# line of a pin nobody holds, and 1 when one could not be read or a held
# pin has been behind for longer than PinWatch::HELD_DAYS.
if $PROGRAM_NAME == __FILE__
  report = PinWatch.load(File.expand_path("..", __dir__)).run(PinWatch::Fetch.new(token: ENV.fetch("GITHUB_TOKEN", nil)))
  File.write(ARGV[0], JSON.pretty_generate(report.map(&:to_h))) if ARGV[0]
  report.each do |finding|
    puts [
      finding.status.to_s.ljust(8),
      finding.name.ljust(18),
      finding.current,
      finding.newer && "-> #{finding.newer}",
      finding.beyond && "(beyond its line: #{finding.beyond})",
      finding.error,
      finding.newer && finding.since && "(since #{finding.since})",
      finding.newer && finding.held && "held for a person, who has #{PinWatch::HELD_DAYS} days: #{finding.held}",
].compact.join(" ")
  end
  exit PinWatch.exit_status(report)
end
