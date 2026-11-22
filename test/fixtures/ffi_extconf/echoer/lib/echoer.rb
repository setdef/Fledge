# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require "ffi"

# Opens the library ext/extconf.rb built by its path, as sassc 2.4.0's
# lib/sassc/native.rb opens libsass: where RubyGems copies it into the
# gem's lib/, or else where the build left it in ext/.
module Echoer
  extend FFI::Library

  dl_ext = RbConfig::MAKEFILE_CONFIG["DLEXT"]
  begin
    ffi_lib File.expand_path("echoer/libechoer.#{dl_ext}", __dir__)
  rescue LoadError
    ffi_lib File.expand_path("libechoer.#{dl_ext}", "#{__dir__}/../ext")
  end

  attach_function :echoer_shout, [:string], :pointer
  attach_function :echoer_free, [:pointer], :void

  # +text+ in capitals, from the library.
  def self.shout(text)
    loud = echoer_shout(text)
    loud.read_string
  ensure
    echoer_free(loud) if loud
  end
end
