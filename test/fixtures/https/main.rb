# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

# The HTTPS probe: a GET over HTTPS, with Ruby's own net/http
# and openssl, to the URL its one argument names, which Delivery
# points at a server of its own on the same computer, whose
# certificate a test authority made for the run has signed
# (.github/scripts/https-server.sh). It prints the status, or
# that the certificate did not verify, with each variable that
# points OpenSSL at a file, so that the line says whose
# certificates were asked. Delivery puts the authority where the
# platform's Ruby looks, or nowhere, and checks the line
# (.github/scripts/deliver-https.sh and deliver-https.ps1).
require "net/http"

uri = URI(ARGV.fetch(0))
# By the names Ruby's OpenSSL and the runtimes' renamed copies of it
# read: SSL_CERT_FILE, and PORTABLE_RUBY_SSL_CERT_FILE, which the
# openssl.rb of macOS's and musl Linux's runtimes sets.
pointed = lambda do
  names = ENV.select { |name, _| name.end_with?("SSL_CERT_FILE") }.sort.map { |pair| pair.join("=") }
  names.empty? ? "no file a variable names" : names.join(" ")
end
begin
  status = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 10, read_timeout: 10) { |http| http.get(uri.path).code }
rescue OpenSSL::SSL::SSLError => e
  puts "HTTPS to #{uri.host}: #{e.message[/certificate verify failed[^)]*\)?/] || e.message}, certificates #{pointed.call}"
  exit 1
end
puts "HTTPS to #{uri.host}: #{status}, certificates #{pointed.call}"
