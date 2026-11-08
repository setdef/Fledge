# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "test_helper"

# Fledge::Archive with the computer's own tar, in folders whose names are
# not ASCII: Windows' tar.exe reads its arguments in the ANSI code page,
# where they are not, and CI runs this test there too.
class ArchiveTest < Minitest::Test
  def test_an_app_packs_and_unpacks_in_folders_named_outside_ascii
    Dir.mktmpdir do |dir|
      place = File.join(dir, "Mein Ort", "Prüfung 日本")
      folder = File.join(place, "Spiel-x86_64-linux")
      FileUtils.mkdir_p(File.join(folder, "app"))
      File.binwrite(File.join(folder, "app", "main.rb"), "puts 1\n")
      File.binwrite(File.join(folder, "notes.txt"), "")
      extension = Gem.win_platform? ? Fledge::Archive::ZIP : Fledge::Archive::TAR_GZ

      archive = Fledge::Archive.pack(folder, to: "#{folder}#{extension}")
      elsewhere = Fledge::Archive.pack(folder, to: File.join(dir, "Mein Ort", "anderswo#{extension}"))
      into = Fledge::Archive.unpack(archive, into: File.join(place, "Entpackt 日本"))

      assert_equal "puts 1\n", File.binread(File.join(into, "Spiel-x86_64-linux", "app", "main.rb"))
      assert_includes Fledge::Archive.names(elsewhere).map { |name| name.chomp("/") }, "Spiel-x86_64-linux/app/main.rb"
      assert_equal "puts 1\n", Fledge::Archive.read(archive, "Spiel-x86_64-linux/app/main.rb")
    end
  end

  # A runtime's launchers and tools alone, which is what fledge build
  # --from on Windows needs of one.
  def test_only_the_paths_asked_for_are_unpacked_with_what_they_hold
    Dir.mktmpdir do |dir|
      folder = File.join(dir, "runtime")
      FileUtils.mkdir_p(File.join(folder, "tools", "nsis"))
      FileUtils.mkdir_p(File.join(folder, "lib"))
      %w[launcher tools/nsis/makensis lib/big].each { |path| File.binwrite(File.join(folder, path), path) }
      archive = Fledge::Archive.pack(folder, to: File.join(dir, "runtime.tar.gz"))

      into = Fledge::Archive.unpack(archive, into: File.join(dir, "out"), only: %w[runtime/launcher runtime/tools])

      assert_equal %w[launcher tools tools/nsis tools/nsis/makensis], Dir.glob("**/*", base: File.join(into, "runtime")).sort
    end
  end

  # A relative archive path names a file in the folder fledge build runs
  # in, wherever tar runs.
  def test_a_relative_archive_path_is_the_callers
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        FileUtils.mkdir_p("dist/Hello-x86_64-linux")
        File.write("dist/Hello-x86_64-linux/hello.rb", "")
        FileUtils.mkdir_p("out")
        Fledge::Archive.pack("dist/Hello-x86_64-linux", to: "out/hello.tar.gz")

        assert_includes Fledge::Archive.names("out/hello.tar.gz").map { |name| name.chomp("/") }, "Hello-x86_64-linux/hello.rb"
      end
    end
  end
end
