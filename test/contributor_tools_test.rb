# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "test_helper"
require "open3"
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

  # The Rust a contributor's mise installs is the release CI's desktop
  # jobs install, with the standard library of every phone target, which
  # a Rust gem's extension is compiled for (MobileExtensions::Rust).
  def test_mise_installs_cis_rust_with_every_phone_target
    rust = YAML.safe_load_file(File.join(ROOT, ".github", "workflows", "ci.yml"), aliases: true).fetch("env").fetch("RUST_TOOLCHAIN")
    line = mise_toml.lines.find { |candidate| candidate.start_with?("rust = ") } or flunk "mise.toml installs no Rust"

    assert_includes line, %(version = "#{rust}")
    assert_includes line, %(targets = "#{Fledge::MobileExtensions::Rust::TRIPLES.values.join(',')}")
  end

  # CI's Windows jobs read the pin from mise.toml with this script.
  def test_ruby_pin_reads_the_pin_and_takes_head_on_windows_for_a_preview
    script = File.join(ROOT, ".github", "scripts", "ruby-pin.sh")
    { "Linux" => ruby_pins.fetch("version"), "Windows" => "head" }.each do |os, expected|
      out, status = Open3.capture2({ "RUNNER_OS" => os }, "sh", script, chdir: ROOT)

      assert status.success?, "ruby-pin.sh failed on #{os}"
      assert_equal "#{expected}\n", out
    end
  end
end
