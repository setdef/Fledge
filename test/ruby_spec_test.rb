# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "test_helper"
require_relative "../tasks/ruby_spec"

# How the ruby/spec comparison reads MSpec's reports and compares a
# built app's with stock Ruby's. CI's ruby/spec jobs run the comparison
# itself (tasks/ruby_spec.rb) on real runtimes.
class RubySpecTest < Minitest::Test
  # What mspec-run's default formatter prints, with an error whose
  # description follows "An exception occurred during:", a spec file
  # that failed to load, which MSpec names on that line itself, and
  # Windows' line endings.
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

    3)
    An exception occurred during: loading D:/work/reference/ruby_spec/spec/core/zlib/adler32_spec.rb ERROR
    LoadError: 126: The specified module could not be found.   - D:/ruby/lib/ruby/4.1.0+6/x64-mingw-ucrt/zlib.so

    Finished in 1.234 seconds

    3 files, 5 examples, 7 expectations, 1 failure, 2 errors, 0 tagged
  OUT

  def test_a_report_lists_each_failure_and_error_and_its_totals
    result = RubySpec::Results.read("core", OUTPUT)

    assert_equal [
      "core: Encoding.locale_charmap when setting LC_ALL=C returns a value based on the LC_ALL environment variable",
      "core: mkmf can be required with --enable-frozen-string-literal",
      "core: loading core/zlib/adler32_spec.rb",
    ], result.failures.keys
    assert_includes result.failures.values.first, "Expected \"UTF-8\" == \"US-ASCII\""
    assert_equal "3 files, 5 examples, 7 expectations, 1 failure, 2 errors, 0 tagged", result.totals
  end

  # Stock Ruby loads ruby/spec from one folder and the app from another,
  # so a file that fails to load is named by its path inside ruby/spec,
  # and the same failure on both sides is no difference.
  def test_a_spec_file_that_fails_to_load_is_named_by_its_path_inside_ruby_spec
    app = OUTPUT.sub("D:/work/reference/ruby_spec/spec/", "C:/Users/a/App/app/spec/")
    name = "core: loading core/zlib/adler32_spec.rb"

    assert_includes RubySpec::Results.read("core", app).failures.keys, name
    assert_includes RubySpec::Results.read("core", OUTPUT).failures.fetch(name), "LoadError: 126"
  end

  # An error in a before :all hook, or in a describe's own body, has no
  # example, so MSpec prints one line with ERROR at its end, then the
  # message, as iOS's app printed for library/etc/getpwuid_spec.rb and
  # struct_group_spec.rb in run 43313316095. Each is a failure, named
  # by the spec file being loaded and the line of it nearest the error.
  def test_an_error_outside_any_example_is_a_failure_named_by_its_spec_file
    output = <<~OUT
      1)
      An exception occurred during: before :all ERROR
      Errno::ENOENT: No such file or directory - id
      /Users/a/RubySpec.app/fledge/app/spec/library/etc/getpwuid_spec.rb:17:in 'Kernel#`'
      /Users/a/RubySpec.app/fledge/app/spec/library/etc/getpwuid_spec.rb:17:in 'block (3 levels) in <top (required)>'
      /Users/a/RubySpec.app/fledge/app/spec/library/etc/getpwuid_spec.rb:14:in '<top (required)>'
      /Users/a/RubySpec.app/fledge/app/main.rb:47:in '<main>'

      2)
      An exception occurred during: Etc::Group ERROR
      Errno::ENOENT: No such file or directory - id
      /work/spec/core/etc/fixtures/common.rb:3:in 'IO.popen'
      /work/spec/library/etc/struct_group_spec.rb:6:in 'block (2 levels) in <top (required)>'
      /work/spec/library/etc/struct_group_spec.rb:4:in '<top (required)>'
      main.rb:47:in '<main>'

      3)
      An exception occurred during: after :all ERROR
      RuntimeError: no backtrace

      Finished in 1.0 seconds

      3 files, 0 examples, 0 expectations, 0 failures, 3 errors, 0 tagged
    OUT

    assert_equal [
      "library: An exception occurred during: before :all, at library/etc/getpwuid_spec.rb:17",
      "library: An exception occurred during: Etc::Group, at library/etc/struct_group_spec.rb:6",
      "An exception occurred during: after :all",
    ], RubySpec::Results.read(nil, output).failures.keys
    assert_equal "library: An exception occurred during: before :all, at library/etc/getpwuid_spec.rb:17",
      RubySpec::Results.read("library", output).failures.keys.first
    assert_includes RubySpec::Results.read(nil, output).failures.values.first, "Errno::ENOENT"
  end

  def test_a_run_that_stopped_has_no_totals
    assert_nil RubySpec::Results.read("core", "ruby 4.0.9\n...\n[BUG] Segmentation fault\n").totals
  end

  def results(**failures_by_side)
    failures_by_side.transform_values do |failures|
      [
RubySpec::Results::Run.new(directory: "core", failures: failures.to_h { |name| ["core: #{name}", ""] },
  totals: "1 file, 0 examples, 0 expectations", listing: RubySpec::Listing.new(examples: [], denied: {}, count: 0)),
]
    end
  end

  # What listing_config.rb prints after the totals, for a run of
  # +directory+ (nil for a phone's), with +examples+ ran, each a spec
  # file, its guards' locations, and its description, and the guards
  # +denied+.
  def listed(directory, examples, denied: {}, failures: {})
    lines = ["ruby/spec listing: begin"]
    examples.each { |file, guards, location, description| lines.push("@ #{file}", "=#{guards.join(',')} #{location} #{description}") }
    denied.each { |location, name| lines << "- #{location} #{name}" }
    lines << "ruby/spec listing: #{examples.size} examples"
    totals = "1 file, #{examples.size} examples, 1 expectation, #{failures.size} failures, 0 errors, 0 tagged"
    failed = failures.each_with_index.map { |(name, detail), index| "#{index + 1})\n#{name} ERROR\n#{detail}\n" }
    RubySpec::Results.read(directory, "#{failed.join("\n")}\nFinished in 1 second\n\n#{totals}\n#{lines.join("\n")}\n")
  end

  def sole(differences)
    assert_equal 1, differences.size, differences.join("\n")
    differences.first
  end

  GROUPS = [
    "core/process/groups_spec.rb", ["core/process/groups_spec.rb:4"], "core/process/groups_spec.rb:5", "Process.groups gets an Array of the gids"
  ].freeze
  EACH = ["core/array/each_spec.rb", [], "core/array/each_spec.rb:9", "Array#each yields each element"].freeze

  def test_a_listing_names_each_example_by_its_directory_and_counts_them
    run = listed(nil, [GROUPS, EACH], denied: { "core/process/groups_spec.rb:33" => "platform_is aix" })

    assert_equal ["core: Process.groups gets an Array of the gids", "core: Array#each yields each element"], run.listing.examples.map(&:name)
    assert_equal ["core/process/groups_spec.rb:4"], run.listing.examples.first.guards
    assert_equal "core/process/groups_spec.rb:5", run.listing.examples.first.location
    assert_equal({ "core/process/groups_spec.rb:33" => "platform_is aix" }, run.listing.denied)
    assert run.listing.complete?(run)
    refute run.listing.complete?(run.with(totals: "1 file, 3 examples, 1 expectation")), "the totals count one more"
    lost = RubySpec::Results.read(nil, "1 file, 2 examples, 0 expectations\nruby/spec listing: begin\n@ core/a_spec.rb\n= - A\n")
    refute lost.listing.complete?(lost), "a listing that never ended"
  end

  # A description holds what the spec inspected as it loaded, which the
  # locale changes: in run 43350707323 on x86_64-linux, stock Ruby with
  # no locale named Symbol#inspect's example for :ê as :"ê". The
  # two sides' examples are matched by their block's file and line.
  def test_an_example_the_locale_names_differently_is_the_same_example
    symbol = ["core/symbol/inspect_spec.rb", [], "core/symbol/inspect_spec.rb:110", "Symbol#inspect returns self as a symbol literal for "]
    stock = listed("core", [symbol.dup.tap { |example| example[3] += ':"ê"' }])
    app = listed("core", [symbol.dup.tap { |example| example[3] += ":ê" }])

    assert_empty RubySpec::Results.compare([stock], [app], platform: "x86_64-linux")
  end

  # MSpec's evaluate helper defines one block, in MSpec, for many
  # examples, as language/lambda_spec.rb's are, so those are matched by
  # name, and two of them are two examples.
  def test_examples_of_a_block_outside_ruby_spec_are_matched_by_name
    lambda_spec = ["language/lambda_spec.rb", [], "/w/stock/mspec/lib/mspec/runner/evaluate.rb:45", "A lambda literal for definition"]
    stock = listed("language", [lambda_spec.dup.tap { |e| e[3] += " a" }, lambda_spec.dup.tap { |e| e[3] += " b" }])
    app = listed("language", [lambda_spec.dup.tap { |e| e[2] = "-"; e[3] += " a" }])

    assert_equal ["runs in stock Ruby only: language: A lambda literal for definition b"],
      RubySpec::Results.compare([stock], [app], platform: "x86_64-linux").map { |d| d.to_s.lines.first.chomp.delete_prefix("DIFFERENT: ") }
  end

  # Run 43313316095 ran 33 fewer examples in iOS's app than in stock
  # Ruby, and nothing compared them. An example that runs on one side
  # only is a difference unless something explains it.
  def test_an_example_that_runs_on_one_side_only_is_a_difference
    differences = RubySpec::Results.compare([listed("core", [GROUPS, EACH])], [listed("core", [EACH])], platform: "x86_64-linux")

    assert_equal ["DIFFERENT: runs in stock Ruby only: core: Process.groups gets an Array of the gids"], differences.map { |d| d.to_s.lines.first.chomp }
    assert_empty RubySpec::Results.compare([listed("core", [EACH, EACH])], [listed("core", [EACH, EACH])], platform: "x86_64-linux")
    assert_equal 1, RubySpec::Results.compare([listed("core", [EACH, EACH])], [listed("core", [EACH])], platform: "x86_64-linux").size,
      "an example that runs twice on one side and once on the other"
  end

  # ruby/spec's platform_is_not :android leaves examples out on Android
  # that stock Ruby on Linux runs: explained by the guard, one difference
  # for each guard, where a guard of another kind explains nothing.
  def test_a_platform_guard_explains_an_example_it_left_out_on_one_side
    stock = listed(nil, [GROUPS, EACH])
    android = listed(nil, [EACH], denied: { "core/process/groups_spec.rb:4" => "platform_is_not android" })
    lambda_guard = listed(nil, [EACH], denied: { "core/process/groups_spec.rb:4" => "guard" })

    difference = RubySpec::Results.compare([stock], [android], platform: "x86_64-linux-android").reject { |found| found.kind == :unused }.then { |found| sole(found) }
    assert_predicate difference, :justified?
    assert_equal "1 example under platform_is_not android at core/process/groups_spec.rb:4", difference.name
    assert_includes difference.to_s, "core: Process.groups gets an Array of the gids"
    unjustified = RubySpec::Results.compare([stock], [lambda_guard], platform: "x86_64-linux-android").reject { |found| found.kind == :unused }.then { |found| sole(found) }
    refute_predicate unjustified, :justified?
    assert_includes unjustified.to_s, "left out by guard at core/process/groups_spec.rb:4 in the built app"
  end

  # An error that kept examples from running on one side is the
  # difference to report, justified or not, not each example it kept.
  def test_examples_an_error_on_one_side_kept_from_running_are_that_error
    hook = "An exception occurred during: before :all"
    detail = "Errno::ENOENT: id\n/w/spec/core/process/groups_spec.rb:9:in 'b'\n/w/spec/core/process/groups_spec.rb:1:in '<top (required)>'"
    differences = RubySpec::Results.compare([listed(nil, [GROUPS])], [listed(nil, [], failures: { hook => detail })], platform: "x86_64-linux")

    assert_equal ["fails in the built app only: core: An exception occurred during: before :all, at core/process/groups_spec.rb:9"],
      differences.map { |d| d.to_s.lines.first.chomp.delete_prefix("DIFFERENT: ") }
  end

  # Logcat dropped a fifth of the listing an Android emulator's app
  # printed in run 43350707323, so a phone's run writes it to a file and
  # prints where, and the comparison reads it from there. The log is
  # text and the file bytes, as the iOS run of 43354884978 found when a
  # failure's message held "ê".
  def test_a_phones_listing_is_read_from_the_file_it_names
    output = "Expected \"ê\"\n1 file, 1 example, 1 expectation, 0 failures, 0 errors, 0 tagged\nruby/spec listing: in /data/user/0/a/cache/l.txt\n"
    listing = "ruby/spec listing: begin\n@ core/array/each_spec.rb\n= core/array/each_spec.rb:9 Array#each yields ê\nruby/spec listing: 1 examples\n".b

    run = RubySpec::Results.read(nil, RubySpec::Phone.listed(output) { |path| (path == "/data/user/0/a/cache/l.txt") ? listing : "" })
    assert run.listing.complete?(run)
    assert_equal "1 file\n", RubySpec::Phone.listed("1 file\n") { raise "no file to read" }
  end

  def test_a_run_with_no_listing_or_one_that_does_not_add_up_is_a_difference
    finished = listed("core", [EACH])
    unlisted = finished.with(listing: nil)

    assert_equal ["DIFFERENT: core in the built app listed no examples, or not as many as its totals count"],
      RubySpec::Results.compare([finished], [unlisted], platform: "x86_64-linux").map(&:to_s)
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

  # With no locale, stock Ruby reads paths as US-ASCII where a built
  # app, whose launcher takes a UTF-8 locale (ADR 041), reads them as
  # UTF-8, so examples that need an ASCII-compatible encoding other than
  # UTF-8 fail under stock Ruby only, and only on macOS and Linux.
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

  # A justification names the examples it explains, each of which must
  # differ in every run of its platforms: iOS's Process.egid= stopped
  # failing and its pattern still passed every run, and the setuid
  # pattern explained any failure of six predicates.
  def test_a_justification_must_explain_each_example_it_names_in_every_run_of_its_platforms
    chdir = "Dir.chdir accepts a path in a non-UTF-8, ASCII-compatible encoding containing non-ASCII characters"
    runs = results(stock: [chdir], app: [])

    unused = RubySpec::Results.compare(runs.fetch(:stock), runs.fetch(:app), platform: "arm64-darwin").reject(&:justified?)
    assert_equal [
      "DIFFERENT: a justification for stock Ruby explains no difference of this run: core: Dir.chdir #{chdir.delete_prefix('Dir.chdir ')} when given a block",
      "DIFFERENT: a justification for stock Ruby explains no difference of this run: core: File.readlink #{chdir.delete_prefix('Dir.chdir ')}",
      "DIFFERENT: a justification for stock Ruby explains no difference of this run: core: File.realpath #{chdir.delete_prefix('Dir.chdir ')}",
    ], unused.map(&:to_s)
    setgid = results(stock: [], app: ["File.setgid? returns true when the gid bit is set"])
    refute_predicate RubySpec::Results.compare(setgid.fetch(:stock), setgid.fetch(:app), platform: "arm64-ios-simulator").first, :justified?
  end

  def test_a_run_that_did_not_finish_is_a_difference
    stopped = [RubySpec::Results::Run.new(directory: "core", failures: {}, totals: nil)]
    finished = [RubySpec::Results::Run.new(directory: "core", failures: {}, totals: "1 file")]

    differences = RubySpec::Results.compare(finished, stopped, platform: "x86_64-linux")

    assert_equal ["DIFFERENT: core did not finish in the built app"], differences.map(&:to_s)
    assert_equal 2, RubySpec::Results.compare(stopped, stopped, platform: "x86_64-linux").size
  end

  # A phone runs every directory in one process, and its formatter
  # names the directory before each description, after the hook an
  # error happened in; the host app's line with the status is not
  # MSpec's.
  def test_a_phones_run_names_each_failures_directory_itself
    entries = [
      "ruby 4.1.0preview1 (2026-10-11 master 2d08b5f42f) +PRISM [arm64-ios]",
      "",
      "1)",
      "language: The if expression returns nil FAILED",
      "Expected nil",
      "",
      "2)",
      "An exception occurred during: before :each",
      "library: Socket.getaddrinfo resolves ERROR",
      "SocketError: none",
      "",
      "3)",
      "An exception occurred during: loading /data/app/spec/library/prism/parse_spec.rb ERROR",
      "LoadError: cannot load such file -- prism",
      "",
      "Finished in 9.5 seconds",
      "",
      "3000 files, 40000 examples, 90000 expectations, 1 failure, 1 error, 0 tagged",
      "RubySpec exited with status 1",
    ]
    output = RubySpec::Phone.output(entries)
    result = RubySpec::Results.read(nil, output)

    assert_equal [
      "language: The if expression returns nil",
      "library: Socket.getaddrinfo resolves",
      "library: loading library/prism/parse_spec.rb",
], result.failures.keys
    assert_equal "3000 files, 40000 examples, 90000 expectations, 1 failure, 1 error, 0 tagged", result.totals
    refute_includes output, "exited with status"
  end

  # A phone's log holds standard error's lines among standard output's,
  # as two threads forward them, so in run 43226291212 on an iPad the
  # warning MSpec prints when it exits came between a failure's number
  # and its description. The phones' runs read standard output alone.
  def test_a_phones_report_is_read_from_standard_output_alone
    lines = [
      ["Default", "2)"],
      ["Error", ""],
      ["Default", "core: Class#initialize is not defined FAILED"],
      ["Error", "The rubyspec temp directory is not empty. Ensure that"],
      ["Default", "Expected [:initialize, :inherited].include? :initialize"],
      ["Default", "1 file, 1 example, 1 expectation, 1 failure, 0 errors, 0 tagged"],
    ]
    ndjson = lines.map { |type, text| JSON.generate({ "processID" => 7, "messageType" => type, "eventMessage" => text }) }.join("\n")
    read = -> (standard_error) { RubySpec::Results.read(nil, RubySpec::Phone.output(MobileParity::IOS.messages(ndjson, 7, standard_error:))) }

    assert_empty read.call(true).failures
    assert_equal ["core: Class#initialize is not defined"], read.call(false).failures.keys
  end

  # The app and stock Ruby must be the same Ruby, as RUBY_DESCRIPTION
  # names it, whether a release's ("revision") or a preview's (its
  # branch).
  def test_a_phones_ruby_is_its_version_and_revision
    assert_equal "4.1.0preview1 (revision 2d08b5f42f)",
      RubySpec::Phone.ruby("ruby 4.1.0preview1 (2026-10-11 master 2d08b5f42f) +PRISM [arm64-darwin27]\n...")
    assert_equal "4.0.9 (revision 3e93b23afc)", RubySpec::Phone.ruby(OUTPUT)
    assert_raises(RuntimeError) { RubySpec::Phone.ruby("[BUG] Segmentation fault\n") }
  end

  # mspec-run's arguments load the phones' formatter, leave out each
  # excluded example and file on that phone, and run the desktop's
  # directories, each exclusion with its reason: iOS leaves out
  # command_line, which starts ruby, and Android, which has a ruby
  # program, runs it.
  def test_a_phones_arguments_leave_out_what_no_phone_can_run
    %w[ios android].each do |phone|
      arguments = RubySpec::Phone.arguments(phone)

      assert_equal ["-B", "../phone_config.rb"], arguments.first(2)
      RubySpec::Phone::EXCLUDED.each do |exclusion|
        refute_empty exclusion.reason
        pairs = arguments.each_cons(2).to_a
        exclusion.examples.each { |example| assert_equal exclusion.applies?(phone), pairs.include?(["-E", example]) }
        (exclusion.files - exclusion.keep.keys).each do |file|
          assert_equal exclusion.applies?(phone), arguments.include?("^#{file}")
          assert_operator arguments.index("^#{file}"), :>, arguments.index("security") if exclusion.applies?(phone)
        end
        exclusion.keep.each do |file, descriptions|
          assert_includes exclusion.files, file
          refute_includes arguments, "^#{file}"
          descriptions.each { |description| assert_equal exclusion.applies?(phone), arguments.include?("--ruby-spec-keep=#{file}:#{description}") }
        end
      end
      assert_equal RubySpec::DIRECTORIES, arguments & RubySpec::DIRECTORIES
    end
    assert_includes RubySpec::Phone.arguments("ios"), "^command_line"
    refute_includes RubySpec::Phone.arguments("android"), "^command_line"
  end

  # iOS left out every example of Process.kill's file and of the files
  # about starting a program, at least 21 of which start nothing; only
  # those that start a program stay out.
  def test_ios_runs_the_examples_of_its_process_files_that_start_nothing
    arguments = RubySpec::Phone.arguments("ios")

    refute_includes arguments, "^core/process/kill_spec.rb"
    refute_includes arguments, "Process.kill checks for existence and permissions to signal a process"
    assert_includes arguments, "Process.kill accepts a Symbol as a signal name"
    assert_includes arguments, "--ruby-spec-keep=core/process/wait_spec.rb:Process.wait raises an Errno::ECHILD if there are no child processes"
    assert_includes arguments, "^core/io/popen_spec.rb"
    assert_operator arguments.grep(/\A--ruby-spec-keep=/).size, :>=, 15
  end

  # Each of these starts id before any example, which iOS lets no app
  # do; run 43313316095 showed their errors once the reader read them.
  def test_ios_leaves_out_the_etc_files_that_start_id_before_any_example
    files = %w[getpwuid_spec.rb struct_group_spec.rb struct_passwd_spec.rb].map { |file| "^library/etc/#{file}" }

    assert_empty files - RubySpec::Phone.arguments("ios")
    assert_empty files & RubySpec::Phone.arguments("android")
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
