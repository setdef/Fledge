# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "../test_helper"
require_relative "../../tasks/mobile_parity"

# The mobile check's HTTPS server (MobileParity::HTTPS), run: the
# computer's own openssl serves a certificate of a test authority, which
# a client trusts only once it holds the authority, as the app does once
# the check has put the authority in its certificates.
class MobileParityHTTPSIntegrationTest < Minitest::Test
  def test_the_server_answers_a_client_that_trusts_its_authority_and_not_one_that_does_not
    skip "this computer has no openssl command" unless system("openssl", "version", out: File::NULL, err: File::NULL)
    app = MobileParity::APPS.find(&:https)
    Dir.mktmpdir do |dir|
      folder = File.join(dir, "https")
      MobileParity::HTTPS.prepare(folder:)

      MobileParity::HTTPS.serving([app], folder:) do |url|
        uri = URI(url)
        trusting = OpenSSL::X509::Store.new.tap { |store| store.add_file(File.join(folder, "ca.pem")) }

        assert_equal "200", get(uri, trusting)
        error = assert_raises(OpenSSL::SSL::SSLError) { get(uri, OpenSSL::X509::Store.new) }

        assert_includes error.message, "certificate verify failed"
      end
    end
  end

  private def get(uri, store)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.cert_store = store
    http.start { |connection| connection.get(uri.path).code }
  end
end
