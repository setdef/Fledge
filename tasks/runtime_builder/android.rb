# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require "fileutils"
require_relative "mobile"

class RuntimeBuilder
  # Android: Ruby for arm64-v8a and x86_64 phones and emulators, built
  # with the NDK's compilers after Termux's configure settings
  # (termux-packages, packages/ruby/build.sh; CONFIGURE), linked with the
  # embedding API into one shared library per ABI, libfledgeruby.so, and
  # packed by Gradle and the Android Gradle plugin as an AAR,
  # FledgeRuby.aar, with the embedding API's Java class
  # (doc/contributors/design/phone-runtimes.md, "What a phone runtime
  # holds").
  #
  # Beside the AAR the runtime holds the Ruby both ABIs run: one lib/ruby
  # (Ruby names each ABI's folder for its own platform, so both fit in
  # one tree), the CA certificates in libexec/, and the headers in
  # include/ that native code linking libfledgeruby.so compiles against.
  # An app puts lib/ and libexec/ with its own code in one asset, which
  # the Java class unpacks on the first launch of each installed version.
  class Android < Mobile
    # What configure is told about bionic that it cannot find out by
    # compiling. Android's seccomp filter for apps stops a process with
    # SIGSYS when it calls setgid, setuid, setregid, setreuid, setresgid,
    # or setgroups, and lets it call setresuid (bionic,
    # libc/SECCOMP_BLOCKLIST_APP.TXT, lines 9 to 30 at 731631f), and
    # bionic's setegid calls setresgid (libc/bionic/setegid.cpp), its
    # initgroups setgroups (libc/bionic/grp_pwd.cpp, lines 624 to 626),
    # and its seteuid setresuid, which the filter allows. Each function
    # the filter would stop is one configure finds in bionic, so Ruby is
    # told it is missing, and raises NotImplementedError for each call
    # that needs it (process.c, as for setruid, which bionic lacks).
    # Termux, whose settings Fledge's Android build follows, says the
    # same of setgroups and setreuid, but also of setresuid, all three
    # "to fix compilation on android" (termux-packages,
    # packages/ruby/build.sh, line 19 at 750b3fc), not for the filter,
    # and nothing of the rest; Process.uid= then calls setuid, and Process.egid=
    # setresgid, and the filter ends the app. Without libcrypt, as for
    # Termux, String#crypt uses Ruby's own missing/crypt.c, and
    # rb_cv_type_deprecated is Termux's fix for clang.
    CONFIGURE = %w[
      ac_cv_func_initgroups=no
      ac_cv_func_setegid=no
      ac_cv_func_setgid=no
      ac_cv_func_setgroups=no
      ac_cv_func_setregid=no
      ac_cv_func_setresgid=no
      ac_cv_func_setreuid=no
      ac_cv_func_setuid=no
      ac_cv_lib_crypt_crypt=no
      rb_cv_type_deprecated=x
    ].freeze

    # The libraries Android itself provides that libfledgeruby.so may need.
    SYSTEM = /\A(?:libc|libm|libdl|liblog|libz)\.so\z/

    # Play requires every native library of a 64-bit app to load on
    # devices with 16 KB pages from 2027-02-01; NDK r28 and later align
    # every LOAD segment so by default, and the link says so anyway.
    PAGE = 16_384

    # The runtime's ruby program in each ABI's folder of native
    # libraries, named as the package installer extracts only lib*.so
    # (ADR 069; runtime/mobile/android.c, FLEDGE_RUBY_PROGRAM).
    PROGRAM = "libfledgerubyexe.so"

    # Ruby's JITs for +target+, with the NDK's tools in +tools+: YJIT, as
    # a desktop Ruby has it, off until the app enables it (the phone
    # parity audit, doc/contributors/research/
    # 2026-11-12-phone-parity-audit.md, item 3). ZJIT, Ruby's
    # experimental second JIT, which rv-ruby's desktop builds carry too
    # (Abstract/rv-ruby.rb, line 122 at f57186e), is not built yet.
    # Android lets an app write code and run it ("WebView and other
    # application-specific JIT compilers", AOSP system/sepolicy,
    # private/app.te, lines 188 and 189 at 4571ddd), and YJIT reads the page size, 4 KB or 16 KB, from
    # sysconf (jit.c, rb_jit_get_page_size, at 4.1.0-preview1).
    # configure.ac (lines 3894 to 3910) builds no JIT by itself when
    # cross-compiling, "we can't easily cross-compile with rustc", which
    # --enable-yjit overrides. Ruby compiles YJIT with rustc alone, and
    # rustc_flags, which configure adds to every rustc it runs, names
    # Rust's own name for the target, the same as the NDK's; mise.toml's
    # Rust adds both targets' standard libraries. libruby holds YJIT as
    # one object that $(LD) -r makes and $(OBJCOPY) leaves only rb_*
    # global in (defs/jit.mk, RUST_LIBOBJ); configure would find neither
    # tool for the NDK's clang, and take the build machine's, so both
    # are the NDK's.
    def self.jit_options(target, tools)
      [
        "--enable-yjit",
        "--disable-zjit",
        "rustc_flags=--target=#{target.triple}",
        "LD=#{File.join(tools, 'ld.lld')}",
        "OBJCOPY=#{File.join(tools, 'llvm-objcopy')}",
      ]
    end

    private def jit_options(target)
      Android.jit_options(target, tools)
    end

    private def edits
      %i[psych_extconf configure ruby_c process_c process_c_umask file_c_umask thread_pthread_c thread_c dir_c setproctitle_c]
    end

    private def host_triple(target)
      target.triple
    end

    # The NDK, unpacked from its pinned download into the build folder,
    # and checked to be the revision runtime/sources.yml names.
    private def ndk
      @ndk ||= begin
        ndk = pin("ndk")
        host = ndk.fetch("hosts").fetch(@builder.host.name)
        zip = @builder.fetch(host.fetch("url"), host.fetch("sha256"))
        tools = File.join(@build_dir, "tools")
        root = File.join(tools, "android-ndk-#{ndk.fetch('version')}")
        @builder.run("unzip", "-q", "-o", zip, "-d", tools) unless File.file?(File.join(root, "source.properties"))
        revision = File.read(File.join(root, "source.properties"))[/^Pkg\.Revision = (\S+)/, 1]
        raise "#{root} is NDK #{revision}, not #{ndk.fetch('revision')}" unless revision == ndk.fetch("revision")

        root
      end
    end

    # The NDK's own LLVM tools, which read the Android runtime's every
    # file for the license audit.
    def readers
      Fledge::Binary::Readers.llvm(tools)
    end

    # How a bundled gem's extension becomes one object with only its Init
    # function global (BundledExtensions.relocate): the NDK's lld links it
    # with -r, and the NDK's llvm-objcopy makes every symbol it defines
    # but the Init function local (--keep-global-symbol).
    private def relocatable
      ["$(CC) -r -nostdlib -o $@ $(FLEDGE_OBJS)", "#{File.join(tools, 'llvm-objcopy')} --keep-global-symbol=$(FLEDGE_INIT) $@"]
    end

    private def tools
      prebuilt = Dir.glob(File.join(ndk, "toolchains", "llvm", "prebuilt", "*")).first or raise "#{ndk} has no LLVM toolchain"
      File.join(prebuilt, "bin")
    end

    private def environment(target)
      {
        "CC" => File.join(tools, "#{target.triple}#{ANDROID_API}-clang"),
        "CXX" => File.join(tools, "#{target.triple}#{ANDROID_API}-clang++"),
        "AR" => File.join(tools, "llvm-ar"),
        "RANLIB" => File.join(tools, "llvm-ranlib"),
        "CFLAGS" => "-O2 -fPIC",
      }
    end

    # OpenSSL's own Android targets find the NDK's clang on PATH.
    private def openssl_environment(_target)
      { "ANDROID_NDK_ROOT" => ndk, "PATH" => [tools, ENV.fetch("PATH", "")].join(File::PATH_SEPARATOR) }
    end

    private def openssl_options(_target)
      ["-D__ANDROID_API__=#{ANDROID_API}"]
    end

    private def target_options(_target, deps)
      ffi = deps.fetch(:libffi)
      [
        *CONFIGURE,
        "--with-libffi-dir=#{ffi}",
        "CFLAGS=-O2 -fPIC -fno-strict-aliasing",
        "CPPFLAGS=-I#{File.join(ffi, 'include')}",
        "LDFLAGS=-L#{File.join(ffi, 'lib')}",
      ]
    end

    private def package(stage)
      libraries = @roots.to_h { |target, root| [target, link(target, root)] }
      merge_trees(stage)
      FileUtils.cp(File.join(MOBILE, "fledge_ruby.h"), File.join(stage, "include"))
      copy_certificates(File.join(stage, "libexec"))
      pack_aar(libraries, File.join(stage, "FledgeRuby.aar"))
    end

    # libfledgeruby.so for +target+: Ruby whole, so that native code that
    # links it finds all of Ruby's C API, with its extensions and
    # encodings, and without libruby's dmyext.o and dmyenc.o (see
    # IOS#library); the embedding API with its JNI functions; and OpenSSL,
    # libyaml, and libffi, whose symbols it keeps to itself
    # (--exclude-libs), so an app's own copies cannot clash with them; and
    # OpenSSL's X509_get_default_cert_file answered by android.c, since
    # OpenSSL reads no SSL_CERT_FILE in an Android app. Returns it, with
    # the ruby program linked against it (#program).
    private def link(target, root)
      folder = File.join(@build_dir, target.name, "package")
      FileUtils.rm_rf(folder)
      FileUtils.mkdir_p(folder)
      cc = environment(target).fetch("CC")
      ruby, libraries = @archives.fetch(target).partition { |path| path.start_with?(File.join(@build_dir, target.name, "ruby")) }
      static = ruby.map do |path|
        next path unless File.basename(path).match?(LIBRUBY)

        copy = File.join(folder, File.basename(path))
        FileUtils.cp(path, copy)
        @builder.run(File.join(tools, "llvm-ar"), "d", copy, "dmyext.o", "dmyenc.o")
        copy
      end
      library = File.join(folder, "libfledgeruby.so")
      excluded = libraries.map { |path| File.basename(path) }.join(":")
      api_sources.each do |source|
        @builder.run(cc, "--analyze", "-Xclang", "-analyzer-werror", *compile_flags(root), source, "-o", File.join(folder, "analysis.plist"))
      end
      @builder.run(cc, "-shared", "-fPIC", "-O2", *compile_flags(root), *api_sources, "-Wl,--whole-archive", *static,
        "-Wl,--no-whole-archive", *libraries, "-Wl,--exclude-libs=#{excluded}", "-Wl,--wrap=X509_get_default_cert_file",
        "-Wl,-z,max-page-size=#{PAGE}", "-llog", "-lz",
        "-ldl", "-lm", "-o", library)
      @builder.run(File.join(tools, "llvm-strip"), "--strip-unneeded", library)
      check(library)
      [library, program(cc, root, folder)]
    end

    # The runtime's ruby program for one ABI, PROGRAM, which RbConfig.ruby
    # names through the link android.c makes (ADR 069): a position-
    # independent executable with Ruby's main.c in libfledgeruby.so, which
    # it finds beside itself, where the package installer extracts both,
    # through its run path ($ORIGIN, which bionic expands), so that it
    # carries no second copy of Ruby.
    private def program(cc, root, folder)
      source = File.join(MOBILE, "ruby_program.c")
      executable = File.join(folder, PROGRAM)
      @builder.run(cc, "--analyze", "-Xclang", "-analyzer-werror", *compile_flags(root), source, "-o", File.join(folder, "analysis.plist"))
      @builder.run(cc, "-fPIE", "-pie", "-O2", *compile_flags(root), source, "-L#{folder}", "-lfledgeruby", "-Wl,-rpath,$ORIGIN",
        "-Wl,-z,max-page-size=#{PAGE}", "-o", executable)
      @builder.run(File.join(tools, "llvm-strip"), "--strip-unneeded", executable)
      check(executable, also: "libfledgeruby.so")
      runpath = @builder.capture(File.join(tools, "llvm-readelf"), "-dW", executable)[/\(RUNPATH\)\s+Library runpath: \[([^\]]*)\]/, 1]
      raise "#{executable} does not look for libfledgeruby.so beside itself: its run path is #{runpath.inspect}" unless runpath == "$ORIGIN"

      executable
    end

    # The embedding API's sources (runtime/mobile/): its C, the logcat
    # and JNI half (android.c), and the launcher's locale.c, each checked
    # by clang's static analyzer with the launcher's warnings as errors.
    private def api_sources
      [
        File.join(MOBILE, "fledge_ruby.c"),
        File.join(MOBILE, "output.c"),
        File.join(MOBILE, "android.c"),
        File.join(Recipe::LAUNCHER, "locale.c"),
        File.join(Recipe::LAUNCHER, "config.c"),
        File.join(Recipe::LAUNCHER, "bundler.c"),
      ]
    end

    private def compile_flags(root)
      headers = Mobile.ruby_headers(root)
      arch = Dir.glob(File.join(headers, "*-linux-android")).first or raise "#{headers} has no Android configuration"
      ["-std=gnu11", *WARNINGS, "-isystem", arch, "-isystem", headers, "-I", MOBILE, "-I", Recipe::LAUNCHER]
    end

    # Fails unless +library+ needs only Android's own libraries and +also+,
    # and every LOAD segment of it is aligned for 16 KB pages.
    private def check(library, also: nil)
      readelf = File.join(tools, "llvm-readelf")
      needed = @builder.capture(readelf, "-dW", library).scan(/\(NEEDED\)\s+Shared library: \[([^\]]+)\]/).flatten
      foreign = needed.grep_v(SYSTEM) - [also]
      raise "#{library} needs libraries Android does not provide: #{foreign.join(', ')}" unless foreign.empty?

      alignments = @builder.capture(readelf, "-lW", library).lines.grep(/\A\s*LOAD\s/).map { |line| Integer(line.split.last) }
      raise "#{library} has a LOAD segment aligned to less than #{PAGE} bytes: #{alignments}" if alignments.empty? || alignments.min < PAGE
    end

    # Both ABIs' lib/ruby and include/ in one tree: Ruby keeps each
    # ABI's files in a folder named for its platform, and every other
    # file must be the same for both.
    private def merge_trees(stage)
      @roots.each_value do |root|
        %w[lib/ruby include].each do |folder|
          Dir.glob("**/*", base: File.join(root, folder)).each do |path|
            from = File.join(root, folder, path)
            to = File.join(stage, folder, path)
            next if File.directory?(from)

            if File.exist?(to)
              raise "#{folder}/#{path} differs between the Android targets" unless FileUtils.identical?(from, to)
            else
              FileUtils.mkdir_p(File.dirname(to))
              FileUtils.cp(from, to, preserve: true)
            end
          end
        end
      end
    end

    # The AAR, packed by the Android Gradle plugin from the Java class in
    # runtime/mobile/android/ and each ABI's library and ruby program,
    # with the pinned
    # Gradle, its project files and caches kept out of the repository.
    private def pack_aar(libraries, aar)
      jni = File.join(@build_dir, "jniLibs")
      libraries.each do |target, files|
        FileUtils.mkdir_p(File.join(jni, target.abi))
        FileUtils.cp(files, File.join(jni, target.abi))
      end
      out = File.join(@build_dir, "gradle")
      @builder.run(gradle, "--no-daemon", "--quiet", "--project-dir", File.join(MOBILE, "android"), "--project-cache-dir",
        File.join(out, "cache"), "assembleRelease", "-Pfledge.jniLibs=#{jni}", "-Pfledge.buildDir=#{File.join(out, 'build')}",
        "-Pfledge.agp=#{pin('agp')}")
      built = Dir.glob(File.join(out, "build", "outputs", "aar", "*-release.aar"))
      raise "Gradle built no single AAR: #{built}" unless built.size == 1

      FileUtils.cp(built.first.to_s, aar)
    end

    # The pinned Gradle, unpacked from its download into the build folder.
    private def gradle
      gradle = pin("gradle")
      zip = @builder.fetch(gradle.fetch("url"), gradle.fetch("sha256"))
      tools = File.join(@build_dir, "tools")
      home = File.join(tools, "gradle-#{gradle.fetch('version')}")
      @builder.run("unzip", "-q", "-o", zip, "-d", tools) unless File.directory?(home)
      File.join(home, "bin", "gradle")
    end
  end
end
