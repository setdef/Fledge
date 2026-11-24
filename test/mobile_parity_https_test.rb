# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "test_helper"
require_relative "../tasks/mobile_parity"

# The mobile check's HTTPS server and the trust it gives the app
# (MobileParity::HTTPS), as far as they need no server: where the check
# puts the test authority, and what the app must print.
# test/integration/mobile_parity_https_test.rb runs the server.
class MobileParityHTTPSTest < Minitest::Test
  HTTPS = MobileParity::HTTPS

  # The app is the one app that asks the server, and its line is the
  # one that says the file the runtime carries was read.
  def test_only_mobile_hello_asks_the_server_and_its_line_shows_both_connections
    asking = MobileParity::APPS.select(&:https)

    assert_equal ["MobileHello"], asking.map(&:name)
    both = "certificate verify failed with an empty trust store, 200 with the runtime's CA certificates"
    line = 'Hello from Ruby 4.1.0 on arm64-darwin: ["csv","3.3.5"], prism 1.6.0 parses 1 + 2 as +, ' \
      "over HTTPS: #{both}, no YJIT"

    assert_match MobileParity::HELLO, line
    refute_match MobileParity::HELLO, line.sub("certificate verify failed", "connected")
    refute_match MobileParity::HELLO, line.sub("200 with", "403 with")
    refute_match MobileParity::HELLO, line.sub("#{both}, ", "")
  end

  # The authority joins the file the app's Ruby reads, after what it
  # held, and a file the project shares with the runtime it came from is
  # left as it was.
  def test_the_authority_is_appended_to_the_projects_certificates_and_not_to_the_runtimes
    Dir.mktmpdir do |dir|
      runtime = File.join(dir, "runtime-cert.pem")
      File.write(runtime, "-----BEGIN CERTIFICATE-----\nroot\n-----END CERTIFICATE-----\n")
      folder = File.join(dir, "https")
      FileUtils.mkdir_p(folder)
      File.write(File.join(folder, "ca.pem"), "-----BEGIN CERTIFICATE-----\ntest\n-----END CERTIFICATE-----\n")
      HTTPS::CERTIFICATES.each do |phone, relative|
        project = File.join(dir, phone)
        FileUtils.mkdir_p(File.dirname(File.join(project, relative)))
        File.symlink(runtime, File.join(project, relative))

        HTTPS.trust(phone, project, folder:)

        assert_equal "-----BEGIN CERTIFICATE-----\nroot\n-----END CERTIFICATE-----\n-----BEGIN CERTIFICATE-----\ntest\n-----END CERTIFICATE-----\n",
          File.read(File.join(project, relative)), phone
        refute File.symlink?(File.join(project, relative)), phone
      end
      assert_equal "-----BEGIN CERTIFICATE-----\nroot\n-----END CERTIFICATE-----\n", File.read(runtime)
    end
  end

  # A project with no such file is not one where the check could put
  # the authority, so the check stops, not passes with the app asking a
  # server it cannot trust.
  def test_a_project_without_the_certificates_file_stops_the_check
    Dir.mktmpdir do |dir|
      error = assert_raises(RuntimeError) { HTTPS.trust("android", dir, folder: dir) }

      assert_includes error.message, "fledge/libexec/cert.pem"
    end
  end

  # With no app that asks it, no server starts and the block gets no
  # address.
  def test_no_server_runs_for_apps_that_do_not_ask
    hello = MobileParity::APPS.find { |app| app.name == "Hello" }

    assert_nil HTTPS.serving([hello], folder: "/nonexistent") { |url| url }
  end

  def test_the_port_is_the_servers
    assert_equal 20_123, HTTPS.port("https://127.0.0.1:20123/ok.http")
  end
end
