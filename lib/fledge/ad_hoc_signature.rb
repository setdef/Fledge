# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "digest"
require_relative "error"

module Fledge
  # Signs a macOS program ad hoc, binding it to the bundle it is in.
  #
  # A Mac with Apple Silicon runs only signed code, and a program inside
  # an <tt>.app</tt> bundle must have a signature that seals the bundle
  # too: its <tt>Info.plist</tt> and every resource, through the hashes of
  # <tt>_CodeSignature/CodeResources</tt>, or <tt>codesign --verify</tt>
  # calls the bundle broken. The launcher arrives signed, but alone; each
  # app's bundle is different, so each app's launcher is signed again when
  # <tt>fledge build</tt> writes the bundle, on whatever computer runs it.
  # Apple's codesign runs only on macOS.
  #
  # This class writes an ad hoc signature, one with no certificate, as
  # Apple's open-source headers describe it (+cs_blobs.h+ in xnu) and as
  # Go's linker writes one (+cmd/internal/codesign+): a SuperBlob holding
  # a CodeDirectory, an empty set of requirements, and an empty CMS
  # signature, as <tt>codesign --sign -</tt> writes them. The
  # CodeDirectory hashes each 4 KiB page of the program with SHA-256, and,
  # in its special slots, the bundle's <tt>Info.plist</tt> (slot 1), the
  # requirements (slot 2), and the bundle's CodeResources (slot 3). It
  # replaces the program's old signature at the end of its +__LINKEDIT+
  # segment, and resizes that segment and the +LC_CODE_SIGNATURE+ command
  # to fit. Signing with a certificate, and notarizing, are a later step,
  # for developers who have Apple's credentials (decision 17).
  #
  # Use it through Fledge::MacBundle.
  #
  # === Example
  #
  #--
  # SPDX-SnippetBegin
  # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
  # SPDX-License-Identifier: MIT-0
  #++
  #   signed = Fledge::AdHocSignature.new(
  #     identifier: "com.example.MyCoolApp", info_plist: plist, code_resources: resources
  #   ).sign(File.binread("launcher"))
  #--
  # SPDX-SnippetEnd
  #++
  class AdHocSignature
    # The magic number of an embedded signature's SuperBlob (cs_blobs.h).
    EMBEDDED_SIGNATURE = 0xFADE0CC0

    # The magic number of a CodeDirectory.
    CODE_DIRECTORY = 0xFADE0C02

    # The magic number of a set of requirements.
    REQUIREMENTS = 0xFADE0C01

    # The magic number of the blob that holds a CMS signature, empty when
    # the signature is ad hoc.
    BLOB_WRAPPER = 0xFADE0B01

    # The SuperBlob slot of the requirements.
    REQUIREMENTS_SLOT = 2

    # The SuperBlob slot of the CMS signature.
    SIGNATURE_SLOT = 0x10000

    # The CodeDirectory version that records the executable segment.
    VERSION = 0x20400

    # The CodeDirectory flag of a signature with no certificate (CS_ADHOC).
    ADHOC = 0x2

    # The CodeDirectory's hash type, SHA-256 (CS_HASHTYPE_SHA256).
    SHA256 = 2

    # The size of the pages each code hash covers, as a power of two:
    # 4 KiB, as the linker and Go write them.
    PAGE_BITS = 12

    # The executable segment flag of a main program
    # (CS_EXECSEG_MAIN_BINARY).
    MAIN_BINARY = 0x1

    # The size of a version 0x20400 CodeDirectory's header.
    HEADER_SIZE = 88

    # The Mach-O magic of a 64-bit program (mach-o/loader.h).
    MAGIC_64 = 0xFEEDFACF

    # The load command of a 64-bit segment.
    LC_SEGMENT_64 = 0x19

    # The load command that points at the code signature.
    LC_CODE_SIGNATURE = 0x1D

    # The page size of a segment on Apple Silicon, to which +__LINKEDIT+'s
    # size in memory is rounded.
    SEGMENT_ALIGNMENT = 0x4000

    # Creates a signer.
    #
    # [identifier] The bundle's identifier, which the signature names.
    # [info_plist] The bytes of the bundle's <tt>Info.plist</tt>.
    # [code_resources] The bytes of its <tt>_CodeSignature/CodeResources</tt>.
    def initialize(identifier:, info_plist:, code_resources:)
      @identifier = identifier
      @special = [
        Digest::SHA256.digest(code_resources),
        Digest::SHA256.digest(requirements),
        Digest::SHA256.digest(info_plist),
      ]
    end

    # A copy of +program+, a thin 64-bit Mach-O program that already has a
    # signature, signed ad hoc for the bundle. Raises Fledge::Error for any
    # other file.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   signer.sign(File.binread("launcher")).bytesize
    #--
    # SPDX-SnippetEnd
    #++
    def sign(program)
      program = program.b
      raise Error, "is not a 64-bit Mach-O program; Fledge signs only those" unless program.byteslice(0, 4).to_s.unpack1("V") == MAGIC_64

      commands = load_commands(program)
      signature = commands.fetch(LC_CODE_SIGNATURE) { raise Error, "has no code signature to replace" }.first
      text = segment(program, commands, "__TEXT")
      linkedit = segment(program, commands, "__LINKEDIT")
      limit = u32(program, signature + 8)
      raise Error, "has a code signature that is not at the end of __LINKEDIT" unless limit + u32(program, signature + 12) <= program.bytesize

      size = signature_size(limit)
      code = program.byteslice(0, limit).to_s
      code.bytesplice(signature + 12, 4, [size].pack("V"))
      linkedit_size = limit + size - u64(code, linkedit + 40)
      code.bytesplice(linkedit + 32, 8, [align(linkedit_size, SEGMENT_ALIGNMENT)].pack("Q<"))
      code.bytesplice(linkedit + 48, 8, [linkedit_size].pack("Q<"))
      code + superblob(code, u64(code, text + 40), u64(code, text + 48)).ljust(size, "\0")
    end

    # The load commands of +program+ by command, each the offsets of those
    # with that command.
    private def load_commands(program)
      count = u32(program, 16)
      at = 32
      commands = Hash.new { |hash, key| hash[key] = [] } # : Hash[Integer, Array[Integer]]
      count.times do
        commands[u32(program, at)] << at
        at += u32(program, at + 4)
      end
      commands
    end

    private def segment(program, commands, name)
      commands.fetch(LC_SEGMENT_64, []).find { |at| program.byteslice(at + 8, 16).to_s.delete("\0") == name } or
        raise Error, "has no #{name} segment"
    end

    private def signature_size(limit)
      pages = (limit + (1 << PAGE_BITS) - 1) >> PAGE_BITS
      directory = HEADER_SIZE + @identifier.bytesize + 1 + ((@special.size + pages) * 32)
      align(12 + (3 * 8) + directory + requirements.bytesize + 8, 16)
    end

    private def superblob(code, text_offset, text_size)
      directory = code_directory(code, text_offset, text_size)
      wrapper = [BLOB_WRAPPER, 8].pack("N2")
      first = 12 + (3 * 8)
      index = [
        [0, first],
        [REQUIREMENTS_SLOT, first + directory.bytesize],
        [SIGNATURE_SLOT, first + directory.bytesize + requirements.bytesize],
]
      length = first + directory.bytesize + requirements.bytesize + wrapper.bytesize
      [EMBEDDED_SIGNATURE, length, 3].pack("N3") + index.flatten.pack("N*") + directory + requirements + wrapper
    end

    private def code_directory(code, text_offset, text_size)
      hashes = (0...(code.bytesize)).step(1 << PAGE_BITS).map { |at| Digest::SHA256.digest(code.byteslice(at, 1 << PAGE_BITS).to_s) }
      identifier = "#{@identifier}\0".b
      hash_offset = HEADER_SIZE + identifier.bytesize + (@special.size * 32)
      length = hash_offset + (hashes.size * 32)
      header = [CODE_DIRECTORY, length, VERSION, ADHOC, hash_offset, HEADER_SIZE, @special.size, hashes.size, code.bytesize].pack("N9") +
        [32, SHA256, 0, PAGE_BITS].pack("C4") + [0, 0, 0, 0].pack("N4") + [0, text_offset, text_size, MAIN_BINARY].pack("Q>4")
      header + identifier + @special.join + hashes.join
    end

    private def requirements
      [REQUIREMENTS, 12, 0].pack("N3")
    end

    private def u32(bytes, at)
      bytes.byteslice(at, 4).to_s.unpack1("V").to_i
    end

    private def u64(bytes, at)
      bytes.byteslice(at, 8).to_s.unpack1("Q<").to_i
    end

    private def align(value, alignment)
      ((value + alignment - 1) / alignment) * alignment
    end
  end
end
