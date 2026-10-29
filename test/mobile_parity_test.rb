# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "test_helper"
require_relative "../tasks/mobile_parity"

# The parts of the mobile check (ADR 011, section 6; ADR 012) that need no
# simulator or emulator: reading the probe's report and an app's status
# back from the entries of a system log, the apps it builds, the
# reference Ruby's environment, and the justifications for what a phone
# does differently. CI's Mobile apps jobs build the apps with fledge
# build and run them in the iOS Simulator and Android emulators.
class MobileParityTest < Minitest::Test
  # The embedding API sends a line longer than a log entry holds as
  # several entries in a row, so the report is the entries from its
  # first, joined, up to where they make a JSON object, but for the
  # host's status line, which its thread may log among them.
  def test_reads_the_report_from_the_log_entries_it_was_split_into
    json = JSON.generate({ "ARGV" => [], "long" => "é" * 900 })
    entries = ["booting", "FLEDGE-PARITY #{json[0, 700]}", json[700, 1000], "Parity exited with status 0", json[1700..]]

    assert_equal JSON.parse(json), MobileParity.report(entries)
  end

  def test_a_log_without_a_whole_report_fails
    assert_raises(RuntimeError) { MobileParity.report(["FLEDGE-PARITY {\"ARGV\":"]) }
    assert_raises(RuntimeError) { MobileParity.report(["nothing here"]) }
  end

  # The host app of every project fledge build writes logs the app's
  # exit status when its program ends (ADR 012).
  def test_the_status_is_the_hosts_last_word
    assert_equal 0, MobileParity.status(["a", "Mobile App exited with status 0"])
    assert_equal 1, MobileParity.status(["Hello exited with status 1"])
    assert_nil MobileParity.status(["a", "exited with status 0"])
  end

  # Each app the check builds names itself as its fledge.yml does, so its
  # project, scheme, and log are found by those names.
  def test_each_app_is_named_as_its_fledge_yml_names_it
    MobileParity::APPS.each do |app|
      built = Fledge::App.at(File.join(MobileParity::ROOT, app.path))
      assert_equal [app.name, app.identifier], [built.name, built.identity.identifier], app.path
    end
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
