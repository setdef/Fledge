# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "test_helper"

# A Mac app's disk image when <tt>hdiutil create</tt> finds its volume
# busy (ADR 010, section 3). On a GitHub macOS runner hdiutil sometimes
# fails with "create failed - Resource busy" when another process
# (XProtect, by the runner image's maintainers' account) holds the
# scratch volume it makes the image from; create-dmg tries again after
# a wait when its output says so, and so does Fledge::Dmg. The failure
# cannot be provoked on demand, so an hdiutil placed first on +PATH+
# fails as the runner's did for as many runs as a test asks, then
# writes the image; the real ditto copies the bundle and the real
# Fledge::Command runs both.
class DmgTest < Minitest::Test
  # An hdiutil that counts its runs in COUNT, fails with FAILURE for the
  # first FAILS of them, and otherwise writes its last argument, the
  # image.
  HDIUTIL = <<~SH
    #!/bin/sh
    count=$(( $(cat "$COUNT" 2>/dev/null || echo 0) + 1 ))
    echo "$count" > "$COUNT"
    if [ "$count" -le "$FAILS" ]; then
      echo "$FAILURE" >&2
      exit 1
    fi
    for image; do :; done
    echo image > "$image"
  SH

  BUSY = "hdiutil: create failed - Resource busy"

  def setup
    skip "a Mac app's disk image is made on a Mac" unless RUBY_PLATFORM.include?("darwin")
  end

  def test_a_busy_volume_is_tried_again_until_hdiutil_makes_the_image
    with_hdiutil(fails: 2, failure: BUSY) do |dir, runs|
      to = File.join(dir, "A.dmg")

      assert_equal to, Fledge::Dmg.write(bundle(dir), name: "A", to:, waits: [0, 0, 0, 0])
      assert_equal "image\n", File.read(to)
      assert_equal 3, runs.call
    end
  end

  def test_a_volume_still_busy_after_every_wait_fails_the_build_with_hdiutils_words
    with_hdiutil(fails: 99, failure: BUSY) do |dir, runs|
      error = assert_raises(Fledge::Error) { Fledge::Dmg.write(bundle(dir), name: "A", to: File.join(dir, "A.dmg"), waits: [0, 0]) }

      assert_includes error.message, BUSY
      assert_equal 3, runs.call
    end
  end

  def test_any_other_failure_is_not_tried_again
    with_hdiutil(fails: 1, failure: "hdiutil: create failed - No space left on device") do |dir, runs|
      error = assert_raises(Fledge::Error) { Fledge::Dmg.write(bundle(dir), name: "A", to: File.join(dir, "A.dmg"), waits: [0, 0]) }

      assert_includes error.message, "No space left on device"
      assert_equal 1, runs.call
    end
  end

  # create-dmg's own waits: 2, 4, 8, and 16 seconds between five tries.
  def test_it_waits_as_create_dmg_does
    assert_equal [2, 4, 8, 16], Fledge::Dmg::WAITS
  end

  private def bundle(dir)
    File.join(dir, "A.app").tap do |app|
      FileUtils.mkdir_p(File.join(app, "Contents"))
      File.write(File.join(app, "Contents", "Info.plist"), "<plist/>")
    end
  end

  private def with_hdiutil(fails:, failure:)
    Dir.mktmpdir do |dir|
      bin = File.join(dir, "bin")
      FileUtils.mkdir_p(bin)
      File.write(File.join(bin, "hdiutil"), HDIUTIL)
      File.chmod(0o755, File.join(bin, "hdiutil"))
      count = File.join(dir, "count")
      saved = ENV.to_h.slice("PATH", "COUNT", "FAILS", "FAILURE")
      ENV.update("PATH" => "#{bin}:#{ENV.fetch('PATH')}", "COUNT" => count, "FAILS" => fails.to_s, "FAILURE" => failure)
      begin
        yield dir, -> { File.read(count).to_i }
      ensure
        %w[PATH COUNT FAILS FAILURE].each { |key| ENV[key] = saved[key] }
      end
    end
  end
end
