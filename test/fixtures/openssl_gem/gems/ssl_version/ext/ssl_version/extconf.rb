# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT-0
#++

require "mkmf"

# OpenSSL found as Puma 8.1.2's extconf.rb finds it: pkg-config first,
# then the libraries and a header by name. Where Puma builds without TLS
# when it finds none, this gem stops, so a build that found no OpenSSL
# cannot pass unseen.
found = pkg_config("openssl") || (have_library("crypto", "CRYPTO_malloc") && have_library("ssl", "SSL_new"))
abort "ssl_version found no OpenSSL to link" unless found && have_header("openssl/ssl.h")

create_makefile("ssl_version/ssl_version")
