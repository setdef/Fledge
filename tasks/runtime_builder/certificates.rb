# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

class RuntimeBuilder
  #--
  # SPDX-SnippetBegin
  # SPDX-License-Identifier: BSD-2-Clause
  # SPDX-SnippetCopyrightText: Homebrew contributors
  # SPDX-SnippetComment: Adapted from rv-ruby's Formula/rv-portable-openssl.rb
  #   (line 77) and Abstract/rv-ruby.rb (lines 203 to 208) at
  #   spinel-coop/rv-ruby 7a0e584a71246aaaf5572547b53670267935aaed.
  #++
  # How a Ruby built from source finds the CA certificates it carries,
  # as rv-ruby's Ruby, the desktops' reference, finds them. OpenSSL bakes
  # its certificate folder in when it is built, so a Ruby that moves
  # finds no certificates. rv-ruby renames the variable OpenSSL reads
  # them from, so that no other program's OpenSSL takes it, and has
  # Ruby's openssl.rb point it at libexec/cert.pem beside the Ruby,
  # unless SSL_CERT_FILE names others. The musl runtimes and the phones'
  # carry the same two edits, so a program's ENV gains the same variable
  # at require "openssl" as under rv-ruby's ruby main.rb, and holds none
  # before.
  module Certificates
    VARIABLE = "PORTABLE_RUBY_SSL_CERT_FILE"

    # Renames the variable in the unpacked OpenSSL +source+.
    def self.rename_variable(source)
      header = File.join(source, "include", "internal", "common.h")
      text = File.read(header)
      raise "#{header} no longer names SSL_CERT_FILE" unless text.include?('"SSL_CERT_FILE"')

      File.write(header, text.sub('"SSL_CERT_FILE"', "\"#{VARIABLE}\""))
    end

    # Has the openssl.rb in +ruby+ (a Ruby's lib/ruby) set the variable
    # before it loads openssl.so.
    def self.point_openssl_rb(ruby)
      openssl_rb = File.join(ruby, RuntimeBuilder.ruby_abi(ruby), "openssl.rb")
      text = File.read(openssl_rb)
      raise "#{openssl_rb} no longer requires 'openssl.so'" unless text.include?("require 'openssl.so'")

      File.write(openssl_rb, text.sub("require 'openssl.so'", <<~RUBY.chomp))
        ENV["#{VARIABLE}"] = ENV["SSL_CERT_FILE"] || File.expand_path("../../libexec/cert.pem", RbConfig.ruby)
        require 'openssl.so'
      RUBY
    end
  end
  #--
  # SPDX-SnippetEnd
  #++
end
