# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "../error"

module Fledge
  class HfsPlus
    # A name as HFS Plus keeps it in its catalog (TN1150, "Unicode
    # Subtleties").
    module Name # :nodoc:
      # +name+ as HFS Plus stores it: its colons as slashes (which a name
      # in macOS's POSIX view cannot hold, and HFS Plus can), decomposed
      # as Apple decomposes it, in UTF-16, big-endian.
      def self.encode(name)
        decomposed = name.tr(":", "/").each_char.map do |char|
          (UNDECOMPOSED.any? { |range| range.cover?(char.ord) }) ? char : char.unicode_normalize(:nfd)
        end.join
        utf16 = decomposed.encode(Encoding::UTF_16BE).b
        raise Error, "#{name.inspect} is longer than a Mac's file system allows (#{NAME_MAX} characters)" if utf16.bytesize / 2 > NAME_MAX

        utf16
      rescue EncodingError
        raise Error, "#{name.inspect} is not a name in UTF-8, which a Mac's file system needs"
      end
    end
  end
end
