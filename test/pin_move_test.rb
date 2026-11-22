# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require "tmpdir"
require_relative "test_helper"
require_relative "support/loopback_server"
require_relative "../tasks/pin_move"

# The move of a pin the watch found behind (doc/contributors/design/
# runtimes.md, "Keeping the pins current"), on small checkouts written
# here, with upstreams' answers given by each test: the assets and
# digests are what GitHub listed for libffi and llvm-mingw on
# 2026-11-22.
class PinMoveTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  LIBFFI = "https://api.github.com/repos/libffi/libffi/releases?per_page=100"
  LIBFFI_381 = "https://github.com/libffi/libffi/releases/download/v3.8.1/libffi-3.8.1.tar.gz"
  LIBFFI_381_SHA256 = "81e879c094cc5ec3186c48510c6385ac6b3e866192e8bc71a35245703757ee40"
  OLD_SHA256 = "f3a3082a23b37c293a4fcd1053147b371f2ff91fa7ea1b2a52e335676bac82dc"

  SOURCES = <<~YAML
    # The phone runtimes' libraries.
    mobile:
      # libffi, for fiddle.
      libffi:
        version: 3.5.2
        url: https://github.com/libffi/libffi/releases/download/v3.5.2/libffi-3.5.2.tar.gz
        sha256: #{OLD_SHA256}
      agp: 9.4.1
      gradle:
        version: 9.8.2
        url: https://services.gradle.org/distributions/gradle-9.8.2-bin.zip
        sha256: 21bd5da2de49b642904077f38c0efdc7778e92b3ed0889392dca61b97e389607
        wrapper_sha256: 3b8a25775a69158b5ad2b1d17a80a88dc7b40a352a73eb27d06c612a7ce68e98
    musl-ruby:
      libffi:
        version: 3.5.2
        url: https://github.com/libffi/libffi/releases/download/v3.5.2/libffi-3.5.2.tar.gz
        sha256: #{OLD_SHA256}
      ca-certificates:
        version: cacert-2026-03-19
        url: https://curl.se/ca/cacert-2026-03-19.pem
        sha256: b6e66569cc3d438dd5abe514d0df50005d570bfc96c14dca8f768d020cb96171
    other:
      version: 3.5.2
  YAML

  LICENSES = <<~YAML
    components:
      - id: libffi
        name: libffi, as rv-ruby compiles it
        version: 3.5.2
        evidence: "3.5.2\\0"
        platforms: [x86_64-linux]

      - id: libffi-musl
        name: libffi, as Fledge compiles it
        version: 3.5.2
        download: https://github.com/libffi/libffi/releases/download/v3.5.2/libffi-3.5.2.tar.gz
        evidence: "3.5.2\\0"
  YAML

  CHANGELOG = <<~MARKDOWN
    # Changelog

    ## [Unreleased]

    ### Fixed

    - Something.

    ## [0.17.0] - 2026-11-22
  MARKDOWN

  # Serves each URL the body a test gives it, and the SHA-256 of each
  # URL it is asked to download.
  class Answers
    attr_reader :downloaded

    def initialize(bodies, sums = {})
      @bodies = bodies
      @sums = sums
      @downloaded = []
    end

    def call(url) = @bodies.fetch(url)

    def sha256(url)
      @downloaded << url
      @sums.fetch(url)
    end
  end

  def libffi_releases(digest: "sha256:#{LIBFFI_381_SHA256}")
    JSON.generate([{ "tag_name" => "v3.8.1", "assets" => [{ "browser_download_url" => LIBFFI_381, "digest" => digest }] }])
  end

  def entries
    YAML.safe_load_file(File.join(ROOT, "runtime/upstreams.yml")).fetch("watched")
  end

  def checkout(files = {})
    Dir.mktmpdir do |root|
      { "runtime/sources.yml" => SOURCES, "runtime/licenses.yml" => LICENSES, "CHANGELOG.md" => CHANGELOG }.merge(files).each do |path, text|
        FileUtils.mkdir_p(File.dirname(File.join(root, path)))
        File.write(File.join(root, path), text)
      end
      yield root
    end
  end

  def finding(name, current, newer) = { "name" => name, "status" => "newer", "current" => current, "newer" => newer }

  # The pins and entries the small checkout has, in place of the
  # repository's.
  SMALL = { "libffi" => { "licenses" => ["libffi-musl"] }, "ca-certificates" => { "pins" => ["musl-ruby.ca-certificates"] } }.freeze

  def mover(root, answers, overrides = {})
    changes = SMALL.merge(overrides)
    PinMove.new(root, entries.merge(changes) { |_, entry, change| entry.merge(change) }, answers)
  end

  def test_a_move_rewrites_each_pin_its_licenses_and_the_changelog_from_githubs_digest
    checkout do |root|
      move = mover(root, Answers.new(LIBFFI => libffi_releases))
      changed = move.call(finding("libffi", "3.5.2", "3.8.1"))
      move.save
      sources = File.read(File.join(root, "runtime/sources.yml"))

      assert_equal %w[runtime/sources.yml runtime/licenses.yml CHANGELOG.md], changed.keys
      assert_equal 2, sources.scan("version: 3.8.1\n").size
      assert_equal 2, sources.scan("url: #{LIBFFI_381}\n").size
      assert_equal 2, sources.scan("sha256: #{LIBFFI_381_SHA256}\n").size
      assert_includes sources, "  # libffi, for fiddle.\n"
      assert_includes sources, "other:\n  version: 3.5.2\n"
      licenses = File.read(File.join(root, "runtime/licenses.yml"))

      assert_includes licenses, "as rv-ruby compiles it\n    version: 3.5.2\n    evidence: \"3.5.2\\0\""
      assert_includes licenses, "    version: 3.8.1\n    download: #{LIBFFI_381}\n    evidence: \"3.8.1\\0\""
      assert_includes File.read(File.join(root, "CHANGELOG.md")), "## [Unreleased]\n\n### Changed\n\n- libffi 3.8.1, from 3.5.2.\n\n### Fixed\n"
    end
  end

  def test_a_quoted_version_keeps_its_quotes
    old = "https://github.com/mstorsjo/llvm-mingw/releases/download/20261020/llvm-mingw-20261020-ucrt-ubuntu-22.04-x86_64.tar.xz"
    new = "https://github.com/mstorsjo/llvm-mingw/releases/download/20261117/llvm-mingw-20261117-ucrt-ubuntu-22.04-x86_64.tar.xz"
    sources = "llvm-mingw:\n  version: \"20261020\"\n  hosts:\n    x86_64-linux:\n      url: #{old}\n      sha256: #{'5c' * 32}\n"
    releases = JSON.generate([
{
"tag_name" => "20261117",
"assets" => [
{
"browser_download_url" => new,
"digest" => "sha256:e7a15a49a2ea95e9f3d8a9d0cfabe5052a4b10fb4777cc54de5a8c27b64bb701",
},
],
},
])
    checkout("runtime/sources.yml" => sources, "runtime/licenses.yml" => "  - id: compiler-rt\n    version: \"20261020\"\n") do |root|
      move = mover(root, Answers.new("https://api.github.com/repos/mstorsjo/llvm-mingw/releases?per_page=100" => releases))
      move.call(finding("llvm-mingw", "20261020", "20261117"))

      assert_equal "llvm-mingw:\n  version: \"20261117\"\n  hosts:\n    x86_64-linux:\n      url: #{new}\n" \
        "      sha256: e7a15a49a2ea95e9f3d8a9d0cfabe5052a4b10fb4777cc54de5a8c27b64bb701\n", move.read("runtime/sources.yml")
    end
  end

  def test_a_release_with_no_digest_is_downloaded_and_hashed
    checkout do |root|
      answers = Answers.new({ LIBFFI => libffi_releases(digest: nil) }, LIBFFI_381 => "ab" * 32)
      move = mover(root, answers)
      move.call(finding("libffi", "3.5.2", "3.8.1"))

      assert_equal [LIBFFI_381], answers.downloaded.uniq
      assert_equal 2, move.read("runtime/sources.yml").scan("sha256: #{'ab' * 32}\n").size
    end
  end

  def test_a_release_without_the_pinned_asset_moves_nothing
    checkout do |root|
      releases = JSON.generate([{ "tag_name" => "v3.8.1", "assets" => [] }])
      move = mover(root, Answers.new(LIBFFI => releases))
      error = assert_raises(PinMove::Error) { move.call(finding("libffi", "3.5.2", "3.8.1")) }

      assert_equal "#{LIBFFI} lists no asset #{LIBFFI_381}", error.message
      assert_equal SOURCES, move.read("runtime/sources.yml")
    end
  end

  def test_a_failed_move_leaves_what_an_earlier_one_wrote
    checkout do |root|
      move = mover(root, Answers.new(LIBFFI => libffi_releases), "zlib" => { "pins" => ["other"], "licenses" => ["zlib"] })
      move.call(finding("libffi", "3.5.2", "3.8.1"))
      after_libffi = move.texts.dup

      assert_raises(PinMove::Error) { move.call(finding("zlib", "3.5.2", "3.6.0")) }
      assert_equal after_libffi, move.texts
    end
  end

  def test_a_pin_named_in_a_pattern_and_a_sha256_beside_its_file
    checkout("runtime/licenses.yml" => "components:\n  - id: ca-certificates\n    version: cacert-2026-03-19\n") do |root|
      new_url = "https://curl.se/ca/cacert-2026-11-05.pem"
      move = mover(root, Answers.new("#{new_url}.sha256" => "#{'cd' * 32}  cacert-2026-11-05.pem\n"))
      move.call(finding("ca-certificates", "2026-03-19", "2026-11-05"))
      sources = move.read("runtime/sources.yml")

      assert_includes sources, "    version: cacert-2026-11-05\n    url: #{new_url}\n    sha256: #{'cd' * 32}\n"
      assert_includes move.read("runtime/licenses.yml"), "version: cacert-2026-11-05"
      assert_includes move.read("CHANGELOG.md"), "- Mozilla's CA certificates 2026-11-05, from 2026-03-19.\n"
    end
  end

  def test_gradle_moves_its_wrappers_properties_and_keeps_the_wrapper
    properties = "distributionSha256Sum=21bd5da2de49b642904077f38c0efdc7778e92b3ed0889392dca61b97e389607\n" \
      "distributionUrl=https\\://services.gradle.org/distributions/gradle-9.8.2-bin.zip\n"
    path = "lib/fledge/templates/android/gradle/wrapper/gradle-wrapper.properties"
    checkout(path => properties) do |root|
      new_url = "https://services.gradle.org/distributions/gradle-9.9.2-bin.zip"
      move = mover(root, Answers.new("#{new_url}.sha256" => "ef" * 32))
      move.call(finding("gradle", "9.8.2", "9.9.2"))

      assert_equal "distributionSha256Sum=#{'ef' * 32}\ndistributionUrl=https\\://services.gradle.org/distributions/gradle-9.9.2-bin.zip\n", move.read(path)
      assert_includes move.read("runtime/sources.yml"), "sha256: #{'ef' * 32}\n    wrapper_sha256: 3b8a25775a69158b5ad2b1d17a80a88dc7b40a352a73eb27d06c612a7ce68e98\n"
    end
  end

  def test_a_plain_value_pin_and_a_file_whose_pattern_no_longer_matches
    path = "lib/fledge/mobile_project/android.rb"
    checkout(path => "      AGP = \"9.4.1\"\n") do |root|
      move = mover(root, Answers.new({}))
      move.call(finding("agp", "9.4.1", "9.5.2"))

      assert_includes move.read("runtime/sources.yml"), "  agp: 9.5.2\n"
      assert_equal "      AGP = \"9.5.2\"\n", move.read(path)
    end
    checkout(path => "      AGP = \"9.3.0\"\n") do |root|
      error = assert_raises(PinMove::Error) { mover(root, Answers.new({})).call(finding("agp", "9.4.1", "9.5.2")) }

      assert_match(/\A#{path} has nothing .* matches with 9\.4\.1\z/, error.message)
    end
  end

  def test_a_key_beside_the_url_that_the_move_cannot_know_stops_it
    sources = SOURCES.sub("version: 3.5.2\n    url:", "version: 3.5.2\n    file_sha256: 00\n    url:")
    checkout("runtime/sources.yml" => sources) do |root|
      error = assert_raises(PinMove::Error) { mover(root, Answers.new(LIBFFI => libffi_releases)).call(finding("libffi", "3.5.2", "3.8.1")) }

      assert_match(/stands beside file_sha256, which a move cannot know\z/, error.message)
    end
  end

  def test_a_held_upstream_is_refused_with_its_reason
    checkout do |root|
      move = mover(root, Answers.new({}))
      error = assert_raises(PinMove::Error) { move.call(finding("ruby", "4.1.0-preview1", "4.1.0-preview2")) }

      assert_match(/\Aruby is held: A move of Ruby is planned work/, error.message)
      assert_includes move.movable, "libffi"
      refute_includes move.movable, "ruby"
    end
  end

  def test_a_second_move_before_a_release_keeps_the_version_the_changelog_moved_from
    checkout("lib/fledge/mobile_project/android.rb" => "AGP = \"9.4.1\"\n") do |root|
      move = mover(root, Answers.new({}))
      move.call(finding("agp", "9.4.1", "9.5.0"))
      move.call(finding("agp", "9.5.0", "9.5.2"))

      assert_equal 1, move.read("CHANGELOG.md").scan("Android Gradle plugin").size
      assert_includes move.read("CHANGELOG.md"), "- Android Gradle plugin 9.5.2, from 9.4.1.\n"
    end
  end

  # What the move needs of this checkout holds for every upstream it may
  # move: each licenses entry names the pin's version, and each pattern
  # of each other file captures it.
  def test_every_movable_pin_is_named_where_the_move_will_look
    watch = PinWatch.load(ROOT)
    licenses = File.read(File.join(ROOT, "runtime/licenses.yml")).split(/(?=^  - id: )/)
    entries.each do |name, entry|
      next if entry["hold"]

      version = watch.current(watch.upstreams.find { |upstream| upstream.name == name })
      entry.fetch("licenses", []).each do |id|
        assert licenses.any? { |text| text.start_with?("  - id: #{id}\n") && text.include?(version) }, "runtime/licenses.yml's #{id} names no #{version}"
      end
      entry.fetch("also", {}).each do |path, patterns|
        text = File.read(File.join(ROOT, path))
        patterns.each { |pattern| assert_equal version, text[Regexp.new(pattern), :version], "#{path}: #{pattern}" }
      end
    end
  end

  # Where a line may name a pin's version beside the input's name: the
  # pins and the license map, which the move rewrites; the record of what
  # changed; and the documents kept as they were on their day.
  RECORDS = %w[
    CHANGELOG.md
    runtime/sources.yml
    runtime/licenses.yml
    doc/licensing.md
    doc/contributors/decisions.md
    doc/contributors/research
    doc/contributors/plan
    doc/contributors/drafts
    test/fixtures/pin_watch
    test/pin_watch_test.rb
    test/pin_move_test.rb
].freeze

  # A line that names the version a pin holds today goes false when the
  # move moves the pin, unless the move rewrites it too: so outside the
  # files above, only a file runtime/upstreams.yml gives the move (also),
  # or says names the version as a fact about that version (named), may.
  def test_a_movable_pin_is_named_only_where_the_move_rewrites_it
    watch = PinWatch.load(ROOT)
    named = entries.reject { |_, entry| entry["hold"] }.flat_map do |name, entry|
      version = watch.current(watch.upstreams.find { |upstream| upstream.name == name })
      words = Array(entry["names"] || name).map(&:downcase)
      left = RECORDS + entry.fetch("also", {}).keys + entry.fetch("named", [])
      found = IO.popen(["git", "-C", ROOT, "grep", "-n", "-I", "-w", "-F", "-e", version, "--", ".", *left.map { |path| ":!#{path}" }], &:read)
      found.lines.select { |line| words.any? { |word| line.downcase.include?(word) } }.map { |line| "#{name} #{version}: #{line[0, 150]}" }
    end

    assert_empty named, "a movable pin's version is named where a move leaves it"
  end

  def test_the_fetch_hashes_a_download_without_keeping_it
    server = LoopbackServer.new("/file" => [200, {}, "bytes of a release"])

    assert_equal Digest::SHA256.hexdigest("bytes of a release"), PinWatch::Fetch.new(timeout: 5).sha256(server.url("/file"))
  ensure
    server&.stop
  end
end
