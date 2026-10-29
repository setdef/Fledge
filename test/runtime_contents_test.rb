# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "test_helper"

class RuntimeContentsTest < Minitest::Test
  def test_reads_the_gem_folder_its_gems_and_its_ruby
    Dir.mktmpdir do |dir|
      {
        "x86_64-linux" => "lib/ruby/gems/4.0.0",
        "x64-mingw-ucrt" => "ruby/lib/ruby/gems/4.0.0",
      }.each do |name, gem_dir|
        contents = Fledge::RuntimeContents.read(FakeRuntime.write(dir, Fledge::Platform.find(name)))

        assert_equal [gem_dir, %w[csv-3.3.5 json-2.18.0], "4.0.9"], [contents.gem_dir, contents.gems, contents.ruby_version]
        assert_equal FakeRuntime::ARCH.fetch(name), contents.arch
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

      assert_equal ["lib/ruby/gems/4.0.0", ["csv-3.3.5", "json-2.18.0"], "4.0.9", "arm64-darwin"],
        [contents.gem_dir, contents.gems, contents.ruby_version, contents.arch]
      error = assert_raises(Fledge::Error) { Fledge::RuntimeContents.read(runtime) }
      assert_match(/holds no one gem folder/, error.message, "two slices are two Rubies")
    end
  end
end
