# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "test_helper"
require_relative "../tasks/mobile_parity"

# The parts of the mobile parity check (ADR 011, section 6) that need no
# simulator or emulator: reading the probe's report back from the
# entries of a system log, the reference Ruby's environment, and the
# justifications for what a phone does differently. CI's mobile parity
# jobs run the probe in the iOS Simulator and an Android emulator.
class MobileParityTest < Minitest::Test
  # The embedding API sends a line longer than a log entry holds as
  # several entries in a row, so the report is the entries from its
  # first, joined, up to where they make a JSON object.
  def test_reads_the_report_from_the_log_entries_it_was_split_into
    json = JSON.generate({ "ARGV" => [], "long" => "é" * 900 })
    entries = ["booting", "FLEDGE-PARITY #{json[0, 700]}", json[700, 1000], json[1700..], "FLEDGE-MOBILE-STATUS 0"]

    assert_equal JSON.parse(json), MobileParity.report(entries)
  end

  def test_a_log_without_a_whole_report_fails
    assert_raises(RuntimeError) { MobileParity.report(["FLEDGE-PARITY {\"ARGV\":"]) }
    assert_raises(RuntimeError) { MobileParity.report(["nothing here"]) }
  end

  def test_the_status_is_the_hosts_last_word
    assert_equal 0, MobileParity.status(["a", "FLEDGE-MOBILE-STATUS 0"])
    assert_equal 1, MobileParity.status(["FLEDGE-MOBILE-STATUS 1"])
    assert_nil MobileParity.status(["a"])
  end

  # The reference runs as a person runs ruby main.rb: in a UTF-8 locale,
  # with a home folder of its own and nothing of the runner's Ruby.
  def test_the_reference_runs_with_a_persons_plain_environment
    env = MobileParity.reference_environment("/work", { "PATH" => "/bin", "RUBYOPT" => "-W0", "GEM_HOME" => "/g", "CI" => "true" })

    assert_equal({ "PATH" => "/bin", "HOME" => "/work/home", "LANG" => "en_US.UTF-8" }, env)
  end

  # A phone starts an app with the system's own environment, so ENV and
  # the facts that come from it differ wholly from a person's, on every
  # mobile target, and only there.
  def test_a_phones_environment_is_justified_on_mobile_targets_only
    reference = { "ENV" => { "PATH" => "/bin", "HOME" => "<home>" } }
    app = { "ENV" => { "HOME" => "<home>", "SIMULATOR_UDID" => "X", "SSL_CERT_FILE" => "<prefix>/libexec/cert.pem" } }

    %w[arm64-ios-simulator x86_64-linux-android].each do |target|
      assert Parity::Reports.compare(reference, app, platform: target).all?(&:justified?), target
    end
    refute Parity::Reports.compare(reference, app, platform: "x86_64-linux").all?(&:justified?)
  end
end
