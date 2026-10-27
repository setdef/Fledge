# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "test_helper"
require_relative "support/binaries"

# What Fledge::Binary reads that only compiling a gem needs: the oldest
# macOS a Mach-O file says it runs on.
class BinaryTest < Minitest::Test
  def test_reads_the_oldest_macos_a_mach_o_file_runs_on
    assert_equal "14.0", Fledge::Binary.macos_minimum(Binaries.macho(needed: ["/usr/lib/libSystem.B.dylib"], minos: "14.0"))
    assert_equal "27.1", Fledge::Binary.macos_minimum(Binaries.macho(minos: "27.1"))
  end

  def test_a_file_that_says_no_macos_or_is_not_mach_o_has_none
    assert_nil Fledge::Binary.macos_minimum(Binaries.macho(needed: ["/usr/lib/libSystem.B.dylib"]))
    assert_nil Fledge::Binary.macos_minimum(Binaries.elf(needed: ["libc.so.6"]))
    assert_nil Fledge::Binary.macos_minimum("plain text")
  end

  # The newest glibc symbol version a Linux file needs is the oldest glibc
  # it loads on, as auditwheel reads it for manylinux.
  def test_reads_the_oldest_glibc_an_elf_file_runs_on
    assert_equal "2.34", Fledge::Binary.glibc_minimum(Binaries.elf(needed: ["libc.so.6"], versions: %w[GLIBC_2.2.5 GLIBC_2.34 GLIBC_2.17]))
    assert_nil Fledge::Binary.glibc_minimum(Binaries.elf(needed: ["libc.so.6"]))
    assert_nil Fledge::Binary.glibc_minimum(Binaries.macho(minos: "14.0"))
  end
end
