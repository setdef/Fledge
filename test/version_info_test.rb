# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "test_helper"

class VersionInfoTest < Minitest::Test
  # What LLVM's resource compiler, llvm-rc from llvm-mingw 20261020 (the
  # toolchain runtime/sources.yml pins), writes for this statement, with
  # llvm-rc -no-preprocess -c 65001, the RT_VERSION resource's data taken
  # from the .res file it wrote:
  #
  #   LANGUAGE 0x09, 0x01
  #   1 VERSIONINFO
  #   FILEVERSION 1,2,3,0
  #   PRODUCTVERSION 1,2,3,0
  #   FILEFLAGSMASK 0x3F
  #   FILEFLAGS 0
  #   FILEOS 0x40004
  #   FILETYPE 1
  #   FILESUBTYPE 0
  #   BEGIN
  #     BLOCK "StringFileInfo"
  #     BEGIN
  #       BLOCK "040904B0"
  #       BEGIN
  #         VALUE "CompanyName", "setdef\0"
  #         VALUE "FileDescription", "Hello Window\0"
  #         VALUE "FileVersion", "1.2.3.pre\0"
  #         VALUE "LegalCopyright", "© 2026\0"
  #         VALUE "OriginalFilename", "Hello Window.exe\0"
  #       END
  #     END
  #     BLOCK "VarFileInfo"
  #     BEGIN
  #       VALUE "Translation", 0x409, 1200
  #     END
  #   END
  LLVM_RC = <<~BASE64.unpack1("m")
    BAI0AAAAVgBTAF8AVgBFAFIAUwBJAE8ATgBfAEkATgBGAE8AAAAAAL0E7/4AAAEAAgABAAAAAwAC
    AAEAAAADAD8AAAAAAAAABAAEAAEAAAAAAAAAAAAAAAAAAABiAQAAAQBTAHQAcgBpAG4AZwBGAGkA
    bABlAEkAbgBmAG8AAAA+AQAAAQAwADQAMAA5ADAANABCADAAAAAuAAcAAQBDAG8AbQBwAGEAbgB5
    AE4AYQBtAGUAAAAAAHMAZQB0AGQAZQBmAAAAAABCAA0AAQBGAGkAbABlAEQAZQBzAGMAcgBpAHAA
    dABpAG8AbgAAAAAASABlAGwAbABvACAAVwBpAG4AZABvAHcAAAAAADQACgABAEYAaQBsAGUAVgBl
    AHIAcwBpAG8AbgAAAAAAMQAuADIALgAzAC4AcAByAGUAAAAyAAcAAQBMAGUAZwBhAGwAQwBvAHAA
    eQByAGkAZwBoAHQAAACpACAAMgAwADIANgAAAAAASgARAAEATwByAGkAZwBpAG4AYQBsAEYAaQBs
    AGUAbgBhAG0AZQAAAEgAZQBsAGwAbwAgAFcAaQBuAGQAbwB3AC4AZQB4AGUAAAAAAEQAAAABAFYA
    YQByAEYAaQBsAGUASQBuAGYAbwAAAAAAJAAEAAAAVAByAGEAbgBzAGwAYQB0AGkAbwBuAAAAAAAJ
    BLAE
  BASE64

  def test_writes_what_a_resource_compiler_writes
    strings = {
"CompanyName" => "setdef",
"FileDescription" => "Hello Window",
"FileVersion" => "1.2.3.pre",
"InternalName" => "",
"LegalCopyright" => "© 2026",
"OriginalFilename" => "Hello Window.exe",
}
    assert_equal LLVM_RC, Fledge::VersionInfo.new(version: "1.2.3.pre", strings:).bytes
  end

  def test_makes_four_numbers_from_a_version
    assert_equal [1, 2, 3, 0], Fledge::VersionInfo.numbers("1.2.3")
    assert_equal [0, 0, 1, 0], Fledge::VersionInfo.numbers("0.0.1.pre.6")
    assert_equal [1, 2, 3, 4], Fledge::VersionInfo.numbers("1.2.3.4.5")
    assert_equal [7, 0, 0, 0], Fledge::VersionInfo.numbers("7")
    assert_equal "the version 70000.1 has a part, 70000, larger than Windows' version numbers hold (65535)",
      assert_raises(Fledge::Error) { Fledge::VersionInfo.numbers("70000.1") }.message
    assert_equal "the version pre does not begin with a number", assert_raises(Fledge::Error) { Fledge::VersionInfo.numbers("pre") }.message
  end
end
