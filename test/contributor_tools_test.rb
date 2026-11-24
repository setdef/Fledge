# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "test_helper"
require "yaml"

# The tools mise installs for a contributor from mise.toml (tasks/setup.rb).
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
  # by SHA-256 (doc/contributors/design/architecture.md, "What the design
  # answers to").
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

  def rust_toml = File.read(File.join(ROOT, "mise.rust.toml"))

  # On x64 Windows, where neither the wheel nor the C compiler's headers
  # serve, mise installs LLVM's own release, which carries libclang with
  # clang's headers, as CI's Windows runners have it, by its SHA-256; but
  # only with MISE_ENV=rust, since it is 4 GB unpacked, and every download
  # that file names is pinned so too (architecture.md, same section).
  def test_mise_installs_llvm_for_bindgen_on_x64_windows_with_mise_env_rust
    downloads = rust_toml.lines.grep(/\burl = "/)

    assert_equal 1, downloads.size
    assert_match(%r{\Aplatforms\.windows-x64 = \{ url = "https://github\.com/llvm/llvm-project/releases/download/llvmorg-23\.1\.6/clang%2Bllvm-23\.1\.6-x86_64-pc-windows-msvc\.tar\.zst", checksum = "sha256:\h{64}", strip_components = 1 \}\n\z}, downloads.first)
    assert_includes rust_toml, %([tools."http:llvm"]\nversion = "23.1.6"\nos = ["windows/x64"]\n)
    refute_includes mise_toml, %([tools."http:llvm"])
  end

  # LIBCLANG_PATH names the folder of the wheel's libclang, or of LLVM's,
  # only where one is installed, through a file mise reads only there;
  # elsewhere neither it nor LIBRARY_PATH is set at all, since an empty
  # one would hide the computer's own libclang, or put the current folder
  # in GCC's search for libraries. bindgen splits the variable's words as
  # a shell would, so LLVM's Windows path has forward slashes.
  def test_libclang_path_names_the_wheel_or_llvm_only_where_one_is_installed
    wheel = %({% if tools["http:libclang"] is defined %})
    either = %({% if tools["http:libclang"] is defined or tools["http:llvm"] is defined %})
    llvm = %({% elif tools["http:llvm"] is defined %}{{ tools["http:llvm"].path | replace(from="\\\\", to="/") }}/bin)

    assert_includes mise_toml, %(FLEDGE_LIBCLANG = { value = '#{wheel}{{ tools["http:libclang"].path }}/libclang-18.1.1.data/platlib/clang/native#{llvm}{% endif %}', tools = true }\n)
    assert_includes mise_toml, %({ path = '.config/mise/#{either}libclang{% else %}none{% endif %}.env', tools = true, expand = true },\n)
    assert_match(/^LIBCLANG_PATH=\$\{FLEDGE_LIBCLANG\}$/, File.read(File.join(ROOT, ".config", "mise", "libclang.env")))
    refute_path_exists File.join(ROOT, ".config", "mise", "none.env")
    refute_match(/^(LIBCLANG_PATH|LIBRARY_PATH) =/, mise_toml)
  end

  # The wheel has no compiler headers of its own, so the C compiler's are
  # searched after every other where it is installed, and a missing
  # compiler leaves the variable as it was rather than failing every mise
  # command. Where LLVM is installed, on Windows, clang is pointed at
  # MinGW and the MSYS2 that mise installs, with CI's Build job's very
  # arguments, so that a contributor's bindgen reads Ruby's headers as
  # CI's does.
  def test_bindgen_gets_the_c_compilers_headers_where_the_wheel_is_installed
    lines = mise_toml.lines.grep(/\ABINDGEN_EXTRA_CLANG_ARGS = /)
    line = lines.first
    ci = File.read(File.join(ROOT, ".github", "workflows", "ci.yml"))[/echo "BINDGEN_EXTRA_CLANG_ARGS=(.*)"$/, 1]

    assert_equal 1, lines.size
    assert_includes line, %({% if tools["http:libclang"] is defined %}{% set include = exec(command="cc -print-file-name=include 2>/dev/null || true") %}{% if include %}-idirafter {{ include }} {% endif %})
    windows = %(--target=x86_64-pc-windows-gnu --sysroot={{ tools["http:msys2"].path | replace(from="\\\\", to="/") }}/ucrt64 -D__AVX512VLFP16INTRIN_H -D__AVX512FP16INTRIN_H)
    assert_includes line, %({% elif tools["http:llvm"] is defined %}#{windows} {% endif %})
    assert_equal(ci.sub("$sysroot") { %({{ tools["http:msys2"].path | replace(from="\\\\", to="/") }}/ucrt64) }, windows)
    assert_includes line, %({{ get_env(name="BINDGEN_EXTRA_CLANG_ARGS", default="") }}', tools = true }\n)
  end

  def android_toml = File.read(File.join(ROOT, "mise.android.toml"))

  # The Android tools mise installs with MISE_ENV=android, from Google's
  # and Adoptium's own downloads, are pinned by SHA-256 too (architecture.md, same section).
  def test_every_download_mise_android_toml_names_is_pinned_by_sha256
    downloads = android_toml.lines.grep(/\burl = "/)

    refute_empty downloads
    downloads.each { |line| assert_match(/checksum = "sha256:\h{64}"/, line) }
  end

  # tasks/setup.rb runs mise install, naming no tool, so that with
  # MISE_ENV=android on x86-64 Linux it installs every tool this file
  # pins (ten, when the issue 14 run installed them from nothing on
  # 2026-11-23): each is for linux/x64 alone and has its download for
  # it, so no tool is skipped there, and none is installed elsewhere.
  def test_every_tool_mise_android_toml_pins_installs_on_x86_64_linux_and_only_there
    sections = android_toml.split(/^(?=\[tools\.")/).drop(1)

    refute_empty sections
    sections.each do |section|
      name = section[/\A\[tools\."([^"]+)"\]/, 1]

      assert_includes section, %(os = ["linux/x64"]), "#{name} would install beyond x86-64 Linux"
      assert_match(%r{^platforms\.linux-x64 = \{ url = "https://}, section, "#{name} has no download for x86-64 Linux")
    end
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
  # a Rust gem's extension is compiled for (MobileExtensions::Rust). On
  # x64 Windows, under MISE_ENV=rust, it is the same release for Rust's
  # GNU host, as CI's Windows Build job asks for it, with RubyInstaller's
  # MinGW Ruby; mise.rust.toml's Rust replaces mise.toml's, so it begins
  # with mise.toml's entry, unchanged.
  def test_mise_installs_cis_rust_with_every_phone_target
    ci = YAML.safe_load_file(File.join(ROOT, ".github", "workflows", "ci.yml"), aliases: true)
    rust = ci.fetch("env").fetch("RUST_TOOLCHAIN")
    windows = ci.dig("jobs", "build-x64-mingw-ucrt", "strategy", "matrix", "include", 0, "rust")
    desktop = mise_toml[/^rust = (\{.*\})\n/, 1] or flunk "mise.toml installs no Rust"
    entries = rust_toml[/^rust = \[\n(.*?)^\]\n/m, 1] or flunk "mise.rust.toml installs no Rust"

    assert_includes desktop, %(version = "#{rust}")
    assert_includes desktop, %(targets = "#{Fledge::MobileExtensions::Rust::TRIPLES.values.join(',')}")
    assert_includes desktop, %(os = ["linux", "macos"])
    assert_equal [%(  #{desktop},\n), %(  { version = "#{rust}#{windows}", profile = "minimal", os = ["windows/x64"] },\n)], entries.lines
  end

  # mise 2026.10.11, the release CI pins, installs every entry of a tool
  # named on its command line whatever its os, and CI's Linux and macOS
  # jobs run mise install ruby rust. So mise.toml gives each tool one
  # entry, and a second one for another system, Windows's Rust, waits in
  # mise.rust.toml, which no CI job reads.
  def test_mise_toml_gives_each_tool_one_entry
    tools = mise_toml[/^\[tools\]\n(.*?)^\[/m, 1] or flunk "mise.toml has no [tools]"

    refute_match(/^[^#\s][^=]* = \[/, tools)
    Dir[File.join(ROOT, ".github", "workflows", "*.yml")].each { |workflow| refute_includes File.read(workflow), "MISE_ENV: rust" }
  end

  # rustup and cargo ask Windows for the account's profile folder and
  # ignore HOME, so on Windows mise's Rust would install into the one
  # store every workspace of the account shares. mise.toml names a home
  # for each inside mise's own data folder instead, through a file mise
  # reads on Windows only, since neither Linux nor macOS has the problem
  # and an empty RUSTUP_HOME there would break rustup.
  def test_mise_keeps_rustups_and_cargos_homes_in_its_data_folder_on_windows_only
    env = File.read(File.join(ROOT, ".config", "mise", "rust-homes.env"))

    assert_match(%r{^RUSTUP_HOME=\$\{FLEDGE_RUST_HOMES\}/rustup$}, env)
    assert_match(%r{^CARGO_HOME=\$\{FLEDGE_RUST_HOMES\}/cargo$}, env)
    assert_includes mise_toml, %(FLEDGE_RUST_HOMES = { value = '{% if os() == "windows" %}{{ env.MISE_DATA_DIR | default(value=xdg_data_home ~ "/mise") | replace(from="\\\\", to="/") }}{% endif %}' }\n)
    assert_includes mise_toml, %({ path = '.config/mise/{% if os() == "windows" %}rust-homes{% else %}none{% endif %}.env', expand = true },\n)
    refute_path_exists File.join(ROOT, ".config", "mise", "none.env")
    refute_match(/^(RUSTUP_HOME|CARGO_HOME) =/, mise_toml)
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

  # On Ruby 4.1 sqlite3 and nokogiri compile from source, and
  # mini_portile2, which builds their libraries, runs the commands
  # pkg-config and xzcat by those names. A stock Mac has neither, so on
  # a Mac mise installs both from prebuilt archives, each by its SHA-256:
  # pkgconf from PyPI's pkgconf wheel, renamed pkg-config, and xz from
  # pkgx's build.
  def test_mise_installs_on_macos_the_pkg_config_and_xzcat_gems_compile_with
    assert_includes mise_toml, %([tools."http:pkgconf"]\nversion = "3.0.7.post0"\nos = ["macos"]\n)
    assert_includes mise_toml, %([tools."http:xz"]\nversion = "5.8.4"\nos = ["macos"]\n)
    %w[macos-arm64 macos-x64].each do |platform|
      pkgconf = mise_toml[/^platforms\.#{platform} = \{ url = "[^"]*pkgconf-3\.0\.7\.post0-py3-none-macosx_[^"]*\.whl".*$/]
      xz = mise_toml[%r{^platforms\.#{platform} = \{ url = "https://dist\.pkgx\.dev/tukaani\.org/xz/darwin/[^"]*/v5\.8\.4\.tar\.xz".*$}]

      assert_match(%r{, format = "zip", bin_path = "pkgconf/\.bin", rename_exe = "pkg-config" \}\z}, pkgconf.to_s)
      assert_match(%r{, bin_path = "tukaani\.org/xz/v5\.8\.4/bin" \}\z}, xz.to_s)
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
