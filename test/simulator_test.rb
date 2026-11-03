# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "test_helper"
require_relative "../tasks/mobile_parity"

# The iOS check's simulators (ADR 011, section 6), with Xcode's own
# simctl: an iPhone and an iPad, created and booting at once, while the
# check builds its apps, and gone once deleted. Booting a simulator takes
# minutes, so these run only when FLEDGE_TEST_SIMULATORS is set, on a
# Mac with an iOS Simulator runtime; CI's Mobile apps (iOS Simulator)
# job runs the same code on every push.
class SimulatorTest < Minitest::Test
  def setup
    skip "set FLEDGE_TEST_SIMULATORS to boot iOS simulators" unless ENV["FLEDGE_TEST_SIMULATORS"]
    skip "the iOS Simulator runs on a Mac" unless RUBY_PLATFORM.include?("darwin")
  end

  def test_boots_an_iphone_and_an_ipad_at_once_and_deletes_both
    Dir.mktmpdir do |work|
      simulators = MobileParity::IOS::FAMILIES.map { |family| MobileParity::Simulator.boot(family, work:) }
      begin
        # Both boot in the background: neither is done when boot returns.
        assert simulators.all?(&:booting?)
        simulators.each(&:wait)
        refute simulators.any?(&:booting?)

        assert_equal %w[Booted Booted], simulators.map { |simulator| state(simulator.udid) }
        assert_match(/\AiPhone \(.+, iOS-/, simulators.first.name)
        assert_match(/\AiPad \(.+, iOS-/, simulators.last.name)
      ensure
        simulators.each(&:delete)
      end

      assert_equal [nil, nil], simulators.map { |simulator| state(simulator.udid) }
    end
  end

  # A check that fails while a simulator boots still deletes it.
  def test_deletes_a_simulator_still_booting
    Dir.mktmpdir do |work|
      simulator = MobileParity::Simulator.boot("iPhone", work:)
      simulator.delete

      assert_nil state(simulator.udid)
      assert_raises(MobileParity::Simulator::NotBooted) { simulator.wait }
    end
  end

  private def state(udid)
    devices = JSON.parse(IO.popen(%w[xcrun simctl list devices -j], &:read)).fetch("devices").values.flatten
    devices.find { |device| device.fetch("udid") == udid }&.fetch("state")
  end
end
