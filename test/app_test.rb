# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "test_helper"

class AppTest < Minitest::Test
  def test_an_app_is_a_folder_with_a_main_rb_named_for_its_folder
    Dir.mktmpdir do |dir|
      root = FakeApp.write(dir, "my_game")
      app = Fledge::App.at(root)

      assert_equal File.expand_path(root), app.root
      assert_equal "my_game", app.name
    end
  end

  def test_a_relative_path_becomes_absolute
    Dir.mktmpdir do |dir|
      FakeApp.write(dir)
      Dir.chdir(dir) { assert_equal File.join(Dir.pwd, "hello"), Fledge::App.at("hello").root }
    end
  end

  def test_a_missing_folder_is_an_error
    Dir.mktmpdir do |dir|
      error = assert_raises(Fledge::Error) { Fledge::App.at(File.join(dir, "nope")) }
      assert_equal "#{File.join(dir, 'nope')} is not a folder. An app is a folder with a main.rb.", error.message
    end
  end

  def test_a_folder_without_main_rb_is_an_error
    Dir.mktmpdir do |dir|
      error = assert_raises(Fledge::Error) { Fledge::App.at(dir) }
      assert_equal "#{dir} has no main.rb. An app is a folder with a main.rb.", error.message
    end
  end

  def test_entries_leave_out_git_history_and_skipped_paths
    Dir.mktmpdir do |dir|
      root = FakeApp.write(dir)
      FileUtils.mkdir_p(File.join(root, ".git/objects"))
      FileUtils.mkdir_p(File.join(root, "dist/hello-x86_64-linux"))
      File.write(File.join(root, "helper.rb"), "")
      File.write(File.join(root, ".env.example"), "")

      paths = Fledge::App.at(root).entries(skip: [File.join(root, "dist")]).map(&:path)

      assert_equal %w[.env.example helper.rb main.rb], paths
    end
  end
end
