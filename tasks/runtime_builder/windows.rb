# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require "digest"
require "fileutils"
require "open3"
require_relative "recipe"
require_relative "../../lib/fledge/binary"

class RuntimeBuilder
  # Windows: RubyInstaller's Ruby, checked against its signature, whose
  # tree goes into ruby\ with its shape unchanged and Fledge's RubyGems
  # defaults in place of RubyInstaller's, and the launcher cross-compiled
  # beside it with llvm-mingw. The launcher loads Ruby's DLL when it runs
  # (runtime/launcher/windows.c), so it needs Ruby's headers to build,
  # and nothing to link. Ruby's own ruby.exe and rubyw.exe are Fledge's,
  # compiled with the same llvm-mingw against the tree's DLL in place of
  # RubyInstaller's (#compile_ruby), as bin/ruby is on macOS and Linux.
  class Windows < Recipe
    # The triple llvm-mingw compiles each Windows target's launcher for.
    TARGETS = { "x64-mingw-ucrt" => "x86_64-w64-mingw32", "aarch64-mingw-ucrt" => "aarch64-w64-mingw32" }.freeze

    # The PE Subsystem of a console program, which Windows gives a
    # console, and of a GUI one, which it does not.
    CONSOLE = 3
    GUI = 2

    # The DLLs a launcher may import: Windows' kernel and its universal C
    # runtime, which every supported Windows ships, and for a windowed
    # one, USER32 for its message box.
    IMPORTS = /\A(?:KERNEL32\.dll|api-ms-win-crt-[a-z0-9-]+\.dll)\z/i
    WINDOWED_IMPORTS = /\AUSER32\.dll\z/i

    def hosts
      @builder.sources.fetch("llvm-mingw").fetch("hosts").keys
    end

    def build(stage)
      tree = @tree = unpack_rubyinstaller
      @toolchain = unpack_toolchain
      compile(tree, File.join(stage, "launcher.exe"))
      ruby = File.join(stage, "ruby")
      FileUtils.cp_r(tree, ruby)
      FileUtils.chmod_R("u+w", ruby)
      Pruning.prune_windows(ruby, @builder.bundled_gems)
      add_missing_dlls(ruby)
      compile_ruby(tree, File.join(ruby, "bin"))
      @builder.install_rubygems_defaults(File.join(ruby, "lib", "ruby"))
      copy_nsis(File.join(stage, "tools", "nsis"))
      copy_rcedit(File.join(stage, "tools", "rcedit.exe"))
      copy_readobj(File.join(stage, "tools", "llvm-readobj.exe"))
    end

    # LLVM's own tools, which read the Windows runtime's every file for
    # the license audit (Fledge::Binary::Readers.llvm): llvm-mingw's.
    def readers
      Fledge::Binary::Readers.llvm(File.join(@toolchain, "bin"))
    end

    # Where each DLL RubyInstaller's Ruby needs and does not ship goes in
    # ruby\ (runtime/sources.yml, windows-dlls): libz-1.dll beside the
    # zlib.so that imports it, in Ruby's architecture folder, and
    # libgcc_s_seh-1.dll among the DLLs RubyInstaller keeps for Ruby's
    # own, which the launcher adds to the folders Windows looks in for an
    # extension's DLLs (windows.c, add_builtin_dlls).
    DLL_FOLDERS = { "libz-1.dll" => :arch, "libgcc_s_seh-1.dll" => :builtin }.freeze

    # Adds to the Ruby tree +ruby+ each DLL its Ruby needs and does not
    # ship, from its pinned MSYS2 package, and names libz-1.dll in
    # zlib.so's assembly manifest, beside the zlib1.dll it names, so that
    # Windows finds it there as it finds zlib1.dll. Raises when the tree
    # ships one already, whose pin should then go.
    private def add_missing_dlls(ruby)
      lib = File.join(ruby, "lib", "ruby")
      folders = {
        arch: File.join(lib, RuntimeBuilder.ruby_abi(lib), @builder.platform.name),
        builtin: File.join(ruby, "bin", "ruby_builtin_dlls"),
      }
      @builder.sources.fetch("windows-dlls").each do |name, dll|
        pin = dll.fetch("platforms")[@builder.platform.name] or next
        target = File.join(folders.fetch(DLL_FOLDERS.fetch(name)), name)
        raise "#{target} is in RubyInstaller's Ruby already: drop its pin from runtime/sources.yml" if File.exist?(target)

        FileUtils.cp(unpack_dll(name, pin), target)
      end
      manifest = File.join(folders.fetch(:arch), "zlib.so-assembly.manifest")
      File.write(manifest, Windows.name_in_manifest(File.read(manifest), after: "zlib1.dll", name: "libz-1.dll"))
    end

    # The assembly manifest +text+ with a file element for the DLL +name+
    # after the one for +after+, as RubyInstaller writes them.
    def self.name_in_manifest(text, after:, name:)
      element = %(<file name="#{after}"/>)
      raise "the manifest names no #{after}: #{text}" unless text.include?(element)

      text.sub(element, %(#{element}<file name="#{name}"/>))
    end

    # The DLL +name+ from the MSYS2 package +pin+ names, unpacked with
    # 7-Zip and checked against its own SHA-256.
    private def unpack_dll(name, pin)
      package = @builder.fetch_pin(pin.fetch("package"))
      unpacked = File.join(@build_dir, "msys2", name)
      FileUtils.rm_rf(unpacked)
      FileUtils.mkdir_p(unpacked)
      extract_tar_zst(package, unpacked, pin.fetch("path"))

      file = File.join(unpacked, pin.fetch("path"))
      actual = Digest::SHA256.file(file).hexdigest
      raise "#{file} has SHA-256 #{actual}, not #{pin.fetch('dll_sha256')}" unless actual == pin.fetch("dll_sha256")

      file
    end

    # llvm-readobj, which fledge build runs on Windows to read what an
    # app's compiled gems import (ADR 013): the one file of LLVM's own
    # release, which 7-Zip unpacks from its long-window archive, pinned by
    # its archive's SHA-256 and its own.
    private def copy_readobj(to)
      pin = @builder.sources.fetch("llvm-readobj")
      archive = @builder.fetch(pin.fetch("url"), pin.fetch("sha256"))
      unpacked = File.join(@build_dir, "llvm-readobj")
      FileUtils.rm_rf(unpacked)
      FileUtils.mkdir_p(unpacked)
      extract_tar_zst(archive, unpacked, pin.fetch("path"))

      file = File.join(unpacked, pin.fetch("path"))
      actual = Digest::SHA256.file(file).hexdigest
      raise "#{file} has SHA-256 #{actual}, not #{pin.fetch('file_sha256')}" unless actual == pin.fetch("file_sha256")

      FileUtils.mkdir_p(File.dirname(to))
      FileUtils.cp(file, to)
      FileUtils.chmod(0o755, to)
    end

    # rcedit, which fledge build runs on Windows to write an app's
    # version information and icon into its program (ADR 010): Electron's
    # release of it, as electron-builder downloads it, pinned by SHA-256.
    private def copy_rcedit(to)
      pin = @builder.sources.fetch("rcedit")
      FileUtils.mkdir_p(File.dirname(to))
      FileUtils.cp(@builder.fetch(pin.fetch("url"), pin.fetch("sha256")), to)
      FileUtils.chmod(0o755, to)
    end

    # What of NSIS's release fledge build compiles an installer with (ADR
    # 009 and ADR 049): its license; makensis, the release's own Windows
    # program, and the zlib1.dll it loads; the stub of solid LZMA
    # compression, NSIS's default and Tauri's, the zlib stub makensis
    # loads as it starts, before a script chooses its compressor, and the
    # uninstaller's icon;
    # the System plug-in, which sets the Start menu shortcut's
    # AppUserModelID, and nsDialogs, which Modern UI's pages use; the
    # script headers; and Modern UI 2 with its dialogs, graphics, and
    # language files. NSIS's source, which LZMA's license (CPL-1.0) asks
    # be available, is in each Windows release's source bundle.
    NSIS = [
      "COPYING",
      "Bin/makensis.exe",
      "Bin/zlib1.dll",
      "Stubs/lzma_solid-x86-unicode",
      "Stubs/zlib-x86-unicode",
      "Stubs/uninst",
      "Plugins/x86-unicode/System.dll",
      "Plugins/x86-unicode/nsDialogs.dll",
      "Include",
      "Contrib/Modern UI 2",
      "Contrib/UIs/modern.exe",
      "Contrib/Graphics",
      "Contrib/Language files",
    ].freeze

    private def copy_nsis(into)
      pin = @builder.sources.fetch("nsis").fetch("binary")
      archive = @builder.fetch(pin.fetch("url"), pin.fetch("sha256"))
      unpacked = File.join(@build_dir, "nsis")
      FileUtils.rm_rf(unpacked)
      FileUtils.mkdir_p(unpacked)
      extract_7z(archive, unpacked)
      release = File.join(unpacked, "nsis-#{@builder.sources.fetch('nsis').fetch('version')}")
      NSIS.each do |path|
        target = File.join(into, path)
        FileUtils.mkdir_p(File.dirname(target))
        FileUtils.cp_r(File.join(release, path), target)
      end
      FileUtils.chmod_R("u+w,go-w", into)
    end

    # Compiles the console launcher to +output+, and the windowed one, a
    # GUI program for windowed apps, beside it as launcherw.exe, as
    # RubyInstaller ships rubyw.exe beside ruby.exe (ADR 037). Both build
    # with warnings as errors, under clang's static analyzer, and may
    # import only what IMPORTS allows.
    private def compile(tree, output)
      sources = %w[windows.c scrub.c config.c bundler.c].map { |file| File.join(LAUNCHER, file) }
      flags = ["-std=gnu11", *WARNINGS, "-municode", "-DFLEDGE_RUBY_DLL=L\"#{ruby_dll(tree)}\"", *includes(tree)]
      sources.each do |source|
        report = File.join(@build_dir, "#{File.basename(source, '.c')}.plist")
        @builder.run(tool("clang"), "--analyze", "-Xclang", "-analyzer-werror", *flags, source, "-o", report)
        @builder.run(tool("clang"), "--analyze", "-Xclang", "-analyzer-werror", *flags, "-DFLEDGE_WINDOWED", source, "-o", report)
      end
      resources = File.join(@build_dir, "windows.res.o")
      @builder.run(tool("windres"), "windows.rc", "-O", "coff", "-o", resources, chdir: LAUNCHER)
      windowed = File.join(File.dirname(output), "launcherw.exe")
      @builder.run(tool("clang"), "-O2", *flags, *sources, resources, "-mconsole", "-s", "-o", output)
      @builder.run(tool("clang"), "-O2", *flags, "-DFLEDGE_WINDOWED", *sources, resources, "-mwindows", "-s", "-o", windowed)
      check(output, CONSOLE, IMPORTS)
      check(windowed, GUI, Regexp.union(IMPORTS, WINDOWED_IMPORTS))
    end

    # Compiles Ruby's own programs, ruby.exe and its GUI twin rubyw.exe,
    # into +bin+, in place of RubyInstaller's: Ruby's main.c
    # (runtime/launcher/ruby_main.c) with Fledge's hand-off to the app's
    # launcher (windows_relaunch.c, ADR 089), linked against Ruby's DLL
    # through the tree's import library, as RubyInstaller links its own,
    # with the launcher's manifest, so a Ruby the app starts has the
    # app's code page (ADR 070). Each may import Ruby's DLL besides what
    # the launcher may.
    RUBY_SOURCES = %w[ruby_main.c windows_relaunch.c config.c].freeze

    private def compile_ruby(tree, bin)
      sources = RUBY_SOURCES.map { |file| File.join(LAUNCHER, file) }
      flags = ["-std=gnu11", *WARNINGS, "-municode", *includes(tree)]
      sources.each do |source|
        report = File.join(@build_dir, "#{File.basename(source, '.c')}.plist")
        @builder.run(tool("clang"), "--analyze", "-Xclang", "-analyzer-werror", *flags, source, "-o", report)
      end
      resources = File.join(@build_dir, "windows.res.o")
      import = File.join(tree, "lib", "lib#{ruby_dll(tree)}.a")
      raise "#{tree} has no import library for its Ruby DLL: #{import}" unless File.file?(import)

      allowed = Regexp.union(IMPORTS, /\A#{Regexp.escape(ruby_dll(tree))}\z/i)
      { "ruby.exe" => ["-mconsole", CONSOLE], "rubyw.exe" => ["-mwindows", GUI] }.each do |name, (subsystem_flag, subsystem)|
        program = File.join(bin, name)
        FileUtils.rm_f(program)
        @builder.run(tool("clang"), "-O2", *flags, *sources, resources, import, subsystem_flag, "-s", "-o", program)
        check(program, subsystem, allowed)
      end
    end

    private def check(program, subsystem, allowed)
      binary = Fledge::Binary.read([program], readers:)[program] or raise "#{program} is not a Windows program"
      raise "#{program} has PE subsystem #{binary.subsystem}, not #{subsystem}" unless binary.subsystem == subsystem

      imports = binary.needed
      raise "#{program} imports no DLLs, which is not a Windows program" if imports.empty?

      foreign = imports.grep_v(allowed)
      raise "#{program} imports DLLs Windows does not ship: #{foreign.join(', ')}" unless foreign.empty?
    end

    private def tool(name, prefix: "#{TARGETS.fetch(@builder.platform.name)}-")
      File.join(@toolchain, "bin", "#{prefix}#{name}")
    end

    private def includes(tree)
      headers = Dir.glob(File.join(tree, "include", "ruby-*")).first or raise "#{tree} has no Ruby headers"
      ["-isystem", headers, "-isystem", File.join(headers, @builder.platform.name), "-I", LAUNCHER]
    end

    # The name of Ruby's DLL in bin\, such as x64-ucrt-ruby410.dll.
    private def ruby_dll(tree)
      dlls = Dir.glob(File.join(tree, "bin", "*-ruby*.dll"))
      raise "#{tree}/bin holds no single Ruby DLL: #{dlls}" unless dlls.size == 1

      File.basename(dlls.first.to_s)
    end

    private def unpack_rubyinstaller
      pin = @builder.sources.fetch("ruby").fetch("platforms").fetch(@builder.platform.name)
      archive = @builder.fetch_pin(pin)
      verify(archive, pin.fetch("signature"))
      unpacked = File.join(@build_dir, "rubyinstaller")
      FileUtils.mkdir_p(unpacked)
      extract_7z(archive, unpacked)
      trees = Dir.glob(File.join(unpacked, "*")).select { |path| File.directory?(path) }
      raise "#{archive} does not hold one RubyInstaller tree: #{trees}" unless trees.size == 1

      trees.first.to_s
    end

    # Checks +archive+ against its detached signature with gpgv, which
    # trusts only the keyring it is given: here, the one key the pin
    # names, and the signature must be that key's, by fingerprint.
    private def verify(archive, pin)
      signature = @builder.fetch_pin(pin)
      key = pin.fetch("key")
      keyring = File.join(@build_dir, "rubyinstaller-signing-key.gpg")
      File.binwrite(keyring, Armor.dearmor(File.read(@builder.fetch(key.fetch("url"), key.fetch("sha256")))))
      gpgv = @builder.which("gpgv") or raise "checking RubyInstaller's signature needs gpgv (GnuPG) on PATH"
      status = @builder.capture(gpgv, "--keyring", keyring, "--status-fd", "1", signature, archive)
      fingerprint = key.fetch("fingerprint")
      raise "#{archive} is not signed by #{fingerprint}" unless status.match?(/^\[GNUPG:\] VALIDSIG #{fingerprint} /)

      puts "#{File.basename(archive)}: good signature from #{fingerprint}"
    end

    # 7-Zip where it is installed (Ubuntu's runners), and libarchive's
    # bsdtar otherwise (macOS's own tar).
    private def extract_7z(archive, into)
      if (seven_zip = @builder.which("7zz", "7z"))
        @builder.run(seven_zip, "x", "-y", "-bd", "-o#{into}", archive, out: File::NULL)
      elsif (bsdtar = @builder.which("bsdtar"))
        @builder.run(bsdtar, "-xf", archive, "-C", into)
      else
        raise "unpacking #{archive} needs 7z or bsdtar on PATH"
      end
    end

    # Unpacks the one +member+ of the Zstandard-compressed tarball
    # +archive+ into +into+, with zstd where the computer has it, as
    # GitHub's runners do, or else with 7-Zip's own 7zz, which mise.toml
    # pins, since Linux releases of zstd ship no program. LLVM's release is
    # compressed with a 2 GB window, which zstd reads only with --long=31. The 7z of
    # p7zip, which Ubuntu's runners also carry, is 16.02 and reads no
    # Zstandard, so it is never used here.
    private def extract_tar_zst(archive, into, member)
      decompress = if (zstd = @builder.which("zstd"))
        [zstd, "-dc", "--long=31", archive]
      elsif (seven_zip = @builder.which("7zz"))
        [seven_zip, "x", "-so", "-bd", archive]
      else
        raise "unpacking #{archive} needs zstd or 7-Zip's 7zz on PATH"
      end
      statuses = Open3.pipeline(decompress, ["tar", "-xf", "-", "-C", into, member])
      raise "could not unpack #{member} from #{archive}" unless statuses.all?(&:success?)
    end

    private def unpack_toolchain
      pin = @builder.sources.fetch("llvm-mingw").fetch("hosts").fetch(@builder.host.name)
      tarball = @builder.fetch(pin.fetch("url"), pin.fetch("sha256"))
      toolchain = File.join(@build_dir, "llvm-mingw")
      FileUtils.mkdir_p(toolchain)
      @builder.run("tar", "-xJf", tarball, "-C", toolchain, "--strip-components=1")
      toolchain
    end
  end
end
