# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "test_helper"
require_relative "support/binaries"

class WindowsProgramTest < Minitest::Test
  MANIFEST = [24, 1, 1033].freeze

  def headers(bytes)
    pe = bytes.byteslice(0x3C, 4).unpack1("V")
    optional = pe + 24
    count = bytes.byteslice(pe + 6, 2).unpack1("v")
    sections = Array.new(count) do |index|
      at = optional + bytes.byteslice(pe + 20, 2).unpack1("v") + (index * 40)
      name, size, address, raw_size, raw = bytes.byteslice(at, 24).unpack("a8V4")
      { name: name.delete("\0"), size:, address:, raw_size:, raw: }
    end
    directories = Array.new(16) { |index| bytes.byteslice(optional + 112 + (index * 8), 8).unpack("V2") }
    image, = bytes.byteslice(optional + 56, 4).unpack("V")
    initialized, = bytes.byteslice(optional + 8, 4).unpack("V")
    { sections:, directories:, image:, initialized: }
  end

  def test_reads_the_resources_and_subsystem
    program = Fledge::WindowsProgram.new(Programs.windows(subsystem: 2, manifest: "<assembly>hi</assembly>"))
    assert_equal({ MANIFEST => "<assembly>hi</assembly>" }, program.resources)
    assert_equal Fledge::WindowsProgram::GUI, program.subsystem
  end

  # The resource section grows in place, and the base relocations after
  # it move up, with the headers that describe them.
  def test_rewrites_the_resources_and_moves_what_follows
    original = Programs.windows
    icon = "\x89PNG".b + ("x" * 5000)
    resources = {
MANIFEST => "<assembly/>",
[3, 1, 1033] => icon,
[14, "MAINICON", 1033] => "group",
[16, 1, 1033] => "version",
["CUSTOM", "Named", 0] => "named",
}
    rewritten = Fledge::WindowsProgram.new(original).with_resources(resources)

    assert_equal resources, Fledge::WindowsProgram.new(rewritten).resources
    before = headers(original)
    after = headers(rewritten)
    rsrc = after[:sections][1]
    reloc = after[:sections][2]
    assert_equal [0x2000, rsrc[:size]], after[:directories][2]
    assert_operator rsrc[:size], :>, 5000
    assert_equal 0x2000 + ((rsrc[:size] + 0xFFF) / 0x1000 * 0x1000), reloc[:address]
    assert_equal rsrc[:raw] + rsrc[:raw_size], reloc[:raw]
    assert_equal [reloc[:address], 0x54], after[:directories][5]
    assert_equal reloc[:address] + 0x1000, after[:image]
    assert_equal before[:initialized] + rsrc[:raw_size] - before[:sections][1][:raw_size], after[:initialized]
    assert_equal original.byteslice(before[:sections][2][:raw], 0x54), rewritten.byteslice(reloc[:raw], 0x54)
    assert_equal original.byteslice(0x400, 0x200), rewritten.byteslice(0x400, 0x200), ".text stays where it was"
    assert_equal rewritten.bytesize, reloc[:raw] + reloc[:raw_size]
  end

  # The resource directory: named entries before IDs, each kind sorted, as
  # Windows' binary search through it expects.
  def test_sorts_each_directory_names_first
    resources = { [24, 1, 1033] => "m", [3, 2, 1033] => "b", [3, 1, 1033] => "a", ["ZED", 1, 0] => "z", ["ALPHA", 1, 0] => "y" }
    program = Fledge::WindowsProgram.new(Fledge::WindowsProgram.new(Programs.windows).with_resources(resources))
    assert_equal [["ALPHA", 1, 0], ["ZED", 1, 0], [3, 1, 1033], [3, 2, 1033], [24, 1, 1033]], program.resources.keys
  end

  def test_keeps_a_checksum_true
    original = Programs.windows(checksum: 1)
    rewritten = Fledge::WindowsProgram.new(original).with_resources({ MANIFEST => "<assembly>longer</assembly>" })
    field = rewritten.byteslice(0x3C, 4).unpack1("V") + 24 + 64
    assert_equal Fledge::WindowsProgram.checksum(rewritten, field), rewritten.byteslice(field, 4).unpack1("V")
    refute_equal 1, rewritten.byteslice(field, 4).unpack1("V")

    unchecked = Fledge::WindowsProgram.new(Programs.windows).with_resources({ MANIFEST => "x" })
    assert_equal 0, unchecked.byteslice(field, 4).unpack1("V")
  end

  def test_refuses_what_it_cannot_rewrite
    resources = { MANIFEST => "<assembly/>" }
    {
      Programs.windows(certificate: true) => "is signed; its resources must change before it is signed, not after",
      Programs.windows(overlay: "symbols") => "has data after its last section, which Fledge cannot move",
      Programs.windows(after: [".reloc", ".data"]) => "has sections after its resources (.reloc, .data) that Fledge cannot move",
    }.each do |bytes, message|
      error = assert_raises(Fledge::Error, message) { Fledge::WindowsProgram.new(bytes).with_resources(resources) }
      assert_equal message, error.message
    end
    assert_equal "is not a Windows program", assert_raises(Fledge::Error) { Fledge::WindowsProgram.new("#!/bin/sh\n") }.message
    assert_equal "is not a Windows program", assert_raises(Fledge::Error) { Fledge::WindowsProgram.new("MZ".ljust(0x40, "\0")) }.message
  end

  # The real checksum algorithm, against a value computed by hand: the
  # 16-bit words 0x0201 and 0x0004 sum to 0x0205, plus a length of 4.
  def test_computes_the_pe_checksum
    assert_equal 0x0205 + 4, Fledge::WindowsProgram.checksum([1, 2, 4, 0].pack("C*"), 100)
    assert_equal 0x0201 + 4, Fledge::WindowsProgram.checksum([1, 2, 4, 0].pack("C*"), 2)
  end
end
