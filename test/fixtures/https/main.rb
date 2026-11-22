# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

# The HTTPS probe: a request to rubygems.org over HTTPS, whose status it
# prints, with the certificate file Ruby's OpenSSL was pointed at by a
# variable, if any, so that the line says whose certificates verified
# the server's:
# the computer's own store where it has one, and the runtime's
# libexec/cert.pem only where it has none, on glibc Linux
# (doc/contributors/design/runtimes.md, "Certificates on glibc Linux").
# rubygems.org is the host the phones' apps ask
# (test/fixtures/mobile_hello/main.rb), and one every Ruby developer's
# computer already reaches. .github/scripts/deliver-https.sh runs it
# where it is delivered and checks the line.
require "net/http"
require "timeout"

# A runner's network drops a connection now and then, so a dropped or
# stalled connection is tried again, at most three times, each bounded;
# a certificate that does not verify is never retried, since that is
# what this probe checks.
attempts = 0
begin
  attempts += 1
  status = Timeout.timeout(60) do
    Net::HTTP.start("rubygems.org", 443, use_ssl: true, open_timeout: 20, read_timeout: 20) { |http| http.head("/").code }
  end
rescue SystemCallError, IOError, SocketError, Timeout::Error => e
  raise if attempts == 3

  warn "main.rb: #{e.class}: #{e.message}; trying again"
  sleep 5
  retry
end
# Any variable that points OpenSSL at a file, by the names Ruby's
# OpenSSL and the runtimes' renamed copies of it read: SSL_CERT_FILE on
# glibc Linux, which the runtime's openssl.rb sets only where the
# computer has no store.
pointed = ENV.select { |name, _| name.end_with?("SSL_CERT_FILE") }.sort.map { |pair| pair.join("=") }
puts "HTTPS to rubygems.org: #{status}, certificates #{pointed.empty? ? 'from no file a variable names' : pointed.join(' ')}"
