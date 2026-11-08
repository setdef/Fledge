# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "test_helper"
require "open3"

# Fledge::Signing (ADR 016): which files each system's signer signs, and
# how. test/built_app_test.rb signs whole apps with the identity
# FLEDGE_TEST_SIGN_IDENTITY names: "-", ad hoc, on any Mac, and in CI a
# self-signed certificate it makes on macOS and Windows; Delivery verifies
# the result with codesign and signtool on fresh runners
# (.github/scripts/deliver-signed.sh and deliver-signed.ps1).
class SigningTest < Minitest::Test
  BINARIES = File.expand_path("fixtures/binaries", __dir__)
  MAC = Fledge::Platform.find("arm64-darwin")
  WINDOWS = Fledge::Platform.find("x64-mingw-ucrt")
  THUMBPRINT = "0123456789ABCDEF0123456789ABCDEF01234567"

  def test_no_identity_means_no_signing
    assert_nil Fledge::Signing.for(MAC, nil)
    assert_nil Fledge::Signing.for(Fledge::Platform.find("x86_64-linux"), nil)
  end

  def test_linux_has_nothing_for_fledge_to_sign_with
    error = assert_raises(Fledge::Error) { Fledge::Signing.for(Fledge::Platform.find("x86_64-linux"), "me") }
    assert_equal "--sign signs apps for macOS and Windows; a Linux app carries no signature for its system to check, " \
      "so build it without --sign", error.message
  end

  def test_a_mac_signs_with_the_identity_as_codesign_names_it
    assert_instance_of Fledge::MacSigning, Fledge::Signing.for(MAC, "Developer ID Application: Example (ABCDE12345)")
  end

  def test_windows_signs_with_a_certificates_thumbprint
    assert_instance_of Fledge::WindowsSigning, Fledge::Signing.for(WINDOWS, THUMBPRINT.downcase, env: {})

    error = assert_raises(Fledge::Error) { Fledge::Signing.for(WINDOWS, "Example, Inc.", env: {}) }
    assert_includes error.message, "takes the SHA-1 thumbprint of a code signing certificate"
  end

  # Every compiled file of the system's own format, by its first bytes,
  # whatever its name, and never through a symbolic link, which points at
  # a file signed where it is.
  def test_code_files_are_found_by_their_first_bytes
    Dir.mktmpdir do |dir|
      macho = Dir.glob("macho-*", base: BINARIES).first
      pe = Dir.glob("pe-*", base: BINARIES).first
      FileUtils.mkdir_p(File.join(dir, "lib/ruby"))
      FileUtils.cp(File.join(BINARIES, macho), File.join(dir, "lib/ruby/ext.bundle"))
      FileUtils.cp(File.join(BINARIES, macho), File.join(dir, "Program"))
      FileUtils.cp(File.join(BINARIES, pe), File.join(dir, "lib/ruby/ext.so"))
      File.write(File.join(dir, "main.rb"), "puts 1\n")
      File.symlink("Program", File.join(dir, "link"))

      assert_equal %w[Program lib/ruby/ext.bundle], Fledge::Signing.code_files(dir, :macho).map { |path| path.delete_prefix("#{dir}/") }
      assert_equal %w[lib/ruby/ext.so], Fledge::Signing.code_files(dir, :pe).map { |path| path.delete_prefix("#{dir}/") }
    end
  end

  # A gem's build can leave object files beside its extension; they are
  # Mach-O too, but codesign signs only what runs or loads.
  def test_a_mac_signs_no_object_file
    Dir.mktmpdir do |dir|
      object = File.join(dir, "ext.o")
      File.binwrite(object, [0xFEEDFACF, 0x0100000C, 0, 1].pack("V4"))
      bundle = File.join(dir, "ext.bundle")
      File.binwrite(bundle, [0xFEEDFACF, 0x0100000C, 0, 8].pack("V4"))

      assert Fledge::MacSigning.object_file?(object)
      refute Fledge::MacSigning.object_file?(bundle)
    end
  end

  # Notarization asks for the hardened runtime, a secure timestamp, and
  # every Mach-O file signed; YJIT asks for executable memory made
  # without MAP_JIT, and Briefcase lets every app load libraries it did
  # not sign (ADR 016).
  def test_a_mac_signs_code_with_the_hardened_runtime_a_timestamp_and_its_entitlements
    signing = Fledge::MacSigning.new("Example")

    assert_equal ["--force", "--sign", "Example", "--options", "runtime", "--timestamp", "--entitlements", Fledge::MacSigning::ENTITLEMENTS],
      signing.code_options
    entitlements = File.read(Fledge::MacSigning::ENTITLEMENTS)
    assert_equal %w[com.apple.security.cs.allow-unsigned-executable-memory com.apple.security.cs.disable-library-validation],
      entitlements.scan(%r{<key>([^<]+)</key>}).flatten
  end

  # An ad hoc signature has no certificate for a timestamp to stamp.
  def test_the_ad_hoc_identity_takes_no_timestamp
    refute_includes Fledge::MacSigning.new("-").code_options, "--timestamp"
  end

  def test_the_entitlements_are_a_property_list_plutil_accepts
    skip "plutil is macOS's" unless RUBY_PLATFORM.include?("darwin")

    out, status = Open3.capture2e("plutil", "-lint", Fledge::MacSigning::ENTITLEMENTS)
    assert_predicate status, :success?, out
  end

  # signtool signs with SHA-256 and a timestamp from DigiCert's server, as
  # Briefcase's default is, so a signature outlives its certificate.
  def test_windows_signs_with_sha256_and_a_timestamp
    signing = Fledge::WindowsSigning.new(THUMBPRINT, env: {})

    assert_equal ["sign", "/sha1", THUMBPRINT, "/fd", "sha256", "/tr", "http://timestamp.digicert.com", "/td", "sha256"],
      signing.arguments
  end

  # makensis signs the installer it writes, and the uninstaller inside
  # it, with the same command (NSIS 3.08's !finalize and !uninstfinalize).
  def test_the_installer_and_its_uninstaller_are_signed_as_makensis_writes_them
    Dir.mktmpdir do |dir|
      signtool = File.join(dir, "signtool.exe")
      File.write(signtool, "")
      signing = Fledge::WindowsSigning.new(THUMBPRINT, env: { "PATH" => dir })

      assert_equal "\"#{Fledge::Nsis.host_path(signtool)}\" sign /sha1 #{THUMBPRINT} /fd sha256 /tr http://timestamp.digicert.com /td sha256 \"%1\"",
        signing.command_line
    end
  end

  # signtool comes with the Windows SDK, which puts it on no PATH; Fledge
  # takes the newest the SDK installed for this computer's architecture.
  def test_signtool_is_found_on_the_path_and_then_in_the_windows_sdk
    Dir.mktmpdir do |dir|
      kits = File.join(dir, "Windows Kits", "10", "bin")
      %w[10.0.22621.0 10.0.26100.0].each do |version|
        %w[x64 arm64].each do |arch|
          FileUtils.mkdir_p(File.join(kits, version, arch))
          File.write(File.join(kits, version, arch, "signtool.exe"), "")
        end
      end
      env = { "PATH" => File.join(dir, "nothing"), "ProgramFiles(x86)" => dir, "PROCESSOR_ARCHITECTURE" => "AMD64" }

      assert_equal File.join(kits, "10.0.26100.0", "x64", "signtool.exe"), Fledge::WindowsSigning.signtool(env)
      assert_equal File.join(kits, "10.0.26100.0", "arm64", "signtool.exe"),
        Fledge::WindowsSigning.signtool(env.merge("PROCESSOR_ARCHITECTURE" => "ARM64"))

      on_path = File.join(dir, "bin")
      FileUtils.mkdir_p(on_path)
      File.write(File.join(on_path, "signtool.exe"), "")
      assert_equal File.join(on_path, "signtool.exe"), Fledge::WindowsSigning.signtool(env.merge("PATH" => on_path))

      error = assert_raises(Fledge::Error) { Fledge::WindowsSigning.signtool({ "PATH" => "" }) }
      assert_includes error.message, "Windows SDK"
    end
  end
end
