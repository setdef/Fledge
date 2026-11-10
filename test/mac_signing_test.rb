# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "test_helper"

# Signing with a timestamp when Apple's timestamp server does not answer
# (doc/contributors/design/signing.md, "Timestamps"). CI's signed build
# once failed with codesign's "A timestamp was expected but was not
# found." (run 42126058497, attempt 1, Build (arm64-darwin)) and passed
# when run again; VS Code and Defold sign again after a wait when
# codesign's output says so, and so does Fledge::MacSigning. Apple's
# server cannot be made to fail on demand, so a codesign placed first on
# +PATH+ fails as the runner's did for as many runs as a test asks, then
# runs the real codesign, which signs ad hoc, and the real
# Fledge::Command runs both.
class MacSigningTest < Minitest::Test
  BINARIES = File.expand_path("fixtures/binaries", __dir__)

  # A codesign that counts its runs in COUNT, fails with FAILURE for the
  # first FAILS of them, as codesign does, naming the file, and otherwise
  # is /usr/bin/codesign.
  CODESIGN = <<~SH
    #!/bin/sh
    count=$(( $(cat "$COUNT" 2>/dev/null || echo 0) + 1 ))
    echo "$count" > "$COUNT"
    if [ "$count" -le "$FAILS" ]; then
      for file; do :; done
      echo "$file: $FAILURE" >&2
      exit 1
    fi
    exec /usr/bin/codesign "$@"
  SH

  MISSING = "A timestamp was expected but was not found."
  UNAVAILABLE = "The timestamp service is not available."

  def setup
    skip "codesign is macOS's" unless RUBY_PLATFORM.include?("darwin")
  end

  def test_a_timestamp_server_that_does_not_answer_is_asked_again_until_the_code_is_signed
    [MISSING, UNAVAILABLE].each do |failure|
      with_codesign(fails: 2, failure:) do |dir, runs|
        program = macho(dir)

        Fledge::MacSigning.new("-", waits: [0, 0, 0]).sign_folder(dir)

        assert_equal 3, runs.call, failure
        assert_match(/flags=\S*\(adhoc,runtime\)/, Fledge::Command.run("/usr/bin/codesign", "-dv", program, install: ""))
      end
    end
  end

  # The image Fledge::Dmg writes, signed as fledge build --sign signs it.
  def test_a_disk_image_is_signed_again_too
    with_codesign(fails: 1, failure: UNAVAILABLE) do |dir, runs|
      bundle = File.join(dir, "A.app")
      FileUtils.mkdir_p(File.join(bundle, "Contents"))
      File.write(File.join(bundle, "Contents", "Info.plist"), "<plist/>")
      image = File.join(File.dirname(dir), "A.dmg")

      Fledge::Dmg.write(bundle, name: "A", to: image, signing: Fledge::MacSigning.new("-", waits: [0]))

      assert_equal 2, runs.call
      assert_includes Fledge::Command.run("/usr/bin/codesign", "-dv", image, install: ""), "Signature=adhoc"
    end
  end

  def test_a_server_still_silent_after_every_wait_fails_the_build_with_codesigns_words
    with_codesign(fails: 99, failure: MISSING) do |dir, runs|
      macho(dir)

      error = assert_raises(Fledge::Error) { Fledge::MacSigning.new("-", waits: [0, 0]).sign_folder(dir) }

      assert_includes error.message, MISSING
      assert_equal 3, runs.call
    end
  end

  # An identity the keychain lacks is the developer's to fix; asking
  # again would only delay saying so.
  def test_any_other_failure_is_not_tried_again
    with_codesign(fails: 1, failure: "no identity found") do |dir, runs|
      macho(dir)

      error = assert_raises(Fledge::Error) { Fledge::MacSigning.new("-", waits: [0, 0]).sign_folder(dir) }

      assert_includes error.message, "no identity found"
      assert_equal 1, runs.call
    end
  end

  # Defold's waits: 5 seconds, doubling, between five tries.
  def test_it_waits_as_defold_does
    assert_equal [5, 10, 20, 40], Fledge::MacSigning::WAITS
  end

  private def macho(dir)
    File.join(dir, "program").tap { |path| FileUtils.cp(File.join(BINARIES, Dir.glob("macho-*", base: BINARIES).min), path) }
  end

  private def with_codesign(fails:, failure:)
    Dir.mktmpdir do |root|
      bin = File.join(root, "bin")
      dir = File.join(root, "app")
      FileUtils.mkdir_p([bin, dir])
      File.write(File.join(bin, "codesign"), CODESIGN)
      File.chmod(0o755, File.join(bin, "codesign"))
      count = File.join(root, "count")
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
