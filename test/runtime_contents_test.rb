# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "test_helper"

class RuntimeContentsTest < Minitest::Test
  def test_reads_the_gem_folder_its_gems_and_its_ruby
    Dir.mktmpdir do |dir|
      {
        "x86_64-linux" => "lib/ruby/gems/4.1.0+5",
        "x64-mingw-ucrt" => "ruby/lib/ruby/gems/4.1.0+5",
      }.each do |name, gem_dir|
        contents = Fledge::RuntimeContents.read(FakeRuntime.write(dir, Fledge::Platform.find(name)))

        assert_equal [gem_dir, %w[csv-3.3.5 json-2.18.0 rdoc-7.0.4], "4.1.0"], [contents.gem_dir, contents.gems, contents.ruby_version]
        assert_equal FakeRuntime::ARCH.fetch(name), contents.arch
        assert_equal ["#{gem_dir}/plugins/rdoc_plugin.rb"], contents.plugins
      end
    end
  end

  # A gem's compiled file may need a library the runtime ships, such as
  # Ruby's DLL on Windows or libxcrypt on Linux.
  def test_reads_the_file_names_of_the_shared_libraries_it_ships
    Dir.mktmpdir do |dir|
      extra = [
        Fledge::Entry.file("ruby/bin/x64-ucrt-ruby400.dll", "MZ"),
        Fledge::Entry.file("ruby/bin/ruby_builtin_dlls/libgmp-10.dll", "MZ"),
        Fledge::Entry.file("ruby/bin/ruby.exe", "MZ"),
]
      windows = Fledge::RuntimeContents.read(FakeRuntime.write(dir, Fledge::Platform.find("x64-mingw-ucrt"), extra:))
      linux = Fledge::RuntimeContents.read(FakeRuntime.write(dir, Fledge::Platform.find("x86_64-linux"),
        extra: [Fledge::Entry.file("lib/libcrypt.so.2", "ELF"), Fledge::Entry.file("lib/libfoo.dylib", "")]))

      assert_equal %w[libgmp-10.dll x64-ucrt-ruby400.dll], windows.libraries
      assert_equal %w[libcrypt.so.2 libfoo.dylib], linux.libraries
    end
  end

  # RubyGems keeps a gem's compiled extensions in a folder named for the
  # Ruby's ABI, with -static for a Ruby without a shared library, as the
  # iOS runtime's is (Gem.extension_api_version).
  def test_reads_the_folder_name_rubygems_gives_a_gems_extensions
    Dir.mktmpdir do |dir|
      rbconfig = "CONFIG[\"MAJOR\"] = \"4\"\nCONFIG[\"MINOR\"] = \"1\"\nCONFIG[\"TEENY\"] = \"0\"\nCONFIG[\"arch\"] = \"x86_64-linux-android\"\n"
      apis = %w[yes no].to_h do |shared|
        archive = File.join(dir, "#{shared}.tar.gz")
        FakeRuntime.pack(archive, "top", [
          Fledge::Entry.file("lib/ruby/gems/4.1.0+5/specifications/a-1.gemspec", ""),
          Fledge::Entry.file("lib/ruby/4.1.0+5/x86_64-linux-android/rbconfig.rb", "#{rbconfig}CONFIG[\"ENABLE_SHARED\"] = \"#{shared}\"\n"),
        ])
        [shared, Fledge::RuntimeContents.read(archive).extension_api]
      end

      assert_equal({ "yes" => "4.1.0+5", "no" => "4.1.0+5-static" }, apis)
    end
  end

  def test_an_archive_that_is_not_a_runtime_is_refused
    Dir.mktmpdir do |dir|
      bare = File.join(dir, "bare.tar.gz")
      FakeRuntime.pack(bare, "top", [Fledge::Entry.file("lib/ruby/gems/4.0.0/specifications/a-1.gemspec", "")])
      error = assert_raises(Fledge::Error) { Fledge::RuntimeContents.read(bare) }
      assert_equal "#{bare} is not a Fledge runtime: it holds no rbconfig.rb", error.message

      archless = File.join(dir, "archless.tar.gz")
      FakeRuntime.pack(archless, "top", [
        Fledge::Entry.file("lib/ruby/gems/4.0.0/specifications/a-1.gemspec", ""),
        Fledge::Entry.file("lib/ruby/4.0.0/x/rbconfig.rb", "CONFIG[\"MAJOR\"] = \"4\"\nCONFIG[\"MINOR\"] = \"0\"\nCONFIG[\"TEENY\"] = \"9\"\n"),
      ])
      error = assert_raises(Fledge::Error) { Fledge::RuntimeContents.read(archless) }
      assert_equal "#{archless} is not a Fledge runtime: its rbconfig.rb names no arch", error.message

      empty = File.join(dir, "empty.tar.gz")
      FakeRuntime.pack(empty, "top", [])
      error = assert_raises(Fledge::Error) { Fledge::RuntimeContents.read(empty) }
      assert_equal "#{empty} is not a Fledge runtime: it holds no one gem folder ()", error.message
    end
  end

  def test_reads_one_slice_of_an_ios_runtime
    Dir.mktmpdir do |dir|
      runtime = FakeRuntime.write_mobile(dir, Fledge::MobilePlatform.find("ios"))

      contents = Fledge::RuntimeContents.read(runtime, under: "FledgeRuby.xcframework/ios-arm64/")

      assert_equal ["lib/ruby/gems/4.1.0+5", ["csv-3.3.5", "json-2.18.0", "rdoc-7.0.4"], "4.1.0", "arm64-darwin"],
        [contents.gem_dir, contents.gems, contents.ruby_version, contents.arch]
      error = assert_raises(Fledge::Error) { Fledge::RuntimeContents.read(runtime) }
      assert_match(/holds no one gem folder/, error.message, "two slices are two Rubies")
    end
  end

  # RubyGems and Bundler compare a gem's required_ruby_version and a
  # Gemfile's ruby with Gem.ruby_version, which for a preview or a
  # development build of Ruby (PATCHLEVEL -1) adds the name
  # RUBY_DESCRIPTION gives it after RUBY_VERSION. rbconfig.rb records no
  # such name, so the runtime's RUBY_DESCRIPTION file, written when the
  # runtime is built, gives it, beside the Ruby of an iOS slice too.
  def test_a_preview_or_development_rubys_version_is_the_one_rubygems_reports
    Dir.mktmpdir do |dir|
      read = lambda do |patchlevel, description, under: ""|
        rbconfig = "CONFIG[\"MAJOR\"] = \"4\"\nCONFIG[\"MINOR\"] = \"1\"\nCONFIG[\"TEENY\"] = \"0\"\n" \
          "CONFIG[\"PATCHLEVEL\"] = \"#{patchlevel}\"\nCONFIG[\"arch\"] = \"x86_64-linux\"\n"
        entries = [
          Fledge::Entry.file("#{under}lib/ruby/gems/4.1.0+5/specifications/a-1.gemspec", ""),
          Fledge::Entry.file("#{under}lib/ruby/4.1.0+5/x86_64-linux/rbconfig.rb", rbconfig),
          *(description ? [Fledge::Entry.file("RUBY_DESCRIPTION", "#{description}\n")] : []),
        ]
        path = File.join(dir, "runtime-#{entries.hash}.tar.gz")
        Fledge::RuntimeContents.read(FakeRuntime.pack(path, "top", entries), under:)
      end

      assert_equal "4.1.0.preview1", read.call("-1", "ruby 4.1.0preview1 (2026-10-11 master 2d08b5f42f)").ruby_version
      assert_equal "4.1.0.dev", read.call("-1", "ruby 4.1.0dev (2026-11-10 master 0e25874222)").ruby_version
      assert_equal "4.1.0.preview1",
        read.call("-1", "ruby 4.1.0preview1 (2026-10-11 master 2d08b5f42f)", under: "FledgeRuby.xcframework/ios-arm64/").ruby_version
      release = read.call("0", "ruby 4.1.0p0 (2026-12-25 revision 0123456789)")
      assert_equal "4.1.0", release.ruby_version, "a release's version is RUBY_VERSION"
      assert_equal "4.1.0", read.call("-1", nil).ruby_version, "a runtime that records no description"
      assert_equal ["0", "-1"], [release.patchlevel, read.call("-1", nil).patchlevel], "RUBY_PATCHLEVEL, which Bundler compares too"
    end
  end
end
