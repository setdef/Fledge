# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "tmpdir"
require_relative "../../lib/fledge/binary"

class LicenseAudit
  # The compiled files of an audited tree, and of the archives in it, as
  # the tools in +readers+ (Fledge::Binary::Readers) read them. A file
  # that begins as compiled code of a format no tool here reads is still
  # compiled code, which the audit must account for, so it is kept, with
  # nothing it can say it needs, and reported to +violate+: the audit is
  # then run where a tool reads it, as CI reads every runtime with LLVM's.
  class Binaries
    def initialize(readers, violate)
      @readers = readers
      @violate = violate
    end

    # The Binary of each compiled file among +files+, a file's label and
    # its path, by label.
    def on_disk(files)
      readable, unread = files.filter_map do |label, path|
        format = (File.symlink?(path) || !File.file?(path)) ? nil : Fledge::Binary.format_of(File.binread(path, 8).to_s)
        [label, path, format] if format
      end.partition { |_, _, format| format == :archive || @readers.reads?(format) }
      read = Fledge::Binary.read(readable.map { |_, path, _| path }, readers: @readers)
      found = readable.filter_map { |label, path, _| (binary = read[path]) && [label, binary] }.to_h
      unread.each { |label, _, format| found[label] = unreadable(label, format) }
      files.keys.filter_map { |label| (binary = found[label]) && [label, binary] }.to_h
    end

    # The Binary of each compiled file among +files+, a file's label and
    # its bytes, by label.
    def in_memory(files)
      compiled = files.select { |_, bytes| Fledge::Binary.format_of(bytes.byteslice(0, 8).to_s) }
      return {} if compiled.empty?

      Dir.mktmpdir("license-audit") do |dir|
        paths = compiled.keys.each_with_index.to_h { |label, index| [label, File.join(dir, index.to_s)] }
        paths.each { |label, path| File.binwrite(path, compiled.fetch(label)) }
        on_disk(paths)
      end
    end

    private def unreadable(label, format)
      @violate.call("unreadable", label, "is compiled code (#{format}) that no tool on this computer reads. #{@readers.install}")
      Fledge::Binary.new(format:, needed: [], rpaths: [], assemblies: [], macos_minimum: nil, glibc_minimum: nil, subsystem: nil)
    end
  end
end
