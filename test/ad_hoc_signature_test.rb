# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "test_helper"
require_relative "support/binaries"
require "digest"

# The signature is read back here as Apple's cs_blobs.h lays it out, by
# code of the test's own. test/built_app_test.rb has Apple's codesign
# verify a real bundle on macOS.
class AdHocSignatureTest < Minitest::Test
  def sign(program = Programs.macho, info: "<plist/>", resources: "<seal/>")
    Fledge::AdHocSignature.new(identifier: "com.example.Hello", info_plist: info, code_resources: resources).sign(program)
  end

  def command(bytes, wanted)
    at = 32
    bytes.byteslice(16, 4).unpack1("V").times do
      cmd, size = bytes.byteslice(at, 8).unpack("V2")
      return at if cmd == wanted

      at += size
    end
    nil
  end

  def linkedit(bytes)
    at = 32
    loop do
      cmd, size = bytes.byteslice(at, 8).unpack("V2")
      return at if cmd == 0x19 && bytes.byteslice(at + 8, 16).delete("\0") == "__LINKEDIT"

      at += size
    end
  end

  def test_signs_the_program_ad_hoc_for_its_bundle
    original = Programs.macho
    signed = sign(original, info: "INFO", resources: "SEAL")
    at = command(signed, 0x1D)
    offset, size = signed.byteslice(at + 8, 8).unpack("V2")

    assert_equal original.byteslice(0, 32), signed.byteslice(0, 32)
    assert_equal signed.bytesize, offset + size
    assert_equal 0, size % 16

    magic, length, count = signed.byteslice(offset, 12).unpack("N3")
    assert_equal [0xFADE0CC0, 3], [magic, count]
    index = signed.byteslice(offset + 12, 24).unpack("N6").each_slice(2).to_h
    assert_equal [0, 2, 0x10000], index.keys
    assert_equal [0xFADE0C01, 12, 0], signed.byteslice(offset + index.fetch(2), 12).unpack("N3")
    assert_equal [0xFADE0B01, 8], signed.byteslice(offset + index.fetch(0x10000), 8).unpack("N2")
    assert_operator length, :<=, size

    directory = offset + index.fetch(0)
    fields = signed.byteslice(directory, 44).unpack("N9C4N")
    magic, _length, version, flags, hash_offset, ident_offset, special, slots, limit, hash_size, hash_type, _, page = fields
    assert_equal [0xFADE0C02, 0x20400, 0x2, 3, 32, 2, 12], [magic, version, flags, special, hash_size, hash_type, page]
    assert_equal offset, limit
    assert_equal "com.example.Hello", signed.byteslice(directory + ident_offset, 17)
    assert_equal (offset + 4095) / 4096, slots
    exec_base, exec_limit, exec_flags = signed.byteslice(directory + 64, 24).unpack("Q>3")
    assert_equal [0, 0x4000, 1], [exec_base, exec_limit, exec_flags]

    hashes = Array.new(slots) { |slot| signed.byteslice(directory + hash_offset + (slot * 32), 32) }
    assert_equal Array.new(slots) { |slot| Digest::SHA256.digest(signed.byteslice(slot * 4096, [4096, offset - (slot * 4096)].min)) }, hashes
    specials = Array.new(3) { |slot| signed.byteslice(directory + hash_offset - ((slot + 1) * 32), 32) }
    assert_equal [Digest::SHA256.digest("INFO"), Digest::SHA256.digest([0xFADE0C01, 12, 0].pack("N3")), Digest::SHA256.digest("SEAL")], specials
  end

  # The signature grows with the identifier and the program, so the
  # segment that holds it, and the command that points at it, grow too.
  def test_resizes_linkedit_and_the_code_signature_command
    signed = sign
    segment = linkedit(signed)
    _, vm_size, file_offset, file_size = signed.byteslice(segment + 24, 32).unpack("Q<4")
    offset, size = signed.byteslice(command(signed, 0x1D) + 8, 8).unpack("V2")
    assert_equal offset + size, file_offset + file_size
    assert_equal 0, vm_size % 0x4000
    assert_operator vm_size, :>=, file_size

    assert_equal signed, sign(signed), "signing again gives the same program"
  end

  def test_refuses_what_it_cannot_sign
    {
      "#!/bin/sh\n" => "is not a 64-bit Mach-O program; Fledge signs only those",
      Programs.macho.byteslice(0, 32 + 72 + 72).then { |head| head.bytesplice(16, 4, [2].pack("V")) + ("\0" * 100) } =>
        "has no code signature to replace",
    }.each do |program, message|
      assert_equal message, assert_raises(Fledge::Error) { sign(program) }.message
    end
  end
end
