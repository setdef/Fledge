# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "digest"

# Compiled files for the tests, each a real shared object, bundle, or
# DLL that LLVM's compiler and linker made (test/fixtures/binaries/
# build.rb), so the tools Fledge reads them with (Fledge::Binary) read
# them as they read any compiler's output. Each names the libraries a
# test asks for, and a test's payload, such as a version string a
# license audit looks for, follows the file's last byte, where every
# format's tools ignore it, as they ignore an installer's data appended
# to a program.
module Binaries
  # Where the files are.
  DIR = File.expand_path("../fixtures/binaries", __dir__)

  # Every file the tests use, as what build.rb makes it from: its format
  # and the libraries it needs, and for ELF the glibc symbol versions it
  # needs, for Mach-O the platform and oldest version it is built for,
  # for PE the DLLs it delay-loads and whether it is a console or a GUI
  # program rather than a DLL.
  CATALOG = [
    { format: "elf", needed: %w[libc.so.6] },
    { format: "elf", needed: [] },
    { format: "elf", needed: %w[libcrypt.so.2 libm.so.6 libc.so.6 ld-linux-x86-64.so.2] },
    { format: "elf", needed: %w[libcrypt.so.2 libc.so.6] },
    { format: "elf", needed: %w[libc.so.6 libcrypt.so.2] },
    { format: "elf", needed: %w[libreadline.so.8 libc.so.6] },
    { format: "elf", needed: %w[liblog.so libz.so libdl.so libm.so libc.so] },
    { format: "elf", needed: %w[libc.so] },
    { format: "elf", needed: %w[libc.so.6 libxml2.so.2] },
    { format: "elf", needed: %w[libc.so.6 libcrypt.so.2 libxml2.so.2 libown.so] },
    { format: "elf", needed: %w[libm.so.6] },
    { format: "elf", needed: %w[libz.so.1 libstdc++.so.6 ld-linux-x86-64.so.2] },
    { format: "elf", needed: %w[libc.so.6], versions: %w[GLIBC_2.2.5 GLIBC_2.34 GLIBC_2.17] },
    { format: "elf", needed: %w[libc.so.6], versions: %w[GLIBC_2.2.5 GLIBC_2.41] },
    { format: "elf", needed: %w[libc.so.6], versions: %w[GLIBC_2.34] },
    { format: "elf", needed: %w[libc.so.6], versions: %w[GLIBC_2.99] },
    { format: "macho", needed: %w[/usr/lib/libSystem.B.dylib] },
    { format: "macho", needed: %w[/usr/lib/libSystem.B.dylib @rpath/libffi.dylib] },
    {
format: "macho",
needed: [
  "/usr/lib/libSystem.B.dylib",
  "/System/Library/Frameworks/CoreFoundation.framework/Versions/A/CoreFoundation",
  "@loader_path/../ports/libpq.5.dylib",
  "/opt/homebrew/opt/libxml2/lib/libxml2.2.dylib",
    ],
},
    { format: "macho", needed: %w[/usr/lib/libz.1.dylib] },
    { format: "macho", needed: [], minos: "14.0" },
    { format: "macho", needed: [], minos: "15.0" },
    { format: "macho", needed: [], minos: "27.0" },
    { format: "macho", needed: [], minos: "27.1" },
    { format: "macho", needed: %w[/usr/lib/libSystem.B.dylib], platform: "ios" },
    { format: "pe", needed: %w[libgmp-10.dll KERNEL32.dll] },
    { format: "pe", needed: %w[KERNEL32.dll] },
    { format: "pe", needed: %w[x64-ucrt-ruby400.dll KERNEL32.dll api-ms-win-crt-heap-l1-1-0.dll libxml2-16.dll] },
    { format: "pe", needed: %w[x64-ucrt-ruby340.dll libother.dll] },
    {
      format: "pe",
      needed: %w[
        x64-ucrt-ruby400.dll
        dwmapi.dll
        IMM32.dll
        SETUPAPI.dll
        cfgmgr32.dll
        HID.dll
        d3d9.dll
        d3d11.dll
        dxgi.dll
        DINPUT8.dll
        DSOUND.dll
        OpenAL32.dll
      ],
    },
    { format: "pe", needed: %w[KERNEL32.dll AVRT.dll ole32.dll WINMM.dll] },
    { format: "pe", needed: %w[KERNEL32.dll], delayed: %w[USER32.dll] },
    { format: "pe", needed: %w[KERNEL32.dll], program: "console" },
    { format: "pe", needed: %w[KERNEL32.dll], program: "windows" },
  ].freeze

  # The defaults of each format's spec.
  DEFAULTS = {
    "elf" => { versions: [] },
    "macho" => { minos: "14.0", platform: "macos" },
    "pe" => { delayed: [], program: nil },
  }.freeze

  # An x86-64 ELF shared object that needs +needed+, and from libc.so.6
  # the symbol versions +versions+, such as "GLIBC_2.34", followed by
  # +payload+.
  def self.elf(needed: [], payload: "", versions: [])
    file({ format: "elf", needed:, versions: }, payload)
  end

  # An arm64 Mach-O bundle that loads +needed+, built for +platform+
  # (macos or ios) +minos+ and later, followed by +payload+.
  def self.macho(needed: [], payload: "", minos: "14.0", platform: "macos")
    file({ format: "macho", needed:, minos:, platform: }, payload)
  end

  # An x86-64 PE DLL, or a +program+ for the console or windows
  # subsystem, that imports +needed+ and delay-loads +delayed+, followed
  # by +payload+ (where a test can put an embedded manifest).
  def self.pe(needed: [], payload: "", delayed: [], program: nil)
    file({ format: "pe", needed:, delayed:, program: }, payload)
  end

  # +spec+ with its format's defaults.
  def self.normalize(spec)
    DEFAULTS.fetch(spec.fetch(:format)).merge(spec)
  end

  # The file name of +spec+'s file in DIR.
  def self.name(spec)
    spec = normalize(spec)
    extension = { "elf" => "so", "macho" => "bundle", "pe" => spec[:program] ? "exe" : "dll" }.fetch(spec.fetch(:format))
    "#{spec.fetch(:format)}-#{Digest::SHA256.hexdigest(spec.sort.to_h.inspect)[0, 12]}.#{extension}"
  end

  # The bytes of +spec+'s file, then +payload+.
  def self.file(spec, payload)
    path = File.join(DIR, name(spec))
    raise "no #{name(spec)} for #{normalize(spec)}: add it to Binaries::CATALOG and run test/fixtures/binaries/build.rb" unless File.file?(path)

    File.binread(path) + payload.b
  end
end
