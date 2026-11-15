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

  # A justification whose patterns name groups on both sides pairs what
  # it explains: a phone's Ruby records each extension by its feature
  # where a desktop's records its file, which is allowed one for one,
  # but an extension loaded on one side only is a difference, as is
  # another Ruby's version in RUBY_DESCRIPTION.
  def test_a_paired_justification_allows_a_renamed_element_but_not_a_missing_one
    arch = "<prefix>/lib/ruby/4.1.0+5/x86_64-linux"
    reference = {
"$LOADED_FEATURES" => ["#{arch}/enc/encdb.so", "#{arch}/json/ext/parser.so"],
"RUBY_DESCRIPTION" => "ruby 4.1.0preview1 (2026-10-11 master 2d08b5f42f) +PRISM [x86_64-linux]",
}
    app = {
"$LOADED_FEATURES" => ["encdb.so", "json/ext/parser.so"],
"RUBY_DESCRIPTION" => "ruby 4.1.0preview1 (2026-10-11 master 2d08b5f42f) +PRISM [x86_64-linux-android]",
}
    compare = -> (changed) { Parity::Reports.compare(reference, app.merge(changed), platform: "x86_64-linux-android") }

    assert compare.call({}).all?(&:justified?)
    refute_predicate compare.call("$LOADED_FEATURES" => ["json/ext/parser.so"]).first, :justified?
    refute_predicate compare.call("$LOADED_FEATURES" => ["encdb.so", "json/ext/parser.so", "date_core.so"]).first, :justified?
    refute compare.call("RUBY_DESCRIPTION" => "ruby 4.1.0 (2026-12-25 master 0123456789) +PRISM [x86_64-linux-android]")
      .all?(&:justified?)
  end

  # bundle exec runs the lockfile's Bundler from the person's gems, the
  # app from the runtime's, the same files paired one for one, but for
  # the feature flags only the person's Bundler asks.
  def test_the_bundlers_files_pair_but_for_the_feature_flags
    person = "<work>/person-gems/gems/bundler-4.0.20/lib"
    app = "<prefix>/lib/ruby/gems/4.1.0+5/gems/bundler-4.0.20/lib"
    reference = { "$LOADED_FEATURES" => ["#{person}/bundler.rb", "#{person}/bundler/feature_flag.rb"] }

    assert_predicate Parity::Reports.compare(reference, { "$LOADED_FEATURES" => ["#{app}/bundler.rb"] }, platform: "x86_64-linux",
      check: :bundle).first, :justified?
    refute_predicate Parity::Reports.compare(reference, { "$LOADED_FEATURES" => [] }, platform: "x86_64-linux", check: :bundle).first,
      :justified?
  end

  # rv-ruby has no RubyGems defaults file, so on macOS and Linux only the
  # app loads Fledge's; RubyInstaller has one at the same path, and on
  # Windows both load what RubyInstaller's start-up loads, so none of it
  # may differ there.
  def test_a_justification_holds_only_on_its_platforms
    defaults = { "$LOADED_FEATURES" => ["<prefix>/lib/ruby/4.0.0/rubygems/defaults/operating_system.rb"] }
    none = { "$LOADED_FEATURES" => [] }

    assert_predicate Parity::Reports.compare(none, defaults, platform: "x86_64-linux").first, :justified?
    refute_predicate Parity::Reports.compare(none, defaults, platform: "x64-mingw-ucrt").first, :justified?
    installer_files = [
      "site_ruby/4.0.0/ruby_installer/runtime.rb",
      "site_ruby/4.0.0/ruby_installer/runtime/msys2_installation.rb",
      "site_ruby/4.0.0/ruby_installer/runtime/colors.rb",
      "site_ruby/4.0.0/ruby_installer/runtime/dll_directory.rb",
      "4.0.0/x64-mingw-ucrt/win32/dll_directory.so",
      "4.0.0/x64-mingw-ucrt/enc/utf_16le.so",
    ]
    installer_files.each do |file|
      installer = { "$LOADED_FEATURES" => ["<prefix>/lib/ruby/#{file}"] }
      refute_predicate Parity::Reports.compare(installer, none, platform: "x64-mingw-ucrt").first, :justified?, file
    end
    %w[RubyInstaller Win32].each do |constant|
      refute_predicate Parity::Reports.compare({ "Object.constants" => [constant] }, { "Object.constants" => [] },
        platform: "x64-mingw-ucrt").first, :justified?, constant
    end
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

  # Windows' own spelling of PATH naming the bundle's gems is justified
  # only in the gem-shaped run with Bundler's variables spelled otherwise,
  # which still allows what the gem-shaped run allows.
  def test_a_path_spelled_as_windows_spells_it_is_justified_only_in_the_spelled_run
    reference = { "Bundler.original_env" => { "Path" => "<work>/person-gems/bin" }, "ENV" => { "GEM_HOME" => "<work>/person-gems" } }
    app = { "Bundler.original_env" => { "Path" => "<prefix>/bin" }, "ENV" => { "GEM_HOME" => "<prefix>" } }

    assert Parity::Reports.compare(reference, app, platform: "x64-mingw-ucrt", check: :spelled).all?(&:justified?)
    refute Parity::Reports.compare(reference, app, platform: "x64-mingw-ucrt", check: :bundle).all?(&:justified?)
    refute Parity::Reports.compare(reference, app, platform: "x86_64-linux", check: :spelled).all?(&:justified?)
  end

  # The app's BUNDLE_GEMFILE where bundle exec keeps the person's
  # bundle_gemfile is justified only in the spelled run, and only when it
  # names the same Gemfile.
  def test_bundlers_spelling_of_the_gemfile_is_justified_only_in_the_spelled_run_for_the_same_gemfile
    reference = { "ENV" => { "bundle_gemfile" => "<project>/Gemfile" }, "Bundler.original_env" => { "bundle_gemfile" => "<project>/Gemfile" } }
    app = { "ENV" => { "BUNDLE_GEMFILE" => "<project>/Gemfile" }, "Bundler.original_env" => {} }
    elsewhere = app.merge("ENV" => { "BUNDLE_GEMFILE" => "<work>/Gemfile" })

    assert Parity::Reports.compare(reference, app, platform: "x64-mingw-ucrt", check: :spelled).all?(&:justified?)
    refute Parity::Reports.compare(reference, app, platform: "x64-mingw-ucrt", check: :bundle).all?(&:justified?)
    refute Parity::Reports.compare(reference, elsewhere, platform: "x64-mingw-ucrt", check: :spelled).all?(&:justified?)
  end

  def test_the_same_elements_in_another_order_differ
    difference = Parity::Reports.compare({ "$LOAD_PATH" => %w[a b] }, { "$LOAD_PATH" => %w[b a] }, platform: "x86_64-linux").first

    refute_predicate difference, :justified?
    assert_includes difference.to_s, "order differs"
  end

  # Each element may be explained by a different justification of its
  # fact, as long as every one is.
  def test_justifications_combine_element_by_element
    reference = { "$LOADED_FEATURES" => ["<prefix>/lib/ruby/4.0.0/bundler/feature_flag.rb", "<work>/person-gems/gems/bundler-4.0.19/lib/bundler.rb"] }
    app = {
"$LOADED_FEATURES" => [
  "<prefix>/lib/ruby/4.0.0/rubygems/defaults/operating_system.rb",
  "<prefix>/lib/ruby/gems/4.0.0/gems/bundler-4.0.19/lib/bundler.rb",
],
}

    difference = Parity::Reports.compare(reference, app, platform: "arm64-darwin", check: :bundle).first

    assert_predicate difference, :justified?
    assert_equal 3, difference.justifications.size
    refute_predicate Parity::Reports.compare(reference, app, platform: "arm64-darwin").first, :justified?, "the bundle check's only"
  end

  # The app's Bundler reads no settings file, so RubyGems' YAML
  # serializer and its hollow Psych may not show in a built app.
  def test_the_yaml_serializer_and_its_psych_must_not_load_in_the_app
    serializer = { "$LOADED_FEATURES" => ["<prefix>/lib/ruby/4.1.0+5/rubygems/yaml_serializer.rb"], "Object.constants" => ["Psych"] }
    none = { "$LOADED_FEATURES" => [], "Object.constants" => [] }

    assert_equal 2, Parity::Reports.compare(none, serializer, platform: "x86_64-linux", check: :bundle).count { |difference| !difference.justified? }
  end

  # A built app sets up the development and test groups, as bundle exec
  # does, so a development gem may not be missing from it.
  def test_a_development_gem_must_be_in_the_app
    rake = { "gems" => ["rake 13.4.2"], "requireable" => { "rake" => "loads" } }
    none = { "gems" => [], "requireable" => {} }

    assert_equal 2, Parity::Reports.compare(rake, none, platform: "x86_64-linux", check: :bundle).count { |difference| !difference.justified? }
  end

  # The built app's gemspec requires what the project's gemspec requires,
  # as Bundler evaluates it under bundle exec, so neither the file nor its
  # constant may be missing.
  def test_a_file_the_gemspec_requires_must_load_in_the_app
    version = { "$LOADED_FEATURES" => ["<project>/lib/my_cool_app/version.rb"], "Object.constants" => ["MyCoolApp"] }
    none = { "$LOADED_FEATURES" => [], "Object.constants" => [] }

    assert_equal 2, Parity::Reports.compare(version, none, platform: "x86_64-linux", check: :bundle).count { |difference| !difference.justified? }
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
