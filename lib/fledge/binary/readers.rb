# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "open3"

module Fledge
  class Binary
    # Which tool reads which format of compiled file on this computer,
    # and how to get them.
    #
    # Each platform's app is built on that platform (ADR 010), so
    # <tt>fledge build</tt> reads its own platform's format with that
    # platform's tool: on a Mac, Xcode's command line tools' objdump
    # (LLVM's), which compiling a gem needs anyway; on Linux, binutils'
    # objdump; on Windows, the llvm-readobj the Windows runtime carries in
    # its <tt>tools</tt> folder, since Windows has no such tool. The
    # license audit, which reads every format of every platform's runtime
    # on one Linux computer in CI, uses LLVM's own llvm-objdump and
    # llvm-readobj, from the llvm-mingw or Android NDK that
    # <tt>runtime/sources.yml</tt> pins (#llvm).
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   Fledge::Binary::Readers.local("linux").reads?(:elf)                 # => true
    #   Fledge::Binary::Readers.llvm("tmp/llvm-mingw/bin").reads?(:macho)  # => true
    #--
    # SPDX-SnippetEnd
    #++
    class Readers < Data.define(:commands, :install)
      ##
      # :attr_reader: commands
      # The tool that reads each format, by format.

      ##
      # :attr_reader: install
      # What to install when a tool is missing.

      # How each format's tool prints what Fledge reads.
      DIALECTS = { elf: Objdump, macho: Objdump, pe: Readobj }.freeze

      # How many files to hand a tool at once, well inside Windows' limit
      # on the length of a command line.
      BATCH = 64

      # The readers <tt>fledge build</tt> uses on a computer whose
      # operating system is +os+ (Fledge::Platform#os): on Windows,
      # +readobj+, the runtime's llvm-readobj.
      #
      # === Example
      #
      #--
      # SPDX-SnippetBegin
      # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
      # SPDX-License-Identifier: MIT-0
      #++
      #   Fledge::Binary::Readers.local("windows", readobj: "tools/llvm-readobj.exe").reads?(:pe) # => true
      #--
      # SPDX-SnippetEnd
      #++
      def self.local(os, readobj: nil)
        case os
        when "darwin"
          new(commands: { elf: "objdump", macho: "objdump" },
            install: "Install Xcode's command line tools (xcode-select --install), whose objdump reads compiled files.")
        when "linux", "linux-musl"
          new(commands: { elf: "objdump" },
            install: "Install binutils, whose objdump reads compiled files (sudo apt install binutils, sudo dnf install binutils).")
        else
          new(commands: readobj ? { pe: readobj } : {}, install: "Windows runtimes from Fledge 0.0.1.pre.11 on carry tools/llvm-readobj.exe.")
        end
      end

      # LLVM's readers in the folder +bin+, which read every format.
      #
      # === Example
      #
      #--
      # SPDX-SnippetBegin
      # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
      # SPDX-License-Identifier: MIT-0
      #++
      #   Fledge::Binary::Readers.llvm("/opt/llvm-mingw/bin").commands[:pe] # => "/opt/llvm-mingw/bin/llvm-readobj"
      #--
      # SPDX-SnippetEnd
      #++
      def self.llvm(bin)
        objdump = File.join(bin, "llvm-objdump")
        new(commands: { elf: objdump, macho: objdump, pe: File.join(bin, "llvm-readobj") },
          install: "#{bin} needs LLVM's llvm-objdump and llvm-readobj, as the llvm-mingw runtime/sources.yml pins has them.")
      end

      # Whether a tool here reads +format+.
      def reads?(format)
        commands.key?(format)
      end

      # These readers, with +other+'s for the formats these do not read.
      def merge(other)
        with(commands: other.commands.merge(commands))
      end

      # What the tool for +format+ says of each of +paths+, files of that
      # format, by path, as a Binary without assemblies: each it does not
      # recognize is left out. Raises Fledge::Error when no tool here
      # reads +format+, or the tool fails.
      def read(format, paths)
        command = commands.fetch(format) { raise Error, "no tool on this computer reads #{format} files, such as #{paths.first}. #{install}" }
        dialect = DIALECTS.fetch(format)
        found = {} # : Hash[String, Binary?]
        pending = paths
        until pending.empty?
          batch = pending.first(BATCH)
          output, error = capture(command, *dialect.arguments, *batch)
          sections = dialect.sections(output, batch)
          refused = batch.reject { |path| sections.key?(path) }.select { |path| dialect.rejected?(error, path) }
          raise Error, "#{File.basename(command)} could not read #{batch.first}. #{install}\n#{error.strip}" if sections.empty? && refused.empty?

          sections.each { |path, section| found[path] = dialect.binary(section) }
          refused.each { |path| found[path] = nil }
          pending = pending.reject { |path| found.key?(path) }
        end
        found.compact
      end

      # The tool's standard output and error. A tool that stops at the
      # first file it does not recognize, as LLVM's do, fails with the
      # files before it read, which #read keeps, reading the rest again.
      private def capture(*command)
        output, error, = Open3.capture3(*command, binmode: true)
        [output.force_encoding(Encoding::UTF_8).scrub, error.force_encoding(Encoding::UTF_8).scrub]
      rescue SystemCallError => e
        raise Error, "reading compiled files needs #{File.basename(command.first.to_s)}, which could not run (#{e.message}). #{install}"
      end
    end
  end
end
