# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++
# Tests .github/scripts/ruby-archive-publish.sh, which ruby-builds.yml
# runs to publish Fledge's own Ruby archives for glibc Linux on a
# pre-release (doc/contributors/design/runtimes.md, "Fledge's own Ruby
# builds"). Each test runs the script with bash on a folder of stand-in
# archives, with a gh on PATH that keeps what it is given in a folder of
# its own and hands it back on download, as GitHub's releases would.

require_relative "../test_helper"
require "digest"
require "open3"
require "tmpdir"

class RubyArchivePublishTest < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)
  SCRIPT = File.join(ROOT, ".github", "scripts", "ruby-archive-publish.sh")
  COMMIT = "0123456789abcdef0123456789abcdef01234567"
  PLATFORMS = %w[x86_64-linux aarch64-linux].freeze
  GH = <<~SH
    echo "$*" >> "$FAKE_GH_LOG"
    case "$1 $2" in
      "release view") [ -n "$FAKE_GH_EXISTS" ] ;;
      "release create")
        for arg in "$@"; do
          case $arg in
            */ruby-*.tar.gz) cp "$arg" "$FAKE_GH_STORE/" ;;
          esac
        done ;;
      "release download")
        dir=.
        while [ $# -gt 0 ]; do [ "$1" = --dir ] && dir=$2; shift; done
        cp "$FAKE_GH_STORE"/ruby-* "$dir/"
        [ -z "$FAKE_GH_CORRUPT" ] || echo changed >> "$dir/$FAKE_GH_CORRUPT" ;;
    esac
  SH

  def setup
    skip "the workflow's script runs on Linux, with bash" if Gem.win_platform?
    @dir = Dir.mktmpdir
    @archives = File.join(@dir, "archives")
    @store = File.join(@dir, "store")
    FileUtils.mkdir_p([@archives, @store, File.join(@dir, "bin")])
    File.write(File.join(@dir, "bin", "gh"), GH)
    File.chmod(0o755, File.join(@dir, "bin", "gh"))
  end

  def teardown
    FileUtils.rm_rf(@dir) if @dir
  end

  def test_a_dry_run_names_the_pre_release_and_lists_each_archives_sha256
    shas = archives("4.1.0-preview1")
    out, status = publish("DRY_RUN" => "1")

    assert status.success?, out
    assert_match(/^pre-release: inputs-fledge-ruby-4\.1\.0-preview1-\d{8}-0123456789$/, out)
    shas.each { |name, sha| assert_includes out, "#{sha}  #{name}" }
    assert_includes out, "from the recipe at #{COMMIT}"
    assert_empty gh_calls
  end

  def test_publishing_creates_a_pre_release_on_the_commit_and_reads_each_archive_back
    archives("4.1.0-preview1")
    out, status = publish

    assert status.success?, out
    create = gh_calls.find { |call| call.start_with?("release create") }
    tag = create.split[2]

    assert_match(/\Ainputs-fledge-ruby-4\.1\.0-preview1-\d{8}-0123456789\z/, tag)
    assert_includes create, "--prerelease --latest=false --target #{COMMIT}"
    assert_equal PLATFORMS.map { |platform| "ruby-4.1.0-preview1-#{platform}.tar.gz" }.sort, Dir.children(@store).sort
    assert(gh_calls.any? { |call| call.start_with?("release download #{tag}") })
    PLATFORMS.each { |platform| assert_match(/ruby-4\.1\.0-preview1-#{platform}\.tar\.gz: OK/, out) }
  end

  def test_an_archive_that_comes_back_changed_fails_the_run
    archives("4.1.0-preview1")
    out, status = publish("FAKE_GH_CORRUPT" => "ruby-4.1.0-preview1-aarch64-linux.tar.gz")

    refute status.success?, out
    assert_match(/aarch64-linux\.tar\.gz: FAILED/, out)
  end

  def test_a_pre_release_that_exists_is_never_overwritten
    archives("4.1.0-preview1")
    out, status = publish("FAKE_GH_EXISTS" => "1")

    refute status.success?, out
    assert_includes out, "is never overwritten"
    refute(gh_calls.any? { |call| call.start_with?("release create") })
  end

  def test_archives_of_two_versions_or_a_missing_platform_publish_nothing
    archives("4.1.0-preview1", platforms: ["x86_64-linux"])
    out, status = publish("DRY_RUN" => "1")

    refute status.success?, out
    assert_includes out, "holds 1 archives"

    archives("4.1.0-preview2", platforms: ["aarch64-linux"])
    out, status = publish

    refute status.success?, out
    assert_includes out, "no ruby-4.1.0-preview1-aarch64-linux.tar.gz"
    assert_empty gh_calls
  end

  # Writes a stand-in archive for each platform, and returns each one's
  # name with its SHA-256.
  private def archives(version, platforms: PLATFORMS)
    platforms.to_h do |platform|
      name = "ruby-#{version}-#{platform}.tar.gz"
      bytes = "#{name} built\n"
      File.binwrite(File.join(@archives, name), bytes)
      [name, Digest::SHA256.hexdigest(bytes)]
    end
  end

  private def publish(env = {})
    File.write(log, "") unless File.exist?(log)
    environment = {
      "PATH" => "#{File.join(@dir, 'bin')}#{File::PATH_SEPARATOR}#{ENV.fetch('PATH')}",
      "FLEDGE_COMMIT" => COMMIT,
      "FAKE_GH_LOG" => log,
      "FAKE_GH_STORE" => @store,
      "FAKE_GH_EXISTS" => "",
      "FAKE_GH_CORRUPT" => "",
      "DRY_RUN" => nil,
    }
    Open3.capture2e(environment.merge(env), "bash", SCRIPT, @archives, chdir: @dir)
  end

  private def log
    File.join(@dir, "gh.log")
  end

  private def gh_calls
    File.exist?(log) ? File.readlines(log, chomp: true) : []
  end
end
