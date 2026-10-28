# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "rubygems/package"
require "stringio"
require "zlib"

class LicenseAudit
  # Reads the words of every text file in an audited tree, and of every
  # file inside its cached .gem archives, for a copyleft license named
  # where no component's license and no person's review accounts for it,
  # and checks each file in a cached gem holds no compiled code and no
  # copyleft library's code.
  class CopyleftText
    # A reader of +audit+'s tree that reports each violation to
    # +violate+, with its rule, path, and message.
    def initialize(audit, violate)
      @audit = audit
      @violate = violate
    end

    # Text that names a copyleft license must be in a file whose own
    # component carries that license, or in one a person reviewed.
    def check_files(files, owners, binaries)
      files.each do |path|
        next if binaries.key?(path) || @audit.symlink?(path)

        text = @audit.bytes(path)
        next if text.bytesize > TEXT_LIMIT

        check_text(path, [path], owners[path], text)
      end
    end

    private def check_text(label, names, owner, text)
      return if owner && LicenseAudit.category(owner.license, first_party: owner.first_party) != :notice_only
      return if text.byteslice(0, 8192).to_s.include?("\0")
      return unless COPYLEFT_BYTES.match?(text)
      return if names.any? { |name| reviewed.any? { |pattern| @audit.matches?(pattern, name) } }

      word = text[COPYLEFT_BYTES]
      @violate.call("copyleft-text", label, "names #{word.inspect}, but #{owner&.id || 'no component'} is #{owner&.license}; review it in runtime/licenses.yml")
    end

    private def reviewed
      @reviewed ||= @audit.map.fetch("reviewed", []).flat_map { |entry| entry.fetch("files") }
    end

    # A gem's .gem in RubyGems' cache holds every file the gem was
    # released with, which can be more than Ruby installed into its folder
    # (Ruby installs a bundled gem's listed files only), and it ships too.
    # So each file in it is checked as a file of the tree is, as
    # CACHE.gem!FILE: it may hold no compiled code and no copyleft
    # library's code, and its words may name a copyleft license only where
    # a person reviewed them, as CACHE.gem!FILE or as the file of the same
    # name in the gem's folder.
    def check_gem_archives(files, owners)
      files.grep(%r{\A(?:#{@audit.prefixes.map { |prefix| Regexp.escape(prefix) }.join('|')})lib/ruby/gems/[^/]+/cache/[^/]+\.gem\z}).each do |path|
        check_gem_archive(path, owners[path])
      end
    end

    private def check_gem_archive(path, owner)
      installed = "#{File.dirname(path, 2)}/gems/#{File.basename(path, '.gem')}"
      read = CopyleftText.gem_files(File.join(@audit.tree, path)) do |name, bytes|
        label = "#{path}!#{name}"
        binary = Binary.parse(bytes)
        @violate.call("unlisted-binary", label, "is compiled code (#{binary.format}) inside a cached gem") if binary
        signature = @audit.map.fetch("signatures").find { |entry| entry.fetch("bytes").any? { |needle| bytes.include?(needle.b) } }
        @violate.call("static-copyleft", label, "holds #{signature.fetch('component')}'s code inside a cached gem") if signature
        check_text(label, [label, "#{installed}/#{name}"], owner, bytes) unless binary || bytes.bytesize > TEXT_LIMIT
      end
      @violate.call("unreadable", path, "is not a .gem the audit can read: it holds no data.tar.gz") unless read
    rescue Gem::Package::TarInvalidError, Zlib::Error, ArgumentError => e
      @violate.call("unreadable", path, "is not a .gem the audit can read (#{e.message})")
    end

    # Yields the name and bytes of each file in the .gem at +path+: the
    # entries of its data.tar.gz (RubyGems' package format, a tar holding
    # metadata.gz, data.tar.gz, and checksums.yaml.gz). Returns whether it
    # found a data.tar.gz at all.
    def self.gem_files(path)
      File.open(path, "rb") do |io|
        Gem::Package::TarReader.new(io).each.count do |outer|
          next false unless outer.full_name == "data.tar.gz"

          Zlib::GzipReader.wrap(StringIO.new(outer.read.to_s)) do |gzip|
            Gem::Package::TarReader.new(gzip).each { |entry| yield entry.full_name, entry.read.to_s.b if entry.file? }
          end
          true
        end.positive?
      end
    end
  end
end
