# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT-0
#++

# Prints the OpenSSL that ssl_version's extension was compiled against
# and the one it runs with, beside the one Ruby's own openssl extension
# runs with, and whether it can make a TLS server's context.
require "openssl"
require "ssl_version"

puts "ssl_version compiled against #{SslVersion.headers}"
puts "ssl_version runs #{SslVersion.library}"
puts "Ruby's openssl runs #{OpenSSL::OPENSSL_LIBRARY_VERSION}"
puts "ssl_version makes a TLS server context: #{SslVersion.server_context?}"
