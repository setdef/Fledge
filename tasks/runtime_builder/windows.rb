# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "fileutils"
require_relative "recipe"

class RuntimeBuilder
  # Windows: RubyInstaller's Ruby, checked against its signature, whose
  # tree goes into ruby\ with its shape unchanged and Fledge's RubyGems
  # defaults in place of RubyInstaller's, and the launcher cross-compiled
  # beside it with llvm-mingw. The launcher loads Ruby's DLL when it runs
  # (runtime/launcher/windows.c), so it needs Ruby's headers to build,
  # and nothing to link.
  class Windows < Recipe
    TARGET = "x86_64-w64-mingw32"

    # The PE Subsystem of a console program, which Windows gives a
    # console, and of a GUI one, which it does not.
    CONSOLE = 3
    GUI = 2

    # The DLLs a launcher may import: Windows' kernel and its universal C
    # runtime, which every supported Windows ships, and for a windowed
    # one, USER32 for its message box.
    IMPORTS = /\A(?:KERNEL32\.dll|api-ms-win-crt-[a-z0-9-]+\.dll)\z/i
    WINDOWED_IMPORTS = /\AUSER32\.dll\z/i

    # The Subsystem field of the Windows program at +path+ (2 for a GUI
    # program, 3 for a console one), from its PE optional header, which
    # starts 24 bytes into the PE header and holds Subsystem at offset 68
    # in both PE32 and PE32+.
    def self.pe_subsystem(path)
      bytes = File.binread(path, 4096).to_s
      raise "#{path} is not a Windows program" unless bytes.start_with?("MZ") && bytes.bytesize >= 64

      header = bytes.byteslice(0x3C, 4).to_s.unpack1("V").to_i
      raise "#{path} is not a Windows program" unless bytes.byteslice(header, 4) == "PE\0\0"

      bytes.byteslice(header + 24 + 68, 2).to_s.unpack1("v")
    end

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
      @builder.install_rubygems_defaults(File.join(ruby, "lib", "ruby"))
      copy_nsis(File.join(stage, "tools", "nsis"))
      copy_rcedit(File.join(stage, "tools", "rcedit.exe"))
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
    # 009 and ADR 010): its license; makensis, the release's own Windows
    # program, and the zlib1.dll it loads; the stubs of solid LZMA
    # compression, NSIS's default and Tauri's, and the uninstaller's icon;
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
    # RubyInstaller ships rubyw.exe beside ruby.exe (ADR 008). Both build
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

    private def check(program, subsystem, allowed)
      actual = Windows.pe_subsystem(program)
      raise "#{program} has PE subsystem #{actual}, not #{subsystem}" unless actual == subsystem

      imports = @builder.capture(tool("objdump", prefix: "llvm-"), "-p", program).scan(/DLL Name: (\S+)/).flatten
      raise "#{program} imports no DLLs, which is not a Windows program" if imports.empty?

      foreign = imports.grep_v(allowed)
      raise "#{program} imports DLLs Windows does not ship: #{foreign.join(', ')}" unless foreign.empty?
    end

    private def tool(name, prefix: "#{TARGET}-")
      File.join(@toolchain, "bin", "#{prefix}#{name}")
    end

    private def includes(tree)
      headers = Dir.glob(File.join(tree, "include", "ruby-*")).first or raise "#{tree} has no Ruby headers"
      ["-isystem", headers, "-isystem", File.join(headers, "x64-mingw-ucrt"), "-I", LAUNCHER]
    end

    # The name of Ruby's DLL in bin\, such as x64-ucrt-ruby400.dll.
    private def ruby_dll(tree)
      dlls = Dir.glob(File.join(tree, "bin", "*-ruby*.dll"))
      raise "#{tree}/bin holds no single Ruby DLL: #{dlls}" unless dlls.size == 1

      File.basename(dlls.first.to_s)
    end

    private def unpack_rubyinstaller
      pin = @builder.sources.fetch("ruby").fetch("platforms").fetch(@builder.platform.name)
      archive = @builder.fetch(pin.fetch("url"), pin.fetch("sha256"))
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
      signature = @builder.fetch(pin.fetch("url"), pin.fetch("sha256"))
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
      if (seven_zip = @builder.which("7z", "7zz"))
        @builder.run(seven_zip, "x", "-y", "-bd", "-o#{into}", archive, out: File::NULL)
      elsif (bsdtar = @builder.which("bsdtar"))
        @builder.run(bsdtar, "-xf", archive, "-C", into)
      else
        raise "unpacking #{archive} needs 7z or bsdtar on PATH"
      end
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
