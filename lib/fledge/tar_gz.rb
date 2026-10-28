# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "zlib"
require_relative "entry"
require_relative "error"
require_relative "tar_gz/writer"
require_relative "tar_gz/reader"

module Fledge
  # Reads and writes gzipped tar archives, the kind a macOS or Linux app
  # ships in.
  #
  # A built app is useless if its launcher loses its executable bit or a
  # symlink turns into a copy on the way to the person who downloads it.
  # The tar command keeps both, but only from a disk that keeps them, and
  # a Windows disk does not, so an archive built from a folder on Windows
  # would ship a launcher nobody can run.
  #
  # This module writes Fledge::Entry values, which carry their own
  # permissions, straight into the archive, and reads them back the same
  # way, so the archive is right wherever it is built. It writes POSIX
  # ustar headers, with pax records for long paths, which every tar
  # reads; it reads the same, plus GNU long names.
  #
  # Use it to read a runtime and to write a built app.
  #
  # === Examples
  #
  #--
  # SPDX-SnippetBegin
  # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
  # SPDX-License-Identifier: MIT-0
  #++
  #   Fledge::TarGz.write("hello.tar.gz") do |archive|
  #     archive.add(Fledge::Entry.directory("hello"))
  #     archive.add(Fledge::Entry.file("hello/hello", launcher, mode: 0o755))
  #   end
  #
  #   Fledge::TarGz.each_entry("hello.tar.gz") { |entry| puts entry.path }
  #   # hello
  #   # hello/hello
  #--
  # SPDX-SnippetEnd
  #++
  module TarGz
    # Tar's unit: headers and contents fill whole blocks of this size.
    BLOCK = 512

    # The extension of a gzipped tar archive.
    EXTENSION = ".tar.gz"

    # The extension of the archives this module writes.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   Fledge::TarGz.extension # => ".tar.gz"
    #--
    # SPDX-SnippetEnd
    #++
    def self.extension
      EXTENSION
    end

    # Writes the archive at +path+, yielding a Writer to add entries to,
    # and returns +path+. Stamps every entry with +mtime+ (default: the
    # current time), as seconds since 1970.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   Fledge::TarGz.write("notes.tar.gz") { |archive| archive.add(Fledge::Entry.file("a.txt", "a\n")) }
    #--
    # SPDX-SnippetEnd
    #++
    def self.write(path, mtime: Time.now.to_i)
      File.open(path, "wb") do |file|
        gzip = Zlib::GzipWriter.new(file, Zlib::BEST_COMPRESSION)
        gzip.mtime = Time.at(mtime)
        writer = Writer.new(gzip, mtime:)
        yield writer
        writer.finish
        gzip.finish
      end
      path
    end

    # Yields each Fledge::Entry in the archive at +path+, in order.
    # Raises Fledge::Error for an archive that is not a tar.gz, holds an
    # unsafe path, or holds a kind of entry an app has no use for (a hard
    # link or a device).
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   Fledge::TarGz.each_entry("hello.tar.gz") { |entry| puts entry.path if entry.type == :file }
    #--
    # SPDX-SnippetEnd
    #++
    def self.each_entry(path, &)
      File.open(path, "rb") do |file|
        Reader.new(Zlib::GzipReader.new(file)).each(&)
      end
    rescue Zlib::Error => e
      raise Error, "#{path} is not a .tar.gz archive (#{e.message})"
    end
  end
end
