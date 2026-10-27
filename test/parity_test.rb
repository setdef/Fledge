# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "test_helper"
require_relative "../tasks/parity"

# How the parity check reads, normalizes, and compares the probe's
# reports. CI's test jobs run the check itself (rake parity) against a
# real runtime and the Ruby it was made from.
class ParityTest < Minitest::Test
  def report(**facts)
    { "paths" => { "app" => "/w/app", "prefix" => "/w/ruby", "home" => "/w/home" } }.merge(facts.transform_keys(&:to_s))
  end

  def test_the_report_is_the_last_marked_line_of_output
    output = "noise\nFLEDGE-PARITY {\"a\":1}\nmore noise\nFLEDGE-PARITY {\"a\":2}\n"

    assert_equal({ "a" => 2 }, Parity.report(output))
    assert_raises(RuntimeError) { Parity.report("no report\n") }
  end

  def test_normalize_replaces_the_longest_paths_first_and_backslashes
    normalized = Parity.normalize(report("$0": "/w/app/main.rb", "Gem.path": ["/w/ruby/lib", "C:\\w\\x"],
      ENV: { "GEM_HOME" => "/tmp/work/gems" }), work: "/tmp/work")

    assert_equal "<app>/main.rb", normalized.fetch("$0")
    assert_equal ["<prefix>/lib", "C:/w/x"], normalized.fetch("Gem.path")
    assert_equal({ "GEM_HOME" => "<work>/gems" }, normalized.fetch("ENV"))
    refute normalized.key?("paths")
  end

  def test_equal_reports_have_no_differences
    facts = { "ARGV" => ["one"], "ENV" => { "A" => "1" }, "$stdout.sync" => false }

    assert_empty Parity.compare(facts, facts, platform: "x86_64-linux")
  end

  def test_a_listed_difference_is_justified_and_says_why
    differences = Parity.compare({ "$0" => "main.rb" }, { "$0" => "<app>/main.rb" }, platform: "x86_64-linux")

    assert_equal 1, differences.size
    assert_predicate differences.first, :justified?
    assert_includes differences.first.to_s, "why: ruby main.rb names the script as typed"
  end

  def test_an_unlisted_difference_is_not_justified
    differences = Parity.compare({ "ENV" => { "A" => "1" } }, { "ENV" => { "A" => "2" } }, platform: "x86_64-linux")

    refute_predicate differences.first, :justified?
    assert_equal "DIFFERENT: ENV\n    reference only: \"A\"=\"1\"\n    built app only: \"A\"=\"2\"", differences.first.to_s
  end

  # A justification covers only the elements it names: one more
  # difference in the same fact is not justified.
  def test_a_justification_does_not_cover_other_elements_of_its_fact
    reference = { "gems" => ["bootsnap 1.24.6", "csv 3.3.5", "json 2.18.0 (default)"] }

    assert_predicate Parity.compare(reference, { "gems" => ["csv 3.3.5", "json 2.18.0 (default)"] }, platform: "arm64-darwin").first,
      :justified?
    refute_predicate Parity.compare(reference, { "gems" => ["json 2.18.0 (default)"] }, platform: "arm64-darwin").first, :justified?
  end

  # rv-ruby has no RubyGems defaults file, so on macOS and Linux only the
  # app loads Fledge's; RubyInstaller has one at the same path, which
  # loads RubyInstaller's runtime, so on Windows only ruby main.rb loads
  # that.
  def test_a_justification_holds_only_on_its_platforms
    defaults = { "$LOADED_FEATURES" => ["<prefix>/lib/ruby/4.0.0/rubygems/defaults/operating_system.rb"] }
    installer = { "$LOADED_FEATURES" => ["<prefix>/lib/ruby/site_ruby/4.0.0/ruby_installer/runtime.rb"] }
    none = { "$LOADED_FEATURES" => [] }

    assert_predicate Parity.compare(none, defaults, platform: "x86_64-linux").first, :justified?
    refute_predicate Parity.compare(none, defaults, platform: "x64-mingw-ucrt").first, :justified?
    assert_predicate Parity.compare(installer, none, platform: "x64-mingw-ucrt").first, :justified?
    refute_predicate Parity.compare(installer, none, platform: "x86_64-linux").first, :justified?
  end

  def test_the_same_elements_in_another_order_differ
    difference = Parity.compare({ "$LOAD_PATH" => %w[a b] }, { "$LOAD_PATH" => %w[b a] }, platform: "x86_64-linux").first

    refute_predicate difference, :justified?
    assert_includes difference.to_s, "order differs"
  end

  # Runs the probe under this Ruby, outside the bundle, as ruby main.rb.
  def probe(*argv, env: {})
    run = -> { Open3.capture3(env, RbConfig.ruby, File.join(Parity::PROBE, "main.rb"), *argv) }
    defined?(Bundler) ? Bundler.with_unbundled_env(&run) : run.call
  end

  def test_the_probe_runs_under_this_ruby_and_reports_every_fact
    out, err, status = probe("a b")

    assert_predicate status, :success?, err
    facts = Parity.report(out)
    assert_equal ["a b"], facts.fetch("ARGV")
    assert_equal "42", facts.fetch("RbConfig.ruby runs")
    assert_equal "loads", facts.fetch("requireable").fetch("csv")
    assert_equal "found", facts.fetch("requireable").fetch("debug")
    %w[$0 $LOAD_PATH $LOADED_FEATURES Gem.path ENV child\ ENV Encoding.default_external RUBY_DESCRIPTION].each do |fact|
      assert facts.key?(fact), fact
    end
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
    gemfile = File.expand_path("../Gemfile", __dir__)

    assert_equal "#{gemfile}\n", bundled_probe(gemfile, "original-child-env", "BUNDLE_GEMFILE")
    assert_equal "(unset)\n", bundled_probe(gemfile, "unbundled-child-env", "BUNDLE_GEMFILE")
    assert_match %r{bundler/setup}, bundled_probe(gemfile, "child-env", "RUBYOPT")
    assert_equal "(no Bundler)\n", probe("original-child-env", "BUNDLE_GEMFILE").first
  end

  # Runs the probe under this Ruby with Bundler set up for +gemfile+, as
  # bundle exec ruby main.rb would, and returns what it printed.
  def bundled_probe(gemfile, *argv)
    out, err, status = Bundler.with_unbundled_env do
      Open3.capture3({ "BUNDLE_GEMFILE" => gemfile }, RbConfig.ruby, "-rbundler/setup", File.join(Parity::PROBE, "main.rb"), *argv)
    end
    assert_predicate status, :success?, err
    out
  end

  # Each element may be explained by a different justification of its
  # fact, as long as every one is.
  def test_justifications_combine_element_by_element
    reference = { "$LOADED_FEATURES" => ["<project>/lib/my_cool_app/version.rb"] }
    app = {
"$LOADED_FEATURES" => [
  "<prefix>/lib/ruby/4.0.0/rubygems/defaults/operating_system.rb",
  "<prefix>/lib/ruby/4.0.0/rubygems/yaml_serializer.rb",
],
}

    difference = Parity.compare(reference, app, platform: "arm64-darwin", check: :bundle).first

    assert_predicate difference, :justified?
    assert_equal 3, difference.justifications.size
    refute_predicate Parity.compare(reference, app, platform: "arm64-darwin").first, :justified?, "the bundle check's only"
  end

  def test_the_gem_shaped_check_has_its_own_names_for_the_program
    reference = { "$0" => "exe/my_cool_app" }

    assert_predicate Parity.compare(reference, { "$0" => "<app>/my_cool_app" }, platform: "x86_64-linux", check: :bundle).first,
      :justified?
    refute_predicate Parity.compare(reference, { "$0" => "<app>/my_cool_app" }, platform: "x86_64-linux").first, :justified?
  end

  # ENV's order is how the environment was built, not something Ruby
  # promises an app; Arrays keep their order.
  def test_a_hashs_order_does_not_count_and_an_arrays_does
    assert_empty Parity.compare({ "ENV" => { "A" => "1", "B" => "2" } }, { "ENV" => { "B" => "2", "A" => "1" } }, platform: "x86_64-linux")

    difference = Parity.compare({ "$LOAD_PATH" => %w[a b] }, { "$LOAD_PATH" => %w[b a] }, platform: "x86_64-linux").first
    refute_predicate difference, :justified?
    assert_includes difference.to_s, "order differs"
  end

  def test_normalize_names_the_project_apart_from_the_programs_folder
    normalized = Parity.normalize(report("$LOAD_PATH": ["/w/project/lib"], "$0": "/w/project/exe/app").tap do |facts|
      facts["paths"] = { "app" => "/w/project/exe", "project" => "/w/project", "prefix" => "/w/ruby", "home" => "/w/home" }
    end, work: "/tmp/work")

    assert_equal [["<project>/lib"], "<app>/app"], [normalized.fetch("$LOAD_PATH"), normalized.fetch("$0")]
  end
end
