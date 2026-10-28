# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "digest"
require "rubygems/package"
require "stringio"
require "zlib"

class RuntimeBuilder
  # Rewrites a .gem without some of its files, in RubyGems' own format,
  # so the gem still verifies.
  module GemRepack
    # Rewrites the .gem at +path+ without the files under +folder+, in
    # RubyGems' own format (a tar of metadata.gz, data.tar.gz, and
    # checksums.yaml.gz): data.tar.gz without them, the specification in
    # metadata.gz no longer listing them, and checksums.yaml.gz over the
    # new two, so Gem::Package#verify, and so gem pristine, accept it.
    # Every other entry, and every timestamp, stays as it was.
    def self.repack(path, folder)
      entries = read_tar(File.binread(path))
      data = entries.fetch("data.tar.gz")
      files = read_tar(gunzip(data.fetch(:bytes))).reject { |name, _| name.start_with?(folder) }
      data[:bytes] = regzip(data.fetch(:bytes), write_tar(files))
      metadata = entries.fetch("metadata.gz")
      spec = Gem::Specification.from_yaml(gunzip(metadata.fetch(:bytes)))
      spec.files = spec.files.reject { |name| name.start_with?(folder) }
      metadata[:bytes] = regzip(metadata.fetch(:bytes), spec.to_yaml)
      checksums = entries.fetch("checksums.yaml.gz")
      checksums[:bytes] = regzip(checksums.fetch(:bytes), gem_checksums(entries.slice("metadata.gz", "data.tar.gz")).to_yaml)
      File.binwrite(path, write_tar(entries))
    end

    # RubyGems' checksums.yaml: each digest of each file (Gem::Package's
    # build, at Ruby 4.0.9).
    private_class_method def self.gem_checksums(entries)
      { "SHA256" => Digest::SHA256, "SHA512" => Digest::SHA512 }.transform_values do |digest|
        entries.transform_values { |entry| digest.hexdigest(entry.fetch(:bytes)) }
      end
    end

    # The files of a tar, by name, each with its bytes, mode, and mtime.
    private_class_method def self.read_tar(bytes)
      Gem::Package::TarReader.new(StringIO.new(bytes)).each.with_object({}) do |entry, files|
        next unless entry.file?

        files[entry.full_name] = { bytes: entry.read.to_s.b, mode: entry.header.mode, mtime: entry.header.mtime }
      end
    end

    private_class_method def self.write_tar(files)
      io = StringIO.new(+"".b)
      Gem::Package::TarWriter.new(io) do |tar|
        files.each { |name, file| tar.add_file(name, file.fetch(:mode), Time.at(file.fetch(:mtime))) { |out| out.write(file.fetch(:bytes)) } }
      end
      io.string
    end

    private_class_method def self.gunzip(bytes)
      Zlib::GzipReader.wrap(StringIO.new(bytes)) { |gzip| gzip.read.to_s.b }
    end

    # +bytes+ compressed as a gzip member with the MTIME of the member
    # +original+ (RFC 1952, section 2.3: bytes 4 to 7, little-endian).
    private_class_method def self.regzip(original, bytes)
      io = StringIO.new(+"".b)
      Zlib::GzipWriter.wrap(io) do |gzip|
        gzip.mtime = original.byteslice(4, 4).to_s.unpack1("V").to_i
        gzip.write(bytes)
      end
      io.string
    end
  end
end
