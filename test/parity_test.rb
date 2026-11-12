# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
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

    assert_equal({ "a" => 2 }, Parity::Reports.report(output))
    assert_raises(RuntimeError) { Parity::Reports.report("no report\n") }
  end

  def test_normalize_replaces_the_longest_paths_first_and_backslashes
    normalized = Parity::Reports.normalize(report("$0": "/w/app/main.rb", "Gem.path": ["/w/ruby/lib", "C:\\w\\x"],
      ENV: { "GEM_HOME" => "/tmp/work/gems" }), work: "/tmp/work")

    assert_equal "<app>/main.rb", normalized.fetch("$0")
    assert_equal ["<prefix>/lib", "C:/w/x"], normalized.fetch("Gem.path")
    assert_equal({ "GEM_HOME" => "<work>/gems" }, normalized.fetch("ENV"))
    refute normalized.key?("paths")
  end

  def test_equal_reports_have_no_differences
    facts = { "ARGV" => ["one"], "ENV" => { "A" => "1" }, "$stdout.sync" => false }

    assert_empty Parity::Reports.compare(facts, facts, platform: "x86_64-linux")
  end

  def test_a_listed_difference_is_justified_and_says_why
    differences = Parity::Reports.compare({ "$0" => "main.rb" }, { "$0" => "<app>/main.rb" }, platform: "x86_64-linux")

    assert_equal 1, differences.size
    assert_predicate differences.first, :justified?
    assert_includes differences.first.to_s, "why: ruby main.rb names the script as typed"
  end

  def test_an_unlisted_difference_is_not_justified
    differences = Parity::Reports.compare({ "ENV" => { "A" => "1" } }, { "ENV" => { "A" => "2" } }, platform: "x86_64-linux")

    refute_predicate differences.first, :justified?
    assert_equal "DIFFERENT: ENV\n    reference only: \"A\"=\"1\"\n    built app only: \"A\"=\"2\"", differences.first.to_s
  end

  # A justification covers only the elements it names: one more
  # difference in the same fact is not justified.
  def test_a_justification_does_not_cover_other_elements_of_its_fact
    reference = { "gems" => ["bootsnap 1.24.6", "csv 3.3.5", "json 2.18.0 (default)"] }

    assert_predicate Parity::Reports.compare(reference, { "gems" => ["csv 3.3.5", "json 2.18.0 (default)"] }, platform: "arm64-darwin").first,
      :justified?
    refute_predicate Parity::Reports.compare(reference, { "gems" => ["json 2.18.0 (default)"] }, platform: "arm64-darwin").first, :justified?
  end

  # rv-ruby has no RubyGems defaults file, so on macOS and Linux only the
  # app loads Fledge's; RubyInstaller has one at the same path, which
  # loads RubyInstaller's runtime, so on Windows only ruby main.rb loads
  # that.
  def test_a_justification_holds_only_on_its_platforms
    defaults = { "$LOADED_FEATURES" => ["<prefix>/lib/ruby/4.0.0/rubygems/defaults/operating_system.rb"] }
    installer = { "$LOADED_FEATURES" => ["<prefix>/lib/ruby/site_ruby/4.0.0/ruby_installer/runtime.rb"] }
    none = { "$LOADED_FEATURES" => [] }

    assert_predicate Parity::Reports.compare(none, defaults, platform: "x86_64-linux").first, :justified?
    refute_predicate Parity::Reports.compare(none, defaults, platform: "x64-mingw-ucrt").first, :justified?
    assert_predicate Parity::Reports.compare(installer, none, platform: "x64-mingw-ucrt").first, :justified?
    refute_predicate Parity::Reports.compare(installer, none, platform: "x86_64-linux").first, :justified?
  end

  # A Ruby's folders are named for its ruby_version, which a preview or a
  # snapshot of master gives its ABI version too, so a justification
  # holds for whichever the runtime's Ruby is, and only for a version.
  def test_a_justification_holds_for_the_folders_of_any_ruby_version
    none = { "$LOADED_FEATURES" => [] }
    %w[4.0.0 4.1.0+5 4.1.0+6].each do |abi|
      defaults = { "$LOADED_FEATURES" => ["<prefix>/lib/ruby/#{abi}/rubygems/defaults/operating_system.rb"] }
      assert_predicate Parity::Reports.compare(none, defaults, platform: "x86_64-linux").first, :justified?
    end
    stray = { "$LOADED_FEATURES" => ["<prefix>/lib/ruby/site_ruby/rubygems/defaults/operating_system.rb"] }
    refute_predicate Parity::Reports.compare(none, stray, platform: "x86_64-linux").first, :justified?
  end

  # The launcher's UTF-8 in place of a bare C locale is justified only in
  # the run with no locale at all; under LC_ALL=C it would be a
  # difference, and the no-locale run still allows what the script check
  # allows.
  def test_a_utf8_locale_in_place_of_c_is_justified_only_with_no_locale
    reference = { "Encoding.default_external" => "US-ASCII", "$0" => "main.rb" }
    app = { "Encoding.default_external" => "UTF-8", "$0" => "<app>/main.rb" }

    assert Parity::Reports.compare(reference, app, platform: "x86_64-linux", check: :no_locale).all?(&:justified?)
    refute_predicate Parity::Reports.compare(reference, app, platform: "x86_64-linux").first, :justified?
    refute_predicate Parity::Reports.compare(app, reference, platform: "x86_64-linux", check: :no_locale).first, :justified?,
      "a C locale where ruby has UTF-8 is not"
  end

  def test_the_same_elements_in_another_order_differ
    difference = Parity::Reports.compare({ "$LOAD_PATH" => %w[a b] }, { "$LOAD_PATH" => %w[b a] }, platform: "x86_64-linux").first

    refute_predicate difference, :justified?
    assert_includes difference.to_s, "order differs"
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

    difference = Parity::Reports.compare(reference, app, platform: "arm64-darwin", check: :bundle).first

    assert_predicate difference, :justified?
    assert_equal 3, difference.justifications.size
    refute_predicate Parity::Reports.compare(reference, app, platform: "arm64-darwin").first, :justified?, "the bundle check's only"
  end

  def test_the_gem_shaped_check_has_its_own_names_for_the_program
    reference = { "$0" => "exe/my_cool_app" }

    assert_predicate Parity::Reports.compare(reference, { "$0" => "<app>/my_cool_app" }, platform: "x86_64-linux", check: :bundle).first,
      :justified?
    refute_predicate Parity::Reports.compare(reference, { "$0" => "<app>/my_cool_app" }, platform: "x86_64-linux").first, :justified?
  end

  # ENV's order is how the environment was built, not something Ruby
  # promises an app; Arrays keep their order.
  def test_a_hashs_order_does_not_count_and_an_arrays_does
    assert_empty Parity::Reports.compare({ "ENV" => { "A" => "1", "B" => "2" } }, { "ENV" => { "B" => "2", "A" => "1" } }, platform: "x86_64-linux")

    difference = Parity::Reports.compare({ "$LOAD_PATH" => %w[a b] }, { "$LOAD_PATH" => %w[b a] }, platform: "x86_64-linux").first
    refute_predicate difference, :justified?
    assert_includes difference.to_s, "order differs"
  end

  def test_normalize_names_the_project_apart_from_the_programs_folder
    normalized = Parity::Reports.normalize(report("$LOAD_PATH": ["/w/project/lib"], "$0": "/w/project/exe/app").tap do |facts|
      facts["paths"] = { "app" => "/w/project/exe", "project" => "/w/project", "prefix" => "/w/ruby", "home" => "/w/home" }
    end, work: "/tmp/work")

    assert_equal [["<project>/lib"], "<app>/app"], [normalized.fetch("$LOAD_PATH"), normalized.fetch("$0")]
  end
end
