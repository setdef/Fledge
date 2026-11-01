# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

module Fledge
  class Binary
    # What LLVM's <tt>llvm-readobj --file-headers --coff-imports</tt>
    # prints for a PE file: "File: FILE", then its headers, the Subsystem
    # among them, then an <tt>Import</tt> block for each DLL the import
    # table names and a <tt>DelayImport</tt> block for each the delay
    # import table names, each beginning with the DLL's Name.
    module Readobj # :nodoc:
      # What to run the tool with before the files.
      ARGUMENTS = ["--file-headers", "--coff-imports"].freeze

      # The options Fledge::Binary::Readers runs the tool with.
      def self.arguments
        ARGUMENTS
      end

      # What the tool printed for each of +paths+ it read, by path.
      def self.sections(output, paths)
        known = paths.to_h { |path| [path, true] }
        sections = {} # : Hash[String, String]
        current = nil # : String?
        output.each_line do |line|
          name = line[/\AFile: (.+?)\s*\z/, 1]
          current = name.to_s if name && known.key?(name.to_s)
          sections[current] = "#{sections[current]}#{line}" if current
        end
        sections
      end

      # Whether +error+ says the tool did not recognize the file at
      # +path+: "error: 'PATH': ...".
      def self.rejected?(error, path)
        error.include?("'#{path}'")
      end

      # The Binary +section+ describes.
      def self.binary(section)
        subsystem = section[/^\s*Subsystem: \S+ \(0x(\h+)\)\s*$/, 1]
        Binary.new(format: :pe, needed: section.scan(/^(?:Import|DelayImport) \{\s*\n\s*Name: (.+?)\s*$/).flatten.map(&:to_s).uniq,
          assemblies: [], macos_minimum: nil, glibc_minimum: nil, subsystem: subsystem&.to_i(16))
      end
    end
  end
end
