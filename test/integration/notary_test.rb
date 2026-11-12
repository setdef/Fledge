# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "../test_helper"
require_relative "../support/stand_in_notary"

# Fledge::Notary, Fledge's gateway to Apple's notary service (ADR 033):
# what it asks notarytool and stapler, in which order, and what it says
# when Apple does not accept an app. No CI runner and no agent has an
# Apple Developer account, so the service is the stand-in xcrun of
# test/support/stand_in_notary.rb, which answers as Apple documents;
# ditto, which zips what is submitted, is the real one. A run with the
# maintainer's own account is test/integration/built_app_test.rb's
# test_a_notarized_build_opens_with_gatekeepers_blessing, with
# FLEDGE_TEST_NOTARY_PROFILE set.
class NotaryTest < Minitest::Test
  PROFILE = "fledge-notary"

  def setup
    skip "notarytool and stapler are macOS's" unless RUBY_PLATFORM.include?("darwin")
  end

  # A disk image is the outermost container, and the only one sent;
  # Apple's ticket is stapled to it, and to the bundle in the folder,
  # which the service issued a ticket for too, each then validated.
  def test_a_disk_image_is_submitted_and_it_and_the_bundle_are_stapled
    StandInNotary.with do |calls, submitted|
      Dir.mktmpdir do |dir|
        folder, bundle = app(dir)
        image = File.join(dir, "Hello Window-arm64-darwin.dmg")
        File.write(image, "image")
        log = StringIO.new

        Fledge::Notary.new(PROFILE, log:).notarize(folder, bundle:, image:)

        assert_equal [
          ["notarytool", "submit", image, "--keychain-profile", PROFILE, "--wait", "--output-format", "json"],
          ["stapler", "staple", File.basename(image), "(in #{File.realpath(dir)})"],
          ["stapler", "validate", File.basename(image), "(in #{File.realpath(dir)})"],
          ["stapler", "staple", "Hello Window.app", "(in #{File.realpath(folder)})"],
          ["stapler", "validate", "Hello Window.app", "(in #{File.realpath(folder)})"],
        ], calls.call
        assert_equal ["Hello Window-arm64-darwin.dmg"], Dir.children(submitted)
        assert_equal StandInNotary::TICKET, File.read(File.join(bundle, "Contents", "CodeResources")).chomp
        assert_includes log.string, "Apple accepted Hello Window-arm64-darwin.dmg (submission #{StandInNotary::ID})"
      end
    end
  end

  # With no disk image (installers: [] in fledge.yml), the bundle goes in
  # a zip archive, as ditto makes one for Apple, and is stapled.
  def test_a_bundle_alone_is_zipped_and_stapled
    StandInNotary.with do |calls, submitted|
      Dir.mktmpdir do |dir|
        folder, bundle = app(dir)

        Fledge::Notary.new(PROFILE).notarize(folder, bundle:)

        submit, *staples = calls.call
        assert_equal ["notarytool", "submit"], submit.first(2)
        assert_equal "Hello Window.app.zip", File.basename(submit[2])
        assert_equal [%w[stapler staple], %w[stapler validate]], staples.map { |call| call.first(2) }
        assert_equal ["Hello Window.app/", "Hello Window.app/Contents/", "Hello Window.app/Contents/Info.plist"], entries(submitted)
      end
    end
  end

  # A console app's programs are lone Mach-O files, which can hold no
  # ticket ("Customizing the notarization workflow"): its folder is
  # zipped and submitted, and nothing is stapled; Gatekeeper finds the
  # ticket online.
  def test_a_console_app_is_zipped_whole_and_nothing_is_stapled
    StandInNotary.with do |calls, submitted|
      Dir.mktmpdir do |dir|
        folder = File.join(dir, "Hello-arm64-darwin")
        FileUtils.mkdir_p(folder)
        File.write(File.join(folder, "Hello"), "program")

        Fledge::Notary.new(PROFILE).notarize(folder)

        assert_equal [%w[notarytool submit]], calls.call.map { |call| call.first(2) }
        assert_equal ["Hello-arm64-darwin/", "Hello-arm64-darwin/Hello"], entries(submitted)
      end
    end
  end

  # An Invalid answer fails the build with what the submission's log
  # says, issue by issue, and how to read the rest; nothing is stapled.
  def test_an_invalid_submission_fails_with_the_issues_its_log_names
    StandInNotary.with("invalid") do |calls, _|
      Dir.mktmpdir do |dir|
        folder, bundle = app(dir)
        image = File.join(dir, "Hello Window-arm64-darwin.dmg")
        File.write(image, "image")

        error = assert_raises(Fledge::Error) { Fledge::Notary.new(PROFILE).notarize(folder, bundle:, image:) }

        assert_equal <<~MESSAGE.chomp, error.message
          Apple did not notarize Hello Window-arm64-darwin.dmg: Invalid (submission #{StandInNotary::ID}).
          Archive contains critical validation errors
            error: Hello Window-arm64-darwin.dmg/Hello Window.app/Contents/MacOS/Hello Window: The signature of the binary is invalid. https://developer.apple.com/documentation/security/resolving-common-notarization-issues
          Read the whole log with: xcrun notarytool log #{StandInNotary::ID} --keychain-profile #{PROFILE}
        MESSAGE
        assert_equal [%w[notarytool submit], %w[notarytool log]], calls.call.map { |call| call.first(2) }
        assert_equal ["notarytool", "log", StandInNotary::ID, "--keychain-profile", PROFILE], calls.call.last
        refute File.exist?(File.join(bundle, "Contents", "CodeResources"))
      end
    end
  end

  # notarytool that cannot reach Apple says so; the build fails with its
  # words, and asks for no log, since there is no submission.
  def test_a_network_failure_fails_with_notarytools_words
    StandInNotary.with("offline") do |calls, _|
      Dir.mktmpdir do |dir|
        folder = File.join(dir, "Hello-arm64-darwin")
        FileUtils.mkdir_p(folder)

        error = assert_raises(Fledge::Error) { Fledge::Notary.new(PROFILE).notarize(folder) }

        assert_match(/\Anotarytool could not notarize Hello-arm64-darwin\.zip \(pid \d+ exit 1\):\n/, error.message)
        assert_includes error.message, "Error: The Internet connection appears to be offline."
        assert_equal [%w[notarytool submit]], calls.call.map { |call| call.first(2) }
      end
    end
  end

  # A profile the keychain does not hold: notarytool's own message, and
  # how to store one under that name.
  def test_a_missing_profile_says_how_to_store_one
    StandInNotary.with("missing") do |_, _|
      Dir.mktmpdir do |dir|
        folder = File.join(dir, "Hello-arm64-darwin")
        FileUtils.mkdir_p(folder)

        error = assert_raises(Fledge::Error) { Fledge::Notary.new("nobody").notarize(folder) }

        assert_includes error.message, "Error: No Keychain password item found for profile: nobody"
        assert_includes error.message, "Store your credentials under that name once, with xcrun notarytool store-credentials nobody"
      end
    end
  end

  # Fledge passes notarytool a keychain profile and nothing else that
  # authenticates: no Apple ID, password, team, or App Store Connect key
  # ever appears in its arguments, where any process could read it.
  def test_credentials_never_reach_a_command_line
    StandInNotary.with do |calls, _|
      Dir.mktmpdir do |dir|
        folder, bundle = app(dir)

        Fledge::Notary.new(PROFILE).notarize(folder, bundle:)

        arguments = calls.call.flatten
        %w[--apple-id --password --team-id --key --key-id --issuer -k -d -i].each { |option| refute_includes arguments, option }
      end
    end
  end

  # A windowed app's folder, with its bundle, under +dir+.
  private def app(dir)
    folder = File.join(dir, "Hello Window-arm64-darwin")
    bundle = File.join(folder, "Hello Window.app")
    FileUtils.mkdir_p(File.join(bundle, "Contents"))
    File.write(File.join(bundle, "Contents", "Info.plist"), "<plist/>")
    [folder, bundle]
  end

  # The names in the one zip archive submitted into +submitted+, as
  # zipinfo lists them, but for the extended attributes ditto keeps
  # beside them, in __MACOSX.
  private def entries(submitted)
    zip = Dir.glob("*.zip", base: submitted).first
    names = Fledge::Command.run("zipinfo", "-1", File.join(submitted, zip.to_s), install: "").lines.map(&:chomp)
    names.reject { |name| name.start_with?("__MACOSX/") }.sort
  end
end
