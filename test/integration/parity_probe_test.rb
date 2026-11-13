# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "../test_helper"
require_relative "../../tasks/parity"
require "open3"

# The parity check's probe (test/fixtures/parity) run as ruby main.rb
# runs it, under this Ruby: each run is a Ruby of its own that loads
# what the probe reports on. test/parity_test.rb covers how the check
# reads and compares the reports.
class ParityProbeTest < Minitest::Test
  # Runs the probe under this Ruby, outside the bundle, as ruby main.rb.
  def probe(*argv, env: {})
    run = -> { Open3.capture3(env, RbConfig.ruby, File.join(Parity::PROBE, "main.rb"), *argv) }
    defined?(Bundler) ? Bundler.with_unbundled_env(&run) : run.call
  end

  # Runs the probe under this Ruby with Bundler set up for +gemfile+, a
  # Gemfile of no gems, as bundle exec ruby main.rb would, and returns
  # what it printed.
  def bundled_probe(gemfile, *argv)
    out, err, status = Bundler.with_unbundled_env do
      Open3.capture3({ "BUNDLE_GEMFILE" => gemfile }, RbConfig.ruby, "-rbundler/setup", File.join(Parity::PROBE, "main.rb"), *argv)
    end
    assert_predicate status, :success?, err
    out
  end

  def test_the_probe_runs_under_this_ruby_and_reports_every_fact
    out, err, status = probe("a b")

    assert_predicate status, :success?, err
    facts = Parity::Reports.report(out)
    assert_equal ["a b"], facts.fetch("ARGV")
    assert_equal "42", facts.fetch("RbConfig.ruby runs")
    assert_equal "loads", facts.fetch("requireable").fetch("csv")
    assert_equal "found", facts.fetch("requireable").fetch("debug")
    %w[$0 $LOAD_PATH $LOADED_FEATURES Gem.path ENV child\ ENV Encoding.default_external RUBY_DESCRIPTION].each do |fact|
      assert facts.key?(fact), fact
    end
  end

  # rv-ruby's openssl.rb names the CA certificates it carries in ENV as
  # openssl loads, and so do the phones' (RuntimeBuilder::Certificates),
  # so the probe reports what require "openssl" adds to ENV, here from
  # an openssl.rb that stands in for one.
  def test_the_probe_reports_what_requiring_openssl_adds_to_env
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "openssl.rb"), "ENV['FLEDGE_PROBE_CERTIFICATES'] = 'named'\n")
      out, err, status = probe(env: { "RUBYLIB" => dir })

      assert_predicate status, :success?, err
      facts = Parity::Reports.report(out)
      assert_equal({ "FLEDGE_PROBE_CERTIFICATES" => "named" }, facts.fetch("ENV from require 'openssl'"))
      refute facts.fetch("ENV").key?("FLEDGE_PROBE_CERTIFICATES")
    end
  end

  # In a C locale an argument outside ASCII is a US-ASCII string with
  # bytes outside it; the probe still reports. Windows has no C locale:
  # Ruby takes its locale from the console's code page, never from
  # LC_ALL (localeinit.c, lines 48 to 51, at Ruby 4.1.0-preview1), and
  # the parity check runs the probe under code page 437 there instead
  # (ADR 003; doc/contributors/design/parity.md, "The environments").
  def test_the_probe_reports_in_a_c_locale
    skip "Windows has no C locale: Ruby's locale follows the console's code page (ADR 003)" if Gem.win_platform?

    out, err, status = probe("ünïcödé", env: { "LC_ALL" => "C" })

    assert_predicate status, :success?, err
    assert_equal "US-ASCII", Parity::Reports.report(out).fetch("Encoding.default_external")
  end

  def test_the_probe_tells_delivery_what_a_child_ruby_sees
    out, err, status = probe("child-env", "FLEDGE_PROBE_TEST", env: { "FLEDGE_PROBE_TEST" => "seen" })

    assert_predicate status, :success?, err
    assert_equal "seen\n", out
  end

  # Under Bundler, the probe starts a child Ruby inside
  # Bundler.with_original_env and with_unbundled_env, as a Bundler app
  # starts a person's own tools; without Bundler it says so.
  def test_the_probe_tells_delivery_what_a_child_ruby_sees_outside_the_bundle
    Dir.mktmpdir do |dir|
      gemfile = File.join(dir, "Gemfile")
      File.write(gemfile, "source \"https://rubygems.org\"\n")

      assert_equal "#{gemfile}\n", bundled_probe(gemfile, "original-child-env", "BUNDLE_GEMFILE")
      assert_equal "(unset)\n", bundled_probe(gemfile, "unbundled-child-env", "BUNDLE_GEMFILE")
      assert_match %r{bundler/setup}, bundled_probe(gemfile, "child-env", "RUBYOPT")
    end
    assert_equal "(no Bundler)\n", probe("original-child-env", "BUNDLE_GEMFILE").first
  end
end
