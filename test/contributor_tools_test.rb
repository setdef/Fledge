# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "test_helper"
require "yaml"

# The tools mise installs for a contributor from mise.toml (bin/setup).
# Each is pinned by SHA-256, and the Ruby is the one the runtimes come
# from on each platform: runtime/sources.yml's release on macOS and
# Linux, and on Windows the very archive of RubyInstaller's head build
# the Windows runtimes are built from, by the same URL and SHA-256.
class ContributorToolsTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  def mise_toml = File.read(File.join(ROOT, "mise.toml"))
  def sources = YAML.safe_load_file(File.join(ROOT, "runtime", "sources.yml"))
  def ruby_pins = sources.fetch("ruby")

  def test_mise_installs_the_release_of_the_runtimes_on_macos_and_linux_only
    assert_includes mise_toml, %(ruby = { version = "#{ruby_pins.fetch('version')}", os = ["linux", "macos"] }\n)
  end

  # A Ruby mise compiles on a contributor's computer links whatever
  # libraries that computer has, such as Homebrew's gmp, and a program
  # the tests link against it then needs them too. mise only downloads.
  def test_mise_never_compiles_ruby
    assert_match(/^\[settings\]\n(?:.*\n)*?ruby\.compile = false\n/, mise_toml)
  end

  def test_mise_installs_on_windows_the_archive_the_windows_runtimes_are_built_from
    { "windows-x64" => "x64-mingw-ucrt", "windows-arm64" => "aarch64-mingw-ucrt" }.each do |mise, platform|
      pin = ruby_pins.fetch("platforms").fetch(platform)
      line = %(platforms.#{mise} = { url = "#{pin.fetch('url')}", checksum = "sha256:#{pin.fetch('sha256')}" }\n)

      assert_includes mise_toml, line
    end
    day = ruby_pins.dig("platforms", "x64-mingw-ucrt", "url")[/inputs-rubyinstaller-head-(\d{8})/, 1]

    assert_includes mise_toml, %([tools."http:rubyinstaller-head"]\nversion = "#{day}"\nos = ["windows"]\n)
  end

  # The DLLs the head build needs and does not ship come from the MSYS2
  # packages a Windows runtime takes them from, in the folder each pin
  # names, which RUBY_DLL_PATH names too.
  def test_mise_installs_on_windows_the_packages_of_the_dlls_the_runtimes_add
    { "libz-1.dll" => "msys2-zlib", "libgcc_s_seh-1.dll" => "msys2-libgcc" }.each do |dll, tool|
      sources.fetch("windows-dlls").fetch(dll).fetch("platforms").each do |platform, pin|
        mise = { "x64-mingw-ucrt" => "windows-x64", "aarch64-mingw-ucrt" => "windows-arm64" }.fetch(platform)
        package = pin.fetch("package")
        folder = File.dirname(pin.fetch("path"))
        line = %(platforms.#{mise} = { url = "#{package.fetch('url')}", checksum = "sha256:#{package.fetch('sha256')}", bin_path = "#{folder}" }\n)

        assert_includes mise_toml, line, "#{tool} on #{platform}"
      end
    end
  end

  # Every file mise.toml names by URL, patchelf's among them, is pinned
  # by SHA-256 (AGENTS.md).
  def test_every_download_mise_toml_names_is_pinned_by_sha256
    downloads = mise_toml.lines.grep(/\burl = "/)

    refute_empty downloads
    downloads.each { |line| assert_match(/checksum = "sha256:\h{64}"/, line) }
  end

  # bindgen, which rb-sys runs for a Rust gem such as native_app's
  # ferro-idna, needs libclang, and a stock Linux computer has none. mise
  # installs LLVM's there, from PyPI's libclang wheels, each by its
  # SHA-256.
  def test_mise_installs_libclang_for_bindgen_on_linux
    wheels = mise_toml.lines.grep(%r{\Aplatforms\.\S+ = \{ url = "[^"]*/libclang-18\.1\.1-[^"]*\.whl"})

    assert_equal %w[linux-arm64 linux-x64], wheels.map { |l| l[/platforms\.(\S+)/, 1] }.sort
    wheels.each { |line| assert_match(/checksum = "sha256:\h{64}", format = "zip" \}/, line) }
    assert_includes mise_toml, %([tools."http:libclang"]\nversion = "18.1.1"\nos = ["linux"]\n)
  end

  # LIBCLANG_PATH names the wheel's folder only where the wheel is
  # installed, through a file mise reads only there; elsewhere neither it
  # nor LIBRARY_PATH is set at all, since an empty one would hide the
  # computer's own libclang, or put the current folder in GCC's search for
  # libraries.
  def test_libclang_path_names_the_wheel_only_where_it_is_installed
    wheel = %({% if tools["http:libclang"] is defined %})

    assert_includes mise_toml, %(FLEDGE_LIBCLANG = { value = '#{wheel}{{ tools["http:libclang"].path }}/libclang-18.1.1.data/platlib/clang/native{% endif %}', tools = true }\n)
    assert_includes mise_toml, %({ path = '.config/mise/#{wheel}libclang{% else %}none{% endif %}.env', tools = true, expand = true },\n)
    assert_match(/^LIBCLANG_PATH=\$\{FLEDGE_LIBCLANG\}$/, File.read(File.join(ROOT, ".config", "mise", "libclang.env")))
    refute_path_exists File.join(ROOT, ".config", "mise", "none.env")
    refute_match(/^(LIBCLANG_PATH|LIBRARY_PATH) =/, mise_toml)
  end

  # The wheel has no compiler headers of its own, so the C compiler's are
  # searched after every other where it is installed, and a missing
  # compiler leaves the variable as it was rather than failing every mise
  # command.
  def test_bindgen_gets_the_c_compilers_headers_where_the_wheel_is_installed
    lines = mise_toml.lines.grep(/\ABINDGEN_EXTRA_CLANG_ARGS = /)
    line = lines.first

    assert_equal 1, lines.size
    assert_includes line, %({% if tools["http:libclang"] is defined %}{% set include = exec(command="cc -print-file-name=include 2>/dev/null || true") %}{% if include %}-idirafter {{ include }} {% endif %}{% endif %})
    assert_includes line, %({{ get_env(name="BINDGEN_EXTRA_CLANG_ARGS", default="") }}', tools = true }\n)
  end

  def android_toml = File.read(File.join(ROOT, "mise.android.toml"))

  # The Android tools mise installs with MISE_ENV=android, from Google's
  # and Adoptium's own downloads, are pinned by SHA-256 too (AGENTS.md).
  def test_every_download_mise_android_toml_names_is_pinned_by_sha256
    downloads = android_toml.lines.grep(/\burl = "/)

    refute_empty downloads
    downloads.each { |line| assert_match(/checksum = "sha256:\h{64}"/, line) }
  end

  # fledge build android compiles a gem's extension with the very NDK the
  # Android runtime is built with, as CI's Mobile apps job installs it.
  def test_mise_installs_for_android_the_ndk_the_android_runtime_is_built_with
    pin = sources.dig("mobile", "ndk", "hosts", "x86_64-linux")

    assert_includes android_toml, %(platforms.linux-x64 = { url = "#{pin.fetch('url')}", checksum = "sha256:#{pin.fetch('sha256')}" }\n)
  end

  # bin/android-sdk lays out every Android package mise.android.toml pins
  # as one SDK, and no package it does not pin.
  def test_bin_android_sdk_lays_out_every_android_package_mise_installs
    pinned = android_toml.scan(/^\[tools\."(http:android-(?!ndk)[\w-]+)"\]$/).flatten
    laid_out = File.read(File.join(ROOT, "bin", "android-sdk")).scan(/^link (http:android-[\w-]+) /).flatten

    refute_empty pinned
    assert_equal pinned.sort, laid_out.sort
  end

  # The Rust a contributor's mise installs is the release CI's desktop
  # jobs install, with the standard library of every phone target, which
  # a Rust gem's extension is compiled for (MobileExtensions::Rust).
  def test_mise_installs_cis_rust_with_every_phone_target
    rust = YAML.safe_load_file(File.join(ROOT, ".github", "workflows", "ci.yml"), aliases: true).fetch("env").fetch("RUST_TOOLCHAIN")
    line = mise_toml.lines.find { |candidate| candidate.start_with?("rust = ") } or flunk "mise.toml installs no Rust"

    assert_includes line, %(version = "#{rust}")
    assert_includes line, %(targets = "#{Fledge::MobileExtensions::Rust::TRIPLES.values.join(',')}")
  end

  # XcodeGen writes the Xcode project fledge build ios makes, which the
  # iOS integration tests build. On a Mac, Apple silicon or Intel, mise
  # installs the release CI installs, by runtime/sources.yml's URL and
  # SHA-256, and puts the bin/ folder of its archive on PATH.
  def test_mise_installs_on_macos_the_xcodegen_ci_installs
    pin = sources.dig("mobile", "xcodegen")

    assert_includes mise_toml, %([tools."http:xcodegen"]\nversion = "#{pin.fetch('version')}"\nos = ["macos"]\n)
    %w[macos-arm64 macos-x64].each do |platform|
      line = %(platforms.#{platform} = { url = "#{pin.fetch('url')}", checksum = "sha256:#{pin.fetch('sha256')}", bin_path = "xcodegen/bin" }\n)

      assert_includes mise_toml, line
    end
  end

  # CI's Windows jobs read the pin from mise.toml with this script.
  # mise.toml's min_version names the oldest mise that reads it, the one
  # whose mise install and mise exec trust it on a computer that has
  # never run mise in this folder. Every mise CI pins satisfies it, or
  # CI would refuse the file a contributor is told to use.
  def test_every_mise_ci_pins_is_at_least_the_one_mise_toml_asks_for
    minimum = mise_toml[/^min_version = "([\d.]+)"$/, 1]
    refute_nil minimum, "mise.toml names no min_version"
    pins = Dir[File.join(ROOT, ".github", "workflows", "*.yml")].flat_map do |workflow|
      File.read(workflow).scan(%r{jdx/mise-action@.*\n(?:(?!\s*- ).*\n){0,6}?\s+version: ([\d.]+)$}).flatten
    end
    refute_empty pins
    pins.each { |pin| assert_operator Gem::Version.new(pin), :>=, Gem::Version.new(minimum) }
  end
end
