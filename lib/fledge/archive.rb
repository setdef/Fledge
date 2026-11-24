# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require "fileutils"
require_relative "command"

module Fledge
  # Packs a folder into the archive it ships in, and unpacks one, with
  # the computer's own tools.
  #
  # A runtime arrives as a <tt>.tar.gz</tt>, and a built app leaves as
  # one, or as a <tt>.zip</tt> on Windows, where a person opens one with
  # a double-click. Every computer that builds an app has a tar that
  # reads and writes a <tt>.tar.gz</tt> without losing an executable bit
  # or a symbolic link: GNU tar on Linux, bsdtar (libarchive) on macOS,
  # and on Windows 10 and 11 the bsdtar Windows ships as
  # <tt>System32\\tar.exe</tt>. Fledge wrote its own tar and ZIP formats
  # only so that one computer could build every platform (ADR 101).
  #
  # This module runs that tar. It packs a folder under its own name, so
  # the archive unpacks into one folder; it unpacks an archive into a
  # folder; and it lists an archive's paths and reads one file from it,
  # which is how Fledge reads what a runtime holds before it unpacks it.
  # It records a neutral owner, id 0 with no name, as an archive meant
  # to be passed on does, not the account that built it. On macOS it
  # asks bsdtar for no AppleDouble files (+COPYFILE_DISABLE+),
  # which no other computer reads. On Windows it names
  # <tt>System32\\tar.exe</tt> itself, since another tar on the +PATH+,
  # such as Git's GNU tar, reads <tt>C:</tt> as a host name. That tar
  # reads its arguments in the system's ANSI code page, which turns a
  # folder named <tt>Prüfung 日本</tt> into <tt>Pr?fung ??</tt>, so no
  # path of a folder goes to it as an argument there: it unpacks in the
  # folder it unpacks into, with the archive on its standard input,
  # which Ruby opens by its UTF-16 name. And it crashes on a name the
  # code page cannot write inside the folder it packs, so on Windows a
  # built app's <tt>.zip</tt> is written by .NET's +ZipFile+, through
  # Windows PowerShell, instead.
  #
  # Use it to unpack a runtime and to pack a built app.
  #
  # === Example
  #
  #--
  # SPDX-SnippetBegin
  # SPDX-SnippetCopyrightText: 2026 setdef <kerrick@setdef.com>
  # SPDX-License-Identifier: MIT-0
  #++
  #   Fledge::Archive.pack("dist/MyApp-x86_64-linux", to: "dist/MyApp-x86_64-linux.tar.gz")
  #   Fledge::Archive.unpack("dist/MyApp-x86_64-linux.tar.gz", into: "/tmp/unpacked")
  #   Fledge::Archive.names("dist/MyApp-x86_64-linux.tar.gz").first # => "MyApp-x86_64-linux/"
  #--
  # SPDX-SnippetEnd
  #++
  module Archive
    # The extension of a gzipped tar archive.
    TAR_GZ = ".tar.gz"

    # The extension of a ZIP archive.
    ZIP = ".zip"

    # What to do when this computer has no tar.
    INSTALL = "Every macOS, Linux, and Windows 10 or newer has one; install tar."

    # Packs +folder+ into the archive +to+, whose extension, TAR_GZ or
    # ZIP, says which, under +folder+'s own name, and returns +to+.
    # Raises Fledge::Error when tar fails.
    #
    # On Windows nothing Fledge builds is a TAR_GZ: an app there ships
    # as a ZIP, and runtimes are built on Linux and macOS. Its tar.exe
    # packs one there only for ArchiveTest, which unpacks it, so the
    # folder's name, and +to+'s path when it is not beside the folder,
    # must be in the ANSI code page, and so must every name inside.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 setdef <kerrick@setdef.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   Fledge::Archive.pack("dist/MyApp-x64-mingw-ucrt", to: "dist/MyApp-x64-mingw-ucrt.zip")
    #--
    # SPDX-SnippetEnd
    #++
    def self.pack(folder, to:)
      zip = to.end_with?(ZIP)
      FileUtils.rm_f(to)
      return pack_with_dotnet(folder, to) if zip && Gem.win_platform?

      format = zip ? ["--format", "zip", "-cf"] : ["-cz", *neutral_owner, "-f"]
      parent = File.dirname(folder)
      file = (File.dirname(to) == parent) ? File.basename(to) : File.expand_path(to)
      Command.run(tar, *format, file, File.basename(folder), env: { "COPYFILE_DISABLE" => "1" }, chdir: parent, install: INSTALL)
      to
    end

    # The options that make tar record owner id 0 and group id 0, with
    # no names, in place of the account that packs: +--numeric-owner+
    # drops the names in both tars, and each takes the ids in its own
    # spelling, GNU tar's +--owner+ and +--group+, bsdtar's +--uid+ and
    # +--gid+. GNU tar says "GNU tar" in its +--version+; bsdtar, which
    # macOS and Windows ship, does not.
    private_class_method def self.neutral_owner
      version = Command.read(tar, "--version", install: INSTALL)
      return ["--owner=0", "--group=0", "--numeric-owner"] if version.include?("GNU tar")

      ["--uid", "0", "--gid", "0", "--numeric-owner"]
    end

    # What Windows PowerShell runs to zip the folder its +FLEDGE_FOLDER+
    # names into the file its +FLEDGE_ZIP+ names, under the folder's own
    # name: .NET's +ZipFile+, which writes each name in UTF-8 with the
    # ZIP's UTF-8 flag. The switch makes it separate a name's folders
    # with slashes, as the ZIP format asks (APPNOTE.TXT 4.4.17.1), not
    # the backslashes .NET Framework writes for a program built for a
    # version before 4.6.1, as Windows PowerShell 5.1 is.
    PACK_ZIP = "$ErrorActionPreference = 'Stop'; " \
      "[AppContext]::SetSwitch('Switch.System.IO.Compression.ZipFile.UseBackslash', $false); " \
      "Add-Type -AssemblyName System.IO.Compression.FileSystem; " \
      "[IO.Compression.ZipFile]::CreateFromDirectory($env:FLEDGE_FOLDER, $env:FLEDGE_ZIP, " \
      "[IO.Compression.CompressionLevel]::Optimal, $true)"

    # Packs +folder+ into the ZIP +to+ on Windows, with .NET's +ZipFile+
    # in Windows PowerShell, which Windows 11 has. Windows'
    # tar.exe cannot: it reads its arguments in the ANSI code page, and
    # crashes on a name inside the folder that code page cannot write.
    # The paths reach PowerShell in its environment, which Windows hands
    # it in UTF-16, so no code page comes between.
    private_class_method def self.pack_with_dotnet(folder, to)
      paths = { "FLEDGE_FOLDER" => File.expand_path(folder), "FLEDGE_ZIP" => File.expand_path(to) }
      Command.run(powershell, "-NoProfile", "-NonInteractive", "-Command", PACK_ZIP, env: paths,
        install: "Windows 11 has Windows PowerShell 5.1 there.")
      to
    end

    # Windows PowerShell, named in full, as #tar names Windows' tar.
    private_class_method def self.powershell
      File.join(ENV.fetch("SystemRoot", "C:\\Windows"), "System32", "WindowsPowerShell", "v1.0", "powershell.exe")
    end

    # Unpacks the archive +archive+ into the folder +into+, which it
    # creates: all of it, or with +only+, those paths in it and what they
    # hold. Raises Fledge::Error when tar fails.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 setdef <kerrick@setdef.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   Fledge::Archive.unpack("fledge-runtime-0.0.1-x86_64-linux.tar.gz", into: "/tmp/runtime")
    #--
    # SPDX-SnippetEnd
    #++
    def self.unpack(archive, into:, only: [])
      FileUtils.mkdir_p(into)
      if Gem.win_platform?
        Command.run(tar, "-xf", "-", *only, chdir: into, input: archive, install: INSTALL)
      else
        Command.run(tar, "-xf", archive, "-C", into, *only, install: INSTALL)
      end
      into
    end

    # The path of every entry in +archive+, as tar lists them, a folder's
    # with a slash at its end, one per line as tar prints them (with
    # Windows' line endings on Windows).
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 setdef <kerrick@setdef.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   Fledge::Archive.names("hello.tar.gz") # => ["hello/", "hello/hello"]
    #--
    # SPDX-SnippetEnd
    #++
    def self.names(archive)
      listing = Gem.win_platform? ? Command.read(tar, "-tf", "-", input: archive, install: INSTALL) : Command.read(tar, "-tf", archive, install: INSTALL)
      listing.force_encoding(Encoding::UTF_8).lines(chomp: true)
    end

    # The contents of the file +name+ in +archive+, as bytes.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 setdef <kerrick@setdef.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   Fledge::Archive.read("hello.tar.gz", "hello/main.rb") # => "puts 'hi'\n"
    #--
    # SPDX-SnippetEnd
    #++
    def self.read(archive, name)
      return Command.read(tar, "-xOf", "-", name, input: archive, install: INSTALL) if Gem.win_platform?

      Command.read(tar, "-xOf", archive, name, install: INSTALL)
    end

    # The tar to run: Windows' own, or the first on the +PATH+.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 setdef <kerrick@setdef.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   Fledge::Archive.tar # => "tar", or "C:\\Windows\\System32\\tar.exe"
    #--
    # SPDX-SnippetEnd
    #++
    def self.tar
      return "tar" unless Gem.win_platform?

      File.join(ENV.fetch("SystemRoot", "C:\\Windows"), "System32", "tar.exe")
    end
  end
end
