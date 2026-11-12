# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "test_helper"
require_relative "support/loopback_server"
require "digest"
require "json"
require "open3"
require "time"
require "yaml"

# .github/scripts/keep-rubyinstaller-head.sh, which keeps RubyInstaller's
# signed head build of the day each Ruby 4.1 release appears
# (doc/contributors/design/runtimes.md, "Keeping RubyInstaller's head
# build"). Each test runs the script with bash against one loopback
# server standing in for cache.ruby-lang.org, GitHub's API, and
# RubyInstaller's release downloads, and against a signing key of the
# test's own, made with gpg, which a sources.yml of the test's own pins
# as runtime/sources.yml pins RubyInstaller's. Publishing is gh's: a gh
# of the test's own records what it is asked and keeps the files it is
# given, so a test sees what would be published and what reading the
# release back returns.
class KeepRubyInstallerHeadTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  SCRIPT = File.join(ROOT, ".github", "scripts", "keep-rubyinstaller-head.sh")
  VERSIONS = %w[4.1.0-preview2 4.1.0-preview3 4.1.0-rc1 4.1.0-rc2 4.1.0].freeze
  FILES = %w[
    rubyinstaller-head-x64.7z
    rubyinstaller-head-x64.7z.asc
    rubyinstaller-head-arm.7z
    rubyinstaller-head-arm.7z.asc
  ].freeze
  ANNOUNCED = Time.utc(2026, 12, 1, 9, 0, 0)
  BUILT = Time.utc(2026, 12, 2, 2, 11, 44)
  RELEASES = "/repos/setdef/Fledge/releases?per_page=100&page=1"
  HEAD_RELEASE = "/repos/oneclick/rubyinstaller2/releases/tags/rubyinstaller-head"
  GH = <<~SH
    #!/bin/sh
    echo "$*" >> "$FAKE_GH_LOG"
    case "$1 $2" in
      "release create")
        for arg in "$@"; do
          case $arg in
            *.md) cp "$arg" "$FAKE_GH_NOTES" ;;
            *) [ ! -f "$arg" ] || cp "$arg" "$FAKE_GH_STORE/" ;;
          esac
        done ;;
      "release download")
        dir=.
        while [ $# -gt 0 ]; do [ "$1" = --dir ] && dir=$2; shift; done
        mkdir -p "$dir" && cp "$FAKE_GH_STORE"/* "$dir/"
        [ -z "$FAKE_GH_CORRUPT" ] || echo changed >> "$dir/$FAKE_GH_CORRUPT" ;;
    esac
  SH

  def setup
    skip "the workflow's script runs on Linux, with bash" if Gem.win_platform?
    skip "signing a test build needs gpg" unless system("gpg", "--version", out: File::NULL, err: File::NULL)
    @dir = Dir.mktmpdir
    @gnupg = File.join(@dir, "gnupg")
    FileUtils.mkdir_p(@gnupg, mode: 0o700)
    @fingerprint = make_key
    @files = FILES.reject { |name| name.end_with?(".asc") }.to_h { |name| [name, "#{name} built #{BUILT}"] }
    @files.dup.each { |name, bytes| @files["#{name}.asc"] = sign(bytes) }
    @key = gpg("--armor", "--export", @fingerprint)
    @key_sha256 = Digest::SHA256.hexdigest(@key)
    @released = []
    @kept = []
    @assets = FILES.to_h { |name| [name, BUILT] }
    @server = LoopbackServer.new(routes)
  end

  def teardown
    @server&.stop
    system({ "GNUPGHOME" => @gnupg }, "gpgconf", "--kill", "gpg-agent", out: File::NULL, err: File::NULL) if @gnupg
    FileUtils.rm_rf(@dir) if @dir
  end

  def test_nothing_after_preview1_has_appeared
    out, status = keep

    assert_predicate status, :success?, out
    assert_includes out, "nothing new"
    assert_empty downloads
    assert_empty published
  end

  def test_a_new_release_keeps_the_days_build_on_a_pre_release_named_for_both
    @released = %w[4.1.0-preview2]
    out, status = keep

    assert_predicate status, :success?, out
    create = published.fetch(0)
    assert_match(/\Arelease create inputs-rubyinstaller-head-20261202-for-4\.1\.0-preview2 /, create)
    assert_includes create, "--prerelease"
    assert_includes create, "--latest=false"
    assert_includes create, "--target 0123456789abcdef0123456789abcdef01234567"
    assert_equal FILES.sort, Dir.children(store).sort
    FILES.each { |name| assert_equal @files.fetch(name), File.binread(File.join(store, name)), name }
    assert_match(/\Arelease download inputs-rubyinstaller-head-20261202-for-4\.1\.0-preview2 /, published.fetch(1))
    assert_includes out, "kept inputs-rubyinstaller-head-20261202-for-4.1.0-preview2"
  end

  def test_the_notes_record_each_files_sha256_the_key_and_rubyinstallers_times
    @released = %w[4.1.0-preview2]
    out, status = keep

    assert_predicate status, :success?, out
    notes = File.read(self.notes)
    FILES.each do |name|
      assert_includes notes, "| `#{name}` | `#{Digest::SHA256.hexdigest(@files.fetch(name))}` | #{BUILT.iso8601} |"
    end
    assert_includes notes, @fingerprint
    assert_includes notes, ANNOUNCED.httpdate
    assert_includes notes, "Ruby 4.1.0-preview2"
  end

  # Each build's Ruby comes from the RUBY_DESCRIPTION in its DLL, which
  # 7-Zip reads out of the archive without running anything.
  def test_the_notes_name_each_builds_ruby_from_its_dll
    seven = %w[7z 7zz].find { |tool| system(tool, "i", out: File::NULL, err: File::NULL) }
    skip "reading a build's Ruby needs 7-Zip" unless seven
    %w[x64 arm].each { |arch| pack_build(seven, arch) }
    @released = %w[4.1.0-preview2]
    out, status = keep

    assert_predicate status, :success?, out
    notes = File.read(self.notes)
    %w[x64 arm].each do |arch|
      assert_includes notes, "- `rubyinstaller-head-#{arch}.7z`: ruby 4.1.0dev (2026-12-02 master 0738c9dfaa) [#{arch}-mingw-ucrt]\n"
    end
    refute_includes notes, "not read"
  end

  def test_a_dry_run_verifies_everything_and_publishes_nothing
    @released = %w[4.1.0-preview2]
    out, status = keep("DRY_RUN" => "1")

    assert_predicate status, :success?, out
    assert_equal FILES.sort, downloads.sort
    assert_includes out, "rubyinstaller-head-x64.7z: good signature from #{@fingerprint}"
    assert_includes out, "rubyinstaller-head-arm.7z: good signature from #{@fingerprint}"
    assert_includes out, "would keep inputs-rubyinstaller-head-20261202-for-4.1.0-preview2"
    assert_includes out, Digest::SHA256.hexdigest(@files.fetch("rubyinstaller-head-arm.7z"))
    assert_empty published
  end

  # Only the newest release's day can still be kept: the build of an
  # older one's day is gone by the time a newer one appears.
  def test_the_newest_release_is_the_one_kept
    @released = %w[4.1.0-preview2 4.1.0-rc1]
    out, status = keep

    assert_predicate status, :success?, out
    assert_match(/\Arelease create inputs-rubyinstaller-head-20261202-for-4\.1\.0-rc1 /, published.fetch(0))
  end

  def test_a_release_already_kept_is_left_alone
    @released = %w[4.1.0-preview2]
    @kept = %w[inputs-rubyinstaller-head-20261130-for-4.1.0-preview2]
    out, status = keep

    assert_predicate status, :success?, out
    assert_includes out, "already kept in inputs-rubyinstaller-head-20261130-for-4.1.0-preview2"
    assert_empty downloads
    assert_empty published
  end

  def test_a_pre_release_kept_for_another_version_does_not_count
    @released = %w[4.1.0-preview2 4.1.0-preview3]
    @kept = %w[inputs-rubyinstaller-head-20261130-for-4.1.0-preview2 inputs-rubyinstaller-head-20261110]
    out, status = keep

    assert_predicate status, :success?, out
    assert_match(/\Arelease create inputs-rubyinstaller-head-20261202-for-4\.1\.0-preview3 /, published.fetch(0))
  end

  # RubyInstaller's head build of the night before the release appeared
  # is not the release's: the run fails, keeps nothing, and the next one
  # tries again.
  def test_a_build_older_than_the_release_fails_and_keeps_nothing
    @released = %w[4.1.0-preview2]
    @assets["rubyinstaller-head-arm.7z"] = ANNOUNCED - 3600
    out, status = keep

    refute_predicate status, :success?, out
    assert_includes out, "rubyinstaller-head-arm.7z was built at #{(ANNOUNCED - 3600).iso8601}, before"
    assert_empty downloads
    assert_empty published
  end

  def test_a_bad_signature_fails_and_publishes_nothing
    @released = %w[4.1.0-preview2]
    @files["rubyinstaller-head-arm.7z"] = "tampered"
    out, status = keep

    refute_predicate status, :success?, out
    assert_includes out, "rubyinstaller-head-arm.7z is not signed by #{@fingerprint}"
    assert_empty published
  end

  def test_a_signature_from_another_key_fails
    @released = %w[4.1.0-preview2]
    other = Dir.mktmpdir(nil, @dir)
    @files["rubyinstaller-head-x64.7z.asc"] = sign(@files.fetch("rubyinstaller-head-x64.7z"), home: other, key: make_key(other))
    out, status = keep

    refute_predicate status, :success?, out
    assert_includes out, "rubyinstaller-head-x64.7z is not signed by #{@fingerprint}"
    assert_empty published
  ensure
    system({ "GNUPGHOME" => other }, "gpgconf", "--kill", "gpg-agent", out: File::NULL, err: File::NULL) if other
  end

  def test_a_key_that_does_not_match_its_pin_fails
    @released = %w[4.1.0-preview2]
    @key = "#{@key}\n"
    out, status = keep

    refute_predicate status, :success?, out
    assert_includes out, "signing-key.asc does not match its pin"
    assert_empty published
  end

  def test_a_failed_download_fails_and_publishes_nothing
    @released = %w[4.1.0-preview2]
    @files.delete("rubyinstaller-head-arm.7z.asc")
    out, status = keep

    refute_predicate status, :success?, out
    assert_empty published
  end

  # A build RubyInstaller replaced while the run downloaded it would be
  # kept with the other build's times.
  def test_a_build_replaced_while_downloading_fails
    @released = %w[4.1.0-preview2]
    reads = 0
    @server.stop
    @server = LoopbackServer.new(routes.merge(HEAD_RELEASE => lambda {
      reads += 1
      @assets["rubyinstaller-head-x64.7z"] = BUILT + 86_400 if reads > 1
      [200, {}, head_release]
    }))
    out, status = keep

    refute_predicate status, :success?, out
    assert_includes out, "changed while it was downloaded"
    assert_empty published
  end

  def test_a_file_read_back_that_differs_fails
    @released = %w[4.1.0-preview2]
    out, status = keep("FAKE_GH_CORRUPT" => "rubyinstaller-head-x64.7z")

    refute_predicate status, :success?, out
    assert_includes out, "rubyinstaller-head-x64.7z: FAILED"
  end

  def test_a_host_that_does_not_answer_fails_rather_than_skip_a_release
    @released = %w[4.1.0-preview2]
    @server.stop
    @server = LoopbackServer.new(routes.merge("/pub/ruby/4.1/ruby-4.1.0-rc1.tar.gz" => [503, {}, "busy"]))
    out, status = keep

    refute_predicate status, :success?, out
    assert_includes out, "ruby-4.1.0-rc1.tar.gz answered 503"
    assert_empty published
  end

  # The schedule, the inputs, and the permissions the job may use. The
  # script is the workflow's only step that does anything.
  def test_the_workflow_runs_on_a_schedule_off_the_hour_and_writes_only_where_it_publishes
    workflow = YAML.load_file(File.join(ROOT, ".github", "workflows", "keep-rubyinstaller-head.yml"))
    triggers = workflow.fetch(true)
    minute = triggers.fetch("schedule").fetch(0).fetch("cron").split.first

    refute_includes %w[0 00 30 *], minute
    assert_equal true, triggers.dig("workflow_dispatch", "inputs", "dry-run", "default")
    assert_empty workflow.fetch("permissions")
    jobs = workflow.fetch("jobs")
    assert_equal [{ "contents" => "write" }], jobs.values.map { |job| job.fetch("permissions") }
    uses = File.readlines(File.join(ROOT, ".github", "workflows", "keep-rubyinstaller-head.yml")).grep(/^\s*-? *uses:/)
    refute_empty uses
    uses.each { |line| assert_match(/uses: \S+@\h{40} # v\d/, line) }
  end

  private def keep(env = {})
    log = File.join(@dir, "gh.log")
    File.write(log, "")
    bin = File.join(@dir, "bin")
    FileUtils.mkdir_p([bin, store])
    File.write(File.join(bin, "gh"), GH)
    File.chmod(0o755, File.join(bin, "gh"))
    out, status = Open3.capture2e(environment(log, bin).merge(env), "bash", SCRIPT, chdir: @dir)
    @published = File.readlines(log, chomp: true)
    [out, status]
  end

  private def environment(log, bin)
    {
      "PATH" => "#{bin}#{File::PATH_SEPARATOR}#{ENV.fetch('PATH')}",
      "KEEP_SOURCES" => sources,
      "KEEP_RUBY_RELEASES_URL" => @server.url("/pub/ruby/4.1"),
      "KEEP_HEAD_URL" => @server.url("/head"),
      "GITHUB_API_URL" => @server.url(""),
      "GITHUB_REPOSITORY" => "setdef/Fledge",
      "GITHUB_SHA" => "0123456789abcdef0123456789abcdef01234567",
      "GITHUB_STEP_SUMMARY" => nil,
      "GITHUB_TOKEN" => nil,
      "GITHUB_RUN_ID" => nil,
      "DRY_RUN" => nil,
      "KEEP_VERSIONS" => nil,
      "FAKE_GH_LOG" => log,
      "FAKE_GH_STORE" => store,
      "FAKE_GH_NOTES" => notes,
      "FAKE_GH_CORRUPT" => nil,
    }
  end

  private def published = @published || []
  private def store = File.join(@dir, "store")
  private def notes = File.join(@dir, "notes.md")

  private def downloads
    @server.requests.filter_map { |path| path.delete_prefix("/head/") if path.start_with?("/head/") }
  end

  private def routes
    releases = VERSIONS.to_h do |version|
      path = "/pub/ruby/4.1/ruby-#{version}.tar.gz"
      [path, -> { @released.include?(version) ? [200, { "Last-Modified" => ANNOUNCED.httpdate }, ""] : [404, {}, "Not Found"] }]
    end
    files = FILES.to_h { |name| ["/head/#{name}", -> { @files.key?(name) ? [200, {}, @files.fetch(name)] : [404, {}, "Not Found"] }] }
    releases.merge(files).merge(
      "/key.asc" => -> { [200, {}, @key] },
      RELEASES => -> { [200, {}, JSON.generate(@kept.map { |tag| { "tag_name" => tag, "prerelease" => true } })] },
      HEAD_RELEASE => -> { [200, {}, head_release] }
    )
  end

  private def head_release
    assets = @assets.map { |name, time| { "name" => name, "size" => @files.fetch(name, "").bytesize, "updated_at" => time.iso8601 } }
    JSON.generate("tag_name" => "rubyinstaller-head", "assets" => assets + [{ "name" => "rubyinstaller-head-x64.exe", "size" => 1, "updated_at" => "2020-01-01T00:00:00Z" }])
  end

  private def sources
    path = File.join(@dir, "sources.yml")
    key = { "url" => @server.url("/key.asc"), "sha256" => @key_sha256, "fingerprint" => @fingerprint }
    platforms = %w[x64-mingw-ucrt aarch64-mingw-ucrt].to_h { |platform| [platform, { "signature" => { "key" => key } }] }
    File.write(path, YAML.dump("ruby" => { "platforms" => platforms }))
    path
  end

  private def make_key(home = @gnupg)
    gpg("--passphrase", "", "--quick-gen-key", "RubyInstaller stand-in <test@example.invalid>", "ed25519", "sign", "never", home:)
    gpg("--with-colons", "--list-keys", home:)[/^fpr:+(\h{40}):/, 1]
  end

  # A real 7-Zip archive laid out as RubyInstaller's, whose Ruby DLL
  # holds a RUBY_DESCRIPTION among other bytes, signed with the test key.
  private def pack_build(seven, arch)
    tree = File.join(@dir, "tree-#{arch}")
    bin = File.join(tree, "rubyinstaller-head-#{arch}", "bin")
    FileUtils.mkdir_p(bin)
    File.binwrite(File.join(bin, "#{arch}-ucrt-ruby410.dll"),
      "MZ\0\0ruby 4.1.0dev (2026-12-02 master 0738c9dfaa) [#{arch}-mingw-ucrt]\0\0#{'x' * 4_000_000}")
    archive = File.join(@dir, "#{arch}.7z")
    out, status = Open3.capture2e(seven, "a", "-bd", archive, "rubyinstaller-head-#{arch}", chdir: tree)
    assert_predicate status, :success?, out
    @files["rubyinstaller-head-#{arch}.7z"] = File.binread(archive)
    @files["rubyinstaller-head-#{arch}.7z.asc"] = sign(@files.fetch("rubyinstaller-head-#{arch}.7z"))
  end

  private def sign(bytes, home: @gnupg, key: @fingerprint)
    file = File.join(@dir, "to-sign")
    File.binwrite(file, bytes)
    gpg("--armor", "--local-user", key, "--output", "-", "--detach-sign", file, home:)
  end

  private def gpg(*args, home: @gnupg)
    out, err, status = Open3.capture3({ "GNUPGHOME" => home }, "gpg", "--batch", "--pinentry-mode", "loopback", "--quiet", *args)
    raise "gpg #{args.join(' ')}: #{err}" unless status.success?

    out
  end
end
