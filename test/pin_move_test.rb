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

    def member_sha256(url, member)
      @downloaded << url
      @sums.fetch([url, member])
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

  def test_a_version_with_a_comment_after_it_moves_and_keeps_the_comment
    sources = SOURCES.sub("version: 3.5.2\n", "version: 3.5.2 # libffi's own tag\n")
    checkout("runtime/sources.yml" => sources) do |root|
      move = mover(root, Answers.new(LIBFFI => libffi_releases))
      move.call(finding("libffi", "3.5.2", "3.8.1"))

      assert_includes move.read("runtime/sources.yml"), "  libffi:\n    version: 3.8.1 # libffi's own tag\n"
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

  def test_an_alpine_package_moves_to_the_build_its_branch_serves_and_alone
    sources = "#{SOURCES}alpine-packages:\n  gcc: 15.2.0-r5\n  glib: 2.88.4-r0\n  glib-dev: 2.88.4-r0\n"
    checkout("runtime/sources.yml" => sources, "runtime/upstreams.yml" => File.read(File.join(ROOT, "runtime/upstreams.yml"))) do |root|
      move = PinMove.load(root, Answers.new({}))
      changed = move.call(finding("alpine-packages.glib", "2.88.4-r0", "2.88.4-r1"))

      assert_equal ["runtime/sources.yml"], changed.keys, "no Alpine package ships, so CHANGELOG.md stays"
      assert_equal sources.sub("glib: 2.88.4-r0", "glib: 2.88.4-r1"), move.read("runtime/sources.yml")
      assert_equal "chore: move Alpine's glib to 2.88.4-r1", move.message([finding("alpine-packages.glib", "2.88.4-r0", "2.88.4-r1")]).lines.first.chomp
    end
  end

  IMAGES = <<~YAML
    manylinux:
      version: 2026.11.21-1
      images:
        x86_64-linux: quay.io/pypa/manylinux_2_28_x86_64:2026.11.21-1@sha256:#{'11' * 32}
        aarch64-linux: quay.io/pypa/manylinux_2_28_aarch64:2026.11.21-1@sha256:#{'22' * 32}
      perl-open:
        url: https://repo.almalinux.org/almalinux/8.10/AppStream/x86_64/os/Packages/perl-open-1.11-423.el8_10.1.noarch.rpm
        sha256: #{'33' * 32}
  YAML

  def quay_tag(arch, tag, digest)
    url = "https://quay.io/api/v1/repository/pypa/manylinux_2_28_#{arch}/tag/?specificTag=#{tag}&onlyActiveTags=true"
    { url => JSON.generate("tags" => [{ "name" => tag, "manifest_digest" => "sha256:#{digest}" }], "page" => 1) }
  end

  def test_an_image_moves_its_tag_and_each_digest_from_quays_record_of_that_tag
    checkout("runtime/sources.yml" => IMAGES) do |root|
      answers = Answers.new(quay_tag("x86_64", "2026.12.01-1", "44" * 32).merge(quay_tag("aarch64", "2026.12.01-1", "55" * 32)))
      move = mover(root, answers, "manylinux" => { "hold" => nil })
      move.call(finding("manylinux", "2026.11.21-1", "2026.12.01-1"))

      assert_equal IMAGES.gsub("2026.11.21-1", "2026.12.01-1").sub("11" * 32, "44" * 32).sub("22" * 32, "55" * 32), move.read("runtime/sources.yml")
      assert_empty answers.downloaded
    end
  end

  def test_an_image_whose_new_tag_quay_does_not_list_moves_nothing
    checkout("runtime/sources.yml" => IMAGES) do |root|
      empty = "https://quay.io/api/v1/repository/pypa/manylinux_2_28_aarch64/tag/?specificTag=2026.12.01-1&onlyActiveTags=true"
      answers = Answers.new(quay_tag("x86_64", "2026.12.01-1", "44" * 32).merge(empty => JSON.generate("tags" => [], "page" => 1)))
      move = mover(root, answers, "manylinux" => { "hold" => nil })
      error = assert_raises(PinMove::Error) { move.call(finding("manylinux", "2026.11.21-1", "2026.12.01-1")) }

      assert_equal "#{empty} lists no tag 2026.12.01-1", error.message
      assert_equal IMAGES, move.read("runtime/sources.yml")
    end
  end

  def test_an_image_on_a_registry_the_move_cannot_ask_stops_it
    sources = IMAGES.sub("quay.io/pypa/manylinux_2_28_aarch64", "ghcr.io/pypa/manylinux_2_28_aarch64")
    checkout("runtime/sources.yml" => sources) do |root|
      move = mover(root, Answers.new(quay_tag("x86_64", "2026.12.01-1", "44" * 32)), "manylinux" => { "hold" => nil })
      error = assert_raises(PinMove::Error) { move.call(finding("manylinux", "2026.11.21-1", "2026.12.01-1")) }

      assert_match(%r{\Aghcr\.io/pypa/manylinux_2_28_aarch64 is on no registry the move can ask for a digest}, error.message)
    end
  end

  HUB_IMAGES = <<~YAML
    images:
      alpine:
        version: 3.24.3
        image: alpine:3.24.3@sha256:#{'66' * 32}
      debian-trixie-slim:
        version: "2026-11-17"
        image: debian:trixie-slim@sha256:#{'77' * 32}
  YAML

  def hub_tag(repository, tag, digest)
    { "https://hub.docker.com/v2/namespaces/library/repositories/#{repository}/tags/#{tag}" => JSON.generate("name" => tag, "digest" => "sha256:#{digest}") }
  end

  def hub_entries
    listed = { "page" => "https://hub.docker.com/", "pattern" => "(?<version>.)", "ships" => false }
    { "alpine" => listed.merge("pins" => ["images.alpine"]), "debian-trixie-slim" => listed.merge("pins" => ["images.debian-trixie-slim"]) }
  end

  def test_an_image_on_docker_hub_moves_its_tag_and_its_digest_from_hubs_record_of_that_tag
    checkout("runtime/sources.yml" => HUB_IMAGES) do |root|
      answers = Answers.new(hub_tag("alpine", "3.24.4", "88" * 32))
      move = mover(root, answers, hub_entries)
      changed = move.call(finding("alpine", "3.24.3", "3.24.4"))

      assert_equal HUB_IMAGES.gsub("3.24.3", "3.24.4").sub("66" * 32, "88" * 32), move.read("runtime/sources.yml")
      assert_equal ["runtime/sources.yml"], changed.keys
    end
  end

  def test_an_image_under_a_tag_that_moves_takes_the_digest_the_tag_names_now
    checkout("runtime/sources.yml" => HUB_IMAGES) do |root|
      move = mover(root, Answers.new(hub_tag("debian", "trixie-slim", "99" * 32)), hub_entries)
      move.call(finding("debian-trixie-slim", "2026-11-17", "2026-12-01"))

      assert_equal HUB_IMAGES.sub("2026-11-17", "2026-12-01").sub("77" * 32, "99" * 32), move.read("runtime/sources.yml")
    end
  end

  def test_a_key_beside_the_url_that_the_move_cannot_know_stops_it
    sources = SOURCES.sub("version: 3.5.2\n    url:", "version: 3.5.2\n    file_sha256: 00\n    url:")
    checkout("runtime/sources.yml" => sources) do |root|
      error = assert_raises(PinMove::Error) { mover(root, Answers.new(LIBFFI => libffi_releases)).call(finding("libffi", "3.5.2", "3.8.1")) }

      assert_match(/stands beside file_sha256, which a move cannot know\z/, error.message)
    end
  end

  NDK_LISTING = <<~XML
    <remotePackage path="ndk;31.0.2">
      <revision><major>31</major><minor>0</minor><micro>2</micro></revision>
      <channelRef ref="channel-0"/>
      <archives><archive><complete><url>android-ndk-r31-darwin.zip</url></complete></archive>
      <archive><complete><url>android-ndk-r31-linux.zip</url></complete></archive></archives>
    </remotePackage>
    <remotePackage path="ndk;31.0.1">
      <revision><major>31</major><minor>0</minor><micro>1</micro><preview>1</preview></revision>
      <channelRef ref="channel-0"/>
      <archives><archive><complete><url>android-ndk-r31-beta1-linux.zip</url></complete></archive></archives>
    </remotePackage>
  XML

  def test_the_ndk_moves_its_revision_and_the_release_name_its_listing_gives
    old = "https://dl.google.com/android/repository/android-ndk-r30-linux.zip"
    new = "https://dl.google.com/android/repository/android-ndk-r31-linux.zip"
    sources = "mobile:\n  ndk:\n    version: r30\n    revision: 30.0.16248370\n    hosts:\n      x86_64-linux:\n        url: #{old}\n        sha256: #{OLD_SHA256}\n"
    tool = "[tools.\"http:android-ndk\"]\nversion = \"r30\"\nplatforms.linux-x64 = { url = \"#{old}\", checksum = \"sha256:#{OLD_SHA256}\" }\n"
    files = {
"runtime/sources.yml" => sources,
"runtime/licenses.yml" => "components:\n  - id: compiler-rt-ndk\n    version: r30\n",
"mise.android.toml" => tool,
"ndk.rb" => "RECOMMENDED = \"30.0.16248370\"\n",
}
    checkout(files) do |root|
      entry = entries.fetch("ndk")
      move = mover(root, Answers.new({ entry.fetch("page") => NDK_LISTING }, new => "ab" * 32),
        "ndk" => {
"also" => { "ndk.rb" => ['RECOMMENDED = "(?<version>[^"]+)"'] },
"release" => entry.fetch("release").merge("also" => { "mise.android.toml" => ['version = "(?<version>[^"]+)"'] }),
})
      watched = PinWatch.new(sources: YAML.safe_load(sources), upstreams: [PinWatch::Upstream.from("ndk", entry)], unwatched: {})

      assert_equal "31.0.2", watched.run(Answers.new(entry.fetch("page") => NDK_LISTING)).first.newer, "a preview is not the NDK's next version"
      move.call(finding("ndk", "30.0.16248370", "31.0.2"))

      assert_equal "mobile:\n  ndk:\n    version: r31\n    revision: 31.0.2\n    hosts:\n      x86_64-linux:\n        url: #{new}\n        sha256: #{'ab' * 32}\n",
        move.read("runtime/sources.yml")
      assert_equal "[tools.\"http:android-ndk\"]\nversion = \"r31\"\nplatforms.linux-x64 = { url = \"#{new}\", checksum = \"sha256:#{'ab' * 32}\" }\n",
        move.read("mise.android.toml")
      assert_equal "RECOMMENDED = \"31.0.2\"\n", move.read("ndk.rb")
      assert_includes move.read("runtime/licenses.yml"), "version: r31\n"
      assert_includes move.read("CHANGELOG.md"), "- NDK r31, from r30.\n"
    end
  end

  LLVM = "https://api.github.com/repos/llvm/llvm-project/releases?per_page=100"
  LLVM_OLD = "https://github.com/llvm/llvm-project/releases/download/llvmorg-23.1.4/clang+llvm-23.1.4-x86_64-pc-windows-msvc.tar.zst"
  LLVM_NEW = "https://github.com/llvm/llvm-project/releases/download/llvmorg-23.1.5/clang+llvm-23.1.5-x86_64-pc-windows-msvc.tar.zst"
  LLVM_SCRIPT = "https://raw.githubusercontent.com/llvm/llvm-project/llvmorg-23.1.5/llvm/utils/release/build_llvm_release.bat"

  # llvm-readobj is one file of LLVM's archive: the move hashes that
  # file, and reads the zlib and Zstandard it links from LLVM's release
  # script at the new tag, whose lines end in CR LF. GitHub lists the
  # asset with its + escaped, as %2B.
  def test_llvm_readobj_moves_the_file_it_takes_from_the_archive_and_the_libraries_it_links
    sources = "llvm-readobj:\n  version: 23.1.4\n  url: #{LLVM_OLD}\n  sha256: #{OLD_SHA256}\n" \
      "  path: clang+llvm-23.1.4-x86_64-pc-windows-msvc/bin/llvm-readobj.exe\n  file_sha256: #{'0f' * 32}\n"
    licenses = <<~YAML
      components:
        - id: llvm-readobj
          version: 23.1.4
          download: https://github.com/llvm/llvm-project/releases/tag/llvmorg-23.1.4
          sha256:
            tools/llvm-readobj.exe: #{'0f' * 32}

        - id: zlib-llvm-readobj
          version: 1.3.2
          download: https://github.com/madler/zlib/releases/download/v1.3.2/zlib-1.3.2.tar.gz
          embedded:
            - evidence: "deflate 1.3.2 "

        - id: zstd-llvm-readobj
          version: 1.5.7
          download: https://github.com/facebook/zstd/releases/tag/v1.5.7
    YAML
    releases = JSON.generate([{ "tag_name" => "llvmorg-23.1.5", "assets" => [{ "browser_download_url" => LLVM_NEW.sub("clang+llvm", "clang%2Bllvm"), "digest" => "sha256:#{'ab' * 32}" }] }])
    answers = Answers.new({ LLVM => releases, LLVM_SCRIPT => "set zlib_version=1.3.3\r\nset zstd_version=1.5.7\r\n" },
      [LLVM_NEW, "clang+llvm-23.1.5-x86_64-pc-windows-msvc/bin/llvm-readobj.exe"] => "cd" * 32)
    checkout("runtime/sources.yml" => sources, "runtime/licenses.yml" => licenses) do |root|
      move = PinMove.new(root, entries, answers)
      move.call(finding("llvm-readobj", "23.1.4", "23.1.5"))

      assert_equal "llvm-readobj:\n  version: 23.1.5\n  url: #{LLVM_NEW}\n  sha256: #{'ab' * 32}\n" \
        "  path: clang+llvm-23.1.5-x86_64-pc-windows-msvc/bin/llvm-readobj.exe\n  file_sha256: #{'cd' * 32}\n", move.read("runtime/sources.yml")
      assert_equal licenses.gsub("23.1.4", "23.1.5").gsub("0f" * 32, "cd" * 32).gsub("1.3.2", "1.3.3"), move.read("runtime/licenses.yml")
      assert_equal [LLVM_NEW], answers.downloaded, "the archive is downloaded once, for its file; GitHub records its own SHA-256"
      assert_includes move.read("CHANGELOG.md"), "- llvm-readobj 23.1.5, from 23.1.4.\n"
    end
  end

  RV = "https://api.github.com/repos/spinel-coop/rv-ruby/releases?per_page=100"

  # An upstream that compiles libraries into a Ruby and names its
  # platform for the macOS it was built on, as rv-ruby's did while it was
  # the Mac's Ruby (runtime/upstreams.yml until 2026-11-22): the move's
  # platform and compiled steps, which jdx/ruby's Mac Ruby needs once its
  # pin moves with no person, are tested on it.
  RV_UPSTREAM = YAML.safe_load(<<~'YAML').freeze
    pins: [ruby]
    field: release
    github: spinel-coop/rv-ruby
    tag: '\A(?<version>\d{8})\z'
    licenses: [rv-ruby]
    platform:
      arm64-darwin: '/lib/ruby/[^/]+/(?<arch>arm64-darwin\d*)/rbconfig\.rb\z'
    compiled:
      arm64-darwin:
        openssl:
          file: '/lib/ruby/[^/]+/[^/]+/openssl\.bundle\z'
          version: 'OpenSSL (?<version>\d+\.\d+\.\d+) '
          title: OpenSSL in the macOS Ruby
        libyaml:
          file: '/lib/ruby/[^/]+/[^/]+/psych\.bundle\z'
          version: '(?<=\0)(?<version>\d+\.\d+\.\d+)(?=\0)'
          title: libyaml in the macOS Ruby
    also:
      lib/fledge/download.rb: []
  YAML
  RV_NEW = "https://github.com/spinel-coop/rv-ruby/releases/download/20261119/ruby-4.1.0-preview1.arm64_sonoma.tar.gz"

  # Answers as Answers does, and lists the files of each archive it is
  # given, with the bytes of those +read+ matches, as Fetch#members does.
  class Archives < Answers
    def initialize(bodies, listings)
      super(bodies)
      @listings = listings
    end

    def members(url, read = nil)
      @downloaded << url
      @listings.fetch(url).to_h { |path, bytes| [path, (read && path.match?(read)) ? bytes : nil] }
    end
  end

  RV_LICENSES = <<~YAML
    platforms:
      arm64-darwin: {os: darwin, arch: arm64-darwin23, gem_arch: arm64-darwin-23, so: bundle}
    components:
      - id: openssl
        version: 3.6.2
        download: https://github.com/openssl/openssl/releases/download/openssl-3.6.2/openssl-3.6.2.tar.gz
        platforms: [arm64-darwin]
        embedded:
          - files: ["{prefix}lib/ruby/{abi}/{arch}/openssl.{so}"]
            evidence: "OpenSSL 3.6.2 "

      - id: libyaml
        version: 0.2.5
        download: https://github.com/yaml/libyaml/releases/download/0.2.5/yaml-0.2.5.tar.gz
        platforms: [arm64-darwin]
        embedded:
          - files: ["{prefix}lib/ruby/{abi}/{arch}/psych.{so}"]
            evidence: "0.2.5\\0"

      - id: rv-ruby
        version: "20261023"
        download: https://github.com/spinel-coop/rv-ruby/tree/20261023
  YAML

  # The files of an rv-ruby archive for macOS the move looks in, as
  # rv-ruby lays them out, with the strings the license audit reads:
  # OpenSSL's version text in openssl.bundle, and libyaml's version
  # between NULs in psych.bundle (both as 20261023's and 20261119's
  # hold them). The debug symbols beside each name an older OpenSSL, so
  # a move that read them would be seen.
  def rv_archive(arch: "arm64-darwin23", openssl: "3.6.2", libyaml: "\0000.2.5\000")
    top = "rv-ruby@4.1.0-preview1/4.1.0-preview1/lib/ruby/4.1.0+5/#{arch}"
    {
      "rv-ruby@4.1.0-preview1/4.1.0-preview1/bin/ruby" => "\xCF\xFA\xED\xFE".b,
      "#{top}/rbconfig.rb" => "{}",
      "#{top}/openssl.bundle" => "\xCF\xFA\xED\xFE\0OpenSSL #{openssl} 7 Apr 2026\0".b,
      "#{top}/openssl.bundle.dSYM/Contents/Resources/DWARF/openssl.bundle" => "\0OpenSSL 1.0.0 \0".b,
      "#{top}/psych.bundle" => "\xCF\xFA\xED\xFE\0%YAML 1.1\0#{libyaml}".b,
    }
  end

  def rv_ruby(listing)
    sources = "ruby:\n  version: 4.1.0-preview1\n  release: \"20261023\"\n  platforms:\n    arm64-darwin:\n" \
      "      url: #{RV_NEW.sub('20261119', '20261023')}\n      sha256: #{OLD_SHA256}\n"
    releases = JSON.generate([{ "tag_name" => "20261119", "assets" => [{ "browser_download_url" => RV_NEW, "digest" => "sha256:#{'ab' * 32}" }] }])
    answers = Archives.new({ RV => releases }, RV_NEW => listing)
    checkout("runtime/sources.yml" => sources, "runtime/licenses.yml" => RV_LICENSES, "lib/fledge/download.rb" => "") do |root|
      yield PinMove.new(root, entries.merge("rv-ruby" => RV_UPSTREAM), answers), answers
    end
  end

  # rv-ruby's Ruby names its platform for the macOS it was built on
  # (rv-ruby 20261119's, built on macOS 15, calls itself arm64-darwin24
  # where 20261023's said arm64-darwin23). The move reads the name in
  # the new archive and moves runtime/licenses.yml's platform to it,
  # which the license audit, parity, and Delivery read, with a line in
  # CHANGELOG.md, since RUBY_PLATFORM is what an app's code sees.
  def test_an_rv_ruby_release_that_renames_its_platform_moves_the_platform
    rv_ruby(rv_archive(arch: "arm64-darwin24")) do |move, answers|
      move.call(finding("rv-ruby", "20261023", "20261119"))

      assert_includes move.read("runtime/sources.yml"), "release: \"20261119\""
      assert_equal RV_LICENSES.gsub("20261023", "20261119").sub("arch: arm64-darwin23, gem_arch: arm64-darwin-23",
        "arch: arm64-darwin24, gem_arch: arm64-darwin-24"), move.read("runtime/licenses.yml")
      assert_includes move.read("CHANGELOG.md"), "- The arm64-darwin app's RUBY_PLATFORM arm64-darwin24, from arm64-darwin23.\n"
      assert_equal [RV_NEW], answers.downloaded
    end
  end

  # The task moves each pin behind and reports each, and a person is
  # needed for those it could not move.
  def test_each_move_is_reported_and_those_not_moved_are_returned
    rv_ruby(rv_archive) do |move, _answers|
      moved = finding("rv-ruby", "20261023", "20261119")
      out = StringIO.new

      assert_equal [[moved], []], PinMove.move_each(move, [moved], out:)
      assert_match(%r{\Amoved    rv-ruby 20261023 -> 20261119: runtime/sources.yml, }, out.string)
      unlisted = finding("rv-ruby", "20261119", "20261201")
      assert_equal [[], [unlisted]], PinMove.move_each(move, [unlisted], out:)
      assert_match(/^failed   rv-ruby 20261119 -> 20261201: /, out.string)
    end
  end

  # A move of rv-ruby moves its own entry's version and its download,
  # which names the release's tag, and leaves the libraries it compiles
  # in where the new archive holds the same.
  def test_an_rv_ruby_release_with_the_same_platform_moves
    rv_ruby(rv_archive) do |move, answers|
      move.call(finding("rv-ruby", "20261023", "20261119"))

      assert_includes move.read("runtime/sources.yml"), "release: \"20261119\"\n  platforms:\n    arm64-darwin:\n      url: #{RV_NEW}\n"
      assert_equal RV_LICENSES.gsub("20261023", "20261119"), move.read("runtime/licenses.yml")
      assert_includes move.read("CHANGELOG.md"), "- rv-ruby 20261119, from 20261023.\n"
      assert_equal [RV_NEW], answers.downloaded
    end
  end

  # rv-ruby compiles OpenSSL and libyaml into the macOS Ruby's
  # extensions, so a release that updates one (a security fix in
  # OpenSSL, say) moves that library's entry as the license audit will
  # read it from the runtime, from the archive the move downloads once,
  # and says so to app developers.
  def test_an_rv_ruby_release_moves_the_libraries_it_compiles_in
    rv_ruby(rv_archive(openssl: "3.6.3")) do |move, answers|
      move.call(finding("rv-ruby", "20261023", "20261119"))

      licenses = move.read("runtime/licenses.yml")
      assert_includes licenses, "  - id: openssl\n    version: 3.6.3\n    download: https://github.com/openssl/openssl/releases/" \
        "download/openssl-3.6.3/openssl-3.6.3.tar.gz\n"
      assert_includes licenses, "evidence: \"OpenSSL 3.6.3 \""
      assert_includes licenses, "  - id: libyaml\n    version: 0.2.5\n"
      changelog = move.read("CHANGELOG.md")
      assert_includes changelog, "- rv-ruby 20261119, from 20261023.\n"
      assert_includes changelog, "- OpenSSL in the macOS Ruby 3.6.3, from 3.6.2.\n"
      assert_equal [RV_NEW], answers.downloaded
    end
  end

  # A compiled file that names no version, or two, is not guessed at.
  def test_a_compiled_file_whose_version_is_unclear_stops_the_move
    rv_ruby(rv_archive(libyaml: "\0000.2.5\0000.2.6\000")) do |move, _|
      error = assert_raises(PinMove::Error) { move.call(finding("rv-ruby", "20261023", "20261119")) }

      assert_equal "#{RV_NEW}'s psych.bundle names libyaml as 0.2.5 and 0.2.6, not one version", error.message
      assert_equal RV_LICENSES, move.read("runtime/licenses.yml")
    end
    rv_ruby(rv_archive.reject { |path, _| path.end_with?("/psych.bundle") }) do |move, _|
      error = assert_raises(PinMove::Error) { move.call(finding("rv-ruby", "20261023", "20261119")) }

      assert_equal "#{RV_NEW} holds no file in which to read libyaml's version", error.message
    end
  end

  JDX = "https://api.github.com/repos/jdx/ruby/releases?per_page=100"
  JDX_MAC = "https://github.com/jdx/ruby/releases/download/4.0.10-2/ruby-4.0.10.macos.tar.gz"
  JDX_LINUX = "https://github.com/jdx/ruby/releases/download/4.0.10-2/ruby-4.0.10.x86_64_linux.tar.gz"

  # An upstream that builds one Ruby for macOS and Linux from one list of
  # the libraries it compiles in, as jdx/ruby builds every target from
  # its recipes/dependencies.yml: one entry of runtime/licenses.yml then
  # describes the library on every platform, and the move reads its
  # version out of each platform's archive.
  JDX_UPSTREAM = YAML.safe_load(<<~'YAML').freeze
    pins: [ruby]
    field: jdx_release
    github: jdx/ruby
    tag: '\A(?<version>\d+\.\d+\.\d+-\d+)\z'
    keep: [build]
    platform:
      arm64-darwin: '/lib/ruby/[^/]+/(?<arch>arm64-darwin\d*)/rbconfig\.rb\z'
    compiled:
      arm64-darwin:
        openssl-jdx:
          file: '/lib/ruby/[^/]+/[^/]+/openssl\.bundle\z'
          version: 'OpenSSL (?<version>\d+\.\d+\.\d+) '
          title: OpenSSL in the macOS and glibc Linux Ruby
      x86_64-linux:
        openssl-jdx:
          file: '/lib/ruby/[^/]+/[^/]+/openssl\.so\z'
          version: 'OpenSSL (?<version>\d+\.\d+\.\d+) '
          title: OpenSSL in the macOS and glibc Linux Ruby
  YAML

  JDX_LICENSES = <<~YAML
    platforms:
      arm64-darwin: {os: darwin, arch: arm64-darwin25, gem_arch: arm64-darwin-25, so: bundle}
      x86_64-linux: {os: linux, arch: x86_64-linux, gem_arch: x86_64-linux, so: so}
    components:
      - id: openssl-jdx
        version: 3.5.5
        download: https://github.com/openssl/openssl/releases/download/openssl-3.5.5/openssl-3.5.5.tar.gz
        platforms: [arm64-darwin, x86_64-linux]
        embedded:
          - files: ["{prefix}lib/ruby/{abi}/{arch}/openssl.{so}"]
            evidence: "OpenSSL 3.5.5 "
  YAML

  # A checkout pinned to jdx/ruby's first build of Ruby 4.0.10, whose
  # second build's archives hold the OpenSSL +mac+ and +linux+ name,
  # listed after the releases +ahead+, a page of them or none.
  def jdx_ruby(mac:, linux:, upstream: JDX_UPSTREAM, ahead: [])
    old = { JDX_MAC => "ab" * 32, JDX_LINUX => "cd" * 32 }
    pins = old.map do |url, sha256|
      platform = url.include?("macos") ? "arm64-darwin" : "x86_64-linux"
      "    #{platform}:\n      url: #{url.sub('4.0.10-2', '4.0.10-1')}\n      sha256: #{sha256}\n      build: jdx\n"
    end
    sources = "ruby:\n  version: 4.0.10\n  jdx_release: 4.0.10-1\n  platforms:\n#{pins.join}"
    assets = old.keys.map.with_index { |url, index| { "browser_download_url" => url, "digest" => "sha256:#{index.to_s * 64}" } }
    top = "ruby-4.0.10/lib/ruby/4.0.0"
    listings = {
      JDX_MAC => { "#{top}/arm64-darwin25/rbconfig.rb" => "{}", "#{top}/arm64-darwin25/openssl.bundle" => "\0OpenSSL #{mac} 1 Jan 2027\0".b },
      JDX_LINUX => { "#{top}/x86_64-linux/rbconfig.rb" => "{}", "#{top}/x86_64-linux/openssl.so" => "\0OpenSSL #{linux} 1 Jan 2027\0".b },
    }
    rebuild = JSON.generate([{ "tag_name" => "4.0.10-2", "assets" => assets }])
    bodies = ahead.empty? ? { JDX => rebuild } : { JDX => JSON.generate(ahead), "#{JDX}&page=2" => rebuild }
    answers = Archives.new(bodies, listings)
    checkout("runtime/sources.yml" => sources, "runtime/licenses.yml" => JDX_LICENSES) do |root|
      yield PinMove.new(root, entries.merge("jdx-ruby" => upstream), answers), answers
    end
  end

  # A new build that compiles in a newer OpenSSL on every platform moves
  # the one entry they share, once, with one line in CHANGELOG.md.
  def test_a_library_every_platform_compiles_in_moves_once_each_archive_names_the_same_version
    jdx_ruby(mac: "3.5.6", linux: "3.5.6") do |move, answers|
      move.call(finding("jdx-ruby", "4.0.10-1", "4.0.10-2"))

      assert_equal JDX_LICENSES.gsub("3.5.5", "3.5.6"), move.read("runtime/licenses.yml")
      assert_includes move.read("runtime/sources.yml"), "jdx_release: 4.0.10-2\n"
      assert_includes move.read("runtime/sources.yml"), "url: #{JDX_LINUX}\n      sha256: #{'1' * 64}\n      build: jdx\n"
      assert_equal 1, move.read("CHANGELOG.md").scan("OpenSSL").size
      assert_includes move.read("CHANGELOG.md"), "- OpenSSL in the macOS and glibc Linux Ruby 3.5.6, from 3.5.5.\n"
      assert_equal [JDX_MAC, JDX_LINUX], answers.downloaded
    end
  end

  # One entry cannot say two versions: when the archives disagree, a
  # person reads them.
  def test_a_library_the_platforms_archives_name_differently_stops_the_move
    jdx_ruby(mac: "3.5.6", linux: "3.5.5") do |move, _|
      error = assert_raises(PinMove::Error) { move.call(finding("jdx-ruby", "4.0.10-1", "4.0.10-2")) }

      assert_equal "jdx-ruby's archives name openssl-jdx as 3.5.6 in #{JDX_MAC} and 3.5.5 in #{JDX_LINUX}, not one version", error.message
      assert_equal JDX_LICENSES, move.read("runtime/licenses.yml")
    end
  end

  # A hold is for a new release: another build of the pinned one, as
  # jdx/ruby's 4.0.10-2 of 4.0.10-1, moves with no person.
  def test_a_held_upstream_moves_another_build_of_the_pinned_release_and_no_new_release
    held = JDX_UPSTREAM.merge("hold" => "A new Ruby is planned work.", "rebuild" => '\A(?<of>.+)-\d+\z')
    jdx_ruby(mac: "3.5.5", linux: "3.5.5", upstream: held) do |move, _|
      error = assert_raises(PinMove::Error) { move.call(finding("jdx-ruby", "4.0.10-1", "4.0.11-1")) }
      assert_equal "jdx-ruby is held: A new Ruby is planned work.", error.message

      move.call(finding("jdx-ruby", "4.0.10-1", "4.0.10-2"))
      assert_includes move.read("runtime/sources.yml"), "jdx_release: 4.0.10-2\n"
      assert_includes move.movable, "jdx-ruby"
    end
  end

  # GitHub lists a page of releases at a time, so the move finds the
  # digest of a rebuild a hundred newer releases follow on a later page,
  # as the watch found the rebuild there.
  def test_a_digest_listed_on_a_later_page_is_found
    others = (1..100).map { |n| { "tag_name" => "3.#{n}.0-1", "assets" => [] } }
    upstream = JDX_UPSTREAM.merge("rebuild" => '\A(?<of>.+)-\d+\z')
    jdx_ruby(mac: "3.5.5", linux: "3.5.5", upstream:, ahead: others) do |move, _|
      move.call(finding("jdx-ruby", "4.0.10-1", "4.0.10-2"))

      assert_includes move.read("runtime/sources.yml"), "url: #{JDX_LINUX}\n      sha256: #{'1' * 64}\n"
    end
  end

  def test_an_archive_that_names_no_platform_is_not_moved
    rv_ruby({ "x/bin/ruby" => "" }) do |move, _|
      error = assert_raises(PinMove::Error) { move.call(finding("rv-ruby", "20261023", "20261119")) }

      assert_equal "#{RV_NEW} holds no file that names its platform", error.message
    end
  end

  def test_the_fetch_lists_a_gzipped_tarballs_files_and_reads_those_asked_for
    tarball = StringIO.new
    Zlib::GzipWriter.wrap(tarball) do |gzip|
      Gem::Package::TarWriter.new(gzip) do |tar|
        tar.add_file_simple("ruby/lib/rbconfig.rb", 0o644, 2) { |file| file.write("{}") }
        tar.add_file_simple("ruby/lib/psych.bundle", 0o644, 3) { |file| file.write("\0\xFF\0".b) }
        tar.mkdir("ruby/bin", 0o755)
      end
    end
    server = LoopbackServer.new("/ruby.tar.gz" => [200, {}, tarball.string])
    fetch = PinWatch::Fetch.new(timeout: 5)

    assert_equal({ "ruby/lib/rbconfig.rb" => nil, "ruby/lib/psych.bundle" => nil, "ruby/bin" => nil }, fetch.members(server.url("/ruby.tar.gz")))
    read = fetch.members(server.url("/ruby.tar.gz"), /psych/)
    assert_equal [nil, "\0\xFF\0".b, nil], read.values
    assert_equal Encoding::BINARY, read.fetch("ruby/lib/psych.bundle").encoding
  ensure
    server&.stop
  end

  def test_a_held_upstream_is_refused_with_its_reason
    checkout do |root|
      move = mover(root, Answers.new({}))
      error = assert_raises(PinMove::Error) { move.call(finding("ruby", "4.1.0-preview1", "4.1.0-preview2")) }

      assert_match(/\Aruby is held: The step from Ruby 4.1's preview to 4.1.0 is the maintainer's/, error.message)
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

  def test_the_commit_message_names_each_move_in_its_subject_or_its_body
    checkout do |root|
      move = mover(root, Answers.new({}))
      one = move.message([finding("libffi", "3.5.2", "3.8.1")])
      two = move.message([finding("libffi", "3.5.2", "3.8.1"), finding("ca-certificates", "2026-03-19", "2026-11-05")])

      assert_equal "chore: move libffi to 3.8.1", one.lines.first.chomp
      assert_equal "chore: move 2 pins to their upstreams' newest releases", two.lines.first.chomp
      assert_includes two.tr("\n", " "), "libffi 3.5.2 to 3.8.1, and Mozilla's CA certificates 2026-03-19 to 2026-11-05."
      assert(two.lines.all? { |line| line.chomp.size <= 72 }, two)
      assert_match(/\n\nProvenance: requested\n\z/, two)
    end
  end

  # Whether the move never moves the upstream +entry+: one held for a
  # person, unless its hold is for a new release alone and another build
  # of its pinned release moves (rebuild).
  def held?(entry) = entry["hold"] && !entry["rebuild"]

  # Each part of the move of each upstream the move may move, as its
  # name, its entry, and the version its pin holds today: the version the
  # watch compares, and the release name of an upstream with release,
  # with that release's licenses and also.
  def movable_parts
    watch = PinWatch.load(ROOT)
    PinWatch.watched(entries, watch.sources).reject { |_, entry| held?(entry) }.flat_map do |name, entry|
      upstream = watch.upstreams.find { |candidate| candidate.name == name }
      parts = [[name, entry, watch.current(upstream)]]
      if (release = entry["release"])
        named = upstream.with(field: release.fetch("field"), current: nil)
        parts << [name, entry.except("licenses", "also").merge(release.slice("licenses", "also")), watch.current(named)]
      end
      parts
    end
  end

  # What the move needs of this checkout holds for every upstream it may
  # move: each licenses entry names the pin's version, and each pattern
  # of each other file captures it.
  def test_every_movable_pin_is_named_where_the_move_will_look
    licenses = File.read(File.join(ROOT, "runtime/licenses.yml")).split(/(?=^  - id: )/)
    movable_parts.each do |_, entry, version|
      entry.fetch("licenses", []).each do |id|
        assert licenses.any? { |text| text.start_with?("  - id: #{id}\n") && text.include?(version) }, "runtime/licenses.yml's #{id} names no #{version}"
      end
      entry.fetch("also", {}).each do |path, patterns|
        text = File.read(File.join(ROOT, path))
        patterns.each { |pattern| assert_equal version, text[Regexp.new(pattern), :version], "#{path}: #{pattern}" }
      end
    end
  end

  # Each library an input compiles in, whose version the move reads from
  # the input's archives, has an entry of its own that describes exactly
  # the platforms whose archives the move reads it from, and that build
  # of Ruby alone, so moving it says nothing of another build's copy or
  # of a platform it did not read; and the move's pattern reads the
  # entry's version out of the evidence the license audit looks for in
  # the same file (a C string, between NULs).
  def test_every_compiled_library_has_an_entry_the_move_can_read_its_version_into
    components = YAML.safe_load_file(File.join(ROOT, "runtime/licenses.yml")).fetch("components")
    sources = YAML.safe_load_file(File.join(ROOT, "runtime/sources.yml"))
    compiled = entries.reject { |_, entry| held?(entry) }.flat_map do |_, entry|
      entry.fetch("compiled", {}).flat_map do |platform, libraries|
        builds = entry.fetch("pins").map { |pin| sources.dig(*pin.split("."), "platforms", platform, "build") || "upstream" }
        libraries.map { |id, library| [id, platform, builds, library] }
      end
    end
    compiled.group_by(&:first).each do |id, reads|
      component = components.find { |each| each.fetch("id") == id }
      assert_equal reads.map { |read| read[1] }.sort, component&.fetch("platforms")&.sort, "runtime/licenses.yml's #{id} describes the platforms the move reads it from"
      assert_equal reads.flat_map { |read| read[2] }.uniq, Array(component["ruby_build"]), "runtime/licenses.yml's #{id} describes the build the move reads it from alone"
      evidence = component.fetch("embedded").map { |embedded| embedded.fetch("evidence") }
      reads.each do |_, platform, _, library|
        found = evidence.map { |text| "\0#{text}\0".b[Regexp.new(library.fetch("version").b), "version"] }
        assert_equal [component.fetch("version").to_s], found.uniq, "#{id}'s version pattern for #{platform} reads its evidence"
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
    named = movable_parts.flat_map do |name, entry, version|
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
