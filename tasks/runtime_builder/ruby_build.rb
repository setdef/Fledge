# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require "etc"
require "fileutils"
require "rbconfig"

class RuntimeBuilder
  # Builds CRuby from its pinned release-shaped tarball into a prefix of
  # its own, as rv-ruby builds its portable Rubies: a static libruby
  # that finds its library from the program that holds it, YJIT, every
  # extension a shared object, and OpenSSL, libyaml, libffi, and zlib
  # built from their pins and linked statically into the extensions that
  # use them, with Mozilla's CA certificates as libexec/cert.pem, found
  # as rv-ruby's Ruby finds them (Certificates). The musl recipe builds
  # its Ruby with it, and RubyArchive the Rubies Fledge publishes for
  # glibc Linux and macOS (doc/contributors/design/runtimes.md, "Fledge's
  # own Ruby builds").
  #
  # Ruby is built in its source folder, as rv-ruby builds it
  # (Abstract/rv-ruby.rb, lines 157 to 174, at spinel-coop/rv-ruby
  # f57186e): tool/rbinstall.rb writes each default gem's specification
  # from its gemspec in the folder make runs in, and built beside its
  # source, io-nonblock's specification keeps RubyGems from activating
  # the gem for require "io/nonblock" (Mobile#build_target).
  class RubyBuild
    # +pins+ holds the pins of ruby, openssl, libyaml, libffi, zlib, and
    # ca-certificates; +edits+ names the RubySource edits Ruby takes;
    # +openssl_target+ is OpenSSL's Configure target; +options+ are
    # configure options beyond the common ones, and +ldflags+ the LDFLAGS
    # Ruby links with. A +library_path+ names a prefix of other libraries
    # Ruby's configure may find (libxcrypt's, on glibc Linux), and +env+
    # sets variables of every step's environment (the Rust compiler's
    # PATH, say).
    def initialize(builder:, build_dir:, pins:, edits:, openssl_target:, options: [], ldflags: "-static-libgcc",
      library_path: nil, env: {}
    )
      @builder = builder
      @build_dir = build_dir
      @pins = pins
      @edits = edits
      @openssl_target = openssl_target
      @options = options
      @ldflags = ldflags
      @library_path = library_path
      @env = env
    end

    # Builds the libraries and Ruby, installs Ruby into +prefix+, and
    # returns it.
    def call(prefix = File.join(@build_dir, "prefix"))
      deps = File.join(@build_dir, "deps")
      %w[zlib libyaml libffi].each { |name| build_autotools(name, deps) }
      build_openssl(deps)
      FileUtils.rm_rf(prefix)
      source = unpack(@pins.fetch("ruby"), "ruby")
      RubySource.apply(source, @edits)
      logged("ruby-configure", "./configure", *configure_options(prefix, deps), chdir: source)
      logged("ruby-make", "make", "-j#{Etc.nprocessors}", chdir: source)
      logged("ruby-install", "make", "install-nodoc", chdir: source)
      ca = @pins.fetch("ca-certificates")
      FileUtils.mkdir_p(File.join(prefix, "libexec"))
      FileUtils.cp(@builder.fetch(ca.fetch("url"), ca.fetch("sha256")), File.join(prefix, "libexec", "cert.pem"))
      Certificates.point_openssl_rb(File.join(prefix, "lib", "ruby"))
      prefix
    end

    # With Mobile::NO_GIT, the build takes the bundled gems the pinned
    # tarball carries in gems/, and downloads none.
    def configure_options(prefix, deps)
      [
        Mobile::NO_GIT,
        "--prefix=#{prefix}",
        "--enable-load-relative",
        "--disable-shared",
        "--enable-yjit",
        *@options,
        "--disable-install-doc",
        "--disable-install-rdoc",
        "--with-baseruby=#{RbConfig.ruby}",
        "--with-openssl-dir=#{deps}",
        "--with-libyaml-dir=#{deps}",
        "--with-libffi-dir=#{deps}",
        "--with-zlib-dir=#{deps}",
        "--without-gmp",
        "--with-out-ext=win32,win32ole",
        *(@library_path ? ["CPPFLAGS=-I#{File.join(@library_path, 'include')}"] : []),
        "LDFLAGS=#{[*(@library_path ? ["-L#{File.join(@library_path, 'lib')}"] : []), @ldflags].join(' ')}",
      ]
    end

    private def build_autotools(name, prefix)
      source = unpack(@pins.fetch(name), name)
      options = (name == "zlib") ? ["--static"] : ["--disable-shared", "--enable-static", "--with-pic"]
      options += %w[--disable-docs --disable-multi-os-directory] if name == "libffi"
      logged("#{name}-configure", "./configure", "--prefix=#{prefix}", "--libdir=#{File.join(prefix, 'lib')}", *options,
        chdir: source, env: { "CFLAGS" => "-O2 -fPIC" })
      logged("#{name}-make", "make", "-j#{Etc.nprocessors}", chdir: source)
      logged("#{name}-install", "make", "install", chdir: source)
    end

    private def build_openssl(prefix)
      source = unpack(@pins.fetch("openssl"), "openssl")
      Certificates.rename_variable(source)
      logged("openssl-configure", "./Configure", @openssl_target, "no-shared", "no-tests", "no-apps", "no-docs", "no-module",
        "-fPIC", "--prefix=#{prefix}", "--libdir=lib", "--openssldir=/etc/ssl", chdir: source)
      logged("openssl-make", "make", "-j#{Etc.nprocessors}", "build_libs", chdir: source)
      logged("openssl-install", "make", "install_dev", chdir: source)
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
      @builder.run(@env.merge(env), *command, chdir:, out: path, err: [:child, :out])
    rescue RuntimeError
      warn File.readlines(path).last(150).join
      raise
    end
  end
end
