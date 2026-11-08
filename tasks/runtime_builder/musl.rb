# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require "etc"
require "fileutils"
require "rbconfig"
require_relative "unix"

class RuntimeBuilder
  # musl Linux (Alpine and the CI images built on it): CRuby built from
  # its pinned source on the computer it is for, as ADR 001's fallback
  # and python-build-standalone build Python, because rv-ruby's musl
  # builds link the standard library's extensions into their own
  # bin/ruby, where a launcher linked against their libruby cannot reach
  # them (Plan 001, spike 1; ADR 017). It is configured as rv-ruby's
  # glibc builds are, a static libruby that finds its library from the
  # program that holds it, with YJIT, but with each extension a shared
  # object, as on glibc, and OpenSSL, libyaml, libffi, and zlib built
  # from their pinned sources and linked statically into the extensions
  # that use them. musl itself is the computer's: every musl Linux has
  # it, as every glibc Linux has glibc, and its own crypt(3) serves
  # String#crypt, so no libxcrypt ships.
  class Musl < Unix
    # The only libraries the launcher and bin/ruby may need: musl's C
    # library, which is also its dynamic linker.
    ALLOWED = /\A(?:libc\.musl-(?:x86_64|aarch64)\.so\.1|ld-musl-(?:x86_64|aarch64)\.so\.1)\z/

    # The architecture of each musl target, as OpenSSL's Configure names
    # its Linux targets.
    ARCHES = { "x86_64-linux-musl" => "x86_64", "aarch64-linux-musl" => "aarch64" }.freeze

    def compile(output, sources, _rpath)
      cc = ENV.fetch("CC", "cc")
      analyze_with_gcc(cc, sources)
      static = File.join(@prefix, "lib", "libruby-static.a")
      FileUtils.mkdir_p(File.dirname(output))
      @builder.run(cc, "-std=gnu11", "-O2", *WARNINGS, *includes, *sources, "-rdynamic", "-static-libgcc",
        "-Wl,--whole-archive", static, "-Wl,--no-whole-archive", *libruby_libraries, "-o", output)
      @builder.run("strip", "--strip-unneeded", output)
      check_dynamic_section(output)
    end

    def finish(stage)
      Dir.glob(File.join(stage, "lib", "ruby", "**", "*.so")).each do |extension|
        @builder.run("strip", "--strip-debug", extension)
      end
      copy_appimage_runtime(File.join(stage, "tools", "appimage-runtime"))
    end

    # Builds Ruby, and the libraries its extensions link statically, from
    # their pinned sources, installs it into a prefix of its own, with
    # Mozilla's CA certificates as libexec/cert.pem where rv-ruby keeps
    # them, and returns the prefix, which the Unix recipe copies a runtime
    # from as it copies rv-ruby's.
    private def unpack_ruby
      deps = File.join(@build_dir, "deps")
      %w[zlib libyaml libffi].each { |name| build_autotools(name, deps) }
      build_openssl(deps)
      prefix = File.join(@build_dir, "prefix")
      source = unpack(pin("ruby"), "ruby")
      build = File.join(@build_dir, "ruby-build")
      FileUtils.rm_rf([build, prefix])
      FileUtils.mkdir_p(build)
      logged("ruby-configure", File.join(source, "configure"), *configure_options(prefix, deps), chdir: build)
      logged("ruby-make", "make", "-j#{Etc.nprocessors}", chdir: build)
      logged("ruby-install", "make", "install-nodoc", chdir: build)
      ca = pin("ca-certificates")
      FileUtils.mkdir_p(File.join(prefix, "libexec"))
      FileUtils.cp(@builder.fetch(ca.fetch("url"), ca.fetch("sha256")), File.join(prefix, "libexec", "cert.pem"))
      find_certificates(prefix)
      prefix
    end

    #--
    # SPDX-SnippetBegin
    # SPDX-License-Identifier: BSD-2-Clause
    # SPDX-SnippetCopyrightText: Homebrew contributors
    # SPDX-SnippetComment: Adapted from rv-ruby's Formula/rv-portable-openssl.rb
    #   (line 77) and Abstract/rv-ruby.rb (lines 203 to 208) at
    #   spinel-coop/rv-ruby 7a0e584a71246aaaf5572547b53670267935aaed.
    #++
    # OpenSSL bakes its certificate folder in when it is built, so a Ruby
    # that moves finds no certificates. rv-ruby renames the variable
    # OpenSSL reads them from, so that no other program's OpenSSL takes
    # it, and has Ruby's openssl.rb point it at libexec/cert.pem beside
    # the Ruby, unless SSL_CERT_FILE names others; every glibc runtime
    # carries that, so the musl runtimes do too.
    PORTABLE_CERT_FILE = "PORTABLE_RUBY_SSL_CERT_FILE"

    private def rename_certificate_variable(source)
      header = File.join(source, "include", "internal", "common.h")
      text = File.read(header)
      raise "#{header} no longer names SSL_CERT_FILE" unless text.include?('"SSL_CERT_FILE"')

      File.write(header, text.sub('"SSL_CERT_FILE"', "\"#{PORTABLE_CERT_FILE}\""))
    end

    private def find_certificates(prefix)
      openssl_rb = File.join(prefix, "lib", "ruby", "4.0.0", "openssl.rb")
      text = File.read(openssl_rb)
      raise "#{openssl_rb} no longer requires 'openssl.so'" unless text.include?("require 'openssl.so'")

      File.write(openssl_rb, text.sub("require 'openssl.so'", <<~RUBY.chomp))
        ENV["#{PORTABLE_CERT_FILE}"] = ENV["SSL_CERT_FILE"] || File.expand_path("../../libexec/cert.pem", RbConfig.ruby)
        require 'openssl.so'
      RUBY
    end
    #--
    # SPDX-SnippetEnd
    #++

    private def configure_options(prefix, deps)
      [
        "--prefix=#{prefix}",
        "--enable-load-relative",
        "--disable-shared",
        "--enable-yjit",
        "--disable-install-doc",
        "--disable-install-rdoc",
        "--with-baseruby=#{RbConfig.ruby}",
        "--with-openssl-dir=#{deps}",
        "--with-libyaml-dir=#{deps}",
        "--with-libffi-dir=#{deps}",
        "--with-zlib-dir=#{deps}",
        "--without-gmp",
        "--with-out-ext=win32,win32ole",
        "LDFLAGS=-static-libgcc",
      ]
    end

    # The libraries libruby-static.a needs, as its own Ruby links them
    # (RbConfig's LIBS), which on musl are all in its C library.
    private def libruby_libraries
      %w[-lm -lpthread]
    end

    private def build_autotools(name, prefix)
      source = unpack(pin(name), name)
      options = (name == "zlib") ? ["--static"] : ["--disable-shared", "--enable-static", "--with-pic"]
      options += %w[--disable-docs --disable-multi-os-directory] if name == "libffi"
      logged("#{name}-configure", "./configure", "--prefix=#{prefix}", "--libdir=#{File.join(prefix, 'lib')}", *options,
        chdir: source, env: { "CFLAGS" => "-O2 -fPIC" })
      logged("#{name}-make", "make", "-j#{Etc.nprocessors}", chdir: source)
      logged("#{name}-install", "make", "install", chdir: source)
    end

    private def build_openssl(prefix)
      source = unpack(pin("openssl"), "openssl")
      rename_certificate_variable(source)
      target = "linux-#{ARCHES.fetch(@builder.platform.name)}"
      logged("openssl-configure", "./Configure", target, "no-shared", "no-tests", "no-apps", "no-docs", "no-module", "-fPIC",
        "--prefix=#{prefix}", "--libdir=lib", "--openssldir=/etc/ssl", chdir: source)
      logged("openssl-make", "make", "-j#{Etc.nprocessors}", "build_libs", chdir: source)
      logged("openssl-install", "make", "install_dev", chdir: source)
    end

    private def pin(name)
      @builder.sources.fetch("musl-ruby").fetch(name)
    end

    private def unpack(pin, name)
      tarball = @builder.fetch(pin.fetch("url"), pin.fetch("sha256"))
      folder = File.join(@build_dir, "sources", name)
      FileUtils.rm_rf(folder)
      FileUtils.mkdir_p(folder)
      @builder.run("tar", "-xzf", tarball, "-C", folder, "--strip-components=1")
      folder
    end

    private def logged(name, *command, chdir:, env: {})
      path = File.join(@build_dir, "logs", "#{name}.log")
      FileUtils.mkdir_p(File.dirname(path))
      @builder.run(env, *command, chdir:, out: path, err: [:child, :out])
    rescue RuntimeError
      warn File.readlines(path).last(150).join
      raise
    end

    private def copy_appimage_runtime(to)
      pin = @builder.sources.fetch("appimage-runtime").fetch("platforms").fetch(@builder.platform.name)
      FileUtils.mkdir_p(File.dirname(to))
      FileUtils.cp(@builder.fetch(pin.fetch("url"), pin.fetch("sha256")), to)
      FileUtils.chmod(0o755, to)
    end

    private def os_file
      "linux.c"
    end

    private def check_dynamic_section(output)
      dynamic = @builder.capture("readelf", "-d", output)
      needed = dynamic.scan(/\(NEEDED\)\s+Shared library: \[([^\]]+)\]/).flatten
      foreign = needed.grep_v(ALLOWED)
      raise "#{output} needs libraries a musl Linux does not have: #{foreign.join(', ')}" unless foreign.empty?
    end
  end
end
