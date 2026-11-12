# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "../test_helper"

# The installer that the Windows runtime's makensis compiles from the
# script Fledge::Nsis writes, on Windows, where FLEDGE_RUNTIME_DIR holds
# the Windows runtime (as CI's Windows test jobs do).
# test/nsis_test.rb covers the script.
class MakensisTest < Minitest::Test
  def identity(file_associations: [])
    Fledge::Identity.new(name: "My App", kind: "windowed", identifier: "com.example.MyApp", version: "1.2.3.pre.4",
      publisher: "Example, Inc.", copyright: "© 2026 Example, Inc.", icon: nil, description: nil, long_description: nil,
      homepage: nil, file_associations:)
  end

  # What the app opens (ADR 052): a folder, an archive by two extensions
  # (one twice, in another case), and text by its MIME type alone, which
  # Windows does not register.
  def file_associations
    association = Fledge::Config::FileAssociation
    [
      association.new(name: "Project folder", role: "viewer", extensions: [], mime_types: [], content_types: [], folders: true),
      association.new(name: "Project archive", role: "editor", extensions: %w[zip ZIP fz], mime_types: [], content_types: [], folders: false),
      association.new(name: "Text", role: "viewer", extensions: [], mime_types: ["text/plain"], content_types: [], folders: false),
    ]
  end

  def test_makensis_compiles_the_installer
    runtimes = ENV.fetch("FLEDGE_RUNTIME_DIR", File.expand_path("../../tmp/runtime", __dir__))
    windows = File.join(runtimes, Fledge::Runtimes.file_name(Fledge::Platform.local))
    unless Gem.win_platform? && File.file?(windows)
      flunk "no Windows runtime in #{runtimes}" if ENV["FLEDGE_REQUIRE_RUNTIME"] && Gem.win_platform?
      skip "an NSIS installer is built on Windows, with the Windows runtime's NSIS"
    end

    Dir.mktmpdir do |dir|
      Fledge::Archive.unpack(windows, into: File.join(dir, "runtime"))
      tools = File.join(Dir.glob(File.join(dir, "runtime", "*")).first.to_s, "tools")
      folder = File.join(dir, "My App-x64-mingw-ucrt")
      Fledge::Entry.file("My App.exe", "MZ", mode: 0o755).write_into(folder)
      nsis = Fledge::Nsis.new(identity: identity(file_associations:), folder:, to: "#{folder}-setup.exe")

      path = nsis.write(tools)
      assert_equal "MZ", File.binread(path, 2)
      assert_includes File.binread(path), "My App Setup".encode(Encoding::UTF_16LE).b, "its version information names it"
    end
  end
end
