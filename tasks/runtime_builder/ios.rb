# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require "digest"
require "fileutils"
require "json"
require "tmpdir"
require_relative "mobile"
require_relative "../../lib/fledge/mobile_project/ios_libraries"

class RuntimeBuilder
  # iOS and iPadOS: Ruby for devices and for the Simulator, both arm64,
  # built with Xcode's compilers after xord/cruby's Rakefile (at 11d62c4,
  # lines 499 to 724), as a shared library with each extension a dynamic
  # library of its own, and packed with Xcode's own tools as an
  # XCFramework of two dynamic frameworks, FledgeRuby.xcframework
  # (doc/contributors/design/phone-runtimes.md, "What a phone runtime
  # holds", and "Ruby's extensions on iOS").
  #
  # Each slice holds FledgeRuby.framework (Ruby and the embedding API,
  # under the install name <tt>@rpath/FledgeRuby.framework/FledgeRuby</tt>,
  # its headers, and a module map, so Swift imports it as FledgeRuby),
  # and, as CPython's XCFramework for iOS does, the Ruby the slice runs:
  # its lib/ruby, with each of Ruby's extensions, encodings, and bundled
  # gems' extensions a dynamic library at its path there, as on a
  # desktop, linked to FledgeRuby; LINKS, which names each one's
  # framework in an app; the privacy manifests of the libraries they
  # link (PRIVACY); Ruby's headers in include/, which mkmf looks for as
  # on a desktop; and its CA certificates in libexec/, which an app
  # copies into its bundle for the slice it builds.
  class IOS < Mobile
    # What iOS declares in its headers but forbids or lacks, for
    # configure (after xord/cruby's Rakefile, line 578): system, which
    # the SDK marks __IOS_PROHIBITED (_stdlib.h); syscall, deprecated
    # there and turned off on macOS too (configure.ac, lines 1155 to
    # 1165); getentropy, which the SDK does not declare; and dup3 and
    # pipe2, which are iOS 27's, past the iOS 15 floor. xord/cruby's list
    # also names backtrace, which the SDK has had since iPhone OS 2.0
    # (execinfo.h, line 39), and with which a [BUG] report lists the C
    # frames, as on macOS, so it is not here.
    MISSING = %w[system syscall __syscall getentropy dup3 pipe2].freeze

    # Ruby's framework, its binary, and the install name an app finds it
    # by.
    FRAMEWORK = "FledgeRuby"
    INSTALL_NAME = "@rpath/#{FRAMEWORK}.framework/#{FRAMEWORK}".freeze

    # The system libraries Ruby's framework links: those the static
    # library's module map had an app link (zlib, Security, and Core
    # Foundation), which the framework's own load commands now name.
    LIBRARIES = %w[-lz -framework Security -framework CoreFoundation].freeze

    # The symbols Ruby's Darwin build keeps out of libruby's exports
    # (configure.ac, lines 3674 to 3679 at 4.1.0-preview1), so that an
    # extension's Init_ function is its own.
    HIDDEN = %w[_Init_* _InitVM_* _ruby_static_id_* *_threadptr_*].freeze

    # The module map of FledgeRuby.framework: a framework's module names
    # no libraries to link, since its binary's own load commands do.
    MODULE_MAP = <<~MAP
      framework module #{FRAMEWORK} {
          header "fledge_ruby.h"
          export *
      }
    MAP

    # The list in each slice of its extensions' frameworks
    # (Fledge::MobileProject::IOSRubyExtensions::LINKS), and the folder
    # of their privacy manifests.
    LINKS = "fledge.links"
    PRIVACY = "privacy"

    # What begins each extension's framework's name.
    EXTENSION = "fledgerubyext"

    # The folders under lib/ruby that Ruby requires an extension from,
    # each followed by the feature: archdir, a gem's lib/, and a gem's
    # extension folder.
    FEATURE = %r{\A(?:[^/]+/[^/]+-darwin|gems/[^/]+/gems/[^/]+/lib|gems/[^/]+/extensions/[^/]+/[^/]+/[^/]+)/(.+\.bundle)\z}

    # A library Apple asks a privacy manifest of, by a symbol that only
    # it defines, and the manifest its own source publishes, in the
    # pinned tarball runtime/sources.yml names
    # (doc/contributors/design/phone-runtimes.md, "Ruby's extensions on
    # iOS").
    MANIFESTS = { "openssl" => ["_OPENSSL_init_crypto", "os-dep/Apple/PrivacyInfo.xcprivacy"] }.freeze

    # The name of the framework of the extension at +path+ under
    # lib/ruby: EXTENSION and its feature, slashes as dots, with any
    # character a bundle identifier does not take as a hyphen.
    def self.extension_name(path)
      feature = path[FEATURE, 1] or raise "lib/ruby/#{path} is in no folder Ruby requires an extension from"

      "#{EXTENSION}.#{feature.tr('/', '.').gsub(/[^A-Za-z0-9.-]/, '-')}"
    end

    # Writes the stub sys/vnode.h the iOS SDK lacks (RubySource), then
    # builds.
    def build(stage)
      @stub = File.join(@build_dir, "stub")
      RubySource.write_vnode_stub(@stub)
      super
    end

    private def edits
      %i[psych_extconf vm_dump ruby_c configure_macos_minimum file_c setproctitle_c]
    end

    private def host_triple(_target)
      "aarch64-apple-darwin"
    end

    private def sysroot(target)
      (@sysroots ||= {})[target.sdk] ||= @builder.capture("xcrun", "--sdk", target.sdk, "--show-sdk-path").strip
    end

    private def compiler(target, name = "clang")
      "#{@builder.capture('xcrun', '--sdk', target.sdk, '--find', name).strip} -target #{target.triple} -isysroot #{sysroot(target)}"
    end

    private def environment(target)
      { "CC" => compiler(target), "CXX" => compiler(target, "clang++"), "IPHONEOS_DEPLOYMENT_TARGET" => IOS_MINIMUM }
    end

    # OpenSSL's own iOS targets; the Simulator's needs its own minimum
    # flag, since with -mios-version-min its assembly is tagged for
    # devices and the Simulator's link fails.
    private def openssl_environment(_target)
      { "IPHONEOS_DEPLOYMENT_TARGET" => IOS_MINIMUM }
    end

    private def openssl_options(target)
      [(target.sdk == "iphonesimulator") ? "-mios-simulator-version-min=#{IOS_MINIMUM}" : "-mios-version-min=#{IOS_MINIMUM}"]
    end

    # Each extension is linked as a dynamic library, which iOS loads from
    # a framework, in place of configure's Darwin default of a bundle
    # (configure.ac, line 3188 at 4.1.0-preview1), against libruby, as
    # --enable-shared links it (lines 3193 to 3195), with room in its
    # header for the install name its framework gets. configure then
    # finds that iOS's linker warns of -undefined dynamic_lookup and
    # leaves it out (lines 3228 to 3249); #check_extension makes sure.
    # CFLAGS hides nothing: configure hides libruby's own names through
    # XCFLAGS (lines 1024 to 1029), which extensions do not take, and an
    # extension's Init function must stay exported for dln.c's dlsym.
    private def target_options(_target, deps)
      ffi = deps.fetch(:libffi)
      [
        *MISSING.map { |name| "ac_cv_func_#{name}=no" },
        "ac_cv_func_setpgrp_void=yes",
        "--with-libffi-dir=#{ffi}",
        "LDSHARED=$(CC) -dynamiclib -Wl,-headerpad_max_install_names",
        "CPPFLAGS=-I#{@stub} -I#{File.join(ffi, 'include')}",
        "CFLAGS=-Os",
        "LDFLAGS=-framework Security -L#{File.join(ffi, 'lib')}",
      ]
    end

    # One framework per slice and the XCFramework of both; then each
    # slice's Ruby beside its framework, with its extensions listed.
    private def package(stage)
      frameworks = @roots.to_h { |target, root| [target, framework(target, root)] }
      xcframework = File.join(stage, "#{FRAMEWORK}.xcframework")
      @builder.run("xcodebuild", "-create-xcframework", *frameworks.values.flat_map { |folder| ["-framework", folder] },
        "-output", xcframework)
      @roots.each do |target, root|
        slice = File.join(xcframework, target.slice)
        raise "#{xcframework} has no slice #{target.slice}" unless File.directory?(slice)

        FileUtils.mkdir_p(File.join(slice, "lib"))
        FileUtils.cp_r(File.join(root, "lib", "ruby"), File.join(slice, "lib", "ruby"))
        FileUtils.cp_r(File.join(root, "include"), File.join(slice, "include"))
        copy_certificates(File.join(slice, "libexec"))
        list_extensions(target, slice, library_line(root))
      end
    end

    # The LINKS line for Ruby's library: where a shared Ruby's install
    # puts it, libdir/LIBRUBY_SO, ROOT/lib/libfledgeruby.dylib, which
    # RbConfig names and ruby/spec looks for, under FRAMEWORK, the
    # framework an app embeds it as. The app's link there leads to the
    # framework's binary, as Android's leads to its libfledgeruby.so
    # (RuntimeBuilder::Android, library_line), so the library is where
    # Ruby says, as under ruby main.rb, and the bundle holds no loose
    # one. Raises unless +root+'s install put it there.
    private def library_line(root)
      path = "lib/lib#{SONAME}.dylib"
      raise "#{root} has no #{path}, which a shared Ruby's install puts at libdir/LIBRUBY_SO" unless File.file?(File.join(root, path))

      "#{FRAMEWORK}\t#{path}\n"
    end

    # FledgeRuby.framework for +target+: Ruby's shared library as Ruby's
    # build links it (template/Makefile.in, lines 354 to 357 at
    # 4.1.0-preview1), from libruby's archive, which already holds
    # dmyext.o and dmyenc.o, by which Ruby loads its extensions and
    # encodings from files (line 346), with LIBRARIES and the embedding
    # API, under INSTALL_NAME in place of the one Ruby's build gave it,
    # and with the symbols Ruby's own Darwin build keeps out of libruby's
    # exports (HIDDEN); its headers, module map, and Info.plist. Local
    # symbols are stripped. OpenSSL, libyaml, and libffi are linked into
    # the extensions that use them, not here.
    private def framework(target, root)
      folder = File.join(@build_dir, target.name, "package")
      FileUtils.rm_rf(folder)
      FileUtils.mkdir_p(folder)
      objects = compile_api(target, root, folder)
      framework = File.join(folder, "#{FRAMEWORK}.framework")
      FileUtils.mkdir_p(File.join(framework, "Modules"))
      binary = File.join(framework, FRAMEWORK)
      @builder.run(*compiler(target).split, "-dynamiclib", "-install_name", INSTALL_NAME, "-Wl,-headerpad_max_install_names",
        *HIDDEN.map { |pattern| "-Wl,-unexported_symbol,#{pattern}" }, *objects,
        *@archives.fetch(target).flat_map { |archive| ["-Wl,-force_load,#{archive}"] }, *LIBRARIES, "-o", binary)
      @builder.run("xcrun", "strip", "-x", binary)
      headers(root, framework)
      File.write(File.join(framework, "Modules", "module.modulemap"), MODULE_MAP)
      info(target, framework)
      framework
    end

    # The framework's Info.plist, with the keys an extension's framework
    # carries (Fledge::MobileProject::IOSLibraries.info), Fledge's own
    # identifier, and Fledge's version.
    private def info(target, framework)
      Dir.mktmpdir("fledge-info") do |work|
        json = File.join(work, "Info.json")
        File.write(json, JSON.generate(Fledge::MobileProject::IOSLibraries.info(FRAMEWORK, identifier: "org.setdef.fledge",
          version: Fledge::VERSION[/\A\d+(?:\.\d+)*/], platform: Fledge::MobileProject::IOSLibraries::PLATFORMS.fetch(target.slice))))
        @builder.run("plutil", "-convert", "xml1", "-o", File.join(framework, "Info.plist"), json)
      end
    end

    # Each dynamic library under +slice+'s lib/ruby: made to find Ruby at
    # INSTALL_NAME, checked (#check_extension), and stripped; listed in
    # LINKS under its framework's name (IOS.extension_name), one name for
    # each file's bytes, since a bundled gem's extension is installed
    # twice; and given the privacy manifest of a library it links that
    # Apple asks one of (MANIFESTS). LINKS begins with +library+, the
    # line for Ruby's own library (#library_line).
    private def list_extensions(target, slice, library)
      ruby = File.join(slice, "lib", "ruby")
      libruby = @builder.capture("xcrun", "otool", "-D", File.join(@build_dir, target.name, "ruby", "lib#{SONAME}.dylib")).lines.last.strip
      named = {} # : Hash[String, String]
      digests = {} # : Hash[String, String]
      lines = Dir.glob("**/*.bundle", base: ruby).sort.filter_map do |path|
        file = File.join(ruby, path)
        next unless File.file?(file) && !File.symlink?(file)

        name = IOS.extension_name(path)
        digest = Digest::SHA256.file(file).hexdigest
        raise "lib/ruby/#{named[name]} and lib/ruby/#{path} would both be #{name}" if named.key?(name) && digests[name] != digest

        named[name] ||= path
        digests[name] = digest
        @builder.run("xcrun", "install_name_tool", "-change", libruby, INSTALL_NAME, file)
        check_extension(file)
        manifest(slice, name, file)
        @builder.run("xcrun", "strip", "-x", file)
        "#{name}\tlib/ruby/#{path}\n"
      end
      File.write(File.join(slice, LINKS), [library, *lines].join)
    end

    # Fails unless +file+ is a dynamic library (MH_DYLIB, mach-o/loader.h)
    # that needs only Apple's libraries and Ruby's, looks up no symbol in
    # whatever image happens to define it (-undefined dynamic_lookup), and
    # exports the Init function dln.c looks it up by: Init_ and the file's
    # name up to its first dot (dln.c, lines 113 to 125 at 4.1.0-preview1).
    private def check_extension(file)
      type = File.binread(file, 16).unpack("V4")
      raise "#{file} is not a 64-bit Mach-O dynamic library" unless type[0] == 0xfeedfacf && type[3] == 6

      needed = @builder.capture("xcrun", "otool", "-L", file).lines.drop(2).map { |line| line.strip.split.first.to_s }
      foreign = needed.reject { |library| library == INSTALL_NAME || library.start_with?("/usr/lib/", "/System/Library/") }
      raise "#{file} needs libraries iOS does not provide: #{foreign.join(', ')}" unless foreign.empty?

      looked_up = @builder.capture("xcrun", "nm", "-m", "-u", file).lines.grep(/dynamically looked up/)
      raise "#{file} looks up symbols in no named library: #{looked_up.first(3).join}" unless looked_up.empty?

      init = "_Init_#{File.basename(file)[/\A[^.]*/]}"
      exported = @builder.capture("xcrun", "nm", "-g", "-U", "-j", file).split
      raise "#{file} does not export #{init.delete_prefix('_')}, which Ruby looks it up by" unless exported.include?(init)
    end

    # Writes the manifest of each library in MANIFESTS that the extension
    # +file+ links, its symbols not yet stripped, as +slice+'s
    # PRIVACY/NAME.xcprivacy.
    private def manifest(slice, name, file)
      symbols = @builder.capture("xcrun", "nm", "-j", file).split
      MANIFESTS.each do |library, (symbol, path)|
        next unless symbols.include?(symbol)

        folder = File.join(slice, PRIVACY)
        FileUtils.mkdir_p(folder)
        source = File.join(@build_dir, "sources", "#{library}-manifest")
        FileUtils.rm_rf(source)
        FileUtils.mkdir_p(source)
        @builder.run("tar", "-xzf", @builder.fetch(pin(library).fetch("url"), pin(library).fetch("sha256")), "-C", source,
          "--strip-components=1", "*/#{path}")
        FileUtils.cp(File.join(source, path), File.join(folder, "#{name}.xcprivacy"))
      end
    end

    # The embedding API (runtime/mobile/fledge_ruby.c) and the system log
    # it writes to (apple.c), compiled for +target+ with the launcher's
    # warnings as errors and under clang's static analyzer.
    private def compile_api(target, root, folder)
      cc = compiler(target).split
      flags = [
        "-std=gnu11",
        "-Os",
        *WARNINGS,
        "-isystem",
        ruby_headers(root),
        "-isystem",
        File.join(ruby_headers(root), "arm64-darwin"),
        "-I",
        MOBILE,
        "-I",
        Recipe::LAUNCHER,
      ]
      api_sources.map do |source|
        object = File.join(folder, "#{File.basename(source, '.c')}.o")
        @builder.run(*cc, "--analyze", "-Xclang", "-analyzer-werror", *flags, source, "-o", File.join(folder, "analysis.plist"))
        @builder.run(*cc, *flags, "-c", source, "-o", object)
        object
      end
    end

    private def api_sources
      [
        File.join(MOBILE, "fledge_ruby.c"),
        File.join(MOBILE, "output.c"),
        File.join(MOBILE, "apple.c"),
        File.join(Recipe::LAUNCHER, "locale.c"),
        File.join(Recipe::LAUNCHER, "config.c"),
        File.join(Recipe::LAUNCHER, "bundler.c"),
      ]
    end

    private def ruby_headers(root)
      Mobile.ruby_headers(root)
    end

    # The Headers folder of +framework+: Ruby's headers, with its
    # configuration header beside the rest (ruby/config.h), so that one
    # folder on the include path serves #include <ruby.h>, and the
    # embedding API's.
    private def headers(root, framework)
      headers = File.join(framework, "Headers")
      FileUtils.cp_r(ruby_headers(root), headers)
      arch = File.join(headers, "arm64-darwin")
      FileUtils.cp_r(File.join(arch, "ruby", "."), File.join(headers, "ruby"))
      FileUtils.rm_rf(arch)
      FileUtils.cp(File.join(MOBILE, "fledge_ruby.h"), headers)
      headers
    end
  end
end
