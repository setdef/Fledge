# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "../test_helper"
require_relative "../support/stand_in_signer"

# Fledge::SignCommand running a signing command on an app's files: the
# stand-in of test/support/stand_in_signer.rb, a .cmd file on Windows
# and a shell script elsewhere, which records each path and marks each
# file. No agent has a certificate in a cloud signing service.
class SignCommandSignerTest < Minitest::Test
  BINARIES = File.expand_path("../fixtures/binaries", __dir__)

  # Once for each PE file, in the order of their paths, and for nothing
  # else: not a text file, nor a Mach-O file with a Windows name.
  def test_each_pe_file_is_signed_once_in_order
    StandInSigner.with do |signer, signed|
      Dir.mktmpdir do |dir|
        folder = app(dir)

        Fledge::SignCommand.new("\"#{signer}\" %1").sign_folder(folder)

        expected = %w[Hello.exe lib/ruby.dll lib/ruby/ext.so].map { |path| Fledge::Nsis.host_path(File.join(folder, path)) }
        assert_equal expected, signed.call
        assert_equal Fledge::WindowsSigning.files(folder).map { |path| Fledge::Nsis.host_path(path) }, expected
        assert File.binread(File.join(folder, "Hello.exe")).end_with?(StandInSigner::MARKER)
        refute File.binread(File.join(folder, "lib/fake.dll")).end_with?(StandInSigner::MARKER)
      end
    end
  end

  # A command that does not exit 0 stops at that file and fails the build
  # naming it, with what the command said, but never the command itself,
  # which may carry a secret (eSigner's CodeSignTool takes a password).
  def test_a_failing_command_names_the_file_and_never_itself
    StandInSigner.with(fail_on: "ruby.dll") do |signer, signed|
      Dir.mktmpdir do |dir|
        folder = app(dir)

        error = assert_raises(Fledge::Error) { Fledge::SignCommand.new("\"#{signer}\" %1 --password=s3cret").sign_folder(folder) }

        failed = Fledge::Nsis.host_path(File.join(folder, "lib/ruby.dll"))
        assert_match(/\Athe signing command failed on #{Regexp.escape(File.join(folder, 'lib/ruby.dll'))} \(.*exit 3\):\n/, error.message)
        assert_includes error.message, "refused #{failed}"
        refute_includes error.message, "s3cret"
        assert_equal 2, signed.call.size, "nothing after the file that failed"
      end
    end
  end

  # An app's folder under +dir+: a program, a library, and an extension,
  # each a PE file; a text file; and a Mach-O file named as a library.
  private def app(dir)
    folder = File.join(dir, "Hello-x64-mingw-ucrt")
    FileUtils.mkdir_p(File.join(folder, "lib", "ruby"))
    pe = File.join(BINARIES, Dir.glob("pe-*", base: BINARIES).min.to_s)
    %w[Hello.exe lib/ruby.dll lib/ruby/ext.so].each { |path| FileUtils.cp(pe, File.join(folder, path)) }
    FileUtils.cp(File.join(BINARIES, Dir.glob("macho-*", base: BINARIES).min.to_s), File.join(folder, "lib", "fake.dll"))
    File.write(File.join(folder, "lib", "README.txt"), "not code\n")
    folder
  end
end
