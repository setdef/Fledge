# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT-0
#++

Gem::Specification.new do |spec|
  spec.name = "ssl_version"
  spec.version = "1.0.0"
  spec.authors = ["Kerrick Long"]
  spec.summary = "A path gem whose C extension links OpenSSL, as Puma's does, in test/fixtures/openssl_gem"
  spec.license = "MIT-0"
  spec.files = ["lib/ssl_version.rb", "ext/ssl_version/extconf.rb", "ext/ssl_version/ssl_version.c"]
  spec.extensions = ["ext/ssl_version/extconf.rb"]
end
