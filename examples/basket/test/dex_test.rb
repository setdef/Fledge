# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT-0
#++

# The dex file that Basket writes in Ruby, checked with Minitest as any
# Ruby is: ruby test/dex_test.rb on your own computer, and inside the app
# on a phone, where test/phone.rb runs it with the others. Android's
# runtime checks a dex file's header and the order of its tables before
# it loads a class from it, so these tests read the same fields.

require "minitest/autorun"
require "zlib"
require "digest/sha1"
require_relative "../lib/basket/android/dex"

# The tests of Basket::Android::Dex.
class DexTest < Minitest::Test
  # The dex file of the class Basket's listeners use.
  def setup
    @dex = Basket::Android::Dex.handler_class("basket.Handler")
  end

  # The file starts as a version 035 dex file and says how long it is.
  def test_it_is_a_dex_file_of_the_length_its_header_gives
    assert_equal "dex\n035\0".b, @dex[0, 8]
    assert_equal @dex.bytesize, @dex[32, 4].unpack1("V")
  end

  # The header's checksum and signature cover the rest of the file.
  def test_its_checksum_and_signature_cover_the_file
    assert_equal Zlib.adler32(@dex[12..]), @dex[8, 4].unpack1("V")
    assert_equal Digest::SHA1.digest(@dex[32..]), @dex[12, 20]
  end

  # The class is named in the file's strings, as Java's runtime finds it.
  def test_it_holds_the_class_name_and_the_method_it_leaves_native
    assert_includes @dex, "Lbasket/Handler;"
    assert_includes @dex, "invoke"
  end

  # The string ids are in the order Android's verifier requires: sorted
  # by the strings they name.
  def test_its_strings_are_sorted
    count, offset = @dex[56, 8].unpack("VV")
    strings = @dex[offset, count * 4].unpack("V*").map { |at| @dex[at..].unpack1("@1Z*") }

    assert_equal strings.sort, strings
  end
end
