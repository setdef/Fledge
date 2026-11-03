# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "test_helper"
require_relative "../tasks/runtime_pins"
require "open3"
require "yaml"

# The two checks that let a pin commit run a short CI (ADR 014, section
# 5), run as CI runs them: .github/scripts/pins-only.sh, which says
# whether a commit is a pin commit, in real git repositories, and
# .github/scripts/check-pins.sh, which checks runtimes against the pins
# with sha256sum, on assets pinned by rake runtime:pin's own code. Both
# run on Linux runners; Windows' tests skip them.
class ReleaseChecksTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  PINS_ONLY = File.join(ROOT, ".github", "scripts", "pins-only.sh")
  CHECK_PINS = File.join(ROOT, ".github", "scripts", "check-pins.sh")

  def setup
    skip "the release's checks run on Linux and macOS, with sh" if Gem.win_platform?
  end

  def test_a_commit_that_changes_only_the_pins_is_a_pin_commit
    in_repository do |repository|
      commit(repository, "lib/fledge/SHA256SUMS" => "new pins\n")

      assert_equal "true", pins_only(repository)
    end
  end

  def test_a_commit_that_changes_anything_else_is_not
    in_repository do |repository|
      commit(repository, "lib/fledge/SHA256SUMS" => "new pins\n", "lib/fledge/version.rb" => "VERSION = 2\n")
      assert_equal "false", pins_only(repository)

      commit(repository, "README.md" => "changed\n")
      assert_equal "false", pins_only(repository)
    end
  end

  # Whose runtimes a merge's pins name depends on which parent's run they
  # came from, so a merge runs the whole of CI, even one whose diff from
  # its first parent is only the pins.
  def test_a_merge_is_not_a_pin_commit_even_when_its_diff_is_only_the_pins
    in_repository do |repository|
      git(repository, "checkout", "--quiet", "-b", "side")
      commit(repository, "lib/fledge/SHA256SUMS" => "new pins\n")
      git(repository, "checkout", "--quiet", "trunk")
      commit(repository, "README.md" => "changed\n")
      git(repository, "merge", "--quiet", "--no-ff", "-m", "Merge", "side")

      assert_equal "lib/fledge/SHA256SUMS", git(repository, "diff", "--name-only", "HEAD^", "HEAD").strip
      assert_equal "false", pins_only(repository)
    end
  end

  def test_a_first_commit_and_a_clone_without_the_parent_are_not
    in_repository do |repository|
      assert_equal "false", pins_only(repository)

      commit(repository, "lib/fledge/SHA256SUMS" => "new pins\n")
      Dir.mktmpdir do |dir|
        shallow = File.join(dir, "shallow")
        git(dir, "clone", "--quiet", "--depth", "1", "file://#{repository}", shallow)
        assert_equal "false", pins_only(shallow)
      end
    end
  end

  def test_runtimes_that_match_their_pins_pass
    with_pinned_assets do |assets, pins|
      out, status = check_pins(assets, pins)

      assert_predicate status, :success?, out
      assert_includes out, "#{RuntimeBuilder.release_assets.first}: OK"
    end
  end

  # A pin written from other bytes than the runtime's: the check must
  # refuse it, as it would refuse a pin commit whose pins came from
  # another run than its parent's.
  def test_a_wrong_pin_fails
    with_pinned_assets do |assets, pins|
      name = RuntimeBuilder.release_assets.first
      wrong = File.read(pins).sub(/^\h{64}(?=  #{Regexp.escape(name)}$)/, Digest::SHA256.hexdigest("another build of #{name}"))
      File.write(pins, wrong)
      out, status = check_pins(assets, pins)

      refute_predicate status, :success?, out
      assert_includes out, "#{name}: FAILED"
    end
  end

  def test_a_runtime_changed_after_it_was_pinned_fails
    with_pinned_assets do |assets, pins|
      name = RuntimeBuilder.release_assets.last
      File.write(File.join(assets, name), "rebuilt")
      out, status = check_pins(assets, pins)

      refute_predicate status, :success?, out
      assert_includes out, "#{name}: FAILED"
    end
  end

  def test_assets_that_are_not_exactly_the_releases_fail
    with_pinned_assets do |assets, pins|
      File.write(File.join(assets, "stray.txt"), "stray")
      out, status = check_pins(assets, pins)

      refute_predicate status, :success?, out
      assert_includes out, "> stray.txt"
    end
  end

  def test_pins_that_leave_an_asset_out_fail
    with_pinned_assets do |assets, pins|
      File.write(pins, File.readlines(pins).drop(1).join)
      out, status = check_pins(assets, pins)

      refute_predicate status, :success?, out
      assert_includes out, "does not pin exactly"
    end
  end

  # release.yml requires the release commit's run to have skipped no
  # job, so no job of ci.yml may be skipped on any commit but a pin
  # commit; and a pin commit's run stays short only while every job with
  # no needs of its own, but the gate and Changes, is skipped on one.
  def test_ci_skips_jobs_on_pin_commits_and_only_there
    jobs = YAML.load_file(File.join(ROOT, ".github", "workflows", "ci.yml"), aliases: true).fetch("jobs")
    conditions = jobs.filter_map { |id, job| [id, job["if"]] if job.key?("if") }.to_h.values.uniq
    roots = jobs.reject { |_, job| job.key?("needs") }.keys

    assert_equal ["needs.changes.outputs.pins-only != 'true'"], conditions
    assert_equal %w[changes gate], roots.sort
    assert jobs.select { |_, job| job["needs"] == "changes" }.all? { |_, job| job.key?("if") }
  end

  private def with_pinned_assets
    Dir.mktmpdir do |dir|
      assets = File.join(dir, "assets")
      FileUtils.mkdir_p(assets)
      RuntimeBuilder.release_assets.each { |name| File.write(File.join(assets, name), "the bytes of #{name}") }
      pins = RuntimePins.write(assets, to: File.join(dir, "SHA256SUMS"))
      yield assets, pins
    end
  end

  private def check_pins(assets, pins)
    Dir.mktmpdir { |elsewhere| Open3.capture2e("sh", CHECK_PINS, assets, pins, chdir: elsewhere) }
  end

  private def in_repository
    Dir.mktmpdir do |dir|
      repository = File.join(dir, "repository")
      FileUtils.mkdir_p(repository)
      git(repository, "init", "--quiet", "--initial-branch=trunk")
      commit(repository, "lib/fledge/SHA256SUMS" => "old pins\n", "README.md" => "Fledge\n")
      yield repository
    end
  end

  private def commit(repository, files)
    files.each do |path, content|
      FileUtils.mkdir_p(File.dirname(File.join(repository, path)))
      File.write(File.join(repository, path), content)
    end
    git(repository, "add", ".")
    git(repository, "commit", "--quiet", "-m", "Change #{files.keys.join(', ')}")
  end

  private def pins_only(repository)
    out, status = Open3.capture2e("sh", PINS_ONLY, chdir: repository)
    assert_predicate status, :success?, out
    out.strip
  end

  private def git(directory, *arguments)
    out, status = Open3.capture2e("git", "-c", "user.name=Fledge", "-c", "user.email=fledge@example.com", *arguments, chdir: directory)
    raise "git #{arguments.join(' ')} failed: #{out}" unless status.success?

    out
  end
end
