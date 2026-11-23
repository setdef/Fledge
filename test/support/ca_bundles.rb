# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

# The CA bundles a runtime carries, byte for byte, which the license
# audit pins by SHA-256 (runtime/licenses.yml): the extract jdx/ruby's
# Rubies hold (+jdx+) and the one Fledge pins for the phones and musl
# Linux (+curl+). A test that audits a runtime writes one of them where
# its platform's runtime holds libexec/cert.pem.
module CaBundles
  DIR = File.expand_path("../fixtures", __dir__)

  def self.jdx = File.binread(File.join(DIR, "cacert-jdx.pem"))

  def self.curl = File.binread(File.join(DIR, "cacert-curl.pem"))
end
