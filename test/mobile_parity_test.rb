# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "test_helper"
require_relative "../tasks/mobile_parity"

# The parts of the mobile check (doc/contributors/design/phone-projects.md,
# "Parity on a phone") that need no simulator or emulator: reading the
# probe's report and an app's status back from the entries of a system
# log, the apps it builds, the reference Ruby's environment, and the
# justifications for what a phone does differently.
# test/integration/mobile_parity_projects_test.rb has fledge build make
# the apps' projects, and CI's Mobile apps jobs build the apps with
# fledge build and run them in the iOS Simulator and Android emulators.
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

  # A line of standard error, which the embedding API logs from a thread
  # of its own, can land inside the report, so the report is read from
  # standard output alone while a failure still shows both streams.
  def test_reads_the_report_from_standard_output_when_standard_error_lands_inside_it
    json = JSON.generate({ "ARGV" => [], "long" => "é" * 900 })
    ndjson = [
      { "processID" => 7, "messageType" => "Default", "eventMessage" => "FLEDGE-PARITY #{json[0, 700]}" },
      { "processID" => 7, "messageType" => "Error", "eventMessage" => "warning: something on standard error" },
      { "processID" => 7, "messageType" => "Default", "eventMessage" => json[700..] },
      { "processID" => 7, "messageType" => "Default", "eventMessage" => "Parity exited with status 0" },
    ].map { |entry| JSON.generate(entry) }.join("\n")
    logged = MobileParity::Logged.new(entries: MobileParity::IOS.messages(ndjson, 7),
      output: MobileParity::IOS.messages(ndjson, 7, standard_error: false))

    refute_equal JSON.parse(json), MobileParity.report(logged.entries)
    assert_equal JSON.parse(json), MobileParity.report(logged.output)
    assert_includes logged.entries, "warning: something on standard error"
  end

  # A report the log cut short, or never held, is not the probe's
  # report, and says so as a CutShort, for which the Android check alone
  # launches the probe again (MobileParity::Android#check_launch).
  def test_a_log_without_a_whole_report_fails
    assert_raises(MobileParity::CutShort) { MobileParity.report(["FLEDGE-PARITY {\"ARGV\":"]) }
    assert_raises(MobileParity::CutShort) { MobileParity.report(["nothing here"]) }
  end

  # The host app of every project fledge build writes logs the app's
  # exit status when its program ends
  # (doc/contributors/design/phone-projects.md, "The host app").
  def test_the_status_is_the_hosts_last_word
    assert_equal 0, MobileParity.status(["a", "Mobile App exited with status 0"])
    assert_equal 1, MobileParity.status(["Hello exited with status 1"])
    assert_nil MobileParity.status(["a", "exited with status 0"])
  end

  # What Ruby printed last may reach the log after the host's status, so
  # the log is read until it stops growing, or until the limit.
  def test_the_log_is_read_until_it_settles
    reads = [["status"], ["status", "a"], ["status", "a", "b"], ["status", "a", "b"]]
    assert_equal ["status", "a", "b"], MobileParity.settled(interval: 0) { reads.shift }
    assert_empty reads

    growing = Enumerator.new { |lines| (1..).each { |n| lines << n } }
    assert_operator MobileParity.settled(interval: 0.01, limit: 0.05) { growing.next }, :>, 1
  end

  # Each app the check builds names itself as its fledge.yml does, so its
  # project, scheme, and log are found by those names.
  def test_each_app_is_named_as_its_fledge_yml_names_it
    MobileParity::APPS.each do |app|
      built = Fledge::App.at(File.join(MobileParity::ROOT, app.path))
      assert_equal [app.name, app.identifier], [built.name, built.identity.identifier], app.path
    end
  end

  # Each app's line matches what it printed on an arm64-v8a phone as
  # well as on CI's x86_64 emulators: these are the lines a OnePlus Nord
  # N30 5G with Android 14 printed on 2026-11-21.
  def test_each_apps_line_matches_what_it_printed_on_an_arm64_android_phone
    printed = {
      "CmakePhone" => "CmakePhone totals 10 in C++ that CMake 3.31.6 built for Android on arm64, on aarch64-linux-android",
      "RustPhone" => "RustPhone totals 10 in Rust built for android on aarch64, on aarch64-linux-android",
      "NativePhone" => "NativePhone adds 5 and totals 10 with a C extension (C and C++) on aarch64-linux-android",
    }
    printed.each do |name, line|
      app = MobileParity::APPS.find { |candidate| candidate.name == name }
      assert_match app.prints, line, name
      assert_match app.prints, line.sub("arm64, on aarch64", "x86_64, on x86_64").sub("aarch64, on aarch64", "x86_64, on x86_64"), name
    end
  end

  # sdl_phone's line matches what it printed on an arm64-v8a phone, which
  # runs Ruby on a thread of its own with a 64 MB stack, and on an iPhone,
  # which runs it on the main thread with one, and not a shallower stack
  # (doc/contributors/design/phone-projects.md, "A host that owns the main
  # loop"); the others it must print are those of a game that took a touch.
  def test_sdl_phones_lines_match_what_it_printed_and_a_shallow_stack_does_not
    app = MobileParity::APPS.find { |candidate| candidate.name == "SdlPhone" }
    phone = "SdlDemo runs Ruby on a thread of its own with a stack of 66583 KB, on aarch64-linux-android with SDL 3.4.18"
    iphone = "SdlDemo runs Ruby on the main thread with a stack of 65536 KB, on arm64-darwin with SDL 3.4.18"

    assert_match app.prints, phone
    assert_match app.prints, phone.sub("aarch64", "x86_64")
    assert_match app.prints, iphone
    refute_match app.prints, phone.sub("66583", "1008")
    refute_match app.prints, iphone.sub("65536", "512")
    assert_match app.touches, "SdlDemo drew 60 frames"
    assert_match app.touched, "SdlDemo touch down at 360, 800 in 1080x2400, frame 75"
    assert(app.sdl3)
    touched = ["SdlDemo touch down at 360, 800 in 1080x2400, frame 75", "SdlDemo drew 150 frames in all, after a touch"]
    touched.each { |line| assert(Array(app.also).any? { |pattern| line.match?(pattern) }, line) }
  end

  # SDL3's build takes minutes on a Mac, so CI keeps its result between
  # runs, and the check builds it again only when the app's script, which
  # holds SDL's version and SHA-256, is not the one that made what is
  # there.
  def test_sdl3_is_built_again_only_when_the_apps_script_changed
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "app", "sdl3"))
      script = File.join(dir, "app", "sdl3", "build.sh")
      File.write(script, "mkdir -p \"$2\" && echo built >> \"$2/runs\"\n")
      app = MobileParity::App.new(path: File.join(dir, "app"), name: "Sdl", identifier: "com.example.Sdl", prints: nil, sdl3: true)
      into = File.join(dir, "kept", "ios")
      runs = -> { File.read(File.join(into, "runs")).lines.size }

      assert_equal into, MobileParity.build_sdl3(app, "ios", into)
      assert_equal 1, runs.call
      MobileParity.build_sdl3(app, "ios", into)
      assert_equal 1, runs.call, "what a run built is kept"

      File.write(script, "mkdir -p \"$2\" && echo built again >> \"$2/runs\"\n")
      MobileParity.build_sdl3(app, "ios", into)
      assert_equal 2, runs.call, "a script that changed builds again"

      File.write(script, "echo no >&2; exit 3\n")
      error = assert_raises(RuntimeError) { MobileParity.build_sdl3(app, "ios", into) }
      assert_match(/failed:\nno/, error.message)
      assert_raises(RuntimeError) { MobileParity.build_sdl3(app, "ios", into) }
    end
  end

  # CmakePhone's line matches what it printed on an iPhone as well as in
  # CI's Simulator: CMake's toolchain names the SDK it builds for, and
  # this is the line an iPhone 12 mini with iOS 27.0 printed on
  # 2026-11-21.
  def test_cmake_phones_line_matches_what_it_printed_on_an_iphone
    app = MobileParity::APPS.find { |candidate| candidate.name == "CmakePhone" }
    line = "CmakePhone totals 10 in C++ that CMake 4.3.2 built for iOS on arm64, on arm64-darwin"

    assert_match app.prints, line
    assert_match app.prints, line.sub("for iOS on", "for iOS Simulator on")
    refute_match app.prints, line.sub("for iOS on", "for watchOS on")
  end

  # An app runs on the phones it names, and every app names both but
  # MobileCommands, which runs a gem's command, a program iOS lets no app
  # run: the libraries for ffi that ffi_library_phone's gems build reach
  # an iOS app as they reach an Android one. Pop runs on Android alone,
  # until Lota has an iOS host for this runtime.
  def test_each_phone_builds_and_runs_every_app_but_a_command_where_none_runs
    ios = MobileParity.apps("ios").map(&:name)

    assert_includes ios, "FfiLibraryPhone"
    assert_equal MobileParity.apps("android").map(&:name) - %w[MobileCommands Pop], ios
    assert_includes MobileParity.apps("android").map(&:name), "MobileCommands"
  end

  # Fledge's own manifest gives the reasons the check expects, and a
  # manifest that names a category with another reason fails it.
  def test_the_privacy_manifest_check_compares_reasons
    skip "plutil is Apple's" unless RUBY_PLATFORM.include?("darwin")
    template = File.join(MobileParity::ROOT, "lib", "fledge", "templates", "ios", "Host", "PrivacyInfo.xcprivacy")
    manifest = JSON.parse(IO.popen(["plutil", "-convert", "json", "-o", "-", template], &:read))

    assert_empty MobileParity::IOS.wrong_reasons(manifest)

    first = manifest["NSPrivacyAccessedAPITypes"].first
    first["NSPrivacyAccessedAPITypeReasons"] = ["DDA9.1"]

    assert_equal({ first["NSPrivacyAccessedAPIType"] => ["DDA9.1"] }, MobileParity::IOS.wrong_reasons(manifest))

    first["NSPrivacyAccessedAPITypeReasons"] = ["DDA9.1", "C617.1"]

    assert_empty MobileParity::IOS.wrong_reasons(manifest)
  end

  # macOS writes a crashed Simulator app's report into the account's own
  # home, which a HOME set elsewhere (a CI step's, a build node's
  # workspace) does not move.
  def test_crash_reports_are_read_from_the_accounts_own_home
    skip "the Simulator's crash reports are a Mac's" unless RUBY_PLATFORM.include?("darwin")
    saved = ENV.to_h
    ENV["HOME"] = File.join(MobileParity::ROOT, "tmp", "not-the-accounts-home")

    assert_equal File.join(Etc.getpwuid.dir, "Library", "Logs", "DiagnosticReports"), MobileParity::IOS.crash_reports
  ensure
    ENV.replace(saved) if saved
  end

  # The reference runs as a person runs ruby main.rb: in a UTF-8 locale,
  # with a home folder of its own and nothing of the runner's Ruby.
  # As a developer's shell hands it to the Ruby they run: that Ruby's
  # bin folder first on PATH, where the shell found ruby.
  def test_the_reference_runs_with_a_persons_plain_environment
    env = MobileParity.reference_environment("/work", "C.UTF-8", "/r/bin/ruby",
      { "PATH" => "/bin", "RUBYOPT" => "-W0", "GEM_HOME" => "/g", "CI" => "true" })

    assert_equal({ "PATH" => "/r/bin#{File::PATH_SEPARATOR}/bin", "HOME" => "/work/home", "LANG" => "C.UTF-8" }, env)
  end

  # Each charmap is what Ruby's Encoding.locale_charmap is under that
  # LANG: glibc reads a locale it lacks as C, ANSI_X3.4-1968, and macOS
  # reads it as US-ASCII.
  GLIBC_WITH_EN_US = { "en_US.UTF-8" => "UTF-8", "C.UTF-8" => "UTF-8", "C.utf8" => "UTF-8", "UTF-8" => "ANSI_X3.4-1968" }.freeze
  STOCK_UBUNTU = GLIBC_WITH_EN_US.merge("en_US.UTF-8" => "ANSI_X3.4-1968").freeze
  MACOS = { "en_US.UTF-8" => "UTF-8", "C.UTF-8" => "UTF-8", "C.utf8" => "US-ASCII", "UTF-8" => "UTF-8" }.freeze

  # The reference keeps en_US.UTF-8 where the computer has it, and on a
  # stock Ubuntu, which has only C and C.UTF-8, takes C.UTF-8 rather than
  # running in the C locale, whose ASCII the check would blame on the
  # phone.
  def test_the_reference_takes_the_first_utf8_locale_the_computer_has
    assert_equal "en_US.UTF-8", MobileParity.reference_locale("ruby", &GLIBC_WITH_EN_US.method(:fetch))
    assert_equal "en_US.UTF-8", MobileParity.reference_locale("ruby", &MACOS.method(:fetch))
    assert_equal "C.UTF-8", MobileParity.reference_locale("ruby", &STOCK_UBUNTU.method(:fetch))
    assert_equal "C.utf8", MobileParity.reference_locale("ruby") { |name| (name == "C.utf8") ? "utf-8" : "US-ASCII" }
  end

  # With no UTF-8 locale at all, the check stops and says what is
  # missing, rather than report the C locale as the phone's difference.
  def test_the_reference_stops_on_a_computer_with_no_utf8_locale
    error = assert_raises(RuntimeError) { MobileParity.reference_locale("/r/ruby") { "ANSI_X3.4-1968" } }

    assert_includes error.message, "no UTF-8 locale"
    assert_includes error.message, "LANG=en_US.UTF-8, C.UTF-8, C.utf8, UTF-8"
  end

  # A phone starts an app with an environment of its own, so the check
  # compares the app's ENV, and a child's, with the one the system gave
  # it, which its host logged, not with the desktop's: a variable Fledge
  # adds fails, but for the HOME Android gives no app, which FledgeRuby
  # sets.
  def test_a_phones_env_is_compared_with_the_environment_the_system_gave_the_app
    paths = { "app" => "/data/app", "prefix" => "/data/ruby", "home" => "/data/files" }
    reference = { "paths" => { "app" => "/w/app", "prefix" => "/w/ruby", "home" => "/w/home" }, "ENV" => { "PATH" => "/bin", "LANG" => "C" } }
    given = { "PATH" => "/system/bin", "TMPDIR" => "/data/cache" }
    app = -> (env) { { "paths" => paths, "ENV" => env, "child ENV" => env } }
    # Android's runtime puts its bin folder first on PATH (below).
    seen = -> (target, env) { target.end_with?("android") ? env.merge("PATH" => "/data/ruby/bin:/system/bin") : env }
    differences = -> (target, env) { MobileParity.differences(reference, app.call(seen.call(target, env)), given, platform: target, work: "/w") }

    %w[arm64-ios-simulator x86_64-linux-android].each do |target|
      assert_empty differences.call(target, given), target
      certificates = differences.call(target, given.merge("SSL_CERT_FILE" => "/data/ruby/libexec/cert.pem"))
      assert_equal ["ENV", "child ENV"], certificates.map(&:fact), target
      refute certificates.any?(&:justified?), target
    end
    home = given.merge("HOME" => "/data/files")
    assert differences.call("x86_64-linux-android", home).all?(&:justified?)
    refute differences.call("arm64-ios-simulator", home).any?(&:justified?)
  end

  # Android's runtime puts its bin folder first on the app's PATH, as a
  # developer's shell has the bin folder of the Ruby they run, so the
  # environment the system gave the app is compared with that folder
  # before its PATH there, and only there: iOS has no programs to find.
  def test_androids_path_is_compared_with_the_apps_ruby_first
    paths = { "app" => "/data/app", "prefix" => "/data/ruby", "home" => "/data/files" }
    reference = { "paths" => { "app" => "/w/app", "prefix" => "/w/ruby", "home" => "/w/home" }, "ENV" => { "PATH" => "/w/ruby/bin:/bin" } }
    given = { "PATH" => "/system/bin" }
    app = -> (env) { { "paths" => paths, "ENV" => env, "child ENV" => env } }
    differences = -> (target, env) { MobileParity.differences(reference, app.call(env), given, platform: target, work: "/w") }

    assert_empty differences.call("x86_64-linux-android", { "PATH" => "/data/ruby/bin:/system/bin" })
    assert_equal ["ENV", "child ENV"], differences.call("x86_64-linux-android", given).map(&:fact)
    assert_empty differences.call("arm64-ios-simulator", given)
  end

  # An extension loaded from a file on both sides differs only in the
  # suffix each system gives a loadable extension (RbConfig::CONFIG["DLEXT"]),
  # ".bundle" on a Mac's reference and ".so" on Android, so each side's own
  # is set aside and the rest of the path must be the same. Any other
  # difference stays one: a name, a folder, a suffix of neither system, an
  # extension on one side only.
  def test_android_pairs_a_macs_bundle_extensions_with_its_so_files_by_everything_else
    paths = { "app" => "/data/app", "prefix" => "/data/ruby", "home" => "/data/files" }
    reference_paths = { "app" => "/w/app", "prefix" => "/w/ruby", "home" => "/w/home" }
    mac = "/w/ruby/lib/ruby/4.1.0/arm64-darwin25"
    android = "/data/ruby/lib/ruby/4.1.0/x86_64-linux-android"
    reference = -> (*files) { { "paths" => reference_paths, "$LOADED_FEATURES" => ["#{mac}/rbconfig.rb", *files.map { |file| "#{mac}/#{file}" }] } }
    report = -> (*files) { { "paths" => paths, "$LOADED_FEATURES" => ["#{android}/rbconfig.rb", *files.map { |file| "#{android}/#{file}" }] } }
    differences = lambda do |expected, actual|
      MobileParity.differences(expected, actual, {}, platform: "x86_64-linux-android", work: "/w").select { |found| found.fact == "$LOADED_FEATURES" }
    end

    whole = differences.call(reference.call("enc/utf_16le.bundle", "json/ext/parser.bundle"),
      report.call("enc/utf_16le.so", "json/ext/parser.so"))
    assert_equal 1, whole.size
    assert_empty whole.reject(&:justified?)
    refute_empty differences.call(reference.call("enc/utf_16le.bundle", "json/ext/parser.bundle"),
      report.call("enc/utf_16be.so", "json/ext/parser.so")).reject(&:justified?)
    refute_empty differences.call(reference.call("json/ext/parser.bundle"), report.call("json/generator/parser.so")).reject(&:justified?)
    refute_empty differences.call(reference.call("json/ext/parser.bundle"), report.call("json/ext/parser.dll")).reject(&:justified?)
    refute_empty differences.call(reference.call("json/ext/parser.bundle", "date_core.bundle"), report.call("json/ext/parser.so")).reject(&:justified?)
    refute_empty differences.call(reference.call("json/ext/parser.bundle"), report.call("json/ext/parser.so", "date_core.so")).reject(&:justified?)
    refute_empty differences.call(reference.call("json/ext/parser.bundle", "set.rb"), report.call("json/ext/parser.so", "set.rb")).reject(&:justified?)
  end

  # Android compares how a program runs a gem's command; iOS, which lets
  # no app start a program, does not yet.
  def test_android_compares_the_gem_commands
    paths = { "app" => "/data/app", "prefix" => "/data/ruby", "home" => "/data/files" }
    reference = {
"paths" => { "app" => "/w/app", "prefix" => "/w/ruby", "home" => "/w/home" },
"gem commands" => { "system" => ["/w/ruby/bin/ruby 13.3.1", true] },
}
    app = { "paths" => paths, "gem commands" => { "system" => ["", nil] } }
    differences = -> (target) { MobileParity.differences(reference, app, {}, platform: target, work: "/w").map(&:fact) }

    assert_includes differences.call("x86_64-linux-android"), "gem commands"
    refute_includes differences.call("arm64-ios-simulator"), "gem commands"
  end

  # The probe's host logs the environment the system gave it, a line
  # for each variable, before it starts Ruby: the host fledge build
  # writes, with one loop more, which the check reads back.
  def test_the_probes_host_logs_the_environment_it_was_given
    MobileParity::Environment::HOSTS.each do |phone, (file, _, loop)|
      Dir.mktmpdir do |project|
        template = File.join(MobileParity::ROOT, "lib", "fledge", "templates", phone, file)
        FileUtils.mkdir_p(File.dirname(File.join(project, file)))
        FileUtils.cp(template, File.join(project, file))

        MobileParity::Environment.record(phone, project)
        host = File.read(File.join(project, file))

        assert_includes host, loop, phone
        assert_operator host.index(loop), :<, host.index((phone == "ios") ? "= fledge_ruby_run_app(" : "FledgeRuby.startAppOnMainThread("), phone
        File.write(File.join(project, file), "")
        assert_raises(RuntimeError, phone) { MobileParity::Environment.record(phone, project) }
      end
    end
    entries = ["FLEDGE-ENVIRON PATH=/system/bin", "booting", "FLEDGE-ENVIRON EMPTY=", "FLEDGE-ENVIRON A=b=c"]
    assert_equal({ "PATH" => "/system/bin", "EMPTY" => "", "A" => "b=c" }, MobileParity::Environment.read(entries))
    assert_raises(RuntimeError) { MobileParity::Environment.read(["booting"]) }
  end

  # The Android SDK's newest build tools, found from ANDROID_HOME as the
  # runner sets it: with Windows's separators on Windows, which Dir.glob
  # reads as escapes, so the check finds them from the path made plain.
  # The SDK's folder is named by its long names, as Dir.glob names what
  # it finds (Fledge::LongPath), where Windows' TMP gives an 8.3 name.
  def test_the_build_tools_are_the_sdks_newest_wherever_its_path_comes_from
    Dir.mktmpdir do |folder|
      sdk = Fledge::LongPath.of(folder)
      %w[35.0.0 36.1.0 36.0.0].each { |version| FileUtils.mkdir_p(File.join(sdk, "build-tools", version)) }
      native = File::ALT_SEPARATOR ? File.expand_path(sdk).tr("/", File::ALT_SEPARATOR) : sdk

      assert_equal File.join(File.expand_path(sdk), "build-tools", "36.1.0"), MobileParity::Android.build_tools(native)
    end
    assert_raises(RuntimeError) { MobileParity::Android.build_tools(File.join(Dir.tmpdir, "no-sdk-here")) }
  end

  # zipalign -c -P 16 passes an entry whether it is stored or compressed,
  # so the check reads its verbose lines for how each entry Android needs
  # a certain way is packed: the asset fledge.zip stored, which
  # FledgeRuby unpacks from the APK, and every native library
  # compressed, which only the package installer's extraction puts where
  # Android lets an app run its ruby program (doc/contributors/design/phone-runtimes.md,
  # "The ruby program on Android").
  def test_what_zipalign_finds_packed_as_android_does_not_take_it
    aligned = <<~ALIGNED
      Verifying alignment of base-master.apk (4)...
            49 AndroidManifest.xml (OK - compressed)
          1332 assets/fledge.zip (OK - compressed)
      30261325 classes.dex (OK - compressed)
         16384 lib/x86_64/libfledgeruby.so (OK)
      16416768 lib/x86_64/libfledgerubyexe.so (OK - compressed)
      Verification succesful
    ALIGNED

    assert_equal ["assets/fledge.zip (compressed)", "lib/x86_64/libfledgeruby.so (stored)"], MobileParity::Android.packed_wrongly(aligned)
    assert_empty MobileParity::Android.packed_wrongly(aligned.sub("fledge.zip (OK - compressed)", "fledge.zip (OK)")
      .sub("libfledgeruby.so (OK)", "libfledgeruby.so (OK - compressed)"))
  end

  # The check types an item into an app's field and taps its button
  # where UI Automator's dump says they are.
  def test_a_ui_automator_dump_gives_the_centre_of_a_node
    xml = <<~XML
      <?xml version='1.0' encoding='UTF-8' standalone='yes' ?><hierarchy rotation="0">
      <node index="0" text="" class="android.widget.EditText" bounds="[0,100][600,200]" />
      <node index="1" text="Add" class="android.widget.Button" bounds="[600,100][800,200]" />
      <node index="2" text="Milk" class="android.widget.TextView" bounds="[0,200][800,300]" /></hierarchy>
      UI hierchary dumped to: /dev/tty
    XML
    nodes = MobileParity::Android.nodes(xml)
    assert_equal 3, nodes.size
    assert_equal [300, 150], MobileParity::Android.centre(nodes, class: "android.widget.EditText")
    assert_equal [700, 150], MobileParity::Android.centre(nodes, text: "Add")
    assert_equal [400, 250], MobileParity::Android.centre(nodes, class: "android.widget.TextView", text: "Milk")
    assert_nil MobileParity::Android.centre(nodes, text: "Eggs")
  end

  # bundletool get-size total prints the smallest and largest download
  # of the APKs it made, as CSV, in bytes; Play's limit is on the largest.
  def test_the_download_size_is_the_largest_bundletool_reports
    assert_equal 17_290_310, MobileParity::Android.download_size("MIN,MAX\n17112131,17290310\n")
    assert_raises(RuntimeError) { MobileParity::Android.download_size("nothing") }
  end

  # A Gradle build that failed is reported by what Gradle's --info log
  # says of each repository's answers, a 404 as "Resource missing" and
  # any other refusal with its status, then by Gradle's own failure, so
  # that a "Could not find" shows which answer it stood for.
  def test_a_failed_gradle_build_is_reported_by_its_repositories_answers_and_its_failure
    log = <<~LOG
      Initialized native services in: /home/runner/.gradle/native
      Resource missing. [HTTP GET: https://dl.google.com/dl/android/maven2/com/google/guava/guava/33.4.0-jre/guava-33.4.0-jre.pom]
      Resource missing. [HTTP GET: https://repo.maven.apache.org/maven2/com/google/guava/guava/33.4.0-jre/guava-33.4.0-jre.pom]
      Failed to get resource: GET. [HTTP 429: https://repo.maven.apache.org/maven2/org/ow2/asm/asm/9.9/asm-9.9.pom)]
      Resolve mutations for :app:compileJava (Thread[included builds,5,main]) started.

      FAILURE: Build failed with an exception.

      * What went wrong:
         > Could not find com.google.guava:guava:33.4.0-jre.

      BUILD FAILED in 9s
      Watched directory hierarchies: []
    LOG

    assert_equal <<~REPORT.chomp, MobileParity::Android.gradle_failure(log)
      Resource missing. [HTTP GET: https://dl.google.com/dl/android/maven2/com/google/guava/guava/33.4.0-jre/guava-33.4.0-jre.pom]
      Resource missing. [HTTP GET: https://repo.maven.apache.org/maven2/com/google/guava/guava/33.4.0-jre/guava-33.4.0-jre.pom]
      Failed to get resource: GET. [HTTP 429: https://repo.maven.apache.org/maven2/org/ow2/asm/asm/9.9/asm-9.9.pom)]
      FAILURE: Build failed with an exception.

      * What went wrong:
         > Could not find com.google.guava:guava:33.4.0-jre.

      BUILD FAILED in 9s
    REPORT
  end

  # Some of GitHub's runners were answered 404 for modules Maven Central
  # holds, which Gradle reports at once and does not cache (issue 27), so
  # a build whose log says a repository answered "Resource missing" runs
  # once more, and no other failure does.
  def test_a_gradle_build_that_a_repository_answered_404_runs_once_more
    Dir.mktmpdir do |dir|
      log = File.join(dir, "gradle.log")
      runs = 0
      built = MobileParity::Android.gradle_with_a_second_try(log) do
        runs += 1
        File.write(log, (runs == 1) ? "Resource missing. [HTTP GET: https://repo.maven.apache.org/maven2/a.pom]\nBUILD FAILED in 9s\n" : "BUILD SUCCESSFUL in 9s\n", mode: "a")
        runs == 2
      end

      assert built
      assert_equal 2, runs
      assert_includes File.read(log), "Resource missing", "the first try's log is kept"
    end
  end

  def test_a_gradle_build_that_failed_for_another_reason_or_twice_is_not_run_again
    Dir.mktmpdir do |dir|
      log = File.join(dir, "gradle.log")
      runs = 0
      refute(MobileParity::Android.gradle_with_a_second_try(log) do
        runs += 1
        File.write(log, "Failed to get resource: GET. [HTTP 429: x]\nBUILD FAILED\n")
        false
      end)
      assert_equal 1, runs

      File.write(log, "")
      runs = 0
      refute(MobileParity::Android.gradle_with_a_second_try(log) do
        runs += 1
        File.write(log, "Resource missing. [HTTP GET: x]\n", mode: "a")
        false
      end)
      assert_equal 2, runs

      File.write(log, "")
      runs = 0
      assert(MobileParity::Android.gradle_with_a_second_try(log) { runs += 1 })
      assert_equal 1, runs
    end
  end

  # An app that never finished is diagnosed from logcat's lines about it:
  # those naming it, those of its process, by the ID ActivityManager
  # started it with, and the crash reporters', not the system's chatter.
  def test_an_unfinished_apps_diagnosis_is_what_logcat_says_of_it
    app = MobileParity::APPS.fetch(1)
    log = <<~LOG
      11-01 05:26:40.100   745   859 I ActivityManager: Start proc 8123:com.setdef.fledge.MobileApp/u0a213 for next-top-activity {com.setdef.fledge.MobileApp/org.setdef.fledge.host.MainActivity}
      11-01 05:26:40.300   745  1024 D WifiScoreCard: txRate: 1 txSpeed: 11
      11-01 05:26:41.000  8123  8140 F libc    : Fatal signal 11 (SIGSEGV), code 1 (SEGV_MAPERR) in tid 8140 (ruby)
      11-01 05:26:41.200  8150  8150 F DEBUG   : pid: 8123, tid: 8140, name: ruby  >>> com.setdef.fledge.MobileApp <<<
      11-01 05:26:41.300  8150  8150 F DEBUG   :       #00 pc 0000000000123456  libfledgeruby.so
      11-01 05:26:41.400  8123  8123 W setdef.fledge.MobileAp: something of its own
      11-01 05:26:42.000  9000  9000 I chatty  : uid=1000 expire 3 lines
    LOG

    lines = MobileParity::Android.about(app, log)

    assert_equal [0, 2, 3, 4, 5], lines.map { |line| log.lines.map(&:chomp).index(line) }
  end

  # An app that sets $0 changes the command line pidof finds it by, so
  # the harness follows the process ActivityManager says it started.
  def test_an_apps_process_is_the_one_activity_manager_started_for_it
    app = MobileParity::APPS.fetch(1)
    log = <<~LOG
      11-01 05:26:40.100   745   859 I ActivityManager: Start proc 8123:com.setdef.fledge.MobileApp/u0a213 for next-top-activity {com.setdef.fledge.MobileApp/org.setdef.fledge.host.MainActivity}
      11-01 05:26:40.200   745   859 I ActivityManager: Start proc 8200:com.setdef.fledge.MobileAppOther/u0a214 for service {}
      11-01 05:26:44.100   745   859 I ActivityManager: Start proc 8301:com.setdef.fledge.MobileApp:worker/u0a213 for service {}
    LOG

    assert_equal %w[8123 8301], MobileParity::Android.started(app, log)
    assert_empty MobileParity::Android.started(app, "11-01 05:26:40.300   745  1024 D WifiScoreCard: txRate: 1\n")
  end

  # An emulator, as MobileParity::Android#launch sees it through adb,
  # that moves on a step each time the app's log is read: the app's
  # process appears, to logcat and to pidof, from step +started+, ends
  # at step +ends+, and logs the host's status from step +finishes+,
  # each nil for never. The app prints the lines +said+ first, and
  # liblog's events buffer holds +dropped+, its count of entries it
  # could not send to logd.
  class Emulator < MobileParity::Android
    PID = "4242"

    # How many times the app was launched, and the touches it was given
    # (each the x and y of an adb input tap, with the lines the app had
    # logged when it came).
    attr_reader :launches, :taps, :settings

    def initialize(app, work:, started: 0, ends: nil, finishes: nil, said: [], dropped: nil, launched: [said], registers: nil, out: StringIO.new)
      super(work:, out:)
      @app = app
      @started = started
      @ends = ends
      @finishes = finishes
      @launched = launched
      @said = said
      @dropped = dropped
      @step = 0
      @launches = 0
      @registers = registers
      @taps = []
      @settings = []
    end

    private def adb(*arguments)
      case arguments
      in ["shell", "wm", "size"] then "Physical size: 1080x2400\n"
      in ["shell", "input", "tap", x, y] then tapped(x, y)
      in ["shell", "settings", "put", *setting] then (@settings << setting).then { "" }
      in ["logcat", "-c"] then launched
      in ["logcat", "-d", "-v", "threadtime"] then whole_log
      in ["logcat", "-d", "-v", "tag", "-s", _, _] then tagged.tap { @step += 1 }
      else ""
      end
    end

    # Each launch clears the log, after which the app says the lines of
    # the next of +launched+, or of its last once none is left.
    private def launched
      @said = @launched.fetch(@launches, @launched.last)
      @launches += 1
      @step = 0
      ""
    end

    # Records a tap with the lines the app had logged, and has the game
    # log a touch from the +registers+th tap on, as one that reaches it.
    private def tapped(x, y)
      @taps << [x, y, @said.dup]
      @said += ["SdlDemo touch down at #{x}, #{y} in 1080x2400, frame 75"] if @registers && @taps.size >= @registers
      ""
    end

    private def whole_log
      return "" unless started?

      "11-19 06:00:00.100   748   781 I ActivityManager: Start proc #{PID}:#{@app.identifier}/u0a213 for next-top-activity " \
        "{#{@app.identifier}/#{ACTIVITY}}\n"
    end

    private def liblog_events
      @dropped ? "11-19 06:00:01.200  #{PID}  #{PID} I liblog  : #{@dropped}\n" : ""
    end

    private def tagged
      lines = ["I/#{@app.identifier}: running", *@said.map { |line| "I/#{@app.identifier}: #{line}" }]
      lines << "I/#{@app.identifier}.host: #{@app.name} exited with status 0" if @finishes && @step >= @finishes
      "#{lines.join("\n")}\n"
    end

    private def pidof(_app) = (PID if running?(PID))

    private def running?(pid) = pid == PID && started? && !(@ends && @step >= @ends)

    private def started? = !@started.nil? && @step >= @started
  end

  # SdlPhone is a game that waits for a touch: the check taps the screen a
  # third of the way across and down, as the iOS check's UI test does,
  # once the game has drawn (its line), and not before; and again while
  # the game logs no touch, since a tap that comes as its window opens may
  # reach nothing, and no more once it does.
  def test_a_game_is_touched_once_it_has_drawn_and_again_until_it_logs_a_touch
    app = MobileParity::APPS.find { |each| each.name == "SdlPhone" }
    Dir.mktmpdir do |work|
      before = Emulator.new(app, work:, finishes: 3, said: ["SdlDemo recurses 3970 levels deep"])
      before.launch(app, timeout: 60, interval: 0)
      assert_empty before.taps

      emulator = Emulator.new(app, work:, finishes: 8, said: ["SdlDemo drew 60 frames"], registers: 2)
      logged = emulator.launch(app, timeout: 60, interval: 0)

      assert_equal [["360", "800"], ["360", "800"]], emulator.taps.map { |tap| tap.first(2) }
      assert_equal ["SdlDemo drew 60 frames"], emulator.taps.first.last
      assert_equal [%w[secure immersive_mode_confirmations confirmed]], emulator.settings
      assert_includes logged.entries, "SdlDemo touch down at 360, 800 in 1080x2400, frame 75"
      assert_includes logged.entries, "SdlPhone exited with status 0"
    end
  end

  def test_an_app_that_asks_for_no_touch_is_given_none
    app = MobileParity::APPS.fetch(0)
    Dir.mktmpdir do |work|
      emulator = Emulator.new(app, work:, finishes: 2, said: ["Hello from Ruby 4.1.0 on aarch64-linux-android"])
      emulator.launch(app, timeout: 60, interval: 0)

      assert_empty emulator.taps
      assert_empty emulator.settings, "an app that takes no touch has the system left as it is"
    end
  end

  def test_the_touch_is_a_third_of_the_way_across_the_screen_wm_size_prints
    assert_equal [360, 800], MobileParity::Android.touch_point("Physical size: 1080x2400\n")
    assert_equal [360, 800], MobileParity::Android.touch_point("Physical size: 1080x2400\nOverride size: 1080x2400\n")
    assert_raises(RuntimeError) { MobileParity::Android.touch_point("") }
  end

  # Logcat holds a line a moment after it is logged, and am start -W can
  # return before ActivityManager has started the process, so a launch
  # that finds no process at first looks again while it waits; on
  # 2026-11-16 the ruby/spec job took a process it had not yet seen for
  # one that had ended.
  def test_a_launch_waits_for_a_process_it_has_not_yet_seen
    app = MobileParity::APPS.fetch(1)
    Dir.mktmpdir do |work|
      logged = Emulator.new(app, work:, started: 1, finishes: 3).launch(app, timeout: 60, interval: 0)

      assert_equal 0, MobileParity.status(logged.entries)
    end
  end

  # A process that was seen and is gone without the host's status has
  # ended, as when Android stopped it; one never seen has not finished.
  def test_a_launch_fails_for_a_process_that_ended_and_one_never_seen
    app = MobileParity::APPS.fetch(1)
    Dir.mktmpdir do |work|
      ended = assert_raises(RuntimeError) { Emulator.new(app, work:, ends: 2).launch(app, timeout: 60, interval: 0) }
      unseen = assert_raises(RuntimeError) { Emulator.new(app, work:, started: nil).launch(app, timeout: 0, interval: 0) }

      assert_match(/\AMobile App ended without a status:/, ended.message)
      assert_match(/\AMobile App did not finish in 0 seconds:/, unseen.message)
    end
  end

  # A real app stays open, as examples/basket does: its line, not its
  # program's end, finishes its launch, and the check fails it if it
  # ended.
  def test_an_app_that_stays_open_is_done_when_it_prints_its_line_and_fails_if_it_ended
    app = MobileParity::App.new(path: "examples/basket", name: "Basket", identifier: "com.setdef.fledge.Basket",
      prints: /\ABasket shows \d+ items?\z/, stays_open: true)
    Dir.mktmpdir do |work|
      logged = Emulator.new(app, work:, said: ["Basket shows 0 items"]).launch(app, timeout: 60, interval: 0)
      parity = MobileParity.new(target: "x86_64-linux-android", work:, out: StringIO.new)

      assert_nil MobileParity.status(logged.entries)
      assert parity.check(app, logged, "an emulator")
      ended = MobileParity::Logged.new(entries: ["Basket shows 0 items", "Basket exited with status 0"], output: [])
      assert_raises(RuntimeError) { parity.check(app, ended, "an emulator") }
      refute app.finished?(["running"])
      refute MobileParity::APPS.fetch(0).finished?(["Hello from Ruby 4.1.0 on arm64-darwin"])
    end
  end

  # Pop, a Lota game, stays open on a phone, which has no environment
  # variable to end it with, so it passes once its third dot is on the
  # screen, and fails if it ended, if it never reached three dots, and
  # (on Android) unless Android was told first that a person has
  # confirmed full-screen mode, as it is for every SDL game.
  def test_pop_passes_once_it_has_three_dots_and_fails_when_it_ended_or_has_fewer
    app = MobileParity::APPS.find { |each| each.name == "Pop" }
    parity = MobileParity.new(target: "x86_64-linux-android", work: Dir.tmpdir, out: StringIO.new)
    running = ["Pop: 1 dot, 0 popped", "Pop: 2 dots, 0 popped", "Pop: 3 dots, 0 popped"]

    assert_equal "examples/lota_pop", app.path
    assert_equal [".github/scripts/lota-pop.sh", "examples/lota_pop"], app.prepare
    assert_equal %w[android], app.phones, "Lota 0.8.0's iOS host does not fit this runtime yet"
    refute_includes MobileParity.apps("ios").map(&:name), "Pop"
    assert parity.check(app, MobileParity::Logged.new(entries: running, output: []), "an emulator")
    refute app.finished?(running.first(2))
    assert app.finished?(running)
    assert_raises(RuntimeError) { parity.check(app, MobileParity::Logged.new(entries: [*running, "Pop exited with status 0"], output: []), "an emulator") }
    assert_raises(RuntimeError) { parity.check(app, MobileParity::Logged.new(entries: running.first(2), output: []), "an emulator") }
    refute_match app.prints, "Pop: 3 popped"
  end

  def test_a_game_that_hides_the_system_bars_has_its_confirmation_given_before_it_starts
    app = MobileParity::APPS.find { |each| each.name == "Pop" }
    Dir.mktmpdir do |work|
      emulator = Emulator.new(app, work:, finishes: 2, said: ["Pop: 3 dots, 0 popped"])
      emulator.launch(app, timeout: 60, interval: 0)

      assert_equal [%w[secure immersive_mode_confirmations confirmed]], emulator.settings
      assert_empty emulator.taps, "Pop needs no touch to say that it runs"
    end
  end

  # An app whose project needs files laid out first has the command that
  # lays them out run before fledge build, so a command that fails stops
  # the check there, with the command's own status.
  def test_a_command_that_lays_an_app_out_runs_first_and_stops_the_build_when_it_fails
    Dir.mktmpdir do |dir|
      app = MobileParity::App.new(path: "examples/lota_pop", name: "Pop", identifier: "com.setdef.fledge.Pop", prints: nil,
        prepare: ["sh", "-c", "echo laid out > \"$0\"; exit 3", File.join(dir, "marker")])

      error = assert_raises(RuntimeError) { MobileParity.projects("ios", runtimes: dir, out: dir, apps: [app]) }

      assert_match(/exit 3/, error.message)
      assert_equal "laid out\n", File.read(File.join(dir, "marker"))
    end
  end

  # Basket prints that it added the item a person typed and removed it,
  # each a line the check requires, so that an app that shows its list
  # and does nothing a person asks of it fails.
  def test_every_other_line_an_app_must_print_is_required
    app = MobileParity::APPS.find { |each| each.name == "Basket" }
    parity = MobileParity.new(target: "x86_64-linux-android", work: Dir.tmpdir, out: StringIO.new)
    both = ["Basket shows 0 items", "Basket added Milk", "Basket removed Milk"]
    assert parity.check(app, MobileParity::Logged.new(entries: both, output: []), "an emulator")
    error = assert_raises(RuntimeError) { parity.check(app, MobileParity::Logged.new(entries: both.first(2), output: []), "an emulator") }
    assert_match(/no line matching .*Basket removed Milk/, error.message)
  end

  # APPS=PATH,... picks the apps a run builds, to prove one alone.
  def test_only_the_apps_named_run_when_some_are
    assert_equal ["Hello"], MobileParity.apps("ios", only: "examples/hello").map(&:name)
    assert_equal ["Hello", "Mobile App"], MobileParity.apps("android", only: "examples/hello, test/fixtures/mobile_app").map(&:name)
    assert_equal MobileParity::APPS.size, MobileParity.apps("android", only: nil).size
  end

  # A launch whose check fails keeps everything logcat holds, and
  # liblog's count of the entries it dropped (logd_writer.cpp,
  # LogdWrite), for the job's artifact: a probe whose report came back
  # short from logcat failed once in CI with nothing kept to say why.
  def test_a_failed_check_keeps_logcat_and_liblogs_drops
    app = MobileParity.apps("android").find { |each| each.prints.nil? }
    Dir.mktmpdir do |work|
      emulator = Emulator.new(app, work:, finishes: 0, said: ['FLEDGE-PARITY {"ARGV":[]}'], dropped: 3)

      failure = assert_raises(RuntimeError) { emulator.check_launch(app, Comparing.new(same: true, work:), "from its release bundle", interval: 0) }

      assert_match(/the probe's host logged no environment/, failure.message)
      assert_includes File.read(File.join(work, "logcat-#{app.identifier}.txt")), "Start proc #{Emulator::PID}:#{app.identifier}"
      assert_includes File.read(File.join(work, "logcat-#{app.identifier}-liblog.txt")), "I liblog  : 3"
    end
  end

  # A MobileParity that compares a whole report with no reference Ruby's
  # and finds it the same when +same+, keeping each it was given.
  class Comparing < MobileParity
    attr_reader :compared

    def initialize(same:, work:)
      super(target: "x86_64-linux-android", work:, out: StringIO.new)
      @same = same
      @compared = []
    end

    def compare(report, _device, environment:)
      @compared << [report, environment]
      @same
    end
  end

  # What the probe's host logs of its environment, and a report whole
  # and cut short, as the log's entries hold them.
  PROBE_HOST = ["FLEDGE-ENVIRON PATH=/system/bin", "FLEDGE-ENVIRON HOME=/data/user/0/com.setdef.fledge.Parity/files"].freeze
  WHOLE = [*PROBE_HOST, 'FLEDGE-PARITY {"ARGV":[],', '"long":"tail"}'].freeze
  CUT = [*PROBE_HOST, 'FLEDGE-PARITY {"ARGV":[],'].freeze

  # liblog drops an entry when logd is busy and tells the app nothing
  # (doc/contributors/design/phone-runtimes.md, "Output to the system
  # log"), so a report the log cut short launches the probe again, the
  # short launch's log kept, and the next launch's whole report is the
  # one compared.
  def test_a_report_the_log_cut_short_launches_the_probe_again
    app = MobileParity.apps("android").find { |each| each.prints.nil? }
    Dir.mktmpdir do |work|
      out = StringIO.new
      emulator = Emulator.new(app, work:, finishes: 0, launched: [CUT, WHOLE], dropped: 3, out:)
      parity = Comparing.new(same: true, work:)

      assert emulator.check_launch(app, parity, "from its release bundle", interval: 0)
      assert_equal 2, emulator.launches
      assert_equal [[{ "ARGV" => [], "long" => "tail" }, { "PATH" => "/system/bin", "HOME" => "/data/user/0/com.setdef.fledge.Parity/files" }]],
        parity.compared
      assert_includes File.read(File.join(work, "logcat-#{app.identifier}-1.txt")), "Start proc #{Emulator::PID}:#{app.identifier}"
      assert_includes File.read(File.join(work, "logcat-#{app.identifier}-1-liblog.txt")), "I liblog  : 3"
      assert_match(/\AParity, from its release bundle, launch 1 of 3: the probe's report ends before it is whole/, out.string)
    end
  end

  # A whole report is compared once, and a difference in it fails the
  # check: launching again could only hide it.
  def test_a_whole_report_that_differs_is_not_launched_again
    app = MobileParity.apps("android").find { |each| each.prints.nil? }
    Dir.mktmpdir do |work|
      emulator = Emulator.new(app, work:, finishes: 0, launched: [WHOLE, WHOLE])
      parity = Comparing.new(same: false, work:)

      refute emulator.check_launch(app, parity, "from its debug APK", interval: 0)
      assert_equal 1, emulator.launches
      assert_equal 1, parity.compared.size
    end
  end

  # A report cut short at every launch fails after Android::ATTEMPTS
  # launches, each one's log kept.
  def test_a_report_cut_short_each_time_fails_after_a_few_launches
    app = MobileParity.apps("android").find { |each| each.prints.nil? }
    Dir.mktmpdir do |work|
      emulator = Emulator.new(app, work:, finishes: 0, launched: [CUT])
      parity = Comparing.new(same: true, work:)

      failure = assert_raises(MobileParity::CutShort) { emulator.check_launch(app, parity, "from its debug APK", interval: 0) }

      assert_match(/the probe's report ends before it is whole/, failure.message)
      assert_equal MobileParity::Android::ATTEMPTS, emulator.launches
      assert_empty parity.compared
      assert_equal((1..MobileParity::Android::ATTEMPTS).map { |launch| "logcat-#{app.identifier}-#{launch}.txt" },
        Dir.children(work).grep(/\Alogcat-[^-]+-\d+\.txt\z/).sort)
    end
  end

  # The embedding API logs standard error as errors on iOS, and standard
  # output and the host's lines as default messages, so a reader that
  # wants one stream in its own order can leave the other out; lines of
  # other processes, and what is not JSON, are not the app's.
  def test_ios_messages_are_the_processes_own_and_may_leave_out_standard_error
    ndjson = [
      { "processID" => 7, "messageType" => "Default", "eventMessage" => "1)" },
      { "processID" => 7, "messageType" => "Error", "eventMessage" => "The rubyspec temp directory is not empty." },
      { "processID" => 8, "messageType" => "Default", "eventMessage" => "another launch" },
      { "processID" => 7, "messageType" => "Default", "eventMessage" => "core: Class#initialize is not defined FAILED" },
      { "processID" => 7, "messageType" => "Default", "eventMessage" => "RubySpec exited with status 1" },
    ].map { |entry| JSON.generate(entry) }.push("Filtering the log data using ...").join("\n")

    assert_equal [
      "1)",
      "The rubyspec temp directory is not empty.",
      "core: Class#initialize is not defined FAILED",
      "RubySpec exited with status 1",
], MobileParity::IOS.messages(ndjson, 7)
    assert_equal ["1)", "core: Class#initialize is not defined FAILED", "RubySpec exited with status 1"],
      MobileParity::IOS.messages(ndjson, 7, standard_error: false)
  end

  # An app that a UI test launches has a process ID the check was never
  # told, so it reads every line the app's subsystem logged since the test
  # began.
  def test_ios_messages_of_no_process_are_every_process_of_the_subsystem
    ndjson = [
      { "processID" => 7, "messageType" => "Default", "eventMessage" => "SdlDemo drew 60 frames" },
      { "processID" => 9, "messageType" => "Default", "eventMessage" => "SdlPhone exited with status 0" },
    ].map { |entry| JSON.generate(entry) }.join("\n")

    assert_equal ["SdlDemo drew 60 frames", "SdlPhone exited with status 0"], MobileParity::IOS.messages(ndjson, nil)
    assert_equal ["SdlDemo drew 60 frames"], MobileParity::IOS.messages(ndjson, 7)
  end

  # A launch SpringBoard denies says only that it did, in a line or two,
  # so the failure carries simctl's own words and what the Simulator held
  # when it was denied, which is what tells a person why.
  def test_ios_launch_failure_carries_simctls_words_and_what_the_simulator_held
    message = MobileParity::IOS.launch_failure(%w[xcrun simctl launch UDID com.example.App],
      "Simulator device failed to launch com.example.App.\nThe request was denied by service delegate (SBMainWorkspace).\n",
      "Booted", ["SpringBoard: denied com.example.App", "FrontBoard: busy"])

    assert_includes message, "xcrun simctl launch UDID com.example.App failed"
    assert_includes message, "denied by service delegate (SBMainWorkspace)"
    assert_includes message, "The device was Booted"
    assert_includes message, "SpringBoard: denied com.example.App\nFrontBoard: busy"
  end

  # On Android the embedding API logs standard error as warnings and
  # standard output as information, as the host logs its status, which
  # logcat -v tag prints before each message, an empty one included.
  def test_android_messages_are_the_tags_own_and_may_leave_out_standard_error
    tag = "com.setdef.fledge.RubySpec"
    log = <<~LOG
      --------- beginning of main
      I/#{tag}: 1)
      W/#{tag}: The rubyspec temp directory is not empty.
      I/#{tag}:#{' '}
      I/#{tag}:   indented
      I/#{tag}: core: Class#initialize is not defined FAILED
      I/OtherTag: not the app's
      I/#{tag}: RubySpec exited with status 1
    LOG

    assert_equal [
      "1)",
      "The rubyspec temp directory is not empty.",
      "",
      "  indented",
      "core: Class#initialize is not defined FAILED",
      "RubySpec exited with status 1",
], MobileParity::Android.messages(log, tag)
    assert_equal ["1)", "", "  indented", "core: Class#initialize is not defined FAILED", "RubySpec exited with status 1"],
      MobileParity::Android.messages(log, tag, standard_error: false)
  end

  # The embedding API writes a NUL byte an app prints as 0xC0 0x80, so
  # that the log keeps the rest of the line (runtime/mobile/output.c); a
  # reader of the log, which then holds bytes that are not valid UTF-8,
  # gives the line as the app printed it.
  def test_the_logcat_reader_turns_the_logs_form_of_a_nul_byte_back
    tag = "com.setdef.fledge.Hello"
    log = "I/#{tag}: NUL: before\xC0\x80after\nI/#{tag}: \xC3\xA9\n"

    assert_equal ["NUL: before\0after", "\u00e9"], MobileParity::Android.messages(log, tag)
    assert_equal "NUL: before\0after", MobileParity.printed("NUL: before\xC0\x80after".b)
    assert_equal "NUL: before\0after", MobileParity.printed("NUL: before␀after", MobileParity::IOS_NUL)
    assert_equal "e\u0301 \u00c0", MobileParity.printed("e\u0301 \u00c0")
  end
end
