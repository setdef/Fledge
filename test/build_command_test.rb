# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "test_helper"
require "digest"
require "stringio"

# fledge build's arguments, through real streams, with runtimes from a
# FLEDGE_RUNTIME_DIR of fake runtimes.
class BuildCommandTest < Minitest::Test
  def setup
    @dir = Dir.mktmpdir
    @runtimes = File.join(@dir, "runtimes")
    FileUtils.mkdir_p(@runtimes)
    Fledge::Platform.names.each { |name| FakeRuntime.write(@runtimes, Fledge::Platform.find(name)) }
    @app = FakeApp.write(@dir)
  end

  def teardown
    FileUtils.rm_rf(@dir)
  end

  def build(*argv, host: Gem::Platform.new("x86_64-linux"), env: { "FLEDGE_RUNTIME_DIR" => @runtimes }, ruby: RUBY_VERSION)
    out = StringIO.new
    err = StringIO.new
    status = Dir.chdir(@dir) { Fledge::CLI::Build.new(out:, err:, env:, host:, ruby:).call(argv) }
    [out.string, err.string, status]
  end

  # ADR 028, section 3: an app runs on the Ruby minor version that runs
  # fledge build, as Briefcase and PyInstaller package the Python that
  # runs them. The fake runtimes are Ruby 4.0.9.
  def test_a_build_on_another_ruby_minor_than_the_runtimes_fails
    out, err, status = build("hello", ruby: "4.1.0")

    assert_equal [1, ""], [status, out]
    assert_equal "fledge build: You are running Ruby 4.1.0, and Fledge #{Fledge::VERSION}'s runtime for x86_64-linux is Ruby 4.0.9.\n" \
      "fledge build: An app runs on the Ruby you build it with: run fledge build with Ruby 4.0, or use a Fledge release that has a runtime for Ruby 4.1.\n",
      err
    refute_path_exists File.join(@dir, "dist/Hello-x86_64-linux")
  end

  # The runtime carries the newest patch of its Ruby minor, which is
  # Fledge's to move (ADR 028, section 3).
  def test_a_build_on_another_patch_of_the_runtimes_ruby_builds
    out, err, status = build("hello", ruby: "4.0.1")

    assert_equal [0, "", "dist/Hello-x86_64-linux.tar.gz\n"], [status, err, out]
  end

  def test_the_build_is_for_this_computer_and_the_default_out_is_dist
    out, err, status = build("hello", host: Gem::Platform.new("arm64-darwin-25"))

    assert_equal [0, ""], [status, err]
    assert_equal "dist/Hello-arm64-darwin.tar.gz\n", out
    assert_path_exists File.join(@dir, "dist/Hello-arm64-darwin/Hello")
  end

  # Beside each file it prints, the build writes that file's SHA-256 in
  # sha256sum's format, which a package manager's recipe needs, and does
  # not print it (ADR 029, section 4).
  def test_the_archive_gets_a_checksum_file_beside_it_that_is_not_printed
    out, err, status = build("hello")

    archive = File.join(@dir, "dist/Hello-x86_64-linux.tar.gz")
    assert_equal [0, "", "dist/Hello-x86_64-linux.tar.gz\n"], [status, err, out]
    assert_equal "#{Digest::SHA256.file(archive).hexdigest}  Hello-x86_64-linux.tar.gz\n",
      File.binread("#{archive}.sha256")
  end

  def test_the_checksum_file_checks_with_sha256sum
    tool = %w[sha256sum shasum].find { |name| system(name, "--version", out: File::NULL, err: File::NULL) }
    skip "neither sha256sum nor shasum is on this computer" unless tool

    build("hello")

    arguments = (tool == "shasum") ? ["shasum", "-a", "256", "-c"] : ["sha256sum", "-c"]
    assert system(*arguments, "Hello-x86_64-linux.tar.gz.sha256", chdir: File.join(@dir, "dist"), out: File::NULL)
  end

  def test_on_another_computer_the_build_is_for_that_computer
    out, err, status = build("hello", host: Gem::Platform.new("aarch64-linux"))

    assert_equal [0, "", "dist/Hello-aarch64-linux.tar.gz\n"], [status, err, out]
  end

  def test_out_and_path_take_their_equals_and_double_dash_forms
    out, _, status = build("--out=elsewhere", "--", "hello")

    assert_equal 0, status
    assert_equal "elsewhere/Hello-x86_64-linux.tar.gz\n", out
  end

  # ADR 016: --sign names the identity a desktop build signs with.
  def test_sign_takes_an_identity_in_either_form
    assert_equal "Developer ID Application: Example", Fledge::CLI::Build::Options.parse(["--sign", "Developer ID Application: Example", "hello"]).sign
    assert_equal "-", Fledge::CLI::Build::Options.parse(%w[--sign=- hello]).sign
    assert_nil Fledge::CLI::Build::Options.parse(%w[hello]).sign
  end

  # Linux apps carry no signature for their system to check.
  def test_a_linux_build_with_an_identity_fails
    out, err, status = build("--sign", "me", "hello")

    assert_equal [1, ""], [status, out]
    assert_includes err, "fledge build: --sign signs apps for macOS and Windows"
  end

  # ADR 033: --sign-command names the developer's own signing command, and
  # --notarize the keychain profile notarytool reads; neither is in
  # fledge.yml, which other people build too.
  def test_sign_command_and_notarize_take_their_values_in_either_form
    options = Fledge::CLI::Build::Options.parse(["--sign-command", "signtool sign /a %1", "hello"])
    assert_equal ["signtool sign /a %1", nil], [options.sign_command, options.notarize]
    options = Fledge::CLI::Build::Options.parse(["--sign=Developer ID Application: Example", "--notarize=fledge", "hello"])
    assert_equal ["Developer ID Application: Example", "fledge"], [options.sign, options.notarize]
    assert_equal "a=b %1", Fledge::CLI::Build::Options.parse(["--sign-command=a=b %1"]).sign_command
  end

  # A command that signs runs only for Windows, and notarization is
  # Apple's, for macOS; Apple notarizes no ad hoc signature.
  def test_signing_a_build_for_the_wrong_system_fails
    windows = Gem::Platform.new("x64-mingw-ucrt")
    mac = Gem::Platform.new("arm64-darwin-25")
    {
      [%w[--sign-command sign.cmd hello], Gem::Platform.new("x86_64-linux")] => "fledge build: --sign-command signs Windows apps; " \
        "on macOS sign with --sign IDENTITY, and a Linux app carries no signature for its system to check\n",
      [%w[--sign-command sign.cmd hello], mac] => "fledge build: --sign-command signs Windows apps; " \
        "on macOS sign with --sign IDENTITY, and a Linux app carries no signature for its system to check\n",
      [%w[--sign 0123456789ABCDEF0123456789ABCDEF01234567 --notarize me hello], windows] =>
        "fledge build: --notarize has Apple notarize a macOS app; build it on a Mac, or build this one without --notarize\n",
      [%w[--sign - --notarize me hello], mac] => "fledge build: --notarize needs a Developer ID Application identity in --sign; " \
        "Apple does not notarize an ad hoc signature (-)\n",
    }.each do |(argv, host), message|
      out, err, status = build(*argv, host:)

      assert_equal [1, "", message], [status, out, err], argv.inspect
    end
  end

  # FLEDGE_SIGN_COMMAND is a Windows build's default for --sign-command:
  # a build for any other system, which it could not sign, ignores it.
  def test_the_signing_command_in_the_environment_is_only_windows
    out, err, status = build("hello", env: { "FLEDGE_RUNTIME_DIR" => @runtimes, "FLEDGE_SIGN_COMMAND" => "false %1" })

    assert_equal [0, "dist/Hello-x86_64-linux.tar.gz\n", ""], [status, out, err]
  end

  def test_the_path_defaults_to_the_current_directory
    out = StringIO.new
    status = Dir.chdir(@app) do
      Fledge::CLI::Build.new(out:, err: StringIO.new, env: { "FLEDGE_RUNTIME_DIR" => @runtimes },
        host: Gem::Platform.new("x86_64-linux")).call(["-o", "../dist"])
    end

    assert_equal 0, status
    assert_equal "../dist/Hello-x86_64-linux.tar.gz\n", out.string
  end

  # A phone's name, first, asks for its project, as Briefcase's create iOS
  # and Flutter's build ios do (ADR 012); after the PATH, or after --, it
  # is a path, and ./ios names a folder called ios.
  def test_a_phone_named_first_asks_for_its_project
    {
      %w[ios] => [".", "ios"],
      %w[android -o out hello] => ["hello", "android"],
      %w[-o out ios hello] => ["hello", "ios"],
      %w[./ios] => ["./ios", nil],
      %w[-- ios] => ["ios", nil],
      %w[ios -- android] => ["android", "ios"],
    }.each do |argv, (path, phone)|
      options = Fledge::CLI::Build::Options.parse(argv)
      assert_equal [path, phone], [options.path, options.phone], argv.inspect
    end
    error = assert_raises(Fledge::UsageError) { Fledge::CLI::Build::Options.parse(%w[hello ios]) }
    assert_equal "takes one PATH, but got 'hello' and 'ios'", error.message
  end

  # Usage errors are the command line's to report, with the usage and
  # exit status 2 (Fledge::CLI), so the command raises them.
  def test_usage_mistakes_raise_a_usage_error
    {
      %w[-t x86_64-linux hello] => "-t is gone: a build is for this computer. Build each platform's app on that platform.",
      %w[--target=x64-mingw-ucrt hello] => "--target is gone: a build is for this computer. Build each platform's app on that platform.",
      %w[--out] => "--out needs a DIR",
      %w[--out=] => "--out needs a DIR",
      %w[--frobnicate hello] => "unrecognized option '--frobnicate'",
      %w[hello other] => "takes one PATH, but got 'hello' and 'other'",
      %w[--sign] => "--sign needs an IDENTITY",
      %w[--sign=] => "--sign needs an IDENTITY",
      %w[ios --sign me] => "--sign signs desktop apps; sign a phone's app with Xcode or Gradle",
      %w[ios --sign-command sign.cmd] => "--sign-command signs desktop apps; sign a phone's app with Xcode or Gradle",
      %w[--sign-command] => "--sign-command needs a COMMAND",
      %w[--sign-command=] => "--sign-command needs a COMMAND",
      %w[--notarize] => "--notarize needs a PROFILE",
      %w[--sign me --sign-command sign.cmd hello] => "--sign and --sign-command each sign the app; give one of them",
      %w[--notarize me hello] => "--notarize needs --sign IDENTITY, the Developer ID Application identity Apple notarizes",
      %w[--sign-command sign.cmd --notarize me hello] => "--notarize needs --sign IDENTITY, the Developer ID Application identity Apple notarizes",
    }.each do |argv, message|
      error = assert_raises(Fledge::UsageError, argv.inspect) { build(*argv) }
      assert_equal message, error.message, argv.inspect
    end
  end

  def test_build_failures_print_one_line_and_exit_one
    {
      %w[nowhere] => "fledge build: nowhere does not exist. Build the program you run, such as exe/my_app or main.rb.\n",
      %w[-o hello hello] => "fledge build: --out can't be the app's own folder, hello\n",
    }.each do |argv, message|
      out, err, status = build(*argv)

      assert_equal [1, "", message], [status, out, err], argv.inspect
    end
  end

  def test_a_computer_with_no_runtime_cannot_build
    _, err, status = build("hello", host: Gem::Platform.new("x86_64-darwin-23"))

    assert_equal 1, status
    assert_equal "fledge build: Fledge has no runtime for this computer's platform (x86_64-darwin-23). " \
      "Build on one it has: arm64-darwin, x86_64-linux, aarch64-linux, x86_64-linux-musl, aarch64-linux-musl, x64-mingw-ucrt, aarch64-mingw-ucrt.\n", err
  end

  def test_a_missing_runtime_is_an_error
    FileUtils.rm_f(File.join(@runtimes, Fledge::Runtimes.file_name(Fledge::Platform.find("aarch64-linux"))))

    _, err, status = build("hello", host: Gem::Platform.new("aarch64-linux"))

    assert_equal 1, status
    assert_equal "fledge build: FLEDGE_RUNTIME_DIR is #{@runtimes}, which has no " \
      "fledge-runtime-#{Fledge::VERSION}-aarch64-linux.tar.gz\n", err
  end

  # A windowed app's installer (ADR 009) is printed after its archive.
  def test_a_windowed_apps_installer_follows_its_archive
    skip "an AppImage is built on Linux, with mksquashfs" unless RUBY_PLATFORM.include?("linux") && system("mksquashfs", "-version", out: File::NULL)
    linux = Fledge::Platform.find("x86_64-linux")
    FakeRuntime.write(@runtimes, linux, extra: [Fledge::Entry.file("tools/appimage-runtime", "\x7FELF", mode: 0o755)])
    File.write(File.join(@app, "fledge.yml"), "name: Hello Window\nkind: windowed\nidentifier: com.example.HelloWindow\n")

    out, err, status = build("hello")

    assert_equal [0, ""], [status, err]
    assert_equal "dist/Hello Window-x86_64-linux.tar.gz\ndist/Hello Window-x86_64-linux.AppImage\n", out
    image = File.join(@dir, "dist/Hello Window-x86_64-linux.AppImage")
    assert_equal "#{Digest::SHA256.file(image).hexdigest}  Hello Window-x86_64-linux.AppImage\n", File.binread("#{image}.sha256")
  end

  def test_the_callers_arguments_are_left_unchanged
    argv = %w[-o dist hello].freeze

    Dir.chdir(@dir) do
      Fledge::CLI::Build.new(out: StringIO.new, err: StringIO.new, env: { "FLEDGE_RUNTIME_DIR" => @runtimes }).call(argv)
    end

    assert_equal %w[-o dist hello], argv
  end
end
