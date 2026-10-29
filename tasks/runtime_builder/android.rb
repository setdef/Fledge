# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "fileutils"
require_relative "mobile"

class RuntimeBuilder
  # Android: Ruby for arm64-v8a and x86_64 phones and emulators, built
  # with the NDK's compilers with Termux's configure settings
  # (termux-packages, packages/ruby/build.sh), linked with the embedding
  # API into one shared library per ABI, libfledgeruby.so, and packed by
  # Gradle and the Android Gradle plugin as an AAR, FledgeRuby.aar, with
  # the embedding API's Java class (ADR 011, section 2).
  #
  # Beside the AAR the runtime holds the Ruby both ABIs run: one lib/ruby
  # (Ruby names each ABI's folder for its own platform, so both fit in
  # one tree), the CA certificates in libexec/, and the headers in
  # include/ that native code linking libfledgeruby.so compiles against.
  # An app puts lib/ and libexec/ with its own code in one asset, which
  # the Java class unpacks on the first launch of each installed version.
  class Android < Mobile
    # What Termux tells configure about bionic: no setgroups, setresuid,
    # or setreuid an app may call, and no libcrypt, so String#crypt uses
    # Ruby's own missing/crypt.c.
    TERMUX = %w[
      ac_cv_func_setgroups=no
      ac_cv_func_setresuid=no
      ac_cv_func_setreuid=no
      ac_cv_lib_crypt_crypt=no
      rb_cv_type_deprecated=x
    ].freeze

    # The libraries Android itself provides that libfledgeruby.so may need.
    SYSTEM = /\A(?:libc|libm|libdl|liblog|libz)\.so\z/

    # Play requires every native library of a 64-bit app to load on
    # devices with 16 KB pages from 2027-02-01; NDK r28 and later align
    # every LOAD segment so by default, and the link says so anyway.
    PAGE = 16_384

    private def edits
      %i[psych_extconf configure ruby_c]
    end

    private def needs_libffi?
      true
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
        *TERMUX,
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
    # OpenSSL reads no SSL_CERT_FILE in an Android app.
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
      library
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
      ]
    end

    private def compile_flags(root)
      headers = File.join(root, "include", "ruby-4.0.0")
      arch = Dir.glob(File.join(headers, "*-linux-android")).first or raise "#{headers} has no Android configuration"
      ["-std=gnu11", *WARNINGS, "-isystem", arch, "-isystem", headers, "-I", MOBILE, "-I", Recipe::LAUNCHER]
    end

    private def check(library)
      readelf = File.join(tools, "llvm-readelf")
      needed = @builder.capture(readelf, "-dW", library).scan(/\(NEEDED\)\s+Shared library: \[([^\]]+)\]/).flatten
      foreign = needed.grep_v(SYSTEM)
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
    # runtime/mobile/android/ and each ABI's library, with the pinned
    # Gradle, its project files and caches kept out of the repository.
    private def pack_aar(libraries, aar)
      jni = File.join(@build_dir, "jniLibs")
      libraries.each do |target, library|
        FileUtils.mkdir_p(File.join(jni, target.abi))
        FileUtils.cp(library, File.join(jni, target.abi))
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
