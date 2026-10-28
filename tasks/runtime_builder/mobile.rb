# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "etc"
require "fileutils"
require "rbconfig"
require_relative "recipe"

class RuntimeBuilder
  # iOS and iPadOS, and Android: CRuby built from its own source for a
  # phone, interpreter only, with every extension linked in (ADR 011).
  #
  # No prebuilt Ruby exists for a phone, so a mobile runtime is built as
  # xord/cruby (the runtime behind RubySketch on the App Store) and
  # Termux build theirs, after the mobile spike (branch spike/mobile,
  # spike/mobile/FINDINGS.txt): Ruby's own configure and make, cross-
  # compiling for each target with Xcode's or the NDK's compiler, against
  # OpenSSL and libyaml built the same way, with --with-static-linked-ext
  # and no JIT. A miniruby built for the build machine from the same
  # source writes the builtin binary a cross build cannot (ADR 011,
  # section 3), and the bundled gems with C extensions stay gems
  # (BundledExtensions). Each subclass names its targets' toolchains and
  # packs what they built: an XCFramework for iOS (IOS), an AAR for
  # Android (Android).
  class Mobile < Recipe
    # One slice of a mobile runtime: the target name Fledge gives it
    # (ADR 011, section 1), what Ruby calls its platform there, its
    # compiler's target triple, OpenSSL's name for it, and for iOS the
    # SDK and XCFramework slice, or for Android the ABI.
    class Target < Data.define(:name, :ruby_platform, :triple, :openssl, :sdk, :slice, :abi)
      def self.new(name:, ruby_platform:, triple:, openssl:, sdk: nil, slice: nil, abi: nil)
        super
      end
    end

    # A mobile runtime: its name, which its release assets carry, the
    # platforms whose computers build it, and its targets.
    class Platform < Data.define(:name, :hosts, :targets)
      def windows?
        false
      end

      def to_s
        name
      end
    end

    # The oldest iOS a runtime runs on, xord/cruby's floor and the spike's.
    IOS_MINIMUM = "15.0"

    # The oldest Android: API 26, Android 8.0, the first whose C library
    # has nl_langinfo, which Ruby's localeinit.c calls.
    ANDROID_API = 26

    PLATFORMS = {
      "ios" => Platform.new(name: "ios", hosts: %w[arm64-darwin], targets: [
        Target.new(name: "arm64-ios", ruby_platform: "arm64-darwin", triple: "arm64-apple-ios#{IOS_MINIMUM}", openssl: "ios64-xcrun",
          sdk: "iphoneos", slice: "ios-arm64"),
        Target.new(name: "arm64-ios-simulator", ruby_platform: "arm64-darwin", triple: "arm64-apple-ios#{IOS_MINIMUM}-simulator",
          openssl: "iossimulator-arm64-xcrun", sdk: "iphonesimulator", slice: "ios-arm64-simulator"),
      ]),
      "android" => Platform.new(name: "android", hosts: %w[x86_64-linux arm64-darwin], targets: [
        Target.new(name: "aarch64-linux-android", ruby_platform: "aarch64-linux-android", triple: "aarch64-linux-android",
          openssl: "android-arm64", abi: "arm64-v8a"),
        Target.new(name: "x86_64-linux-android", ruby_platform: "x86_64-linux-android", triple: "x86_64-linux-android",
          openssl: "android-x86_64", abi: "x86_64"),
      ]),
    }.freeze

    # Where the embedding API's C lives (ADR 011, section 5).
    MOBILE = File.join(ROOT, "runtime", "mobile")

    # Static libruby, as Ruby's build names it: libruby-static.a, or on
    # Apple systems libruby.4.0-static.a.
    LIBRUBY = /\Alibruby(?:\.[\d.]+)?-static\.a\z/

    # The ABI version of a Ruby without a shared libruby, as RubyGems
    # names its extension folders (Gem.extension_api_version).
    EXTENSION_API = "4.0.0-static"

    def hosts
      @builder.platform.hosts
    end

    def build(stage)
      @source = prepare_source
      @host = build_host_miniruby
      @roots = @builder.platform.targets.to_h { |target| [target, build_target(target)] }
      package(stage)
    end

    private def pin(name)
      @builder.sources.fetch("mobile").fetch(name)
    end

    # Ruby's release tarball, unpacked once for every target of the
    # runtime (each configures in a folder of its own), with this
    # platform's edits made and the bundled gems' extensions copied among
    # Ruby's own.
    private def prepare_source
      source = unpack(pin("ruby"), "ruby")
      RubySource.apply(source, edits)
      @kept = BundledExtensions.copy(source, omit: omitted_gems)
      @without = [*BundledExtensions.without(source), "win32", "win32ole"].uniq
      source
    end

    # The bundled gems this platform leaves out: none but on iOS.
    private def omitted_gems
      []
    end

    # Unpacks the tarball +pin+ names into a fresh folder named +name+
    # and returns the folder it holds.
    private def unpack(pin, name)
      tarball = @builder.fetch(pin.fetch("url"), pin.fetch("sha256"))
      folder = File.join(@build_dir, "sources", name)
      FileUtils.rm_rf(folder)
      FileUtils.mkdir_p(folder)
      @builder.run("tar", "-xzf", tarball, "-C", folder, "--strip-components=1")
      folder
    end

    # A miniruby for the build machine, from the same source: a cross
    # build cannot run its own miniruby, so configure.ac (lines 1584 to
    # 1588 at 4.0.9) leaves out the builtin binary, and builtin.c falls
    # back to mini_builtin.c, which never loads gem_prelude, so the Ruby
    # boots with no RubyGems. An iseq binary depends only on Ruby's
    # version, endianness, and word size (compile.c,
    # ibf_load_setup_bytes), so this miniruby writes the one the target's
    # Ruby would.
    private def build_host_miniruby
      host = File.join(@build_dir, "host")
      FileUtils.mkdir_p(host)
      logged("host-configure", File.join(@source, "configure"), "--disable-shared", "--disable-yjit", "--disable-zjit",
        "--disable-install-doc", "--with-baseruby=#{RbConfig.ruby}", chdir: host, env: host_environment)
      logged("host-make", "make", "-j#{Etc.nprocessors}", "miniruby", chdir: host, env: host_environment)
      host
    end

    # The build machine's own compiler, whatever a cross build set.
    private def host_environment
      %w[CC CXX CFLAGS CPPFLAGS LDFLAGS AR RANLIB IPHONEOS_DEPLOYMENT_TARGET].to_h { |name| [name, nil] }
    end

    # Builds Ruby, with the libraries it links, for +target+, and
    # returns the folder it installed into: its prefix, lib/ruby and
    # include/ among it, with Fledge's RubyGems defaults, pruned as a
    # desktop runtime prunes Ruby (ADR 003, section 2).
    private def build_target(target)
      deps = build_dependencies(target)
      build = File.join(@build_dir, target.name, "ruby")
      root = File.join(@build_dir, target.name, "root")
      FileUtils.rm_rf([build, root])
      FileUtils.mkdir_p(build)
      logged("#{target.name}-configure", File.join(@source, "configure"), *configure_options(target, deps), chdir: build,
        env: environment(target))
      use_host_builtin_binary(build)
      logged("#{target.name}-make", "make", "-j#{Etc.nprocessors}", chdir: build, env: environment(target))
      BundledExtensions.mark_built(build, @kept, platform: target.ruby_platform, api: EXTENSION_API)
      logged("#{target.name}-install", "make", "install-nodoc", "DESTDIR=#{root}", chdir: build, env: environment(target))
      finish_tree(target, root)
      @archives ||= {}
      @archives[target] = archives(build, deps)
      root
    end

    private def finish_tree(target, root)
      gems = File.join(root, "lib", "ruby", "gems", "4.0.0")
      BundledExtensions.check_installed(gems, @kept, platform: target.ruby_platform, api: EXTENSION_API)
      Pruning.prune(File.join(root, "lib", "ruby"), @builder.bundled_gems)
      @builder.install_rubygems_defaults(File.join(root, "lib", "ruby"))
    end

    # What configure is told for every target: a static Ruby, every
    # extension linked in, interpreter only, finding its library relative
    # to itself, built with the libraries built for the target and none
    # of the build machine's (PKG_CONFIG=false), and without GMP (LGPL),
    # Windows' extensions, or the bundled gems' own builds (their
    # extensions are linked in among Ruby's; BundledExtensions).
    private def configure_options(target, deps)
      [
        "--host=#{host_triple(target)}",
        "--target=#{host_triple(target)}",
        "--prefix=/",
        "--enable-load-relative",
        "--disable-shared",
        "--with-static-linked-ext",
        "--disable-yjit",
        "--disable-zjit",
        "--disable-install-doc",
        "--disable-install-rdoc",
        "--with-baseruby=#{RbConfig.ruby}",
        "--with-openssl-dir=#{deps.fetch(:openssl)}",
        "--with-libyaml-dir=#{deps.fetch(:libyaml)}",
        "--without-gmp",
        "--with-out-ext=#{@without.join(',')}",
        "PKG_CONFIG=false",
        *target_options(target, deps),
      ]
    end

    # Writes the build machine's builtin binary into the target's build
    # folder, and keeps make from replacing it with the empty stub a cross
    # build writes: a rule after GNUmakefile's includes overrides
    # common.mk's recipe.
    private def use_host_builtin_binary(build)
      binary = File.join(build, "builtin_binary.rbbin")
      @builder.run(File.join(@host, "miniruby"), "-I#{File.join(@source, 'lib')}", "-I.", "-I.ext/common",
        File.join(@source, "tool", "generic_erb.rb"), "-o", binary, File.join(@source, "template", "builtin_binary.rbbin.tmpl"),
        chdir: @host)
      raise "#{binary} holds no builtin binary" unless File.read(binary).include?("BUILTIN_BINARY_SIZE")

      makefile = File.join(build, "Makefile")
      text = File.read(makefile)
      raise "#{makefile} has no BUILTIN_BINARY = no" unless text.match?(/^BUILTIN_BINARY = no$/)

      File.write(makefile, text.sub(/^BUILTIN_BINARY = no$/, "BUILTIN_BINARY = yes"))
      File.write(File.join(build, "GNUmakefile"), "\nbuiltin_binary.rbbin: ; @:\n", mode: "a")
    end

    # Every static archive Ruby's build made for the target (libruby,
    # each extension's, the encodings' and transcoders'), the objects
    # that register the extensions and encodings (extinit.o, encinit.o),
    # and the libraries built for it.
    private def archives(build, deps)
      ruby = Dir.glob("**/*.a", base: build).reject { |path| path.start_with?(".bundle/") || path == "libruby.a" }.sort
      raise "#{build} built no static libruby" unless ruby.any? { |path| path.match?(LIBRUBY) }

      libraries = deps.values.flat_map { |prefix| Dir.glob(File.join(prefix, "lib", "*.a")) }.sort
      [*ruby.map { |path| File.join(build, path) }, File.join(build, "ext", "extinit.o"), File.join(build, "enc", "encinit.o"), *libraries]
    end

    # Builds libyaml, OpenSSL, and on Android libffi for +target+, once,
    # and returns each one's prefix by name.
    private def build_dependencies(target)
      prefixes = {}
      prefixes[:libyaml] = build_autotools("libyaml", target)
      prefixes[:openssl] = build_openssl(target)
      prefixes[:libffi] = build_autotools("libffi", target, "--disable-docs", "--disable-multi-os-directory") if needs_libffi?
      prefixes
    end

    private def needs_libffi?
      false
    end

    private def build_autotools(name, target, *options)
      prefix = File.join(@build_dir, target.name, name)
      return prefix if Dir.glob(File.join(prefix, "lib", "*.a")).any?

      source = unpack(pin(name), "#{target.name}-#{name}")
      logged("#{target.name}-#{name}-configure", "./configure", "--host=#{host_triple(target)}", "--prefix=#{prefix}",
        "--enable-static", "--disable-shared", "--with-pic", *options, chdir: source, env: environment(target))
      logged("#{target.name}-#{name}-make", "make", "-j#{Etc.nprocessors}", "install", chdir: source, env: environment(target))
      prefix
    end

    # OpenSSL with its own target for the platform, no shared library, no
    # programs, tests, or documents, and no loadable modules.
    private def build_openssl(target)
      prefix = File.join(@build_dir, target.name, "openssl")
      return prefix if File.file?(File.join(prefix, "lib", "libssl.a"))

      source = unpack(pin("openssl"), "#{target.name}-openssl")
      logged("#{target.name}-openssl-configure", "./Configure", target.openssl, "no-shared", "no-tests", "no-apps", "no-docs",
        "no-module", *openssl_options(target), "--prefix=#{prefix}", "--libdir=lib", chdir: source, env: openssl_environment(target))
      logged("#{target.name}-openssl-make", "make", "-j#{Etc.nprocessors}", "build_libs", chdir: source, env: openssl_environment(target))
      logged("#{target.name}-openssl-install", "make", "install_dev", chdir: source, env: openssl_environment(target))
      prefix
    end

    # Copies the pinned CA certificates into the folder +libexec+ as
    # cert.pem, where a desktop runtime keeps rv-ruby's copy of the same
    # file and the embedding API points OpenSSL (SSL_CERT_FILE).
    private def copy_certificates(libexec)
      certificates = pin("ca-certificates")
      FileUtils.mkdir_p(libexec)
      FileUtils.cp(@builder.fetch(certificates.fetch("url"), certificates.fetch("sha256")), File.join(libexec, "cert.pem"))
    end

    # A file in the build folder that a command's output goes to.
    private def log(name)
      FileUtils.mkdir_p(File.join(@build_dir, "logs"))
      File.join(@build_dir, "logs", "#{name}.log")
    end

    # Runs +command+ with its output in the log +name+, and when it fails,
    # prints the log's last lines before raising, since make's errors
    # come at the end of thousands of lines.
    private def logged(name, *command, chdir:, env: {})
      path = log(name)
      @builder.run(env, *command, chdir:, out: path, err: [:child, :out])
    rescue RuntimeError
      lines = File.readlines(path)
      warn lines.last(150).join
      raise
    end
  end
end
