# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

# Requires each extension of the linked gem, which imports a DLL that
# a RubyInstaller Ruby finds in MSYS2's bin folder (libz-1.dll,
# libffi-8.dll), and calls it. Each is tried on its own, so a run shows
# every one that does not load, by Ruby's own LoadError.

failed = false
{
  "linked_zlib" => -> { "LinkedZlib.crc32(\"abc\") = #{LinkedZlib.crc32('abc').to_s(16)}" },
  "linked_ffi" => -> { "LinkedFfi.add(2, 3) = #{LinkedFfi.add(2, 3)}" },
}.each do |feature, call|
  require feature
  puts call.call
rescue LoadError => e
  warn "#{feature}: #{e.message}"
  failed = true
end
exit(!failed)
