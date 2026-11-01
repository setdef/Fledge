# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
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
end
