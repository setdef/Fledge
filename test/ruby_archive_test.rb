# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "test_helper"
require_relative "support/binaries"
require_relative "support/ca_bundles"
require_relative "../tasks/ruby_archive"

class RubyArchiveTest < Minitest::Test
  SOURCES = YAML.safe_load_file(File.join(RuntimeBuilder::ROOT, "runtime", "sources.yml"))

  # Stands in for the builder, keeping the commands it would run and
  # answering a download with its file name.
  class Commands
    attr_reader :ran

    def initialize
      @ran = []
    end

    def sources
      SOURCES
    end

    def run(*command, **)
      @ran << command
    end

    def fetch(url, _sha256)
      File.basename(url)
    end
  end

  def archive(platform, work, commands = Commands.new)
    RubyArchive.new(platform: Fledge::Platform.find(platform), work:, builder: commands)
  end

  # The archive's Ruby is ruby-build's source, built with the libraries
  # and certificates the musl runtimes' Ruby takes.
  def test_ruby_builds_from_its_own_source_pin_and_musl_rubys_libraries
    pins = archive("x86_64-linux", "work").pins

    assert_equal SOURCES.dig("ruby-build", "ruby"), pins.fetch("ruby")
    %w[openssl libyaml libffi zlib ca-certificates].each { |name| assert_equal SOURCES.dig("musl-ruby", name), pins.fetch(name) }
    assert_equal SOURCES.dig("ruby-build", "ruby", "version"), archive("arm64-darwin", "work").version
  end

  # Lota runs both JITs, so ZJIT is asked for and a build without it
  # fails; on glibc Linux, configure finds the libxcrypt built beside it.
  def test_glibc_ruby_configures_zjit_and_the_libxcrypt_it_links
    Dir.mktmpdir do |dir|
      build = archive("x86_64-linux", dir).ruby_build("/xcrypt")
      options = build.configure_options("/prefix", "/deps")

      assert_equal "/xcrypt/lib", build.instance_variable_get(:@env).fetch("LD_LIBRARY_PATH")
      assert_includes options, "--enable-yjit"
      assert_includes options, "--enable-zjit"
      assert_includes options, "CPPFLAGS=-I/xcrypt/include"
      assert_includes options, "LDFLAGS=-L/xcrypt/lib -static-libgcc"
    end
  end

  # Lota and Tokra compile extensions against the archive wherever it is
  # unpacked, so what Ruby's install recorded of the build folder in
  # rbconfig.rb and ruby.pc is rewritten, and the check refuses an
  # archive in which any of it is left.
  def test_rbconfig_and_pkg_config_name_no_folder_of_the_build
    Dir.mktmpdir do |work|
      ruby = archive("x86_64-linux", work)
      build = File.join(work, "x86_64-linux")
      prefix = File.join(build, "ruby", ruby.version)
      xcrypt = File.join(build, "libxcrypt-prefix")
      deps = File.join(build, "deps")
      rbconfig = File.join(prefix, "lib", "ruby", "4.1.0+5", "x86_64-linux", "rbconfig.rb")
      pc = File.join(prefix, "lib", "pkgconfig", "ruby-4.1.pc")
      FileUtils.mkdir_p([File.dirname(rbconfig), File.dirname(pc), File.join(prefix, "include")])
      File.write(rbconfig, <<~RUBY)
        CONFIG["prefix"] = (TOPDIR || DESTDIR + "#{prefix}")
        CONFIG["configure_args"] = " '--prefix=#{prefix}' '--enable-load-relative' '--with-openssl-dir=#{deps}' '--with-libyaml-dir=#{deps}' 'CPPFLAGS=-I#{xcrypt}/include' 'LDFLAGS=-L#{xcrypt}/lib -static-libgcc'"
        CONFIG["CPPFLAGS"] = "-I#{xcrypt}/include $(DEFS) $(cppflags)"
        CONFIG["LDFLAGS"] = "-L. -L#{xcrypt}/lib -static-libgcc -fstack-protector-strong"
      RUBY
      File.write(pc, "prefix=#{prefix}\nexec_prefix=${prefix}\nlibdir=${exec_prefix}/lib\nLDFLAGS=-L. -L#{xcrypt}/lib -static-libgcc\n")

      ruby.relocate(prefix, xcrypt)
      ruby.check_relocated(prefix)

      assert_equal <<~RUBY, File.read(rbconfig)
        CONFIG["prefix"] = (TOPDIR || DESTDIR + "/ruby/#{ruby.version}")
        CONFIG["configure_args"] = " '--prefix=/ruby/#{ruby.version}' '--enable-load-relative' 'CPPFLAGS=' 'LDFLAGS=-L$(libdir) -static-libgcc'"
        CONFIG["CPPFLAGS"] = "$(DEFS) $(cppflags)"
        CONFIG["LDFLAGS"] = "-L. -L$(libdir) -static-libgcc -fstack-protector-strong"
      RUBY
      assert_equal "prefix=${pcfiledir}/../..\nexec_prefix=${prefix}\nlibdir=${exec_prefix}/lib\nLDFLAGS=-L. -L${libdir} -static-libgcc\n",
        File.read(pc)
      File.write(File.join(prefix, "include", "config.h"), "#define SOMEWHERE \"#{deps}/include\"\n")
      error = assert_raises(RuntimeError) { ruby.check_relocated(prefix) }
      assert_includes error.message, "config.h: #define SOMEWHERE"
    end
  end

  # rustc and its standard library come from their pins, installed by
  # each tarball's own installer into one prefix that leads PATH for
  # every step, and a Mac's build targets the macOS floor.
  def test_the_pinned_rust_leads_the_builds_path
    Dir.mktmpdir do |dir|
      commands = Commands.new
      build = archive("arm64-darwin", dir, commands).ruby_build(nil)
      env = build.instance_variable_get(:@env)

      rust = File.join(dir, "arm64-darwin", "rust")
      assert_equal File.join(rust, "bin"), env.fetch("PATH").split(File::PATH_SEPARATOR).first
      assert_equal Fledge::Platform::MACOS_MINIMUM, env.fetch("MACOSX_DEPLOYMENT_TARGET")
      installs = commands.ran.select { |command| command.first == "sh" }
      assert_equal [["sh", "install.sh", "--prefix=#{rust}", "--disable-ldconfig"]] * 2, installs
      unpacked = commands.ran.select { |command| command.first == "tar" }.map { |command| command[2] }
      assert_equal %w[rustc-1.99.1-aarch64-apple-darwin.tar.xz rust-std-1.99.1-aarch64-apple-darwin.tar.xz], unpacked
      refute build.configure_options("/prefix", "/deps").any? { |option| option.start_with?("CPPFLAGS") }
    end
  end

  # Apple's clang refuses -static-libgcc ("unsupported option"), and with
  # it Ruby's configure finds no working compiler, so a Mac's build
  # passes no LDFLAGS of its own; macOS has no libgcc to take statically.
  def test_a_macs_build_links_with_no_libgcc_flag
    Dir.mktmpdir do |dir|
      options = archive("arm64-darwin", dir).ruby_build(nil).configure_options("/prefix", "/deps")

      refute options.any? { |option| option.start_with?("LDFLAGS") }, options.inspect
    end
  end

  # What the archive carries is what a runtime carries (doc/contributors/
  # design/license-audit.md): NOTICES.txt and the SBOM in notices/, and
  # the source of its LGPL library in notices/sources/, made by the
  # license audit, which refuses an archive holding a file nothing
  # accounts for.
  def test_the_archive_carries_notices_an_sbom_and_the_source_of_its_lgpl_library
    TestReaders.need(self, :elf)
    Dir.mktmpdir do |dir|
      prefix = File.join(dir, "ruby", "4.1.0-preview1")
      work = File.join(dir, "work")
      ruby = archive("x86_64-linux", work, RuntimeBuilder.new(platform: Fledge::Platform.find("x86_64-linux"), work:))
      rust = "/rustc/58cf8f9c35b355199727627d07ae34a4e2846d67/"
      openssl = SOURCES.dig("musl-ruby", "openssl", "version")
      files = {
        "bin/ruby" => Binaries.elf(needed: %w[libcrypt.so.2 libc.so.6], payload: "ruby (revision 2d08b5f42f) #{rust} GCC: (Ubuntu 11.4.0)"),
        "lib/libcrypt.so.2" => Binaries.elf(needed: %w[libc.so.6], payload: "XCRYPT_4.4\0yescrypt-ROMhash"),
        "lib/ruby/4.1.0+5/x86_64-linux/openssl.so" => Binaries.elf(needed: %w[libc.so.6], payload: "OpenSSL #{openssl} "),
        "lib/ruby/4.1.0+5/set.rb" => "class Set; end\n",
        "libexec/cert.pem" => CaBundles.curl,
      }
      files.each do |path, bytes|
        FileUtils.mkdir_p(File.dirname(File.join(prefix, path)))
        File.binwrite(File.join(prefix, path), bytes)
      end
      downloads = File.join(dir, "downloads")
      pretend = "pretend libxcrypt"
      FileUtils.mkdir_p(File.join(downloads, Digest::SHA256.hexdigest(pretend)))
      File.write(File.join(downloads, Digest::SHA256.hexdigest(pretend), "libxcrypt-pretend.tar.xz"), pretend)
      sources = File.join(dir, "sources.yml")
      File.write(sources, {
"libxcrypt" => {
"version" => "1.0",
"url" => "https://example.com/libxcrypt-pretend.tar.xz",
"sha256" => Digest::SHA256.hexdigest(pretend),
},
}.to_yaml)
      bundle = LicenseAudit::SourceBundle.new(platform: "x86_64-linux", version: Fledge::VERSION, sources:, downloads:, archive: true)

      ruby.license(prefix, bundle:, readers: TestReaders.all)

      text = File.read(File.join(prefix, "notices", "NOTICES.txt"))
      assert_equal "Fledge's own build of Ruby in this archive", text.lines.first.chomp
      assert_includes text, "notices/sources/libxcrypt/"
      assert_equal "SPDX-2.3", JSON.parse(File.read(File.join(prefix, "notices", "sbom.spdx.json"))).fetch("spdxVersion")
      assert_equal pretend, File.read(File.join(prefix, "notices", "sources", "libxcrypt", "libxcrypt-pretend.tar.xz"))

      File.write(File.join(prefix, "stray.txt"), "nobody's\n")
      failure = assert_raises(LicenseAudit::Failure) { ruby.license(prefix, bundle:, readers: TestReaders.all) }
      assert_includes failure.message, "stray.txt"
    end
  end
end
