# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "test_helper"
require_relative "support/loopback_server"
require_relative "../tasks/pin_watch"
require "stringio"

# The watch that finds a pin upstream has released a newer version of
# (doc/contributors/design/runtimes.md, "Keeping the pins current"),
# against what each upstream answered on 2026-11-22, saved in
# test/fixtures/pin_watch with each answer cut down to what the watch
# reads: the tags and flags of GitHub's releases, and the lines of each
# page that name a version.
class PinWatchTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  ANSWERS = File.join(__dir__, "fixtures/pin_watch")

  # Serves each URL its saved answer, or the body +bodies+ gives it, and
  # counts the requests.
  class Answers
    attr_reader :asked

    def initialize(bodies = {})
      @bodies = bodies
      @asked = []
    end

    def call(url)
      @asked << url
      body = @bodies.fetch(url) { File.binread(File.join(ANSWERS, url.sub(%r{\Ahttps://}, "").gsub(/[^A-Za-z0-9.]+/, "_"))) }
      raise body if body.is_a?(Exception)

      body
    end
  end

  def watch(sources, upstreams)
    PinWatch.new(sources:, upstreams: upstreams.map { |name, entry| PinWatch::Upstream.from(name, entry) }, unwatched: {})
  end

  def entry(name)
    YAML.safe_load_file(File.join(ROOT, "runtime/upstreams.yml")).fetch("watched").fetch(name)
  end

  def finding(sources, name, upstream = entry(name), answers = Answers.new)
    watch(sources, name => upstream).run(answers).first
  end

  def test_every_component_of_the_pins_is_watched_or_says_why_not
    watch = PinWatch.load(ROOT)
    named = watch.upstreams.flat_map(&:pins) + watch.unwatched.keys

    assert_includes watch.components, "mobile.xcode", "a plain value is a component"
    assert_includes watch.components, "windows-dlls.libz-1.dll", "a mapping of components is not one"
    assert_empty watch.unaccounted, "runtime/upstreams.yml names neither where these are released nor why they are not watched"
    assert_empty named - watch.components, "runtime/upstreams.yml names what runtime/sources.yml does not pin"
  end

  def test_todays_pins_and_todays_answers_leave_no_upstream_unread
    report = PinWatch.load(ROOT).run(Answers.new)

    assert_equal PinWatch.load(ROOT).upstreams.map(&:name), report.map(&:name)
    assert_empty report.select(&:error).map { |f| "#{f.name}: #{f.error}" }
  end

  def test_a_newer_release_in_the_line_is_the_next_version_and_a_newer_line_is_only_reported
    sources = { "mobile" => { "openssl" => { "version" => "3.6.4" } }, "musl-ruby" => { "openssl" => { "version" => "3.6.4" } } }
    found = finding(sources, "openssl")

    assert_equal [:newer, "3.6.4", "3.6.5", "4.1.0"], [found.status, found.current, found.newer, found.beyond]

    newest = finding(sources.transform_values { { "openssl" => { "version" => "3.6.5" } } }, "openssl")

    assert_equal [:beyond, nil, "4.1.0"], [newest.status, newest.newer, newest.beyond]
  end

  # zlib's deflateInit_ and inflateInit_ refuse a caller built against
  # another first character of the version (deflate.c, my_version[0]),
  # and its soname is libz.so.1; libxcrypt keeps libcrypt.so.1 through
  # 4.x, and a new soname would be another major. So each takes any
  # release of its major and reports the next major (runtimes.md,
  # "Keeping the pins current").
  def test_zlib_and_libxcrypt_take_any_release_of_their_major_and_report_the_next_major
    releases = -> (*tags) { JSON.generate(tags.map { |tag| { "tag_name" => tag, "draft" => false, "prerelease" => false } }) }
    url = -> (repository) { "https://api.github.com/repos/#{repository}/releases?per_page=100" }
    zlib = finding({ "musl-ruby" => { "zlib" => { "version" => "1.3.2" } } }, "zlib", entry("zlib"), Answers.new(url.("madler/zlib") => releases.("v2.0", "v1.4", "v1.3.2")))
    xcrypt = finding({ "libxcrypt" => { "version" => "4.4.38" } }, "libxcrypt", entry("libxcrypt"), Answers.new(url.("besser82/libxcrypt") => releases.("v5.0.0", "v4.5.2", "v4.4.38")))

    assert_equal [:newer, "1.4", "2.0"], [zlib.status, zlib.newer, zlib.beyond]
    assert_equal [:newer, "4.5.2", "5.0.0"], [xcrypt.status, xcrypt.newer, xcrypt.beyond]
  end

  def test_a_prerelease_counts_only_for_a_pin_that_is_one
    libyaml = finding({ "mobile" => { "libyaml" => { "version" => "0.2.5" } } }, "libyaml", entry("libyaml").merge("pins" => ["mobile.libyaml"]))
    agp = finding({ "mobile" => { "agp" => "9.4.1" } }, "agp")
    preview = "ruby-4.1.0-preview2\thttps://cache.ruby-lang.org/pub/ruby/4.1/ruby-4.1.0-preview2.tar.gz\tx\n"
    ruby = -> (version, body) { finding({ "ruby" => { "version" => version } }, "ruby", entry("ruby").merge("pins" => ["ruby"]), Answers.new(entry("ruby")["page"] => body)) }

    assert_equal "0.2.6", libyaml.newer, "GitHub marks 0.2.6-rc.1 a prerelease"
    assert_equal "9.5.2", agp.newer, "9.6.0-alpha05 is a prerelease"
    assert_equal "4.1.0-preview2", ruby.("4.1.0-preview1", preview).newer
    assert_nil ruby.("4.0.0", "ruby-4.0.1\turl.tar.gz\tx\n#{preview}").beyond, "a prerelease does not count for a release"
  end

  def test_versions_are_compared_as_numbers_dates_included
    found = finding({ "mobile" => { "ca-certificates" => { "version" => "cacert-2026-03-19" } } }, "ca-certificates",
      entry("ca-certificates").merge("pins" => ["mobile.ca-certificates"]))
    llvm = finding({ "llvm-readobj" => { "version" => "23.1.4" } }, "llvm-readobj")

    assert_equal ["2026-03-19", "2026-11-05"], [found.current, found.newer]
    assert_equal "23.1.6", llvm.newer, "23.1.10 would be newer still, not older"
  end

  def test_a_listing_names_only_what_its_pattern_takes
    stable = '<remotePackage path="ndk;30.0.1"><channelRef ref="channel-0"/></remotePackage>'
    beta = '<remotePackage path="ndk;31.0.1"><channelRef ref="channel-1"/></remotePackage>'
    found = finding({ "mobile" => { "ndk" => { "revision" => "29.0.1" } } }, "ndk", entry("ndk"),
      Answers.new(entry("ndk")["page"] => "#{beta}\n#{stable}\n"))
    # rv-ruby, the Mac's Ruby until 2026-11-22, as runtime/upstreams.yml
    # watched it: its listing has a rolling tag beside its dated ones.
    rv_ruby = { "pins" => ["ruby"], "field" => "release", "github" => "spinel-coop/rv-ruby", "tag" => '\A(?<version>\d{8})\z' }
    rv = finding({ "ruby" => { "release" => "20261023" } }, "rv-ruby", rv_ruby)

    assert_equal "30.0.1", found.newer, "only the stable channel counts"
    assert_equal "20261119", rv.newer, "rubies, the rolling tag, is not a version"
  end

  def test_pins_that_disagree_are_an_error
    sources = { "mobile" => { "libffi" => { "version" => "3.5.2" } }, "musl-ruby" => { "libffi" => { "version" => "3.5.1" } } }
    found = finding(sources, "libffi")

    assert_equal :error, found.status
    assert_equal "mobile.libffi, musl-ruby.libffi hold different versions: 3.5.2, 3.5.1", found.error
  end

  def test_an_upstream_that_cannot_be_read_is_an_error_and_the_rest_are_still_asked
    sources = { "libxcrypt" => { "version" => "4.5.1" }, "rcedit" => { "version" => "2.0.0" }, "nsis" => { "version" => "3.13" } }
    upstreams = %w[libxcrypt rcedit nsis].to_h { |name| [name, entry(name)] }
    answers = Answers.new(PinWatch::Upstream.from("libxcrypt", entry("libxcrypt")).url => PinWatch::Error.new("answered 503"),
      entry("nsis")["page"] => "<rss>nothing</rss>")
    report = watch(sources, upstreams).run(answers)

    assert_equal %i[error current error], report.map(&:status)
    assert_equal "answered 503", report[0].error
    assert_match(/lists no version that/, report[2].error)
  end

  def test_each_url_is_asked_once
    sources = { "mobile" => { "openssl" => { "version" => "3.6.5" } }, "musl-ruby" => { "openssl" => { "version" => "3.6.5" } } }
    answers = Answers.new
    watch(sources, "openssl" => entry("openssl"), "also" => entry("openssl")).run(answers)

    assert_equal ["https://api.github.com/repos/openssl/openssl/releases?per_page=100"], answers.asked
  end

  def test_the_fetch_follows_a_redirect_and_refuses_a_failure
    server = LoopbackServer.new("/moved" => [302, { "Location" => "/here" }, ""], "/here" => [200, {}, "listing"], "/gone" => [404, {}, "no"])
    fetch = PinWatch::Fetch.new(timeout: 5)

    assert_equal "listing", fetch.call(server.url("/moved"))
    error = assert_raises(PinWatch::Error) { fetch.call(server.url("/gone")) }
    assert_equal "#{server.url('/gone')} answered 404", error.message
  ensure
    server&.stop
  end

  # GitHub's API answers 403 or 429 with x-ratelimit-remaining 0 when a
  # caller's allowance is spent ("Rate limits for the REST API",
  # docs.github.com), which the run's reader must not take for a
  # missing release.
  def test_the_fetch_says_when_a_rate_limit_is_spent
    spent = { "x-ratelimit-remaining" => "0", "x-ratelimit-reset" => "1795368308" }
    server = LoopbackServer.new("/spent" => [403, spent, "{}"], "/slow" => [429, spent, "{}"], "/denied" => [403, {}, "no"])
    anonymous = PinWatch::Fetch.new(timeout: 5)
    with_token = PinWatch::Fetch.new(token: "t", timeout: 5)

    error = assert_raises(PinWatch::Error) { anonymous.call(server.url("/spent")) }
    assert_equal "#{server.url('/spent')} answered 403: its rate limit for this caller is spent until 2026-11-22T17:25:08Z, " \
      "and it was asked with no token (GITHUB_TOKEN), which GitHub allows 60 requests an hour", error.message
    error = assert_raises(PinWatch::Error) { with_token.call(server.url("/slow")) }
    assert_equal "#{server.url('/slow')} answered 429: its rate limit for this caller is spent until 2026-11-22T17:25:08Z",
      error.message
    assert_equal "#{server.url('/denied')} answered 403", assert_raises(PinWatch::Error) { anonymous.call(server.url("/denied")) }.message
  ensure
    server&.stop
  end

  HELD = { "pins" => ["tool"], "github" => "owner/tool", "tag" => '\Av(?<version>\d+\.\d+\.\d+)\z', "hold" => "A person reads its release notes." }.freeze

  def releases(*dated)
    JSON.generate(dated.map { |tag, published| { "tag_name" => tag, "draft" => false, "prerelease" => false, "published_at" => published } })
  end

  def test_a_held_pin_behind_is_reported_and_fails_only_once_it_has_been_behind_longer_than_the_stated_days
    body = releases(["v1.0.6", "2026-11-17T16:32:45Z"], ["v1.0.5", "2026-11-03T21:35:47Z"], ["v1.0.4", "2026-10-20T13:03:13Z"])
    answers = Answers.new(PinWatch::Upstream.from("tool", HELD).url => body)
    held = -> (today) { watch({ "tool" => { "version" => "1.0.4" } }, "tool" => HELD).run(answers, today:).first }
    day = Date.new(2026, 11, 3) + PinWatch::HELD_DAYS

    assert_equal [:held, "1.0.6", "2026-11-03", "A person reads its release notes."],
      [held.(day).status, held.(day).newer, held.(day).since, held.(day).held], "behind since the oldest release newer than the pin"
    assert_equal :overdue, held.(day + 1).status
    assert_equal :newer, watch({ "tool" => { "version" => "1.0.4" } }, "tool" => HELD.except("hold")).run(answers, today: day + 1).first.status,
      "a pin nobody holds is the move's, however long it has been behind"
  end

  def test_the_watch_fails_for_an_unread_upstream_or_an_overdue_hold_and_not_for_a_hold_in_time
    found = -> (status) { Struct.new(:status).new(status) }

    assert_equal 0, PinWatch.exit_status([found.(:current), found.(:held), found.(:beyond)])
    assert_equal 3, PinWatch.exit_status([found.(:held), found.(:newer)])
    assert_equal 1, PinWatch.exit_status([found.(:newer), found.(:overdue)])
    assert_equal 1, PinWatch.exit_status([found.(:newer), found.(:error)])
  end

  # An Alpine index as Alpine serves one: a gzip member holding the
  # signature's tar entry, with no end of archive, then one holding the
  # index, whose blocks +served+ gives as package => version.
  def apkindex(served)
    text = served.map { |package, version| "P:#{package}\nV:#{version}\nA:x86_64\nt:1763000000\n\n" }.join
    gzip = lambda do |entries, close|
      tar = StringIO.new(+"".b)
      writer = Gem::Package::TarWriter.new(tar)
      entries.each { |name, body| writer.add_file_simple(name, 0o644, body.bytesize) { |io| io.write(body) } }
      writer.close if close
      Zlib.gzip(tar.string)
    end
    gzip.([[".SIGN.RSA.key.rsa.pub", "signature"]], false) + gzip.([["DESCRIPTION", "v3.24"], ["APKINDEX", text]], true)
  end

  def alpine(version, x86_64:, aarch64: x86_64, community: {})
    sources = { "alpine-packages" => { "glib" => version } }
    entries = { "alpine-packages" => entry("alpine-packages") }
    upstreams = PinWatch.watched(entries, sources).map { |name, upstream| PinWatch::Upstream.from(name, upstream) }
    bodies = { "x86_64" => x86_64, "aarch64" => aarch64 }.flat_map do |arch, served|
      %w[main community].map do |repository|
        url = "https://dl-cdn.alpinelinux.org/alpine/v3.24/#{repository}/#{arch}/APKINDEX.tar.gz"
        [url, apkindex((repository == "main") ? { "glib" => served }.compact : community)]
      end
    end
    PinWatch.new(sources:, upstreams:, unwatched: {}).run(Answers.new(bodies.to_h)).first
  end

  def test_an_alpine_package_is_behind_when_its_branch_serves_another_build_and_ahead_of_nothing
    rebuilt = alpine("2.88.4-r0", x86_64: "2.88.4-r1")
    older = alpine("2.88.4-r1", x86_64: "2.88.4-r0")

    assert_equal ["alpine-packages.glib", ["alpine-packages.glib"], :newer, "2.88.4-r0", "2.88.4-r1"],
      [rebuilt.name, rebuilt.pins, rebuilt.status, rebuilt.current, rebuilt.newer], "the branch keeps only its newest build"
    assert_equal "2.88.4-r0", older.newer, "what the branch serves is the only build that installs, whatever its number"
    assert_equal :current, alpine("2.88.4-r1", x86_64: "2.88.4-r1").status
  end

  def test_an_alpine_package_its_architectures_serve_differently_or_not_at_all_is_an_error
    apart = alpine("2.88.4-r0", x86_64: "2.88.4-r1", aarch64: "2.88.4-r0")
    missing = alpine("2.88.4-r0", x86_64: nil)

    assert_equal "Alpine's indexes serve glib 2.88.4-r1 on x86_64 and 2.88.4-r0 on aarch64, and no one build of it on every architecture", apart.error
    assert_equal "Alpine's indexes serve no glib on x86_64 or on aarch64", missing.error
    assert_equal :current, alpine("2.88.4-r0", x86_64: nil, community: { "glib" => "2.88.4-r0" }).status, "a package may be in either repository"
  end

  def test_every_package_alpine_packages_sh_installs_is_pinned_and_every_pin_is_installed
    script = File.read(File.join(ROOT, ".github/scripts/alpine-packages.sh"))
    installed = script.scan(/^\s+\w+\) names="([^"]*)"/).flatten.flat_map(&:split).uniq
    pinned = YAML.safe_load_file(File.join(ROOT, "runtime/sources.yml")).fetch("alpine-packages").keys

    refute_empty installed
    assert_equal pinned.sort, installed.sort
  end

  def test_every_held_pin_is_dated_by_a_held_upstream_whose_releases_github_dates
    upstreams = PinWatch.load(ROOT).upstreams
    dated = upstreams.select { |upstream| upstream.hold && upstream.github? }.flat_map(&:pins)
    undated = upstreams.select(&:hold).reject { |upstream| upstream.github? || upstream.pins.intersect?(dated) }

    assert_empty undated.map(&:name), "a held pin nothing dates could stay behind for ever and never call a person"
  end
end
