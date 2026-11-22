# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "../test_helper"
require_relative "../../tasks/runtime_builder"

# The certificate edits a phone's runtime makes to OpenSSL and
# openssl.rb, with the edited openssl.rb run in a Ruby of its own; the
# rest of the mobile runtimes' parts that need no runtime are
# test/mobile_runtime_test.rb's.
class MobileCertificatesTest < Minitest::Test
  # A phone's Ruby, as a musl runtime's, finds its CA certificates as
  # rv-ruby's Ruby does: OpenSSL reads them from a variable of rv-ruby's
  # name, which openssl.rb sets as openssl loads, to SSL_CERT_FILE or
  # else to libexec/cert.pem beside the Ruby, so ENV holds nothing of the
  # runtime's before require "openssl" and the same after it as under
  # rv-ruby's ruby main.rb.
  def test_a_built_ruby_finds_its_certificates_as_rv_rubys_does
    Dir.mktmpdir do |dir|
      header = File.join(dir, "openssl", "include", "internal", "common.h")
      FileUtils.mkdir_p(File.dirname(header))
      File.write(header, "# define X509_CERT_FILE_EVP \"SSL_CERT_FILE\"\n")
      ruby = File.join(dir, "root", "lib", "ruby")
      FileUtils.mkdir_p(File.join(ruby, "4.1.0"))
      File.write(File.join(ruby, "4.1.0", "openssl.rb"), "require 'openssl.so'\n")

      RuntimeBuilder::Certificates.rename_variable(File.join(dir, "openssl"))
      RuntimeBuilder::Certificates.point_openssl_rb(ruby)

      assert_equal "# define X509_CERT_FILE_EVP \"PORTABLE_RUBY_SSL_CERT_FILE\"\n", File.read(header)
      set, load = File.readlines(File.join(ruby, "4.1.0", "openssl.rb"), chomp: true)
      assert_equal "require 'openssl.so'", load
      script = File.join(dir, "set.rb")
      File.write(script, "RbConfig.singleton_class.define_method(:ruby) { #{File.join(dir, 'root', 'bin', 'ruby').dump} }\n" \
        "#{set}\nprint ENV.fetch('PORTABLE_RUBY_SSL_CERT_FILE')")
      named = -> (value) { IO.popen({ "SSL_CERT_FILE" => value }, [RbConfig.ruby, script], &:read) }
      assert_equal File.join(dir, "root", "libexec", "cert.pem"), named.call(nil)
      assert_equal "/elsewhere.pem", named.call("/elsewhere.pem")
      assert_raises(RuntimeError) { RuntimeBuilder::Certificates.rename_variable(File.join(dir, "openssl")) }
    end
  end
end
