# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT-0
#++

# The app that proves, on iOS and Android, gems whose Rakefiles build a library
# of C for Ruby's ffi to open by its path: llhttp-ffi parses an HTTP
# request in nodejs's llhttp, and scrypt derives a key in Colin
# Percival's scrypt, each through the library its Rakefile built. The
# key is RFC 7914's second test vector, so a wrong library cannot pass
# for the right one.
require "llhttp"
require "scrypt"
require "scrypt/version" # scrypt.rb requires it not, on a desktop either

# Keeps the target of the request llhttp parses.
class Request < LLHttp::Delegate
  # The request's target, as llhttp read it.
  attr_reader :url

  # Keeps +url+, which llhttp calls back with.
  def on_url(url)
    @url = url
  end
end

request = Request.new
parser = LLHttp::Parser.new(request, type: :request)
parser << "GET /hello HTTP/1.1\r\nHost: example.com\r\n\r\n"

# RFC 7914, section 12: scrypt of "password" and "NaCl", N = 1024,
# r = 8, p = 16, 64 bytes.
vector = "fdbabe1c9d3472007856e7190d01e9fe7c6ad7cbc8237830e77376634b3731622eaf30d92e22a3886ff109279d9830" \
  "dac727afb94a83ee6d8360cbdfa2cc0640"
key = SCrypt::Engine.scrypt("password", "NaCl", 1024, 8, 16, 64).unpack1("H*")
scrypt = (key == vector) ? "matches RFC 7914" : "is #{key}, not RFC 7914's"

puts "FfiLibraryPhone: llhttp-ffi #{LLHttp::VERSION} parses #{parser.method_name} #{request.url}, and scrypt " \
  "#{SCrypt::VERSION}'s key #{scrypt}, on #{RUBY_PLATFORM}"
