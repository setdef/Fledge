# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "error"

module Fledge
  # A Windows program's version information: the name, version, and
  # publisher Explorer's Properties dialog and Task Manager show.
  #
  # Task Manager names a running program by its version information's
  # FileDescription, and Explorer shows its ProductName, CompanyName,
  # versions, and LegalCopyright (decision 18). A program without one
  # shows only its file name. A resource compiler writes this resource
  # from a VERSIONINFO statement; Fledge has no resource compiler on the
  # computer that builds the app, which may not run Windows.
  #
  # This class writes the resource's bytes as Microsoft's "Version
  # Information" reference lays them out (VS_VERSIONINFO, with its
  # VS_FIXEDFILEINFO, a StringFileInfo holding one StringTable, and a
  # VarFileInfo holding its Translation): every block a header of three
  # 16-bit words and a UTF-16 key, its value and each child starting on a
  # 32-bit boundary, as Windows' own resource compiler pads them. The
  # strings are in U.S. English (0x0409) and Unicode (code page 1200), the
  # language the resource is written under.
  #
  # Use it through Fledge::WindowsResources.
  #
  # === Example
  #
  #--
  # SPDX-SnippetBegin
  # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
  # SPDX-License-Identifier: MIT-0
  #++
  #   info = Fledge::VersionInfo.new(version: "1.2.3", strings: { "ProductName" => "MyCoolApp" })
  #   info.bytes # => "\x..." for an RT_VERSION resource
  #--
  # SPDX-SnippetEnd
  #++
  class VersionInfo < Data.define(:version, :strings)
    ##
    # :attr_reader: version
    # The version, such as <tt>"1.2.3"</tt> or <tt>"0.0.1.pre.6"</tt>.

    ##
    # :attr_reader: strings
    # The string values, by name, such as <tt>"FileDescription"</tt>.
    # Empty values are left out.

    # The language of the strings: U.S. English.
    LANGUAGE = 0x0409

    # The code page of the strings: Unicode (UTF-16).
    CODE_PAGE = 1200

    # VS_FIXEDFILEINFO's signature.
    SIGNATURE = 0xFEEF04BD

    # VS_FIXEDFILEINFO's structure version, 1.0.
    STRUCTURE_VERSION = 0x0001_0000

    # Every file flag Windows defines (VS_FFI_FILEFLAGSMASK).
    FLAGS_MASK = 0x3F

    # The operating system the program is for: 32-bit Windows NT and later
    # (VOS_NT_WINDOWS32), as resource compilers write it for any program.
    OS = 0x0004_0004

    # The kind of file: an application (VFT_APP).
    APPLICATION = 1

    # The largest part of a Windows version number: each is 16 bits.
    MAX_PART = 65_535

    # The four numbers of a Windows file version made from +version+: its
    # leading parts that are numbers, padded with zeros. Raises
    # Fledge::Error when it has none, or one too large for 16 bits.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   Fledge::VersionInfo.numbers("0.0.1.pre.6") # => [0, 0, 1, 0]
    #   Fledge::VersionInfo.numbers("2026.10")     # => [2026, 10, 0, 0]
    #--
    # SPDX-SnippetEnd
    #++
    def self.numbers(version)
      parts = version.split(".").take_while { |part| part.match?(/\A\d+\z/) }.first(4).map(&:to_i)
      raise Error, "the version #{version} does not begin with a number" if parts.empty?

      too_large = parts.find { |part| part > MAX_PART }
      raise Error, "the version #{version} has a part, #{too_large}, larger than Windows' version numbers hold (#{MAX_PART})" if too_large

      parts.fill(0, (parts.size)...4)
    end

    # The RT_VERSION resource's bytes.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   Fledge::VersionInfo.new(version: "1.0", strings: {}).bytes.byteslice(6, 32)
    #   # => "VS_VERSION_INFO" in UTF-16, and its terminator
    #--
    # SPDX-SnippetEnd
    #++
    def bytes
      numbers = VersionInfo.numbers(version)
      ms = (numbers.fetch(0) << 16) | numbers.fetch(1)
      ls = (numbers.fetch(2) << 16) | numbers.fetch(3)
      fixed = [SIGNATURE, STRUCTURE_VERSION, ms, ls, ms, ls, FLAGS_MASK, 0, OS, APPLICATION, 0, 0, 0].pack("V13")
      table = format("%<language>04X%<code_page>04X", language: LANGUAGE, code_page: CODE_PAGE)
      texts = strings.reject { |_, value| value.to_s.empty? }.map { |name, value| block(name, utf16(value.to_s), (value.to_s.encode(Encoding::UTF_16LE).bytesize / 2) + 1, 1) }
      string_info = block("StringFileInfo", "", 0, 1, [block(table, "", 0, 1, texts)])
      var_info = block("VarFileInfo", "", 0, 1, [block("Translation", [LANGUAGE, CODE_PAGE].pack("v2"), 4, 0)])
      block("VS_VERSION_INFO", fixed, fixed.bytesize, 0, [string_info, var_info])
    end

    # One block: its length, the length of its value (in bytes for binary
    # values, in 16-bit characters for text), its type (1 for text), its
    # key, then its value and children, each on a 32-bit boundary.
    private def block(key, value, value_length, type, children = [])
      out = [0, value_length, type].pack("v3") + utf16(key)
      out = pad(out) + value.b
      children.each { |child| out = pad(out) + child }
      out.bytesplice(0, 2, [out.bytesize].pack("v"))
      out
    end

    private def utf16(text)
      "#{text}\0".encode(Encoding::UTF_16LE).b
    end

    private def pad(bytes)
      bytes.ljust((bytes.bytesize + 3) / 4 * 4, "\0")
    end
  end
end
