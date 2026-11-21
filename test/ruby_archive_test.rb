# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "test_helper"
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
end
