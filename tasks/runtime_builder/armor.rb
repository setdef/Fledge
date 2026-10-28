# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

class RuntimeBuilder
  # OpenPGP's ASCII armor (RFC 4880, section 6), which gpgv reads only
  # as binary.
  module Armor
    # The bytes of an ASCII-armored OpenPGP block (RFC 4880, section 6),
    # which gpgv reads only as binary. Raises when the armor's CRC-24 does
    # not match.
    def self.dearmor(armored)
      body = armored[/^-----BEGIN PGP [A-Z ]+-----\r?\n(.*?)^-----END PGP /m, 1] or raise "not an ASCII-armored OpenPGP block"
      lines = body.split(/\r?\n\r?\n/, 2).last.to_s.lines.map(&:strip).reject(&:empty?)
      checksum = lines.last.to_s.start_with?("=") ? lines.pop.to_s.delete_prefix("=") : nil
      bytes = lines.join.unpack1("m0")
      raise "the armor's CRC-24 does not match its data" if checksum && [crc24(bytes)].pack("N").byteslice(1, 3) != checksum.unpack1("m0")

      bytes
    end

    def self.crc24(bytes)
      bytes.each_byte.reduce(0xB704CE) do |crc, byte|
        crc ^= byte << 16
        8.times { crc = (crc << 1).then { |shifted| shifted.anybits?(0x1000000) ? shifted ^ 0x1864CFB : shifted } }
        crc
      end & 0xFFFFFF
    end
  end
end
