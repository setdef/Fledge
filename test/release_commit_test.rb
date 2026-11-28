# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "test_helper"
require_relative "../tasks/release_commit"
require "tmpdir"

# The release commit and its record on trunk, written by
# tasks/release_commit.rb for a release made with nobody in it, on a
# copy of the files a release changes.
class ReleaseCommitTest < Minitest::Test
  CHANGELOG = <<~MARKDOWN
    # Changelog

    ## [Unreleased]

    ### Changed

    - libexample 2.0.1, from 2.0.0.

    ### Fixed

    - A gem's build that runs `strip` runs the NDK's.

    ## [0.17.0] - 2026-11-22

    ### Added

    - Something old.

    [Unreleased]: https://github.com/setdef/Fledge/compare/v0.17.0...HEAD
    [0.17.0]: https://github.com/setdef/Fledge/compare/v0.16.0...v0.17.0
  MARKDOWN

  def test_a_release_of_fixes_and_moved_pins_is_a_patch
    in_tree { |release| assert_equal "0.17.1", release.next_version }
  end

  def test_a_release_with_a_breaking_change_or_a_removal_moves_the_middle_number
    ["- **Breaking:** `fledge.yml`'s `icon` names no extension.", "- Breaking: Ruby 4.0."].each do |entry|
      in_tree(CHANGELOG.sub("### Fixed\n", "### Fixed\n\n#{entry}")) { |release| assert_equal "0.18.0", release.next_version }
    end
    in_tree(CHANGELOG.sub("### Fixed\n", "### Removed\n\n- `--target`.\n\n### Fixed\n")) { |release| assert_equal "0.18.0", release.next_version }
  end

  # From 1.0, SemVer's own rule: a break is a major, an addition or a
  # deprecation a minor, anything else a patch.
  def test_from_one_point_oh_a_break_is_a_major_and_an_addition_a_minor
    in_tree(version: "1.2.3") { |release| assert_equal "1.2.4", release.next_version }
    in_tree(CHANGELOG.sub("### Fixed", "### Added\n\n- A key.\n\n### Fixed"), version: "1.2.3") { |release| assert_equal "1.3.0", release.next_version }
    in_tree(CHANGELOG.sub("### Fixed\n", "### Fixed\n\n- **Breaking:** a key is gone."), version: "1.2.3") { |release| assert_equal "2.0.0", release.next_version }
  end

  def test_refuses_a_release_with_nothing_unreleased
    in_tree(CHANGELOG.sub(/### Changed.*?(?=## \[0\.17\.0\])/m, "")) do |release|
      assert_match(/nothing under \[Unreleased\]/, assert_raises(ReleaseCommit::Error) { release.next_version }.message)
    end
  end

  # A move of pins that ship nothing adds no CHANGELOG line, so a
  # release picked on it has nothing to say unless something else is
  # unreleased; the pin watch asks before it starts one.
  def test_a_changelog_is_pending_only_when_it_has_unreleased_entries
    assert ReleaseCommit.pending?(CHANGELOG)
    assert_equal false, ReleaseCommit.pending?(CHANGELOG.sub(/### Changed.*?(?=## \[0\.17\.0\])/m, ""))
  end

  def test_writes_the_version_everywhere_a_release_names_it_and_dates_the_changelog
    in_tree do |release, root|
      release.write("0.17.1", date: "2026-11-23")

      assert_equal "VERSION = \"0.17.1\"\n", File.read(File.join(root, "lib/fledge/version.rb"))
      assert_equal "    fledge (0.17.1)\n  fledge (0.17.1)\n", File.read(File.join(root, "Gemfile.lock"))
      assert_equal "# $schema=https://raw.githubusercontent.com/setdef/Fledge/v0.17.1/lib/fledge/config.schema.json\n" \
        "tag: \"v0.17.1\" fledge-runtime-0.17.1-arm64-darwin and fledge 0.17.1, not 10.17.0\n", File.read(File.join(root, "lib/fledge/config.rb"))
      changelog = File.read(File.join(root, "CHANGELOG.md"))
      assert_includes changelog, "## [Unreleased]\n\n## [0.17.1] - 2026-11-23\n\n### Changed\n\n- libexample 2.0.1, from 2.0.0.\n\n### Fixed\n"
      assert_includes changelog, "[Unreleased]: https://github.com/setdef/Fledge/compare/v0.17.1...HEAD\n" \
        "[0.17.1]: https://github.com/setdef/Fledge/compare/v0.17.0...v0.17.1\n[0.17.0]:"
    end
  end

  # On trunk, after the tag: what was released moves under the release,
  # and what landed on trunk after the released commit stays unreleased.
  def test_records_on_a_later_trunk_only_what_was_released
    released = ReleaseCommit.unreleased(CHANGELOG)
    later = CHANGELOG.sub("### Fixed\n\n", "### Fixed\n\n- Landed after the release was picked.\n")
      .sub("### Changed\n\n", "### Added\n\n- A key, also later.\n\n### Changed\n\n")
    in_tree(later) do |release, root|
      release.write("0.17.1", date: "2026-11-23", released:)

      changelog = File.read(File.join(root, "CHANGELOG.md"))
      assert_includes changelog, "## [Unreleased]\n\n### Added\n\n- A key, also later.\n\n### Fixed\n\n- Landed after the release was picked.\n\n" \
        "## [0.17.1] - 2026-11-23\n\n### Changed\n\n- libexample 2.0.1, from 2.0.0.\n\n### Fixed\n\n- A gem's build that runs `strip` runs the NDK's.\n\n## [0.17.0]"
    end
  end

  # A pin moved again after the release was picked: its line was
  # rewritten in place, still from the version before the release. The
  # record names the version the release shipped as its old one.
  def test_a_pin_moved_again_after_the_pick_is_from_the_version_the_release_shipped
    released = ReleaseCommit.unreleased(CHANGELOG)
    later = CHANGELOG.sub("libexample 2.0.1, from 2.0.0.", "libexample 2.0.2, from 2.0.0.")
    in_tree(later) do |release, root|
      release.write("0.17.1", date: "2026-11-23", released:)

      changelog = File.read(File.join(root, "CHANGELOG.md"))
      assert_includes changelog, "## [Unreleased]\n\n### Changed\n\n- libexample 2.0.2, from 2.0.1.\n\n## [0.17.1]"
      assert_includes changelog, "## [0.17.1] - 2026-11-23\n\n### Changed\n\n- libexample 2.0.1, from 2.0.0.\n"
    end
  end

  def test_refuses_a_file_that_no_longer_names_the_version
    in_tree do |release, root|
      File.write(File.join(root, "lib/fledge/config.rb"), "no version here\n")
      assert_match(%r{lib/fledge/config.rb names no 0.17.0}, assert_raises(ReleaseCommit::Error) { release.write("0.17.1", date: "2026-11-23") }.message)
    end
  end

  # The list of files is the repository's: each names the version today,
  # so a release would change every one of them.
  def test_every_file_the_release_rewrites_names_the_version_today
    root = File.expand_path("..", __dir__)
    version = ReleaseCommit.new(root:).current
    ReleaseCommit::FILES.each { |file| assert_includes File.read(File.join(root, file)), version, file }
  end

  private def in_tree(changelog = CHANGELOG, version: "0.17.0")
    Dir.mktmpdir do |root|
      files = {
        "CHANGELOG.md" => changelog.gsub("0.17.0", version),
        "lib/fledge/version.rb" => "VERSION = \"#{version}\"\n",
        "Gemfile.lock" => "    fledge (#{version})\n  fledge (#{version})\n",
        "lib/fledge/config.rb" => "# $schema=https://raw.githubusercontent.com/setdef/Fledge/v#{version}/lib/fledge/config.schema.json\n" \
          "tag: \"v#{version}\" fledge-runtime-#{version}-arm64-darwin and fledge #{version}, not 10.17.0\n",
        "lib/fledge/config.schema.json" => "{\"$id\": \"https://raw.githubusercontent.com/setdef/Fledge/v#{version}/lib/fledge/config.schema.json\"}\n",
      }
      files.each do |path, text|
        FileUtils.mkdir_p(File.dirname(File.join(root, path)))
        File.write(File.join(root, path), text)
      end
      yield ReleaseCommit.new(root:), root
    end
  end
end
