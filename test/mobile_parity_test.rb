# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "test_helper"
require_relative "support/gems"
require_relative "support/loopback_server"
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

  # fledge build prints the project's folder on standard output and what
  # it downloads on standard error, as GNU's conventions keep a command's
  # result apart from its diagnostics, so the check takes the folder from
  # the output alone, even when the app's gems are downloaded first.
  def test_each_project_is_the_folder_fledge_build_prints_while_it_reports_downloads
    begin
      Fledge::MobilePlatform.find("android").check_host(Fledge::Platform.local)
    rescue Fledge::Error => e
      skip e.message
    end
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p([File.join(dir, ".git"), File.join(dir, "runtimes"), File.join(dir, "gems")])
      FakeRuntime.write_mobile(File.join(dir, "runtimes"), Fledge::MobilePlatform.find("android"))
      gem = FakeGem.build(File.join(dir, "gems"), "pure", "1.0.0")
      server = LoopbackServer.new({ "/gems/#{gem.file_name}" => [200, {}, File.binread(gem.path)] })
      begin
        root = FakeProject.write(dir, dependencies: { "pure" => ">= 0" }, locked: [gem], remote: server.url("/"), platforms: %w[ruby])
        File.write(File.join(root, "fledge.yml"), "identifier: com.example.MyApp\n")
        app = MobileParity::App.new(path: root, name: "MyApp", identifier: "com.example.MyApp", prints: nil)

        projects = MobileParity.projects("android", runtimes: File.join(dir, "runtimes"), out: File.join(dir, "dist"), apps: [app],
          env: { "XDG_CACHE_HOME" => File.join(dir, "cache") })

        assert_equal({ app => File.join(dir, "dist", "MyApp-android") }, projects)
        assert_path_exists File.join(dir, "cache"), "the gem was downloaded"
      ensure
        server.stop
      end
    end
  end

  # The Android SDK's newest build tools, found from ANDROID_HOME as the
  # runner sets it: with Windows's separators on Windows, which Dir.glob
  # reads as escapes, so the check finds them from the path made plain.
  def test_the_build_tools_are_the_sdks_newest_wherever_its_path_comes_from
    Dir.mktmpdir do |sdk|
      %w[35.0.0 36.1.0 36.0.0].each { |version| FileUtils.mkdir_p(File.join(sdk, "build-tools", version)) }
      native = File::ALT_SEPARATOR ? File.expand_path(sdk).tr("/", File::ALT_SEPARATOR) : sdk

      assert_equal File.join(File.expand_path(sdk), "build-tools", "36.1.0"), MobileParity::Android.build_tools(native)
    end
    assert_raises(RuntimeError) { MobileParity::Android.build_tools(File.join(Dir.tmpdir, "no-sdk-here")) }
  end

  # zipalign -c -P 16 passes a native library it finds compressed, since
  # only a stored one needs aligning, so the check reads its verbose
  # lines for what must be stored: every native library, which Android
  # maps from the APK, and the asset fledge.zip, which FledgeRuby unpacks.
  def test_what_zipalign_finds_compressed_that_must_be_stored
    aligned = <<~ALIGNED
      Verifying alignment of base-master.apk (4)...
            49 AndroidManifest.xml (OK - compressed)
          1332 assets/fledge.zip (OK - compressed)
      30261325 classes.dex (OK - compressed)
         16384 lib/x86_64/libfledgeruby.so (OK)
      16416768 lib/x86_64/libfledgeext.so (OK - compressed)
      Verification succesful
    ALIGNED

    assert_equal %w[assets/fledge.zip lib/x86_64/libfledgeext.so], MobileParity::Android.compressed_but_mapped(aligned)
    assert_empty MobileParity::Android.compressed_but_mapped(aligned.gsub("(OK - compressed)", "(OK)"))
  end

  # bundletool get-size total prints the smallest and largest download
  # of the APKs it made, as CSV, in bytes; Play's limit is on the largest.
  def test_the_download_size_is_the_largest_bundletool_reports
    assert_equal 17_290_310, MobileParity::Android.download_size("MIN,MAX\n17112131,17290310\n")
    assert_raises(RuntimeError) { MobileParity::Android.download_size("nothing") }
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
end
