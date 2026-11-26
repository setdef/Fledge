# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require "digest"
require "fileutils"
require_relative "mobile"

class RuntimeBuilder
  # Android: Ruby for arm64-v8a and x86_64 phones and emulators, built
  # with the NDK's compilers after Termux's configure settings
  # (termux-packages, packages/ruby/build.sh; CONFIGURE) as a shared
  # library, as a desktop Linux runtime's Ruby is, linked again with the
  # embedding API into one shared library per ABI, libfledgeruby.so, with
  # each of Ruby's extensions, encodings, and bundled gems' extensions a
  # file of its own beside it (#extension_files), and packed by Gradle
  # and the Android Gradle plugin as an AAR, FledgeRuby.aar, with the
  # embedding API's Java class (doc/contributors/design/phone-runtimes.md,
  # "What a phone runtime holds").
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
    # and its seteuid setresuid, which the filter allows. configure finds
    # each in bionic, as on Linux, and Ruby's process.c calls its own in
    # their place, which answer as Linux does for a process without the
    # capabilities to change its IDs, without the calls the filter stops
    # (RubySource.process_c_ids). Termux, whose settings Fledge's Android
    # build follows, tells configure that setgroups, setreuid, and
    # setresuid are missing "to fix compilation on android"
    # (termux-packages, packages/ruby/build.sh, line 19 at 750b3fc), not
    # for the filter; Fledge's build compiles with them. Without
    # libcrypt, as for Termux, String#crypt uses Ruby's own
    # missing/crypt.c, and rb_cv_type_deprecated is Termux's fix for
    # clang.
    CONFIGURE = %w[
      ac_cv_lib_crypt_crypt=no
      rb_cv_type_deprecated=x
    ].freeze

    # The libraries Android itself provides that libfledgeruby.so and
    # Ruby's extensions may need.
    SYSTEM = /\A(?:libc|libm|libdl|liblog|libz)\.so\z/

    # What begins the name in the AAR of each of Ruby's own extension
    # files: libfledgerubyext.PATH.so, PATH its path under lib/ruby with
    # its slashes as dots (#extension_files).
    EXTENSION = "libfledgerubyext"

    # The file at the runtime's top that lists, for each ABI, each of
    # Ruby's extension files in the AAR and its path under the app's
    # Ruby, as fledge build's own fledge.links does for an app's gems
    # (Fledge::MobileProject::AndroidLibraries), which an app's
    # fledge.links begins with.
    LINKS = "fledge.links"

    # The source in runtime/mobile/ that ext/openssl compiles in
    # (RubySource.openssl_extconf), as fledge_certificates.c.
    CERTIFICATES = "openssl_certificates.c"

    # The symbols Ruby's build makes local in its shared library
    # (template/Makefile.in, lines 358 to 360 at 4.1.0-preview1).
    LOCAL = %w[Init_* InitVM_* ruby_static_id_* *_threadptr_* *_ec_*].freeze

    # Play requires every native library of a 64-bit app to load on
    # devices with 16 KB pages from 2027-02-01; NDK r28 and later align
    # every LOAD segment so by default, and the link says so anyway.
    PAGE = 16_384

    # The runtime's ruby program in each ABI's folder of native
    # libraries, named as the package installer extracts only lib*.so
    # (doc/contributors/design/phone-runtimes.md, "The ruby program on Android";
    # runtime/mobile/android.c, FLEDGE_RUBY_PROGRAM).
    PROGRAM = "libfledgerubyexe.so"

    # Ruby's JITs for +target+, with the NDK's tools in +tools+: YJIT and
    # ZJIT, as a desktop Ruby has them, each off until the app enables
    # it (the phone parity audit, doc/contributors/research/
    # 2026-11-12-phone-parity-audit.md, item 3). Android lets an app
    # write code and run it ("WebView and other application-specific JIT
    # compilers", AOSP system/sepolicy, private/app.te, lines 188 and 189
    # at 4571ddd), and both JITs read the page size, 4 KB or 16 KB, from
    # sysconf (jit.c, rb_jit_get_page_size, and zjit/src/virtualmem.rs,
    # at 4.1.0-preview1). configure.ac (lines 3894 to 3910) builds no JIT
    # by itself when cross-compiling, "we can't easily cross-compile
    # with rustc", which --enable-yjit and --enable-zjit override. With
    # both, Ruby compiles them with rustc alone, as three rlibs and a
    # static library that links them (configure.ac, the release build of
    # YJIT+ZJIT; defs/jit.mk), and rustc_flags, which configure adds to
    # every rustc it runs, names Rust's own name for the target, the
    # same as the NDK's; mise.toml's Rust adds both targets' standard
    # libraries. libruby holds the JITs as one object that $(LD) -r makes
    # and $(OBJCOPY) leaves only rb_* global in (defs/jit.mk,
    # RUST_LIBOBJ); configure would find neither tool for the NDK's
    # clang, and take the build machine's, so both are the NDK's.
    def self.jit_options(target, tools)
      [
        *JITS,
        "rustc_flags=--target=#{target.triple}",
        "LD=#{File.join(tools, 'ld.lld')}",
        "OBJCOPY=#{File.join(tools, 'llvm-objcopy')}",
      ]
    end

    private def jit_options(target)
      Android.jit_options(target, tools)
    end

    # The JITs Android's Ruby has, YJIT and ZJIT, as configure is told
    # them for each target and for the build machine's miniruby
    # (Mobile#jits).
    JITS = %w[--enable-yjit --enable-zjit].freeze

    private def jits
      JITS
    end

    private def edits
      %i[psych_extconf configure configure_soname openssl_extconf ruby_c ruby_c_source prism_compile_c process_c process_c_umask process_c_ids file_c_umask thread_pthread_c thread_c dir_c setproctitle_c]
    end

    private def host_triple(target)
      target.triple
    end

    # The source as Mobile#prepare_source makes it, with CERTIFICATES
    # among ext/openssl's sources.
    private def prepare_source(source)
      super
      FileUtils.cp(File.join(MOBILE, CERTIFICATES), File.join(source, "ext", "openssl", "fledge_certificates.c"))
      source
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
      links = @roots.flat_map do |target, root|
        files, lines = extension_files(target, root)
        libraries.fetch(target).concat(files)
        [library_line(target), *lines]
      end
      File.write(File.join(stage, LINKS), links.join)
      merge_trees(stage)
      FileUtils.cp(File.join(MOBILE, "fledge_ruby.h"), File.join(stage, "include"))
      copy_certificates(File.join(stage, "libexec"))
      pack_aar(libraries, File.join(stage, "FledgeRuby.aar"))
    end

    # libfledgeruby.so for +target+: Ruby's shared library as Ruby's
    # build links it (template/Makefile.in, lines 354 to 360 at
    # 4.1.0-preview1), from the objects in libruby's archive with
    # dmyext.o and dmyenc.o, by which Ruby loads its extensions and
    # encodings from files, and with the same symbols made local (LOCAL);
    # and with the embedding API and its JNI functions, under the SONAME
    # each extension Ruby built needs (RubySource.configure_soname).
    # OpenSSL, libyaml, and libffi are linked into the extensions that use
    # them, not here. Returns it, with the ruby program linked against it
    # (#program).
    private def link(target, root)
      folder = File.join(@build_dir, target.name, "package")
      FileUtils.rm_rf(folder)
      FileUtils.mkdir_p(folder)
      cc = environment(target).fetch("CC")
      static = @archives.fetch(target)
      build = File.join(@build_dir, target.name, "ruby")
      members = static.flat_map { |archive| @builder.capture(File.join(tools, "llvm-ar"), "t", archive).split }
      objects = %w[dmyext.o dmyenc.o].reject { |object| members.include?(object) }.map { |object| File.join(build, object) }
      library = File.join(folder, "libfledgeruby.so")
      api_sources.each do |source|
        @builder.run(cc, "--analyze", "-Xclang", "-analyzer-werror", *compile_flags(root), source, "-o", File.join(folder, "analysis.plist"))
      end
      @builder.run(cc, "-shared", "-fPIC", "-O2", *compile_flags(root), *api_sources, *objects, "-Wl,--whole-archive", *static,
        "-Wl,--no-whole-archive", "-Wl,-soname,libfledgeruby.so", "-Wl,-z,max-page-size=#{PAGE}", "-llog", "-lz",
        "-ldl", "-lm", "-o", library)
      @builder.run(File.join(tools, "llvm-objcopy"), "-w", *LOCAL.flat_map { |pattern| ["-L", pattern] }, library)
      @builder.run(File.join(tools, "llvm-strip"), "--strip-unneeded", library)
      check(library)
      [library, program(cc, root, folder)]
    end

    # The LINKS line for +target+ from where Ruby's install puts a shared
    # Ruby's library, libdir/LIBRUBY_SO, ROOT/lib/libfledgeruby.so, to
    # the library in the AAR, which the package installer extracts into a
    # folder of its own: ruby/spec and a program that links Ruby look for
    # it there, as under ruby main.rb. Ruby's install puts nothing else
    # beside it, since its SONAME is that name and it has no alias
    # (RubySource.configure_soname).
    private def library_line(target)
      "#{target.abi}\tlibfledgeruby.so\tlib/libfledgeruby.so\n"
    end

    # Each ELF file Ruby installed under +root+'s lib/ruby for +target+:
    # its extensions, encodings and transcoders, and its bundled gems'
    # extensions, in each gem's require path and in its extension folder,
    # as on a desktop. The package installer extracts only lib*.so
    # files, into a folder of its own, so each is copied, stripped, and
    # checked as libfledgeruby.so is, into the AAR's folder for the ABI
    # as EXTENSION.PATH.so, and taken out of the tree, which then holds
    # the same files for both ABIs. Returns the copies, one for each
    # file's bytes, and a LINKS line for each path.
    private def extension_files(target, root)
      ruby = File.join(root, "lib", "ruby")
      folder = File.join(@build_dir, target.name, "extensions")
      FileUtils.rm_rf(folder)
      FileUtils.mkdir_p(folder)
      named = {} # : Hash[String, String]
      digests = {} # : Hash[String, String]
      lines = Dir.glob("**/*.so", base: ruby).sort.filter_map do |path|
        from = File.join(ruby, path)
        next unless File.file?(from) && File.binread(from, 4) == "\x7FELF".b

        name = digests[Digest::SHA256.file(from).hexdigest] ||= extension_file(from, path, folder, named)
        FileUtils.rm(from)
        "#{target.abi}\t#{name}\tlib/ruby/#{path}\n"
      end
      [named.keys.map { |name| File.join(folder, name) }, lines]
    end

    # Copies the extension file +from+, at +path+ under lib/ruby, into
    # +folder+ under its name in the AAR, stripped and checked, and
    # returns the name. Raises when another file in +named+ has that name.
    private def extension_file(from, path, folder, named)
      name = "#{EXTENSION}.#{path.tr('/', '.')}"
      raise "lib/ruby/#{named[name]} and lib/ruby/#{path} would both be #{name}" if named.key?(name)

      named[name] = path
      copy = File.join(folder, name)
      FileUtils.cp(from, copy)
      @builder.run(File.join(tools, "llvm-strip"), "--strip-unneeded", copy)
      check(copy, also: "libfledgeruby.so")
      name
    end

    # The runtime's ruby program for one ABI, PROGRAM, which RbConfig.ruby
    # names through the link android.c makes: a position-
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
        File.join(MOBILE, "library_links.c"),
        File.join(MOBILE, "commands.c"),
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

    # Both ABIs' lib/ruby, include/, and bin/ in one tree: Ruby keeps
    # each ABI's files in a folder named for its platform, and every
    # other file must be the same for both. bin/ holds the wrappers
    # RubyGems wrote for the gems' commands, as a desktop runtime's does,
    # without the ruby program make install put there: the runtime's is
    # PROGRAM, in the AAR, and an app's Ruby links bin/ruby to it
    # (doc/contributors/design/phone-runtimes.md, "Gem commands on
    # Android").
    private def merge_trees(stage)
      @roots.each_value do |root|
        %w[lib/ruby include bin].each do |folder|
          Dir.glob("**/*", base: File.join(root, folder)).each do |path|
            from = File.join(root, folder, path)
            to = File.join(stage, folder, path)
            next if File.directory?(from) || (folder == "bin" && path == "ruby")

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
    # Gradle, its project files and caches kept out of the repository,
    # and tried a second time when a repository answered 404 for a file
    # Maven Central holds (MobileParity::Android.gradle_with_a_second_try).
    private def pack_aar(libraries, aar)
      require_relative "../mobile_parity"
      jni = File.join(@build_dir, "jniLibs")
      libraries.each do |target, files|
        FileUtils.mkdir_p(File.join(jni, target.abi))
        FileUtils.cp(files, File.join(jni, target.abi))
      end
      out = File.join(@build_dir, "gradle")
      log = File.join(out, "gradle.log")
      FileUtils.mkdir_p(out)
      File.write(log, "")
      packed = MobileParity::Android.gradle_with_a_second_try(log, step: "Gradle assembleRelease of the AAR project") do
        @builder.run(gradle, "--no-daemon", "--info", "--project-dir", File.join(MOBILE, "android"), "--project-cache-dir",
          File.join(out, "cache"), "assembleRelease", "-Pfledge.jniLibs=#{jni}", "-Pfledge.buildDir=#{File.join(out, 'build')}",
          "-Pfledge.agp=#{pin('agp')}", out: [log, "a"], err: %i[child out])
        true
      rescue RuntimeError
        false
      end
      raise "Gradle did not pack the AAR (#{log}):\n#{MobileParity::Android.gradle_failure(File.read(log))}" unless packed

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
