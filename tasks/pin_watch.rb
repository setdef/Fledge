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
require "stringio"
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

  # When a pin's line has ended, as the watch tells it from the days its
  # upstream released on, with no support policy read: newer lines have
  # released on ENDED_RELEASES days or more since the line's newest
  # release, and that release is older than ENDED_DAYS, or than
  # ENDED_GAPS times the longest the upstream's listing ever went between
  # two releases, whichever is longer. Measured against every line
  # OpenSSL's, RubyInstaller's, jdx/ruby's, and Ruby's histories hold, it
  # called no line ended that released again, and called OpenSSL's ended
  # lines ended 181 to 189 days after their last release
  # (doc/contributors/design/runtimes.md, "A line that has ended").
  ENDED_DAYS = 180
  ENDED_GAPS = 1.5
  ENDED_RELEASES = 3

  # What the watch found for one upstream: the pin's version, the newest
  # release in its line, and the newest beyond the line, or the error
  # that kept it from knowing; for a pin held for a person, why, the day
  # the oldest release newer than the pin came out, when the upstream
  # dates its releases, and whether that was more than HELD_DAYS ago; and,
  # for a pin whose only newer release is beyond its line, the day its
  # line last released, when the upstream dates it, and whether the line
  # has ended.
  class Finding < Data.define(:name, :pins, :ships, :current, :newer, :beyond, :error, :held, :since, :overdue, :last, :ended)
    # :error when the upstream could not be read; when it has a release
    # in the pin's line newer than the pin, :overdue when the pin is held
    # and has been behind for longer than HELD_DAYS, :held when it is
    # held, and :newer otherwise; when its only newer release is in
    # another line, :ended when the pin's line has ended and :beyond
    # otherwise; and :current otherwise.
    def status
      if error then :error
      elsif newer && held then overdue ? :overdue : :held
      elsif newer then :newer
      elsif beyond then ended ? :ended : :beyond
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
"last" => last,
}.compact
    end
  end

  # The days an upstream's listing dates its releases on, as they bear on
  # one pin's line: the day of the line's newest release, every day
  # anything came out, and the days a newer line released on.
  class Quiet < Data.define(:last, :days, :newer)
    # The days +dates+ gives each version, with +place+ saying of a
    # version whether its line is the pin's (0), older (-1), or newer (1);
    # nil when the upstream dates nothing. A line the listing holds no
    # release of last released before anything it lists.
    def self.from(dates, &place)
      dated = dates.transform_values { |day| Date.iso8601(day) }
      return nil if dated.empty?

      lines = dated.group_by { |version, _| place.call(version) }.transform_values { |pairs| pairs.map(&:last) }
      days = dated.values.uniq.sort
      new(last: lines.fetch(0, []).max || days.first, days:, newer: lines.fetch(1, []).uniq)
    end

    # How long the line may go with no release before it has ended: the
    # longer of ENDED_DAYS and ENDED_GAPS times the upstream's longest
    # silence between two releases.
    def limit
      [ENDED_DAYS, ENDED_GAPS * days.each_cons(2).map { |before, after| after - before }.max.to_i].max
    end

    # Whether the line has ended on +today+.
    def ended?(today)
      newer.count { |day| day > last } >= ENDED_RELEASES && today - last > limit
    end
  end

  # One Alpine package, read from its branch's index for each repository
  # and architecture (apk in runtime/upstreams.yml). A branch keeps only
  # each package's newest build, so the build its indexes serve is the
  # only one that installs, and a pin of any other is behind, whichever
  # number is higher: apk's versions need no order of their own.
  class AlpinePackage < Data.define(:name, :indexes)
    # The URLs of the indexes +entry+ names, by architecture, from the
    # template +url+.
    def self.indexes(url, entry)
      entry.fetch("architectures").to_h do |arch|
        [arch, entry.fetch("repositories").map { |repository| url.gsub("{repository}", repository).gsub("{arch}", arch) }]
      end
    end

    # The build every architecture's index serves, when it is not
    # +current+, asking +answer+ for each index; nil when each serves
    # +current+.
    def newer(current, &answer)
      served = indexes.transform_values { |urls| urls.flat_map { |url| versions(answer.call(url), url) }.uniq }
      return nil if served.values.all? { |versions| versions.include?(current) }

      common = served.values.reduce(:&)
      return common.first if common.one?

      raise Error, unserved(served)
    end

    private def unserved(served)
      return "Alpine's indexes serve no #{name} on #{served.keys.join(' or on ')}" if served.values.all?(&:empty?)

      each = served.map { |arch, versions| "#{versions.empty? ? 'nothing' : versions.join(' and ')} on #{arch}" }
      "Alpine's indexes serve #{name} #{each.join(' and ')}, and no one build of it on every architecture"
    end

    # The versions of this package the index +body+ lists. Alpine serves
    # an index as two gzip members, the signature's tar entry and then
    # the index's, so the members are read as one stream.
    private def versions(body, url)
      index = nil
      Gem::Package::TarReader.new(StringIO.new(Zlib::GzipReader.zcat(StringIO.new(body)))).each do |entry|
        index = entry.read if entry.full_name == "APKINDEX"
      end
      raise Error, "#{url} holds no APKINDEX" unless index

      index.split(/\n\n+/).filter_map { |block| block[/^V:(.+)$/, 1] if block[/^P:(.+)$/, 1] == name }
    rescue Zlib::Error, Gem::Package::Error => e
      raise Error, "#{url} is no Alpine index: #{e.message}"
    end
  end

  # Where one input is released, as runtime/upstreams.yml says.
  class Upstream < Data.define(:name, :pins, :field, :current, :url, :pattern, :line, :ships, :hold, :package, :rebuild, :modified)
    # How many releases GitHub lists on one page at most.
    PAGE = 100

    # How many pages of releases are read at most, past which an upstream
    # lists more than the watch can know it read whole.
    PAGES = 20

    # The upstream runtime/upstreams.yml names +name+ with +entry+.
    def self.from(name, entry)
      if (repository = entry["github"])
        url = "https://api.github.com/repos/#{repository}/releases?per_page=#{PAGE}"
        pattern = entry.fetch("tag")
      elsif (url = entry["apk"])
        pattern = "\\A\\z"
      else
        url = entry.fetch("page")
        pattern = entry.fetch("pattern")
      end
      current = entry["current"] && Regexp.new(entry["current"])
      new(name:, pins: entry.fetch("pins"), field: entry.fetch("field", "version"), current:, url:,
        pattern: Regexp.new(pattern, Regexp::MULTILINE), line: entry["line"], ships: entry.fetch("ships", true), hold: entry["hold"],
        package: entry["package"] && AlpinePackage.new(name: entry["package"], indexes: AlpinePackage.indexes(url, entry)),
        rebuild: entry["rebuild"] && Regexp.new(entry["rebuild"]), modified: entry.fetch("modified", false))
    end

    # Whether the versions come from GitHub's list of releases.
    def github?
      url.start_with?("https://api.github.com/")
    end

    # Whether +version+ is another build of the release the pin's version
    # +current+ is a build of: the rebuild pattern's +of+ capture takes
    # the same release from both, as 4.0.10 from jdx/ruby's
    # 4.0.10-1 and 4.0.10-2.
    def rebuild?(version, current)
      return false unless rebuild

      of = current[rebuild, "of"]
      !of.nil? && version[rebuild, "of"] == of
    end

    # What the upstream answers, asking +answer+ for each URL. GitHub lists
    # releases newest first, a page at a time, and one rebuild of every
    # release an upstream has can list more than a page above the pin's,
    # so for an upstream with rebuild every page is read and joined, until
    # one lists fewer than a page holds.
    def listing(&answer)
      return answer.call(url) unless rebuild && github?

      listed = []
      (1..PAGES).each do |page|
        releases = JSON.parse(answer.call((page == 1) ? url : "#{url}&page=#{page}"))
        listed.concat(releases)
        return JSON.generate(listed) if releases.size < PAGE
      end
      raise Error, "#{url} lists more than #{PAGES} pages of releases"
    rescue JSON::ParserError => e
      raise Error, "#{url} answered with no JSON: #{e.message}"
    end

    # Every version the upstream's answer +body+ lists, for a pin that
    # holds +current+.
    def versions(body, current = nil)
      found = github? ? tags(body, current) : body.scan(pattern).map { |match| match[pattern.names.index("version")] }
      raise Error, "#{url} lists no version that #{pattern.source} matches" if found.empty?

      found.uniq
    end

    # The URL of each release's tarball in the answer +body+, from the
    # pattern's url capture, for an upstream that is dated by its files
    # (modified).
    def tarballs(body)
      body.to_enum(:scan, pattern).to_h { Regexp.last_match.values_at(:version, :url) }
    end

    # The day each version the answer +body+ lists came out, as GitHub
    # dates a release; a page dates none.
    def dates(body, current = nil)
      return {} unless github?

      releases(body, current).to_h { |version, release| [version, release["published_at"]&.slice(0, 10)] }.compact
    end

    private def tags(body, current)
      releases(body, current).map(&:first)
    end

    # The releases of +body+ the watch takes, each with its version: no
    # draft, and no release GitHub marks as a prerelease unless the pin is
    # a prerelease too, or it is another build of the pin's own release,
    # which an upstream marks as it marked the pin's, as jdx/ruby marks
    # every build of a preview.
    private def releases(body, current)
      JSON.parse(body).reject { |release| release["draft"] }.filter_map do |release|
        version = release.fetch("tag_name")[pattern, "version"] or next
        next if release["prerelease"] && !(current && (rebuild?(version, current) || prerelease?(current)))

        [version, release]
      end
    rescue JSON::ParserError => e
      raise Error, "#{url} answered with no JSON: #{e.message}"
    end

    private def prerelease?(version)
      Gem::Version.new(version.tr("-", ".")).prerelease?
    rescue ArgumentError
      false
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

    # The Last-Modified header of the file at +url+, from one HEAD
    # request, which follows redirects as a GET does; an error when the
    # answer has none, since nothing else dates the file.
    def last_modified(url)
      get(url, verb: Net::HTTP::Head) { |response| response["last-modified"] } or raise Error, "#{url} sent no Last-Modified"
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
    # order it holds them, each with its bytes when +read+, a pattern,
    # matches its path, and nil otherwise; read with RubyGems' tar reader
    # from a copy kept in a folder of its own and removed. GNU tar writes
    # a path longer than a header holds as an entry of type L before the
    # entry it names, which RubyGems' reader yields as an entry of its
    # own, ././@LongLink; its bytes are the next entry's path.
    def members(url, read = nil)
      Dir.mktmpdir("pin-move") do |folder|
        archive = File.join(folder, "archive")
        get(url) { |response| File.open(archive, "wb") { |file| response.read_body { |chunk| file.write(chunk) } } }
        Zlib::GzipReader.open(archive) do |gzip|
          long = nil
          Gem::Package::TarReader.new(gzip).each_with_object({}) do |entry, files|
            next long = entry.read.to_s.sub(/\0+\z/, "") if entry.header.typeflag == "L"

            path = long || entry.full_name
            long = nil
            files[path] = (read && entry.file? && path.match?(read)) ? entry.read.to_s.b : nil
          end
        end
      end
    rescue Zlib::Error, Gem::Package::Error => e
      raise Error, "#{url} is no gzipped tarball: #{e.message}"
    end

    private def get(url, redirects = REDIRECTS, verb: Net::HTTP::Get, &read)
      uri = URI(url)
      Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: @timeout, read_timeout: @timeout) do |http|
        http.request(request(uri, verb)) do |response|
          return read.call(response) if response.is_a?(Net::HTTPSuccess)
          return get(URI.join(url, response["location"]).to_s, redirects - 1, verb:, &read) if response.is_a?(Net::HTTPRedirection) && redirects.positive?

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

    # Whether +name+ is a program on PATH. On Windows a name is tried
    # with each extension PATHEXT lists, as cmd does, so zstd is found
    # as zstd.exe.
    private def tool?(name)
      extensions = ["", *(ENV.fetch("PATHEXT", "").split(File::PATH_SEPARATOR) if Gem.win_platform?)]
      ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).product(extensions).map { |folder, extension| File.join(folder, name + extension) }
        .any? { |path| File.file?(path) && File.executable?(path) }
    end

    private def request(uri, verb)
      request = verb.new(uri)
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
    upstreams = watched(file.fetch("watched"), sources).map { |name, entry| Upstream.from(name, entry) }
    new(sources:, upstreams:, unwatched: file.fetch("unwatched"))
  end

  # The watched upstreams of runtime/upstreams.yml's +entries+, by name,
  # each entry with apk made one upstream for each package of the mapping
  # +sources+ holds at its pin, named for that package's path there.
  def self.watched(entries, sources)
    entries.flat_map do |name, entry|
      next [[name, entry]] unless entry["apk"]

      path = entry.fetch("pins").first
      sources.dig(*path.split(".")).keys.map do |package|
        ["#{path}.#{package}", entry.merge("pins" => ["#{path}.#{package}"], "package" => package, "names" => ["Alpine's #{package}", package])]
      end
    end.to_h
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
  # could not be read, a held pin is overdue, or a pin's line has ended,
  # since a person is needed; else 3 when a pin is behind, for the move;
  # and else 0.
  def self.exit_status(report)
    statuses = report.map(&:status)
    if statuses.intersect?(%i[error overdue ended]) then 1
    elsif statuses.include?(:newer) then 3
    else 0
    end
  end

  # Whether a pin behind since +since+, the day its oldest newer release
  # came out, has been behind for longer than HELD_DAYS on +today+; never
  # when its upstream dates no release.
  def self.overdue?(since, today)
    !since.nil? && today - Date.iso8601(since) > HELD_DAYS
  end

  # What each upstream has released, asking +fetch+ once for each URL, as
  # it stands on +today+.
  def run(fetch, today: Date.today)
    answers = Hash.new { |cache, url| cache[url] = fetch.call(url) }
    days = Hash.new { |cache, url| cache[url] = day(fetch.last_modified(url), url) }
    upstreams.map { |upstream| find(upstream, answers, days, today) }
  end

  # The version the pins of +upstream+ hold.
  def current(upstream)
    values = upstream.pins.map { |pin| version_of(upstream, pin) }.uniq
    raise Error, "#{upstream.pins.join(', ')} hold different versions: #{values.join(', ')}" unless values.one?

    values.first
  end

  private def find(upstream, answers, days, today)
    current = current(upstream)
    return finding(upstream, current:, newer: upstream.package.newer(current) { |url| answers[url] }) if upstream.package

    body = upstream.listing { |url| answers[url] }
    newer = upstream.versions(body, current).select { |version| newer?(version, current) }
    in_line, beyond = newer.partition { |version| same_line?(upstream, version, current) }
    # A hold is for a new release; another build of the pinned one moves
    # as any pin does, and a held new release is reported once it has.
    rebuilds = in_line.select { |version| upstream.rebuild?(version, current) }
    return finding(upstream, current:, newer: newest(rebuilds), beyond: newest(beyond), held: nil) if upstream.hold && rebuilds.any?

    dates = upstream.dates(body, current)
    # An upstream that dates no release in its listing is dated by its
    # files: each newer release in the line by its tarball's Last-Modified.
    dates = upstream.tarballs(body).slice(*in_line).transform_values { |tarball| days[tarball] } if upstream.modified
    since = dates.values_at(*in_line).compact.min
    quiet = Quiet.from(dates) { |version| place(upstream, version, current) } if upstream.line && in_line.empty? && beyond.any?
    finding(upstream, current:, newer: newest(in_line), beyond: newest(beyond), since:, overdue: PinWatch.overdue?(since, today),
      last: quiet&.last&.iso8601, ended: quiet&.ended?(today) || false)
  rescue Error => e
    finding(upstream, current:, error: e.message)
  end

  # The day, as an ISO 8601 date, of +header+, a Last-Modified header of
  # the file at +url+ (an HTTP date, always GMT).
  private def day(header, url)
    Time.httpdate(header).utc.to_date.iso8601
  rescue ArgumentError
    raise Error, "#{url} sent a Last-Modified that is no HTTP date: #{header}"
  end

  private def finding(upstream, current: nil, newer: nil, beyond: nil, error: nil, since: nil, overdue: false, held: upstream.hold,
    last: nil, ended: false
  )
    Finding.new(name: upstream.name, pins: upstream.pins, ships: upstream.ships, current:, newer:, beyond:, error:,
      held:, since:, overdue:, last:, ended:)
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

    place(upstream, version, current).zero?
  end

  # Whether the line of +version+ is older than the pin's, at +current+
  # (-1), the same (0), or newer (1).
  private def place(upstream, version, current)
    numbers(version).first(upstream.line) <=> numbers(current).first(upstream.line)
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
# line of a pin nobody holds, and 1 when one could not be read, a held
# pin has been behind for longer than PinWatch::HELD_DAYS, or a pin's
# line has ended (PinWatch::Quiet).
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
      finding.last && "(its line last released on #{finding.last})",
      ("its line has ended, and a person moves the pin to a newer one" if finding.ended),
      finding.error,
      finding.newer && finding.since && "(since #{finding.since})",
      finding.newer && finding.held && "held for a person, who has #{PinWatch::HELD_DAYS} days: #{finding.held}",
].compact.join(" ")
  end
  exit PinWatch.exit_status(report)
end
