# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "test_helper"
require_relative "../tasks/ruby_spec"

# How the ruby/spec comparison reads MSpec's reports and compares a
# built app's with stock Ruby's. CI's ruby/spec jobs run the comparison
# itself (tasks/ruby_spec.rb) on real runtimes.
class RubySpecTest < Minitest::Test
  # What mspec-run's default formatter prints, with an error whose
  # description follows "An exception occurred during:", and Windows'
  # line endings.
  OUTPUT = <<~OUT.gsub("\n", "\r\n")
    ruby 4.0.9 (2026-10-23 revision 3e93b23afc) +PRISM [x86_64-linux]
    ..F.E

    1)
    Encoding.locale_charmap when setting LC_ALL=C returns a value based on the LC_ALL environment variable FAILED
    Expected "UTF-8" == "US-ASCII"
    to be truthy but was false
    /work/spec/core/encoding/locale_charmap_spec.rb:30:in 'block (4 levels) in <top (required)>'

    2)
    An exception occurred during: before :each
    mkmf can be required with --enable-frozen-string-literal ERROR
    RuntimeError: boom

    Finished in 1.234 seconds

    2 files, 5 examples, 7 expectations, 1 failure, 1 error, 0 tagged
  OUT

  def test_a_report_lists_each_failure_and_error_and_its_totals
    result = RubySpec::Results.read("core", OUTPUT)

    assert_equal [
      "core: Encoding.locale_charmap when setting LC_ALL=C returns a value based on the LC_ALL environment variable",
      "core: mkmf can be required with --enable-frozen-string-literal",
    ], result.failures.keys
    assert_includes result.failures.values.first, "Expected \"UTF-8\" == \"US-ASCII\""
    assert_equal "2 files, 5 examples, 7 expectations, 1 failure, 1 error, 0 tagged", result.totals
  end

  def test_a_run_that_stopped_has_no_totals
    assert_nil RubySpec::Results.read("core", "ruby 4.0.9\n...\n[BUG] Segmentation fault\n").totals
  end

  def results(**failures_by_side)
    failures_by_side.transform_values do |failures|
      [RubySpec::Results::Run.new(directory: "core", failures: failures.to_h { |name| ["core: #{name}", ""] }, totals: "1 file")]
    end
  end

  def test_the_same_failures_on_both_sides_are_no_difference
    runs = results(stock: ["A fails"], app: ["A fails"])

    assert_empty RubySpec::Results.compare(runs.fetch(:stock), runs.fetch(:app), platform: "x86_64-linux")
  end

  def test_a_failure_on_one_side_only_is_a_difference_unless_justified
    runs = results(stock: [], app: ["mkmf can be required with --enable-frozen-string-literal"])
    differences = RubySpec::Results.compare(runs.fetch(:stock), runs.fetch(:app), platform: "x86_64-linux")

    assert_equal 1, differences.size
    refute_predicate differences.first, :justified?
    assert_equal "DIFFERENT: fails in the built app only: core: mkmf can be required with --enable-frozen-string-literal",
      differences.first.to_s.lines.first.chomp
  end

  # With no locale, stock Ruby reads paths as US-ASCII where a built app,
  # whose launcher takes a UTF-8 locale (ADR 026, section 1), reads them
  # as UTF-8, so examples that need an ASCII-compatible encoding other
  # than UTF-8 fail under stock Ruby only, and only on macOS and Linux.
  def test_a_justified_difference_names_its_reason_and_holds_only_where_listed
    name = "Dir.chdir accepts a path in a non-UTF-8, ASCII-compatible encoding containing non-ASCII characters"
    runs = results(stock: [name], app: [])

    difference = RubySpec::Results.compare(runs.fetch(:stock), runs.fetch(:app), platform: "arm64-darwin").first
    assert_predicate difference, :justified?
    assert_includes difference.to_s, "why: "
    refute_predicate RubySpec::Results.compare(runs.fetch(:app), runs.fetch(:stock), platform: "arm64-darwin").first, :justified?,
      "the same failure in the app only is not justified"
    refute_predicate RubySpec::Results.compare(runs.fetch(:stock), runs.fetch(:app), platform: "x64-mingw-ucrt").first, :justified?
  end

  def test_a_run_that_did_not_finish_is_a_difference
    stopped = [RubySpec::Results::Run.new(directory: "core", failures: {}, totals: nil)]
    finished = [RubySpec::Results::Run.new(directory: "core", failures: {}, totals: "1 file")]

    differences = RubySpec::Results.compare(finished, stopped, platform: "x86_64-linux")

    assert_equal ["DIFFERENT: core did not finish in the built app"], differences.map(&:to_s)
    assert_equal 2, RubySpec::Results.compare(stopped, stopped, platform: "x86_64-linux").size
  end

  # The pins are commits of ruby/spec and MSpec, each downloaded from
  # GitHub's archive of that commit and checked against its SHA-256.
  def test_each_source_is_pinned_by_commit_and_sha256
    RubySpec::SOURCES.each do |source|
      assert_match(/\A\h{40}\z/, source.commit)
      assert_match(/\A\h{64}\z/, source.sha256)
      assert_equal "https://github.com/ruby/#{source.name}/archive/#{source.commit}.tar.gz", source.url
    end
  end
end
