# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require "fileutils"
require "open3"
require "uri"

class MobileParity
  # The HTTPS server the mobile check's app asks (test/fixtures/mobile_hello),
  # on the computer that runs the check, so that the check reaches
  # nothing beyond it and a server anyone else runs cannot turn it red:
  # the one Delivery's desktop checks ask (.github/scripts/https-server.sh),
  # whose certificate a test authority made for the run has signed.
  #
  # The check puts that authority where the phone's Ruby reads its
  # certificates, the runtime's libexec/cert.pem in the project fledge
  # build wrote, before the project is built (HTTPS.trust), so the app
  # trusts the server only if OpenSSL read that very file, and refuses
  # it when the app gives OpenSSL an empty trust store. The Simulator
  # shares the Mac's network, so its app is given the server's address;
  # an Android emulator reaches it through adb reverse, at PORT on its
  # own loopback (Android#call).
  module HTTPS
    # Where the check keeps the authority, the certificate, and the
    # server's files.
    FOLDER = File.join(ROOT, "tmp", "mobile-parity", "https")

    # The script that makes them and runs the server.
    SCRIPT = File.join(ROOT, ".github", "scripts", "https-server.sh")

    # The port on an Android emulator's loopback that the app asks, the
    # default of test/fixtures/mobile_hello.
    PORT = 18_443

    # The environment variable that gives the app the server's address.
    VARIABLE = "FLEDGE_PARITY_HTTPS_URL"

    # Where each phone's project keeps the certificates its app's Ruby
    # reads: Android's ROOT, which Gradle stores as the app's asset, and
    # the iOS Simulator's slice of the runtime, which the build copies
    # into the app.
    CERTIFICATES = {
      "ios" => File.join("FledgeRuby.xcframework", "ios-arm64-simulator", "libexec", "cert.pem"),
      "android" => File.join("fledge", "libexec", "cert.pem"),
    }.freeze

    # Makes the check's authority and certificate, new, in +folder+.
    def self.prepare(folder: FOLDER)
      FileUtils.rm_rf(folder)
      script("prepare", folder)
    end

    # Appends the authority +prepare+ made to the certificates of the
    # +phone+'s +project+. The file is written anew, so that a link into
    # the runtime or a second name for its file leaves the runtime's own
    # as it was.
    def self.trust(phone, project, folder: FOLDER)
      path = File.join(project, CERTIFICATES.fetch(phone))
      raise "#{project} holds no #{CERTIFICATES.fetch(phone)}, where its Ruby reads its certificates" unless File.file?(path)

      certificates = File.read(path)
      File.delete(path)
      File.write(path, certificates.chomp << "\n" << File.read(File.join(folder, "ca.pem")))
    end

    # Runs the server while the block does, giving it its address, such
    # as https://127.0.0.1:20123/ok.http, when one of +apps+ asks it
    # (App#https), and nil when none does.
    def self.serving(apps, folder: FOLDER)
      return yield(nil) unless apps.any?(&:https)

      begin
        script("start", folder)
        yield File.read(File.join(folder, "url")).strip
      ensure
        script("stop", folder)
      end
    end

    # The port of the server at +url+.
    def self.port(url)
      URI(url).port
    end

    # Runs the server's +command+ on +folder+, and returns what it
    # printed.
    def self.script(command, folder)
      printed, status = Open3.capture2e("sh", SCRIPT, command, folder)
      raise "https-server.sh #{command} failed:\n#{printed}" unless status.success?

      printed
    end
  end
end
