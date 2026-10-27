# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "test_helper"
require_relative "support/binaries"
require_relative "../tasks/runtime_builder"

# The parts of rake runtime that need no compiler: the pins it reads, the
# pruning it does, and the license audit it runs before it archives. CI's runtime jobs build real
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

  def test_gmp_is_pinned_to_msys2s_source_package_and_the_dll_it_built
    pin = builder("x64-mingw-ucrt").sources.fetch("gmp")

    assert_match(%r{\Ahttps://repo\.msys2\.org/mingw/sources/mingw-w64-gmp-#{pin.fetch('version')}-\d+\.src\.tar\.zst\z}, pin.fetch("url"))
    assert_match(%r{\Ahttps://repo\.msys2\.org/mingw/ucrt64/}, pin.fetch("package").fetch("url"))
    [pin, pin.fetch("package")].each { |entry| assert_match(/\A\h{64}\z/, entry.fetch("sha256")) }
    licensed = YAML.safe_load_file(LicenseAudit::MAP).fetch("components").find { |component| component.fetch("id") == "gmp" }
    assert_equal pin.fetch("dll_sha256"), licensed.fetch("sha256").values.first
  end

  # A release publishes these beside each runtime, and fledge build
  # downloads the first by the name Fledge::Runtimes gives it.
  def test_the_assets_are_named_for_the_version_and_platform
    assert_equal({
      runtime: "fledge-runtime-1.2.3-x86_64-linux.tar.gz",
      sbom: "fledge-runtime-1.2.3-x86_64-linux.spdx.json",
      notices: "fledge-runtime-1.2.3-x86_64-linux-NOTICES.txt",
      sources: "fledge-runtime-1.2.3-x86_64-linux-lgpl-sources.tar.gz",
    }, builder("x86_64-linux").assets(version: "1.2.3"))
    assert_equal Fledge::Runtimes.file_name(Fledge::Platform.find("x64-mingw-ucrt")), builder("x64-mingw-ucrt").assets.fetch(:runtime)
  end

  # Linux and Windows ship an LGPL library, so their releases carry its
  # source; macOS ships none.
  def test_a_release_publishes_every_platforms_assets_and_the_lgpl_sources_where_they_ship
    assets = RuntimeBuilder.release_assets(version: "1.2.3")

    assert_equal 15, assets.size
    assert_equal assets.sort, assets
    assert_includes assets, "fledge-runtime-1.2.3-x64-mingw-ucrt-lgpl-sources.tar.gz"
    assert_includes assets, "fledge-runtime-1.2.3-aarch64-linux-lgpl-sources.tar.gz"
    refute_includes assets, "fledge-runtime-1.2.3-arm64-darwin-lgpl-sources.tar.gz"
    assert_includes assets, "fledge-runtime-1.2.3-arm64-darwin.spdx.json"
  end

  # A small Linux runtime made of real (minimal) ELF files, shaped like
  # the one the Linux recipe stages.
  def linux_stage(root)
    rust = "/rustc/4eb161250e340c8f48f66e2b929ef4a5bed7c181/"
    {
      "launcher" => Binaries.elf(needed: %w[libcrypt.so.2 libc.so.6], rpath: "$ORIGIN/lib", payload: "3e93b23afc #{rust} GCC: ("),
      "bin/ruby" => Binaries.elf(needed: %w[libcrypt.so.2 libc.so.6], rpath: "$ORIGIN/../lib", payload: "3e93b23afc #{rust} GCC: ("),
      "lib/libcrypt.so.2" => Binaries.elf(needed: %w[libc.so.6], payload: "XCRYPT_4.4\0yescrypt-ROMhash"),
      "lib/ruby/4.0.0/set.rb" => "class Set; end\n",
      "libexec/cert.pem" => "-----BEGIN CERTIFICATE-----\n",
    }.each do |path, bytes|
      FileUtils.mkdir_p(File.dirname(File.join(root, path)))
      File.binwrite(File.join(root, path), bytes)
    end
    root
  end

  def test_license_writes_the_notices_and_sbom_of_a_runtime_that_meets_the_policy
    Dir.mktmpdir do |stage|
      report = nil
      out, = capture_io { report = builder("x86_64-linux").license(linux_stage(stage)) }

      assert_equal "x86_64-linux: 5 files in 6 components meet the license policy\n", out
      assert_empty report.violations
      assert_equal %w[NOTICES.txt sbom.spdx.json], Dir.children(File.join(stage, "notices")).sort
      notices = File.read(File.join(stage, "notices/NOTICES.txt"))
      assert_includes notices, "libxcrypt, which backs String#crypt\n  Version: 4.5.2\n  License: LGPL-2.1-or-later"
      assert_includes notices, "fledge-runtime-#{Fledge::VERSION}-x86_64-linux-lgpl-sources.tar.gz"
      assert_includes notices, "=== libxcrypt/COPYING.LIB"
      sbom = JSON.parse(File.read(File.join(stage, "notices/sbom.spdx.json")))
      assert_equal %w[./bin/ruby ./launcher ./lib/libcrypt.so.2 ./lib/ruby/4.0.0/set.rb ./libexec/cert.pem],
        sbom.fetch("files").map { |file| file.fetch("fileName") }
    end
  end

  # The build's gate: a runtime that breaks the policy is never archived.
  def test_license_refuses_a_runtime_with_libxcrypt_linked_into_bin_ruby_or_a_gpl_gem
    Dir.mktmpdir do |stage|
      linux_stage(stage)
      File.binwrite(File.join(stage, "bin/ruby"), Binaries.elf(needed: %w[libc.so.6], payload: "3e93b23afc /rustc/4eb161250e340c8f48f66e2b929ef4a5bed7c181/ GCC: ( yescrypt-ROMhash"))
      gems = File.join(stage, "lib/ruby/gems/4.0.0")
      write_spec(gems, "copyleft", "1.0.0", licenses: ["GPL-3.0-only"])
      FileUtils.mkdir_p(File.join(gems, "gems/copyleft-1.0.0"))
      File.write(File.join(gems, "gems/copyleft-1.0.0/copyleft.rb"), "")

      error = assert_raises(LicenseAudit::Failure) { builder("x86_64-linux").license(stage) }
      assert_includes error.message, "static-copyleft: bin/ruby: holds libxcrypt's code"
      assert_includes error.message, "gem-copyleft-1.0.0 is GPL-3.0-only, which the policy does not allow"
      refute_path_exists File.join(stage, "notices")
    end
  end

  # nkf's ext/java goes from the installed gem and from its .gem, which
  # RubyGems still verifies and installs.
  def test_prune_jruby_removes_nkfs_java_sources_from_the_gem_and_its_cache
    Dir.mktmpdir do |gems|
      files = { "lib/nkf.rb" => "module NKF; end\n", "ext/nkf/nkf.c" => "/* nkf */\n", "ext/java/org/jruby/ext/nkf/RubyNKF.java" => "/* EPL 2.0/LGPL 2.1 */\n" }
      files.each do |name, content|
        FileUtils.mkdir_p(File.dirname(File.join(gems, "gems/nkf-0.2.0", name)))
        File.write(File.join(gems, "gems/nkf-0.2.0", name), content)
      end
      spec = Gem::Specification.new do |gem|
        gem.name = "nkf"
        gem.version = "0.2.0"
        gem.summary = "nkf"
        gem.authors = ["x"]
        gem.files = files.keys
      end
      FileUtils.mkdir_p(File.join(gems, "cache"))
      cache = File.join(gems, "cache/nkf-0.2.0.gem")
      capture_io { Dir.chdir(File.join(gems, "gems/nkf-0.2.0")) { Gem::Package.build(spec, true, false, cache) } }

      RuntimeBuilder.prune_jruby(gems)

      refute_path_exists File.join(gems, "gems/nkf-0.2.0/ext/java")
      assert_path_exists File.join(gems, "gems/nkf-0.2.0/ext/nkf/nkf.c")
      package = Gem::Package.new(File.join(gems, "cache/nkf-0.2.0.gem"))
      package.verify
      assert_equal %w[ext/nkf/nkf.c lib/nkf.rb], package.contents.sort
      assert_equal %w[ext/nkf/nkf.c lib/nkf.rb], package.spec.files.sort
      package.extract_files(File.join(gems, "pristine"))
      assert_equal "module NKF; end\n", File.read(File.join(gems, "pristine/lib/nkf.rb"))
    end
  end

  # Ruby 4.0.9's gems/bundled_gems, at its v4.0.9 tag.
  def test_the_bundled_gems_are_ruby_4_0_9s
    bundled = builder("x86_64-linux").bundled_gems

    assert_equal 39, bundled.size
    assert_equal %w[minitest power_assert rake test-unit], bundled.first(4)
    assert_includes bundled, "csv"
    assert_includes bundled, "fiddle"
    refute_includes bundled, "bootsnap"
  end

  def make_files(root, files)
    files.each do |file|
      FileUtils.mkdir_p(File.dirname(File.join(root, file)))
      FileUtils.touch(File.join(root, file))
    end
  end

  def write_spec(gems, name, version, default: false, executables: [], licenses: [])
    folder = File.join(gems, "specifications", *("default" if default))
    FileUtils.mkdir_p(folder)
    spec = Gem::Specification.new do |s|
      s.name = name
      s.version = version
      s.summary = name
      s.authors = ["x"]
      s.executables = executables
      s.licenses = licenses
    end
    File.write(File.join(folder, "#{name}-#{version}.gemspec"), spec.to_ruby)
  end

  def kept(root)
    Dir.glob("**/*", base: root).select { |path| File.file?(File.join(root, path)) }.sort
  end

  # Everything a standard Ruby installs and Ruby code can reach stays;
  # what only compilers, debuggers, and documentation tools read goes,
  # and so do gems no standard Ruby 4.0.9 installs, such as rv-ruby's
  # bootsnap.
  def test_prune_keeps_default_and_bundled_gems_and_drops_what_no_ruby_code_reads
    Dir.mktmpdir do |ruby|
      gems = File.join(ruby, "gems/4.0.0")
      make_files(ruby, %w[
        4.0.0/json.rb
        4.0.0/arm64-darwin23/json/ext/parser.bundle
        4.0.0/arm64-darwin23/json/ext/parser.bundle.dSYM/Contents/Info.plist
        4.0.0/arm64-darwin23/portable_ruby_gems.rb
        4.0.0/arm64-darwin23/stray.a
        include/ruby.h
        pkgconfig/ruby-4.0.pc
        gems/4.0.0/gems/bundler-4.0.20/exe/bundle
        gems/4.0.0/gems/csv-3.3.5/lib/csv.rb
        gems/4.0.0/gems/bigdecimal-4.0.1/lib/bigdecimal.rb
        gems/4.0.0/gems/bigdecimal-4.0.1/ext/bigdecimal/bigdecimal.h
        gems/4.0.0/gems/bootsnap-1.24.6/lib/bootsnap.rb
        gems/4.0.0/cache/csv-3.3.5.gem
        gems/4.0.0/cache/bootsnap-1.24.6.gem
        gems/4.0.0/build_info/csv-3.3.5.info
        gems/4.0.0/build_info/bootsnap-1.24.6.info
        gems/4.0.0/extensions/arm64-darwin-23/4.0.0-static/bigdecimal-4.0.1/bigdecimal.bundle
        gems/4.0.0/extensions/arm64-darwin-23/4.0.0-static/bootsnap-1.24.6/bootsnap.bundle
        gems/4.0.0/doc/csv-3.3.5/ri/x
        gems/4.0.0/plugins/rdoc_plugin.rb
      ])
      write_spec(gems, "json", "2.18.0", default: true)
      write_spec(gems, "bundler", "4.0.20", default: true, executables: %w[bundle bundler])
      write_spec(gems, "csv", "3.3.5")
      write_spec(gems, "bigdecimal", "4.0.1")
      write_spec(gems, "bootsnap", "1.24.6", executables: %w[bootsnap])

      removed = RuntimeBuilder.prune(ruby, %w[csv bigdecimal])

      assert_equal %w[bootsnap], removed
      assert_equal %w[
        4.0.0/arm64-darwin23/json/ext/parser.bundle
        4.0.0/json.rb
        gems/4.0.0/build_info/csv-3.3.5.info
        gems/4.0.0/cache/csv-3.3.5.gem
        gems/4.0.0/extensions/arm64-darwin-23/4.0.0-static/bigdecimal-4.0.1/bigdecimal.bundle
        gems/4.0.0/gems/bigdecimal-4.0.1/lib/bigdecimal.rb
        gems/4.0.0/gems/bundler-4.0.20/exe/bundle
        gems/4.0.0/gems/csv-3.3.5/lib/csv.rb
        gems/4.0.0/plugins/rdoc_plugin.rb
        gems/4.0.0/specifications/bigdecimal-4.0.1.gemspec
        gems/4.0.0/specifications/csv-3.3.5.gemspec
        gems/4.0.0/specifications/default/bundler-4.0.20.gemspec
        gems/4.0.0/specifications/default/json-2.18.0.gemspec
      ], kept(ruby)
    end
  end

  def test_prune_bin_drops_the_executables_of_removed_gems_only
    Dir.mktmpdir do |bin|
      make_files(bin, %w[ruby gem bundle rake bootsnap])

      RuntimeBuilder.prune_bin(bin, %w[bootsnap])

      assert_equal %w[bundle gem rake ruby], kept(bin)
    end
  end

  # RubyInstaller's tree keeps its shape; what goes is documentation,
  # headers and import libraries, and RubyInstaller's tools for setting
  # up MSYS2 and a developer's shell. The gems' wrappers stay.
  def test_prune_windows_keeps_rubys_programs_dlls_wrappers_and_gems
    Dir.mktmpdir do |tree|
      make_files(tree, %w[
        LICENSE.txt
        bin/ruby.exe
        bin/rubyw.exe
        bin/x64-ucrt-ruby400.dll
        bin/ruby_builtin_dlls/libgmp-10.dll
        bin/ruby_builtin_dlls/ruby_builtin_dlls.manifest
        bin/bundle
        bin/bundle.bat
        bin/gem.cmd
        bin/ridk.cmd
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
        lib/ruby/gems/4.0.0/gems/csv-3.3.5/lib/csv.rb
        lib/ruby/gems/4.0.0/extensions/x64-mingw-ucrt/4.0.0/fiddle-1.1.8/libffi-8.dll
        lib/ruby/site_ruby/4.0.0/ruby_installer.rb
        packages/msys2-keyring.pkg.tar.zst
        ridk_use/ridk_use.rb
        share/doc/ruby/README.md
        share/ri/4.0.0/system/String/cdesc-String.ri
      ])
      gems = File.join(tree, "lib/ruby/gems/4.0.0")
      write_spec(gems, "json", "2.18.0", default: true)
      write_spec(gems, "csv", "3.3.5")
      write_spec(gems, "fiddle", "1.1.8")

      RuntimeBuilder.prune_windows(tree, %w[csv fiddle])

      assert_equal %w[
        LICENSE.txt
        bin/bundle
        bin/bundle.bat
        bin/gem.cmd
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
        lib/ruby/gems/4.0.0/extensions/x64-mingw-ucrt/4.0.0/fiddle-1.1.8/libffi-8.dll
        lib/ruby/gems/4.0.0/gems/csv-3.3.5/lib/csv.rb
        lib/ruby/gems/4.0.0/specifications/csv-3.3.5.gemspec
        lib/ruby/gems/4.0.0/specifications/default/json-2.18.0.gemspec
        lib/ruby/gems/4.0.0/specifications/fiddle-1.1.8.gemspec
        lib/ruby/site_ruby/4.0.0/ruby_installer.rb
      ], kept(tree)
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
