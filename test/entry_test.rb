# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "test_helper"

class EntryTest < Minitest::Test
  def test_constructors_set_type_mode_content_and_link
    file = Fledge::Entry.file("a/b.rb", "x")
    executable = Fledge::Entry.file("run", "#!", mode: 0o755)
    folder = Fledge::Entry.directory("a")
    link = Fledge::Entry.symlink("c", "a")

    assert_equal [:file, 0o644, "x", ""], [file.type, file.mode, file.content, file.link]
    assert_equal 0o755, executable.mode
    assert_equal [:directory, 0o755, "", ""], [folder.type, folder.mode, folder.content, folder.link]
    assert_equal [:symlink, "", "a"], [link.type, link.content, link.link]
  end

  def test_unsafe_paths_are_refused
    ["", "/etc/passwd", "../up", "a/../../up", "a//b", "./a", "a/", "a\\b", "C:", "a\0b"].each do |path|
      error = assert_raises(Fledge::Error, path.inspect) { Fledge::Entry.file(path, "") }
      assert_equal "#{path.inspect} is not a safe path for a file in an app", error.message
    end
  end

  def test_unsafe_paths_are_refused_by_with_too
    entry = Fledge::Entry.file("a", "")

    assert_raises(Fledge::Error) { entry.with(path: "../a") }
  end

  def test_unknown_types_are_refused
    assert_raises(ArgumentError) { Fledge::Entry.new(path: "a", type: :fifo, mode: 0o644) }
  end

  def test_write_into_creates_files_folders_and_links_with_their_modes
    Dir.mktmpdir do |root|
      Fledge::Entry.directory("bin", mode: 0o700).write_into(root)
      Fledge::Entry.file("deep/er/run", "#!/bin/sh\n", mode: 0o755).write_into(root)
      Fledge::Entry.symlink("bin/link", "../deep/er/run").write_into(root)

      assert_equal "#!/bin/sh\n", File.read(File.join(root, "deep/er/run"))
      assert_equal "../deep/er/run", File.readlink(File.join(root, "bin/link"))
      unless Gem.win_platform?
        assert_equal 0o700, File.stat(File.join(root, "bin")).mode & 0o777
        assert_equal 0o755, File.stat(File.join(root, "deep/er/run")).mode & 0o777
      end
    end
  end

  def test_write_into_refuses_to_write_through_a_symlink
    Dir.mktmpdir do |root|
      Dir.mktmpdir do |outside|
        Fledge::Entry.symlink("escape", outside).write_into(root)

        error = assert_raises(Fledge::Error) { Fledge::Entry.file("escape/owned", "x").write_into(root) }
        assert_includes error.message, "would be written through the symlink"
        assert_empty Dir.children(outside)
      end
    end
  end

  def test_walk_lists_folders_before_contents_in_name_order_and_normalizes_modes
    Dir.mktmpdir do |root|
      FileUtils.mkdir_p(File.join(root, "b/c"))
      File.write(File.join(root, "b/c/z.rb"), "z")
      File.write(File.join(root, "a.sh"), "#!/bin/sh\n")
      File.chmod(0o700, File.join(root, "a.sh"))
      File.write(File.join(root, "b/private.txt"), "p")
      File.chmod(0o600, File.join(root, "b/private.txt"))
      File.symlink("b/c", File.join(root, "link")) unless Gem.win_platform?

      entries = Fledge::Entry.walk(root)

      paths = entries.map(&:path)
      expected = Gem.win_platform? ? %w[a.sh b b/c b/c/z.rb b/private.txt] : %w[a.sh b b/c b/c/z.rb b/private.txt link]
      assert_equal expected, paths
      by_path = entries.to_h { |entry| [entry.path, entry] }
      assert_equal "z", by_path.fetch("b/c/z.rb").content
      assert_equal 0o644, by_path.fetch("b/private.txt").mode
      assert_equal 0o755, by_path.fetch("b").mode
      assert_equal 0o755, by_path.fetch("a.sh").mode unless Gem.win_platform?
      assert_equal [:symlink, "b/c"], [by_path.fetch("link").type, by_path.fetch("link").link] unless Gem.win_platform?
    end
  end

  def test_walk_skips_the_paths_it_is_told_to_and_what_they_hold
    Dir.mktmpdir do |root|
      FileUtils.mkdir_p(File.join(root, "dist/x"))
      File.write(File.join(root, "dist/x/f"), "f")
      File.write(File.join(root, "main.rb"), "")

      assert_equal ["main.rb"], Fledge::Entry.walk(root, skip: [File.join(root, "dist")]).map(&:path)
    end
  end
end
