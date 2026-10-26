# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "test_helper"
require_relative "../tasks/runtime_builder"

# The parts of rake runtime that need no compiler: the pins it reads, the
# pruning it does, and the notices it writes. CI's runtime jobs build real
# runtimes, and test/built_app_test.rb runs them.
class RuntimeBuilderTest < Minitest::Test
  def builder(name)
    RuntimeBuilder.new(platform: Fledge::Platform.find(name))
  end

  def test_every_platform_pins_a_ruby_build_by_sha256
    pins = builder("x86_64-linux").sources.fetch("ruby").fetch("platforms")

    assert_equal Fledge::Platform.names.sort, pins.keys.sort
    pins.except("x64-mingw-ucrt").each_value do |pin|
      assert_match(%r{\Ahttps://github\.com/spinel-coop/rv-ruby/releases/download/20261023/ruby-4\.0\.9\.}, pin.fetch("url"))
      assert_match(/\A\h{64}\z/, pin.fetch("sha256"))
    end
  end

  def test_windows_pins_rubyinstaller_its_signature_and_the_key_that_signed_it
    pin = builder("x64-mingw-ucrt").sources.fetch("ruby").fetch("platforms").fetch("x64-mingw-ucrt")
    signature = pin.fetch("signature")
    key = signature.fetch("key")

    assert_equal "https://github.com/oneclick/rubyinstaller2/releases/download/RubyInstaller-4.0.9-1/rubyinstaller-4.0.9-1-x64.7z",
      pin.fetch("url")
    assert_equal "1dc0715916251a13c4f6a550a3da1f2c726bff869371fd573a65234c008f47b4", pin.fetch("sha256")
    assert_equal "#{pin.fetch('url')}.asc", signature.fetch("url")
    assert_match(/\A\h{64}\z/, signature.fetch("sha256"))
    assert_match(%r{\Ahttps://raw\.githubusercontent\.com/oneclick/rubyinstaller2/\h{40}/}, key.fetch("url"))
    assert_match(/\A\h{64}\z/, key.fetch("sha256"))
    assert_equal "79D1D4E12FF93365DEAA8DCEF98B8484BE8BF1C5", key.fetch("fingerprint")
    assert_equal "2027-06-15", key.fetch("expires")
  end

  def test_llvm_mingw_is_pinned_for_every_unix_platform_that_builds_the_windows_runtime
    pin = builder("x64-mingw-ucrt").sources.fetch("llvm-mingw")

    assert_equal %w[aarch64-linux arm64-darwin x86_64-linux], pin.fetch("hosts").keys.sort
    pin.fetch("hosts").each_value do |host|
      assert_match(%r{\Ahttps://github\.com/mstorsjo/llvm-mingw/releases/download/#{pin.fetch('version')}/llvm-mingw-#{pin.fetch('version')}-ucrt-}, host.fetch("url"))
      assert_match(/\A\h{64}\z/, host.fetch("sha256"))
    end
  end

  def test_libxcrypt_is_pinned_by_sha256
    pin = builder("x86_64-linux").sources.fetch("libxcrypt")

    assert_match(/\A\h{64}\z/, pin.fetch("sha256"))
    assert_match(%r{\Ahttps://}, pin.fetch("url"))
  end

  def test_linux_carries_the_notices_of_what_it_links_statically_and_macos_does_not
    linux = builder("aarch64-linux").notices.map { |notice| notice.fetch("folder") }
    darwin = builder("arm64-darwin").notices.map { |notice| notice.fetch("folder") }

    assert_equal %w[fledge ruby rust openssl libyaml ca-certificates zlib libxcrypt], linux
    assert_equal %w[fledge ruby rust openssl libyaml ca-certificates], darwin
  end

  # RubyInstaller's Ruby has no YJIT, so no Rust, and ships its libraries
  # as DLLs, whose notices name them.
  def test_windows_carries_the_notices_of_rubyinstaller_and_the_dlls_it_ships
    notices = builder("x64-mingw-ucrt").notices

    assert_equal %w[fledge ruby rubyinstaller openssl libyaml zlib gmp mingw-w64 ca-certificates],
      notices.map { |notice| notice.fetch("folder") }
    assert_includes notices.find { |notice| notice.fetch("folder") == "openssl" }.fetch("name"), "OpenSSL 3.6.5"
    assert_includes notices.find { |notice| notice.fetch("folder") == "gmp" }.fetch("name"), "which you may replace"
  end

  def test_write_notices_for_windows_copies_rubyinstallers_license_and_the_gmp_texts
    Dir.mktmpdir do |stage|
      builder("x64-mingw-ucrt").write_notices(stage)

      assert_path_exists File.join(stage, "notices/rubyinstaller/LICENSE.txt")
      assert_equal %w[COPYING.LESSERv3 COPYINGv2 COPYINGv3], Dir.children(File.join(stage, "notices/gmp")).sort
      assert_path_exists File.join(stage, "notices/mingw-w64/COPYING.MinGW-w64-runtime.txt")
      refute_path_exists File.join(stage, "notices/rust")
      index = File.read(File.join(stage, "notices/README.txt"))
      assert_includes index, "gmp/\n  GNU MP 6.3.0"
      assert_includes index, "License: LGPL-3.0-or-later OR GPL-2.0-or-later"
    end
  end

  def test_every_notice_folder_has_its_license_texts
    builder("x86_64-linux").sources.fetch("notices").each do |notice|
      next if notice.fetch("folder") == "fledge"

      refute_empty Dir.glob(File.join(RuntimeBuilder::ROOT, "runtime/notices", notice.fetch("folder"), "*")), notice.fetch("folder")
    end
  end

  def test_write_notices_copies_each_and_indexes_them
    Dir.mktmpdir do |stage|
      builder("x86_64-linux").write_notices(stage)

      assert_equal %w[README.txt ca-certificates fledge libxcrypt libyaml openssl ruby rust zlib], Dir.children(File.join(stage, "notices")).sort
      assert_path_exists File.join(stage, "notices/fledge/AGPL-3.0-or-later.txt")
      assert_path_exists File.join(stage, "notices/libxcrypt/COPYING.LIB")
      index = File.read(File.join(stage, "notices/README.txt"))
      assert_includes index, "libxcrypt/\n  libxcrypt 4.5.2"
      assert_includes index, "License: LGPL-2.1-or-later\n  Source: https://github.com/besser82/libxcrypt/releases/download/v4.5.2/libxcrypt-4.5.2.tar.xz"
    end
  end

  def test_prune_keeps_the_standard_library_and_default_gems_and_drops_the_rest
    Dir.mktmpdir do |ruby|
      files = %w[
        4.0.0/json.rb
        4.0.0/arm64-darwin23/json/ext/parser.bundle
        4.0.0/arm64-darwin23/json/ext/parser.bundle.dSYM/Contents/Info.plist
        4.0.0/arm64-darwin23/portable_ruby_gems.rb
        4.0.0/arm64-darwin23/stray.a
        gems/4.0.0/specifications/default/json-2.18.0.gemspec
        gems/4.0.0/specifications/csv-3.3.5.gemspec
        gems/4.0.0/gems/bundler-4.0.20/exe/bundle
        gems/4.0.0/gems/csv-3.3.5/lib/csv.rb
        gems/4.0.0/cache/csv-3.3.5.gem
        gems/4.0.0/extensions/arm64-darwin-23/4.0.0-static/bigdecimal-4.0.1/bigdecimal.bundle
        gems/4.0.0/doc/x
        gems/4.0.0/build_info/x
        gems/4.0.0/plugins/rdoc_plugin.rb
      ]
      FileUtils.touch(File.join(ruby, "x"))
      files.each do |file|
        FileUtils.mkdir_p(File.dirname(File.join(ruby, file)))
        FileUtils.touch(File.join(ruby, file))
      end
      FileUtils.mkdir_p(File.join(ruby, "gems/4.0.0/specifications/default"))
      File.write(File.join(ruby, "gems/4.0.0/specifications/default/bundler-4.0.20.gemspec"), "")

      RuntimeBuilder.prune(ruby)

      kept = Dir.glob("**/*", base: ruby).select { |path| File.file?(File.join(ruby, path)) }.sort
      assert_equal %w[
        4.0.0/arm64-darwin23/json/ext/parser.bundle
        4.0.0/json.rb
        gems/4.0.0/gems/bundler-4.0.20/exe/bundle
        gems/4.0.0/specifications/default/bundler-4.0.20.gemspec
        gems/4.0.0/specifications/default/json-2.18.0.gemspec
        x
      ], kept
    end
  end

  # RubyInstaller's tree keeps its shape; what goes is documentation,
  # headers and import libraries, ridk's files, the command-line wrappers
  # in bin, and the bundled gems, as on Unix.
  def test_prune_windows_keeps_rubys_dlls_executables_and_library
    Dir.mktmpdir do |tree|
      files = %w[
        LICENSE.txt
        bin/ruby.exe
        bin/rubyw.exe
        bin/x64-ucrt-ruby400.dll
        bin/ruby_builtin_dlls/libgmp-10.dll
        bin/ruby_builtin_dlls/ruby_builtin_dlls.manifest
        bin/bundle
        bin/bundle.bat
        bin/gem.cmd
        bin/ridk.ps1
        bin/setrbvars.cmd
        bin/startmenu.rb
        include/ruby-4.0.0/ruby.h
        lib/libx64-ucrt-ruby400.dll.a
        lib/pkgconfig/ruby-4.0.pc
        lib/ruby/4.0.0/json.rb
        lib/ruby/4.0.0/x64-mingw-ucrt/zlib1.dll
        lib/ruby/4.0.0/x64-mingw-ucrt/zlib.so
        lib/ruby/4.0.0/x64-mingw-ucrt/zlib.so-assembly.manifest
        lib/ruby/4.0.0/etc/ssl/cert.pem
        lib/ruby/gems/4.0.0/specifications/default/json-2.18.0.gemspec
        lib/ruby/gems/4.0.0/specifications/csv-3.3.5.gemspec
        lib/ruby/gems/4.0.0/gems/csv-3.3.5/lib/csv.rb
        lib/ruby/gems/4.0.0/extensions/x64-mingw-ucrt/4.0.0/fiddle-1.1.8/libffi-8.dll
        lib/ruby/site_ruby/4.0.0/ruby_installer.rb
        packages/msys2-keyring.pkg.tar.zst
        ridk_use/ridk_use.rb
        share/doc/ruby/README.md
      ]
      files.each do |file|
        FileUtils.mkdir_p(File.dirname(File.join(tree, file)))
        FileUtils.touch(File.join(tree, file))
      end

      RuntimeBuilder.prune_windows(tree)

      kept = Dir.glob("**/*", base: tree).select { |path| File.file?(File.join(tree, path)) }.sort
      assert_equal %w[
        LICENSE.txt
        bin/ruby.exe
        bin/ruby_builtin_dlls/libgmp-10.dll
        bin/ruby_builtin_dlls/ruby_builtin_dlls.manifest
        bin/rubyw.exe
        bin/x64-ucrt-ruby400.dll
        lib/ruby/4.0.0/etc/ssl/cert.pem
        lib/ruby/4.0.0/json.rb
        lib/ruby/4.0.0/x64-mingw-ucrt/zlib.so
        lib/ruby/4.0.0/x64-mingw-ucrt/zlib.so-assembly.manifest
        lib/ruby/4.0.0/x64-mingw-ucrt/zlib1.dll
        lib/ruby/gems/4.0.0/specifications/default/json-2.18.0.gemspec
        lib/ruby/site_ruby/4.0.0/ruby_installer.rb
      ], kept
    end
  end

  def test_install_rubygems_defaults_replaces_rubyinstallers_hook_with_fledges
    Dir.mktmpdir do |ruby|
      defaults = File.join(ruby, "4.0.0/rubygems/defaults")
      FileUtils.mkdir_p(defaults)
      File.write(File.join(defaults, "operating_system.rb"), "require 'ruby_installer/runtime'\n")

      builder("x64-mingw-ucrt").install_rubygems_defaults(ruby)

      assert_equal File.read(File.join(RuntimeBuilder::ROOT, "runtime/rubygems/operating_system.rb")),
        File.read(File.join(defaults, "operating_system.rb"))
    end
  end

  def test_dearmor_decodes_ascii_armor_and_checks_its_crc
    armored = "-----BEGIN PGP ARMORED FILE-----\nComment: Use \"gpg --dearmor\" for unpacking\n\n" \
      "RmxlZGdl\n=jMjj\n-----END PGP ARMORED FILE-----\n"

    assert_equal "Fledge", RuntimeBuilder.dearmor(armored)
    assert_equal "Fledge", RuntimeBuilder.dearmor(armored.gsub("\n", "\r\n"))
    error = assert_raises(RuntimeError) { RuntimeBuilder.dearmor(armored.sub("RmxlZGdl", "RmxlZGdm")) }
    assert_equal "the armor's CRC-24 does not match its data", error.message
    assert_raises(RuntimeError) { RuntimeBuilder.dearmor("not armor") }
  end

  def pe(subsystem)
    bytes = "MZ".b.ljust(0x80, "\0")
    bytes[0x3C, 4] = [0x80].pack("V")
    bytes << "PE\0\0".b << ("\0" * 20) << ("\0" * 68) << [subsystem].pack("v") << ("\0" * 64)
  end

  def test_pe_subsystem_reads_a_programs_subsystem
    Dir.mktmpdir do |dir|
      { "gui.exe" => 2, "console.exe" => 3 }.each do |name, subsystem|
        File.binwrite(File.join(dir, name), pe(subsystem))

        assert_equal subsystem, RuntimeBuilder.pe_subsystem(File.join(dir, name))
      end
      File.binwrite(File.join(dir, "elf"), "\x7FELF".b.ljust(256, "\0"))
      assert_raises(RuntimeError) { RuntimeBuilder.pe_subsystem(File.join(dir, "elf")) }
    end
  end

  def test_the_runtime_is_named_for_this_fledge_version_and_platform
    assert_equal "fledge-runtime-#{Fledge::VERSION}-aarch64-linux", builder("aarch64-linux").top
  end

  def test_a_unix_runtime_builds_only_on_its_own_platform
    darwin = Fledge::Platform.find("arm64-darwin")
    linux = Fledge::Platform.find("x86_64-linux")

    error = assert_raises(RuntimeError) { RuntimeBuilder.new(platform: darwin, host: linux).call }
    assert_equal "arm64-darwin runtimes build on arm64-darwin only; this is x86_64-linux", error.message
  end

  # The Windows launcher cross-compiles, so Windows runtimes build where
  # llvm-mingw is pinned, and not on Windows itself.
  def test_a_windows_runtime_builds_on_the_unix_platforms_llvm_mingw_is_pinned_for
    windows = Fledge::Platform.find("x64-mingw-ucrt")

    error = assert_raises(RuntimeError) { RuntimeBuilder.new(platform: windows, host: windows).call }
    assert_equal "x64-mingw-ucrt runtimes build on x86_64-linux, aarch64-linux, arm64-darwin only; " \
      "this is x64-mingw-ucrt", error.message
  end
end
