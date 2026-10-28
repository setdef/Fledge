# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

module Fledge
  class Binary
    # What every format's reader reads a file's bytes with: numbers of a
    # pack format at an offset, and C strings. A reader reads past the end
    # as zeros and empty strings, as the readers of each format did before
    # they shared this, so a truncated file reads as one that names nothing
    # rather than raising where the format's own tools would not.
    class Reader # :nodoc:
      def initialize(bytes)
        @bytes = bytes
      end

      # The unsigned number of +size+ bytes at +offset+, in the pack
      # +format+, or 0 past the end.
      private def number(offset, size, format)
        @bytes.byteslice(offset, size).to_s.unpack1(format).to_i
      end

      # The NUL-terminated string at +offset+, as UTF-8.
      private def c_string(offset)
        ending = @bytes.index("\0".b, offset) || @bytes.bytesize
        @bytes.byteslice(offset, ending - offset).to_s.force_encoding(Encoding::UTF_8)
      end
    end
  end
end
