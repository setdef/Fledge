# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "test_helper"
require_relative "support/binaries"
require_relative "../tasks/runtime_builder"

# The parts of rake runtime that need no compiler: the pins it reads, the
# pruning it does, and the license audit it runs before it archives. CI's runtime jobs build real
# runtimes, and test/integration/built_app_test.rb runs them.
class RuntimeBuilderTest < Minitest::Test
  LEAKED = { "RUBYOPT" => "-rbundler/setup", "BUNDLE_GEMFILE" => "/nowhere/Gemfile", "RUBYLIB" => "/nowhere/lib" }.freeze
  PRINT_LEAKED = LEAKED.keys.map { |name| "echo #{name}=${#{name}-unset}" }.join("; ").freeze

  def builder(name)
    RuntimeBuilder.new(platform: Fledge::Platform.find(name))
  end

  # bundle exec rake runtime sets RUBYOPT=-rbundler/setup, which the
  # miniruby of a cross build on the build machine cannot load without
  # rbconfig; the steps run as they do under ruby tasks/runtime_builder.rb.
  def test_a_step_runs_without_the_bundler_variables_of_the_rake_that_started_it
    seen = with_env(LEAKED) do
      Dir.mktmpdir do |dir|
        out = File.join(dir, "seen")
        builder("x86_64-linux").run("sh", "-c", PRINT_LEAKED, out:)
        File.read(out)
      end
    end

    assert_equal(LEAKED.keys.map { |name| "#{name}=unset" }, seen.lines.map(&:chomp))
  end

  def test_a_captured_step_runs_without_the_bundler_variables_of_the_rake_that_started_it
    seen = with_env(LEAKED) { builder("x86_64-linux").capture("sh", "-c", PRINT_LEAKED) }

    assert_equal(LEAKED.keys.map { |name| "#{name}=unset" }, seen.lines.map(&:chomp))
  end

  def with_env(variables)
    saved = ENV.to_h.slice(*variables.keys)
    ENV.update(variables)
    yield
  ensure
    variables.each_key { |name| saved.key?(name) ? ENV[name] = saved[name] : ENV.delete(name) }
  end

  def test_every_platform_pins_a_ruby_build_by_sha256
    pins = builder("x86_64-linux").sources.fetch("ruby").fetch("platforms")

    assert_equal Fledge::Platform.names.reject { |name| name.end_with?("-musl") }.sort, pins.keys.sort
    pins.except("x64-mingw-ucrt", "aarch64-mingw-ucrt").each_value do |pin|
      assert_match(%r{\Ahttps://github\.com/spinel-coop/rv-ruby/releases/download/20261023/ruby-4\.1\.0-preview1\.}, pin.fetch("url"))
      assert_match(/\A\h{64}\z/, pin.fetch("sha256"))
    end
  end

  # musl Linux builds its Ruby from source (ADR 017), from pins of its
  # own: Ruby's release, and what its extensions link statically.
  def test_musl_pins_the_sources_its_ruby_builds_from
    pins = builder("x86_64-linux").sources.fetch("musl-ruby")

    assert_equal %w[ca-certificates libffi libyaml openssl ruby zlib], pins.keys.sort
    pins.each_value do |pin|
      assert_match(%r{\Ahttps://}, pin.fetch("url"))
      assert_match(/\A\h{64}\z/, pin.fetch("sha256"))
    end
    assert_equal builder("x86_64-linux").sources.fetch("ruby").fetch("version"), pins.fetch("ruby").fetch("version")
  end

  # Windows on ARM64 takes RubyInstaller's ARM64 build of the same day,
  # signed with the same key (ADR 035;
  # doc/contributors/design/runtimes.md, "Windows on ARM64").
  def test_windows_on_arm_pins_rubyinstallers_arm64_build_signed_by_the_same_key
    platforms = builder("x64-mingw-ucrt").sources.fetch("ruby").fetch("platforms")
    arm = platforms.fetch("aarch64-mingw-ucrt")

    assert_equal "https://github.com/setdef/Fledge/releases/download/inputs-rubyinstaller-head-20261110/rubyinstaller-head-arm.7z", arm.fetch("url")
    assert_equal "#{arm.fetch('url')}.asc", arm.fetch("signature").fetch("url")
    assert_equal platforms.fetch("x64-mingw-ucrt").fetch("signature").fetch("key"), arm.fetch("signature").fetch("key")
  end

  # RubyInstaller's rubyinstaller-head URL serves each day's build in
  # place of the last, so the pin names the copy of the day's files that
  # Fledge keeps as a pre-release of its own repository, named for the
  # source and the day (doc/contributors/design/runtimes.md).
  def test_windows_pins_rubyinstaller_its_signature_and_the_key_that_signed_it
    pin = builder("x64-mingw-ucrt").sources.fetch("ruby").fetch("platforms").fetch("x64-mingw-ucrt")
    signature = pin.fetch("signature")
    key = signature.fetch("key")

    assert_equal "https://github.com/setdef/Fledge/releases/download/inputs-rubyinstaller-head-20261110/rubyinstaller-head-x64.7z", pin.fetch("url")
    assert_equal "901473edafd6b174d79978fc109d3df3ab73b1436719233f35c1a31b5b18bf58", pin.fetch("sha256")
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

  # libxcrypt 4.5.2 turns its warnings into errors, and GCC 15's C23
  # default with glibc 2.43's const-preserving strchr warns in
  # crypt-sm3-yescrypt.c and crypt-gost-yescrypt.c, so the build keeps
  # warnings as warnings, with rv-ruby's options otherwise.
  def test_libxcrypt_builds_with_rv_rubys_options_and_warnings_left_as_warnings
    Dir.mktmpdir do |dir|
      commands = Pinned.new(builder("x86_64-linux").sources)
      recipe = RuntimeBuilder::Linux.new(builder: commands, build_dir: dir)

      recipe.__send__(:build_libxcrypt)

      configure = commands.ran.find { |command| command.first == "./configure" }
      expected = %w[
        --enable-shared
        --disable-static
        --disable-obsolete-api
        --disable-xcrypt-compat-files
        --disable-failure-tokens
        --disable-valgrind
        --disable-werror
      ]
      assert_equal ["./configure", "--prefix=#{File.join(dir, 'libxcrypt-prefix')}", *expected], configure
    end
  end

  def test_gmp_is_pinned_to_msys2s_source_package_and_the_dll_it_built
    pin = builder("x64-mingw-ucrt").sources.fetch("gmp")

    assert_match(%r{\Ahttps://repo\.msys2\.org/mingw/sources/mingw-w64-gmp-#{pin.fetch('version')}-\d+\.src\.tar\.zst\z}, pin.fetch("url"))
    assert_match(%r{\Ahttps://repo\.msys2\.org/mingw/ucrt64/}, pin.fetch("package").fetch("url"))
    [pin, pin.fetch("package")].each { |entry| assert_match(/\A\h{64}\z/, entry.fetch("sha256")) }
    licensed = YAML.safe_load_file(LicenseAudit::MAP).fetch("components").find { |component| component.fetch("id") == "gmp" }
    assert_equal pin.fetch("dll_sha256"), licensed.fetch("sha256").values.first
  end

  # The DLLs RubyInstaller's head build lacks come from MSYS2's packages,
  # each pinned with its source package and the DLL's own SHA-256, which
  # the license audit checks again in the runtime.
  def test_the_dlls_rubyinstaller_lacks_are_pinned_to_msys2s_packages_and_audited
    pins = builder("x64-mingw-ucrt").sources.fetch("windows-dlls")
    components = YAML.safe_load_file(LicenseAudit::MAP).fetch("components")

    assert_equal %w[libgcc_s_seh-1.dll libz-1.dll], pins.keys.sort
    assert_equal({ "libz-1.dll" => %w[aarch64-mingw-ucrt x64-mingw-ucrt], "libgcc_s_seh-1.dll" => %w[x64-mingw-ucrt] },
      pins.transform_values { |pin| pin.fetch("platforms").keys.sort })
    pins.each do |name, pin|
      assert_match(%r{\Ahttps://repo\.msys2\.org/mingw/sources/mingw-w64-[a-z]+-#{Regexp.escape(pin.fetch('version'))}-\d+\.src\.tar\.zst\z},
        pin.fetch("url"))
      assert_match(/\A\h{64}\z/, pin.fetch("sha256"))
      pin.fetch("platforms").each do |platform, dll|
        assert_match(%r{\Ahttps://repo\.msys2\.org/mingw/(?:ucrt64|clangarm64)/}, dll.fetch("package").fetch("url"))
        assert_match(/\A\h{64}\z/, dll.fetch("package").fetch("sha256"))
        assert_equal name, File.basename(dll.fetch("path"))
        audited = components.select { |component| component.fetch("platforms").include?(platform) }
          .flat_map { |component| component.fetch("sha256", {}).to_a }.select { |path, _| path.end_with?("/#{name}") }
        assert_equal [dll.fetch("dll_sha256")], audited.map(&:last), "#{name} on #{platform}"
      end
    end
  end

  # zlib.so finds libz-1.dll through the private assembly its own
  # manifest names, as it finds zlib1.dll.
  def test_name_in_manifest_adds_a_dll_beside_the_one_the_manifest_names
    manifest = <<~XML
      <assembly xmlns="urn:schemas-microsoft-com:asm.v1" manifestVersion="1.0">
        <assemblyIdentity type="win32" name="zlib.so-assembly" version="1.0.0.0"></assemblyIdentity>

        <file name="zlib1.dll"/>
      </assembly>
    XML

    assert_includes RuntimeBuilder::Windows.name_in_manifest(manifest, after: "zlib1.dll", name: "libz-1.dll"),
      %(  <file name="zlib1.dll"/><file name="libz-1.dll"/>\n</assembly>)
    error = assert_raises(RuntimeError) { RuntimeBuilder::Windows.name_in_manifest(manifest, after: "zlib.dll", name: "libz-1.dll") }
    assert_match(/names no zlib\.dll/, error.message)
  end

  # Only .github/scripts/fetch_pin.rb passes a pin's mirrors to the
  # download (RuntimeBuilder#fetch_pin), and it alone reads the
  # replaceability pins; mirrors named anywhere else would never be tried.
  def test_only_the_pins_fetch_pin_reads_name_mirrors_and_each_is_https
    mirrored = mirrored_pins(builder("x86_64-linux").sources)

    assert_equal [%w[replaceability gmp], %w[replaceability musl]], mirrored.keys.sort
    mirrored.each_value do |urls|
      refute_empty urls
      urls.each { |url| assert_match(%r{\Ahttps://}, url) }
    end
  end

  def mirrored_pins(node, path = [])
    return {} unless node.is_a?(Hash)

    own = node.key?("mirrors") ? { path => node.fetch("mirrors") } : {}
    node.except("mirrors").reduce(own) { |found, (key, child)| found.merge(mirrored_pins(child, path + [key])) }
  end

  # A release publishes these beside each runtime, and fledge build
  # downloads the first by the name Fledge::Runtimes gives it.
  def test_the_assets_are_named_for_the_version_and_platform
    assert_equal({
      runtime: "fledge-runtime-1.2.3-x86_64-linux.tar.gz",
      sbom: "fledge-runtime-1.2.3-x86_64-linux.spdx.json",
      notices: "fledge-runtime-1.2.3-x86_64-linux-NOTICES.txt",
      sources: "fledge-runtime-1.2.3-x86_64-linux-lgpl-sources.tar.gz",
      dev: "fledge-runtime-1.2.3-x86_64-linux-dev.tar.gz",
    }, builder("x86_64-linux").assets(version: "1.2.3"))
    assert_equal Fledge::Runtimes.dev_file_name(Fledge::Platform.find("x86_64-linux")), builder("x86_64-linux").assets.fetch(:dev)
    assert_equal Fledge::Runtimes.file_name(Fledge::Platform.find("x64-mingw-ucrt")), builder("x64-mingw-ucrt").assets.fetch(:runtime)
  end

  # Linux, musl Linux too, and Windows, on ARM64 too, ship an LGPL library, so their
  # releases carry its source; macOS ships none. The mobile runtimes carry three each
  # (test/mobile_runtime_test.rb).
  def test_a_release_publishes_every_platforms_assets_and_the_lgpl_sources_where_they_ship
    assets = RuntimeBuilder.release_assets(version: "1.2.3")

    assert_equal 40, assets.size
    assert_equal assets.sort, assets
    Fledge::Platform.names.each { |name| assert_includes assets, "fledge-runtime-1.2.3-#{name}-dev.tar.gz" }
    assert_includes assets, "fledge-runtime-1.2.3-x64-mingw-ucrt-lgpl-sources.tar.gz"
    assert_includes assets, "fledge-runtime-1.2.3-aarch64-mingw-ucrt-lgpl-sources.tar.gz"
    assert_includes assets, "fledge-runtime-1.2.3-aarch64-linux-lgpl-sources.tar.gz"
    assert_includes assets, "fledge-runtime-1.2.3-x86_64-linux-musl-lgpl-sources.tar.gz"
    refute_includes assets, "fledge-runtime-1.2.3-arm64-darwin-lgpl-sources.tar.gz"
    assert_includes assets, "fledge-runtime-1.2.3-arm64-darwin.spdx.json"
  end

  # The build-only companion holds what compiling an extension against
  # the runtime's Ruby needs and the runtime prunes (ADR 006): the
  # library to link against, the import library of Ruby's DLL on Windows
  # and static libruby elsewhere, with their licenses beside it. Ruby's
  # headers are in the runtime itself (ADR 085). Nothing else of Ruby's
  # tree, and never libxcrypt's static archive.
  def test_copy_dev_takes_the_library_to_link_against
    Dir.mktmpdir do |dir|
      tree = File.join(dir, "tree")
      {
"include/ruby-4.0.0/ruby.h" => "/* ruby */\n",
"include/ruby-4.0.0/x64-mingw-ucrt/ruby/config.h" => "/* config */\n",
"lib/libx64-ucrt-ruby400.dll.a" => "!<arch>\n",
"lib/libruby-static.a" => "!<arch>\n",
"lib/libcrypt.a" => "!<arch>\n",
"lib/ruby/4.0.0/set.rb" => "",
"bin/ruby.exe" => "MZ",
}.each do |path, content|
        FileUtils.mkdir_p(File.dirname(File.join(tree, path)))
        File.write(File.join(tree, path), content)
      end
      windows = File.join(dir, "windows")
      unix = File.join(dir, "unix")

      RuntimeBuilder::DevCompanion.copy(tree, windows, windows: true)
      RuntimeBuilder::DevCompanion.copy(tree, unix, windows: false)

      assert_equal %w[DEV-NOTICES.txt ruby/lib/libx64-ucrt-ruby400.dll.a], files(windows)
      assert_equal %w[DEV-NOTICES.txt lib/libruby-static.a], files(unix)
      notices = File.read(File.join(unix, "DEV-NOTICES.txt"))
      assert_includes notices, "never copies it into an app"
      %w[ruby/COPYING ruby/BSDL rust/LICENSE-MIT rust/LICENSE-APACHE].each do |notice|
        assert_includes notices, File.read(File.join(RuntimeBuilder::ROOT, "runtime/notices", notice))
      end
      refute_includes File.read(File.join(windows, "DEV-NOTICES.txt")), File.read(File.join(RuntimeBuilder::ROOT, "runtime/notices/rust/LICENSE-MIT"))
    end
  end

  def files(root)
    Dir.glob("**/*", base: root).select { |path| File.file?(File.join(root, path)) }.sort
  end

  # A small Linux runtime made of real (small) ELF files, shaped like
  # the one the Linux recipe stages, which a tool here must read.
  def linux_stage(root)
    TestReaders.need(self, :elf)
    rust = "/rustc/4eb161250e340c8f48f66e2b929ef4a5bed7c181/"
    {
      "launcher" => Binaries.elf(needed: %w[libcrypt.so.2 libc.so.6], payload: "2d08b5f42f #{rust} GCC: ("),
      "bin/ruby" => Binaries.elf(needed: %w[libcrypt.so.2 libc.so.6], payload: "2d08b5f42f #{rust} GCC: ( ruby: could not run "),
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
      File.binwrite(File.join(stage, "bin/ruby"), Binaries.elf(needed: %w[libc.so.6], payload: "2d08b5f42f /rustc/4eb161250e340c8f48f66e2b929ef4a5bed7c181/ GCC: ( yescrypt-ROMhash"))
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

      RuntimeBuilder::Pruning.prune_jruby(gems)

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

  # Ruby 4.1.0-preview1's gems/bundled_gems, at its v4_1_0_preview1 tag
  # (2d08b5f42f), in its order: prism, tsort, and win32-registry joined
  # it in 4.1, and net-ftp and net-pop left.
  def test_the_bundled_gems_are_ruby_4_1_0_preview1s
    bundled = builder("x86_64-linux").bundled_gems

    expected = "minitest power_assert rake test-unit rexml rss net-imap net-smtp matrix prime rbs typeprof debug racc " \
      "mutex_m getoptlong base64 bigdecimal observer abbrev resolv-replace rinda drb nkf syslog csv repl_type_completor " \
      "ostruct pstore benchmark logger rdoc prism win32ole irb reline readline fiddle tsort win32-registry"
    assert_equal expected.split, bundled
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
  # and so do gems no standard Ruby 4.1 installs, such as rv-ruby's
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

      removed = RuntimeBuilder::Pruning.prune(ruby, %w[csv bigdecimal])

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

  # mkmf links the test program of every have_func and have_library
  # against the static libruby in $(libdir), so a runtime keeps it beside
  # lib/ruby; rv-ruby's other static library, libxcrypt's, and its
  # pkg-config files stay out.
  def test_a_unix_runtime_keeps_the_static_libruby_mkmf_links_against
    Dir.mktmpdir do |dir|
      prefix = File.join(dir, "prefix")
      make_files(prefix, %w[
        bin/ruby
        bin/gem
        include/ruby-4.1.0+5/ruby.h
        lib/libruby.4.1-static.a
        lib/libcrypt.a
        lib/pkgconfig/ruby-4.1.pc
        lib/ruby/4.1.0+5/rubygems.rb
        libexec/cert.pem
      ])
      FileUtils.mkdir_p(File.join(prefix, "lib/ruby/gems/4.1.0+5/specifications"))
      recipe = RuntimeBuilder::Linux.new(builder: builder("x86_64-linux"), build_dir: dir)
      recipe.instance_variable_set(:@prefix, prefix)
      stage = File.join(dir, "stage")

      recipe.__send__(:copy_ruby, stage)

      assert_equal %w[lib/libruby.4.1-static.a], kept(File.join(stage)).grep(/\.a\z/)
      refute_path_exists File.join(stage, "lib/pkgconfig")
    end
  end

  def test_prune_bin_drops_the_executables_of_removed_gems_only
    Dir.mktmpdir do |bin|
      make_files(bin, %w[ruby gem bundle rake bootsnap])

      RuntimeBuilder::Pruning.prune_bin(bin, %w[bootsnap])

      assert_equal %w[bundle gem rake ruby], kept(bin)
    end
  end

  # RubyInstaller's tree keeps its shape; what goes is documentation,
  # static libraries and pkg-config files, and RubyInstaller's tools for
  # setting up MSYS2 and a developer's shell. The gems' wrappers stay, and
  # so does the import library of Ruby's DLL, which mkmf links against.
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
        lib/libother-static.a
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

      RuntimeBuilder::Pruning.prune_windows(tree, %w[csv fiddle])

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
        include/ruby-4.0.0/ruby.h
        lib/libx64-ucrt-ruby400.dll.a
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
      defaults = File.join(ruby, "4.1.0+6/rubygems/defaults")
      FileUtils.mkdir_p(defaults)
      File.write(File.join(ruby, "4.1.0+6/rubygems.rb"), "module Gem; end\n")
      FileUtils.mkdir_p(File.join(ruby, "site_ruby/4.1.0+6"))
      File.write(File.join(defaults, "operating_system.rb"), "require 'ruby_installer/runtime'\n")

      builder("x64-mingw-ucrt").install_rubygems_defaults(ruby)

      assert_equal File.read(File.join(RuntimeBuilder::ROOT, "runtime/rubygems/operating_system.rb")),
        File.read(File.join(defaults, "operating_system.rb"))
    end
  end

  # Ruby's own tree names the folder of its library: MAJOR.MINOR.0 for a
  # release, with its ABI version for a preview or a snapshot of master.
  def test_ruby_abi_is_the_folder_that_holds_rubygems
    Dir.mktmpdir do |ruby|
      FileUtils.mkdir_p(File.join(ruby, "gems/4.1.0+5"))
      FileUtils.mkdir_p(File.join(ruby, "site_ruby/4.1.0+5"))
      error = assert_raises(RuntimeError) { RuntimeBuilder.ruby_abi(ruby) }
      assert_equal "#{ruby} holds no one Ruby standard library: ", error.message

      FileUtils.mkdir_p(File.join(ruby, "4.1.0+5"))
      File.write(File.join(ruby, "4.1.0+5/rubygems.rb"), "module Gem; end\n")
      assert_equal "4.1.0+5", RuntimeBuilder.ruby_abi(ruby)
    end
  end

  def test_the_extension_api_of_a_static_ruby_is_its_rbconfigs_ruby_version
    Dir.mktmpdir do |build|
      File.write(File.join(build, "rbconfig.rb"), %(  CONFIG["MAJOR"] = "4"\n  CONFIG["ruby_version"] = "4.1.0+5"\n))
      assert_equal "4.1.0+5-static", RuntimeBuilder::Mobile.extension_api(build)
    end
  end

  def test_dearmor_decodes_ascii_armor_and_checks_its_crc
    armored = "-----BEGIN PGP ARMORED FILE-----\nComment: Use \"gpg --dearmor\" for unpacking\n\n" \
      "RmxlZGdl\n=jMjj\n-----END PGP ARMORED FILE-----\n"

    assert_equal "Fledge", RuntimeBuilder::Armor.dearmor(armored)
    assert_equal "Fledge", RuntimeBuilder::Armor.dearmor(armored.gsub("\n", "\r\n"))
    error = assert_raises(RuntimeError) { RuntimeBuilder::Armor.dearmor(armored.sub("RmxlZGdl", "RmxlZGdm")) }
    assert_equal "the armor's CRC-24 does not match its data", error.message
    assert_raises(RuntimeError) { RuntimeBuilder::Armor.dearmor("not armor") }
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

  # Stands in for the builder where a recipe compiles, keeping the
  # commands it would run; readelf answers with no libraries needed.
  class Commands
    attr_reader :ran

    def initialize
      @ran = []
    end

    def run(*command, **)
      @ran << command
    end

    def capture(*)
      ""
    end
  end

  # Commands that also reads runtime/sources.yml and answers a download
  # with its file name, for a recipe that builds a pinned source.
  class Pinned < Commands
    attr_reader :sources

    def initialize(sources)
      super()
      @sources = sources
    end

    def fetch(url, _sha256)
      File.basename(url)
    end
  end

  # gcc's analyzer checks every musl launcher source, warnings as errors,
  # as it does on glibc Linux, before anything links.
  def test_a_musl_compile_analyzes_each_source_before_it_links
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "prefix", "include", "ruby-4.0.0", "aarch64-linux-musl"))
      commands = Commands.new
      recipe = RuntimeBuilder::Musl.new(builder: commands, build_dir: dir)
      recipe.instance_variable_set(:@prefix, File.join(dir, "prefix"))
      sources = %w[unix.c scrub.c].map { |file| File.join(RuntimeBuilder::Recipe::LAUNCHER, file) }

      recipe.compile(File.join(dir, "launcher"), sources, "$ORIGIN/lib")

      analyzed = commands.ran.take(2)
      assert_equal sources, analyzed.map { |command| command[-3] }
      analyzed.each { |command| assert_equal %w[cc -fanalyzer -Werror -std=gnu11], command.take(4) }
      assert_includes commands.ran[2], "-O2"
    end
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
