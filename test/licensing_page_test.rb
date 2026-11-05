# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "test_helper"
require_relative "support/binaries"
require_relative "../tasks/licensing_page"

# The licensing page from runtime archives for all nine platforms, small
# but made of real (minimal) ELF, Mach-O, and PE files, which the real
# license audit checks against the real runtime/licenses.yml. CI runs
# the page against the nine real runtimes and fails when doc/licensing.md
# differs.
class LicensingPageTest < Minitest::Test
  RUST = "/rustc/4eb161250e340c8f48f66e2b929ef4a5bed7c181/"

  def runtime(directory, platform, files)
    top = "fledge-runtime-0.0.0-#{platform}"
    FakeRuntime.pack(File.join(directory, "#{top}.tar.gz"), top, files.map { |path, bytes| Fledge::Entry.file(path, bytes) })
  end

  def gemspec(name, version, licenses)
    Gem::Specification.new do |gem|
      gem.name = name
      gem.version = version
      gem.summary = name
      gem.authors = ["someone"]
      gem.licenses = licenses
    end.to_ruby
  end

  # A macOS or Linux runtime: its launcher, and its bin/ruby, which is
  # Ruby's main.c with Fledge's code compiled in (ADR 026), so the same
  # binary with the string runtime/licenses.yml looks for.
  def unix(binary)
    {
      "launcher" => binary.call(""),
      "bin/ruby" => binary.call(" ruby: could not run "),
      "lib/ruby/4.0.0/rubygems/defaults/operating_system.rb" => "# Fledge's RubyGems defaults for a built app.\n",
      "lib/ruby/4.0.0/set.rb" => "class Set; end\n",
      "libexec/cert.pem" => "-----BEGIN CERTIFICATE-----\n",
      "lib/ruby/gems/4.0.0/specifications/csv-3.3.5.gemspec" => gemspec("csv", "3.3.5", %w[Ruby BSD-2-Clause]),
      "lib/ruby/gems/4.0.0/gems/csv-3.3.5/LICENSE.txt" => "Ruby or BSD-2-Clause\n",
      "lib/ruby/gems/4.0.0/specifications/rake-13.3.1.gemspec" => gemspec("rake", "13.3.1", %w[MIT]),
      "lib/ruby/gems/4.0.0/gems/rake-13.3.1/MIT-LICENSE" => "MIT\n",
    }
  end

  def page
    TestReaders.need(self, :elf, :macho, :pe)
    Dir.mktmpdir do |directory|
      runtime(directory, "arm64-darwin", unix(-> (more) { Binaries.macho(needed: %w[/usr/lib/libSystem.B.dylib], payload: "3e93b23afc #{RUST}#{more}") }))
      %w[x86_64-linux aarch64-linux].each do |platform|
        runtime(directory, platform, unix(-> (more) { Binaries.elf(needed: %w[libcrypt.so.2 libc.so.6], payload: "3e93b23afc #{RUST} GCC: (#{more}") }).merge(
          "lib/libcrypt.so.2" => Binaries.elf(needed: %w[libc.so.6], payload: "XCRYPT_4.4\0yescrypt-ROMhash"),
          "notices/sources/libxcrypt/libxcrypt-4.5.2.tar.xz" => "pretend libxcrypt",
          "notices/sources/libxcrypt/BUILD.txt" => "how it was built\n"
        ))
      end
      %w[x86_64-linux-musl aarch64-linux-musl].each do |platform|
        runtime(directory, platform, unix(lambda do |more|
          Binaries.elf(needed: %w[libc.so], payload: "3e93b23afc /rustc/31fca3adb283cc9dfd56b49cdee9a96eb9c96ffd/ GCC: (Alpine 15.2.0) 15.2.0#{more}")
        end))
      end
      %w[x64-mingw-ucrt aarch64-mingw-ucrt].each do |platform|
        runtime(directory, platform, "launcher.exe" => Binaries.pe(needed: %w[KERNEL32.dll]), "ruby/lib/ruby/4.0.0/set.rb" => "class Set; end\n")
      end
      defaults = "# Fledge's RubyGems defaults for a built app.\n"
      slices = %w[ios-arm64 ios-arm64-simulator].flat_map do |slice|
        [
          ["FledgeRuby.xcframework/#{slice}/lib/ruby/4.0.0/set.rb", "class Set; end\n"],
          ["FledgeRuby.xcframework/#{slice}/lib/ruby/4.0.0/rubygems/defaults/operating_system.rb", defaults],
]
      end.to_h
      runtime(directory, "ios", slices.merge("FledgeRuby.xcframework/Info.plist" => "<plist/>\n"))
      runtime(directory, "android", "include/fledge_ruby.h" => "int fledge_ruby_run_app(void);\n", "lib/ruby/4.0.0/set.rb" => "class Set; end\n",
        "lib/ruby/4.0.0/rubygems/defaults/operating_system.rb" => defaults, "libexec/cert.pem" => "-----BEGIN CERTIFICATE-----\n")
      LicensingPage.new(directory, version: "9.8.7").text
    end
  end

  def section(text, title)
    text[/^## #{Regexp.escape(title)}\n.*?(?=^## )/m].to_s
  end

  def test_each_platform_lists_what_its_runtime_holds_and_what_that_asks
    text = page
    darwin = section(text, "macOS on Apple Silicon (arm64-darwin)")
    linux = section(text, "Linux on x86-64 (x86_64-linux)")

    assert_includes text, "for Fledge 9.8.7, every third-party component"
    assert_includes darwin, "| Fledge launcher and RubyGems defaults | 9.8.7 | `AGPL-3.0-or-later` |"
    assert_includes darwin, "no LGPL library ships on this platform"
    refute_includes darwin, "libxcrypt"
    assert_includes linux, "| libxcrypt, which backs String#crypt | 4.5.2 | `LGPL-2.1-or-later` |"
    assert_includes linux, "meet the LGPL for libxcrypt (`lib/libcrypt.so.2`), as"
    assert_includes linux, "| libxcrypt's source code, as its authors released it, and how the runtime's copy was built | 4.5.2 | `LGPL-2.1-or-later` |"
    assert_includes linux, "The source is in every app, in `notices/sources/`, and in Fledge's release as " \
      "`fledge-runtime-9.8.7-x86_64-linux-lgpl-sources.tar.gz`."
    refute_includes linux, "LGPL for libxcrypt's source"
    assert_includes linux, "- `MIT`: rake"
    assert_includes linux, "- `Ruby OR BSD-2-Clause`: csv"
    refute_empty section(text, "Windows on x64 (x64-mingw-ucrt)")
    android = section(text, "Android (aarch64-linux-android, x86_64-linux-android)")
    assert_includes android, "| Fledge's embedding API, and the library and packages it is built into | 9.8.7 | `AGPL-3.0-or-later` |"
    assert_includes android, "no LGPL library ships on this platform"
    refute_empty section(text, "iOS and iPadOS (arm64-ios, arm64-ios-simulator)")
  end

  # bin/ruby on macOS and Linux carries Fledge's AGPL code (ADR 026), so
  # the page counts it among Fledge's files, which the AGPL asks the
  # source of, and the desktop rows say so.
  def test_it_counts_bin_ruby_among_fledges_own_files
    text = page
    everywhere = section(text, "On every platform").split.join(" ")

    assert_includes everywhere, "**Fledge's own files** in an app are `launcher`, the program your app's users run, renamed for your app; " \
      "`bin/ruby`, the Ruby that `RbConfig.ruby` names, which is Ruby's `main.c` with Fledge's code compiled in; " \
      "and `lib/ruby/4.0.0/rubygems/defaults/operating_system.rb`."
    assert_includes section(text, "Linux on x86-64 (x86_64-linux)"), "; on macOS and Linux bin/ruby, which holds Fledge's code beside Ruby's;"
  end

  # A phone's app is built from the project fledge build writes (ADR 012),
  # so the page says what of Fledge's goes into it, and that the host app
  # the developer compiles is Fledge's own code too.
  def test_it_says_what_of_fledges_a_phones_app_holds
    phones = section(page, "On iOS and Android")

    assert_includes phones, "Fledge's embedding API, compiled into the runtime's library"
    assert_includes phones, "`Host/main.m` on iOS and `MainActivity.java` on Android"
    assert_includes phones, "the project's `fledge/notices/` goes into the app"
    assert_includes phones, "Gradle wrapper"
  end

  # A phone's app has no Fledge launcher: the host app starts Ruby, so
  # its section names only the RubyGems defaults among Fledge's files.
  def test_a_phones_section_names_no_launcher_the_apps_user_runs
    text = page
    ["iOS and iPadOS (arm64-ios, arm64-ios-simulator)", "Android (aarch64-linux-android, x86_64-linux-android)"].each do |title|
      phone = section(text, title)

      assert_includes phone, "| Fledge's RubyGems defaults |", title
      assert_includes phone, "which RubyGems loads as the app's Ruby starts", title
      refute_includes phone, "the program the app's user runs", title
    end
    assert_includes section(text, "Linux on x86-64 (x86_64-linux)"), "the program the app's user runs"
  end

  # An app's own gems are the developer's choice and responsibility
  # (2026-10-28; ADR 007): the page says Fledge takes no position on
  # them, judges no gem by its license, and writes no notices of its own
  # for them.
  def test_it_says_an_apps_own_gems_are_the_developers_to_comply_with
    gems = section(page, "Your app's own gems")

    assert_includes gems, "Fledge takes no position on the licenses of the gems your app depends on"
    assert_includes gems, "your choice and your responsibility"
    assert_includes gems, "`bundle licenses`"
    refute_includes gems, "`BSD-3-Clause`"
    refute_includes gems, "GEMS.txt"
    refute_includes gems, "fledge.yml"
  end

  def test_it_cites_the_license_sections_and_says_to_ask_a_lawyer
    text = page

    assert_includes text, "ask your own lawyer"
    assert_includes text, "(LGPL-2.1, section 6)"
    assert_includes text, "(4(d)(1))"
    assert_includes text, "a commercial license will likely be offered"
    assert_includes text, "Generated by tasks/licensing_page.rb"
  end

  def test_a_runtime_that_breaks_the_policy_makes_no_page
    TestReaders.need(self, :macho)
    Dir.mktmpdir do |directory|
      runtime(directory, "arm64-darwin", unix(-> (more) { Binaries.macho(needed: %w[/usr/lib/libSystem.B.dylib], payload: "3e93b23afc #{RUST}#{more}") }).merge(
        "stray.txt" => "hello\n"
      ))

      error = assert_raises(RuntimeError) { LicensingPage.new(directory).audit("arm64-darwin") }
      assert_includes error.message, "unaccounted: stray.txt"
    end
  end
end
