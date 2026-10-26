# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "test_helper"

class AssemblyTest < Minitest::Test
  LINUX = Fledge::Platform.find("x86_64-linux")

  def assemble(dir, app_root, runtime: FakeRuntime.write(dir, LINUX))
    out = File.join(dir, "dist")
    Fledge::Assembly.new(app: Fledge::App.at(app_root), platform: LINUX, runtime:, out:).call
  end

  def entries(archive)
    found = {}
    Fledge::TarGz.each_entry(archive) { |entry| found[entry.path] = entry }
    found
  end

  def test_the_runtime_and_app_land_in_a_folder_and_an_archive_with_the_launcher_renamed
    Dir.mktmpdir do |dir|
      app = FakeApp.write(dir)
      File.write(File.join(app, "helper.rb"), "")

      archive = assemble(dir, app)

      assert_equal File.join(dir, "dist", "hello-x86_64-linux.tar.gz"), archive
      folder = File.join(dir, "dist", "hello-x86_64-linux")
      assert_equal %w[app hello lib], Dir.children(folder).sort
      assert_equal FakeRuntime::LAUNCHER, File.read(File.join(folder, "hello"))
      assert_equal "puts 'hi'\n", File.read(File.join(folder, "app/main.rb"))
      assert_equal "ruby", File.readlink(File.join(folder, "lib/current")) unless Gem.win_platform?

      found = entries(archive)
      assert_equal %w[
        hello-x86_64-linux
        hello-x86_64-linux/app
        hello-x86_64-linux/app/helper.rb
        hello-x86_64-linux/app/main.rb
        hello-x86_64-linux/hello
        hello-x86_64-linux/lib
        hello-x86_64-linux/lib/current
        hello-x86_64-linux/lib/ruby
        hello-x86_64-linux/lib/ruby/stdlib.rb
      ], found.keys.sort
      assert_equal 0o755, found.fetch("hello-x86_64-linux/hello").mode
      assert_equal :symlink, found.fetch("hello-x86_64-linux/lib/current").type
    end
  end

  def test_the_launcher_stays_executable_in_the_archive_whatever_the_disk_keeps
    Dir.mktmpdir do |dir|
      archive = assemble(dir, FakeApp.write(dir))

      assert_equal 0o755, entries(archive).fetch("hello-x86_64-linux/hello").mode
    end
  end

  def test_a_build_replaces_the_previous_one
    Dir.mktmpdir do |dir|
      app = FakeApp.write(dir)
      assemble(dir, app)
      stale = File.join(dir, "dist/hello-x86_64-linux/stale.txt")
      File.write(stale, "old")

      assemble(dir, app)

      refute_path_exists stale
    end
  end

  def test_build_output_inside_the_app_is_not_copied_into_the_app
    Dir.mktmpdir do |dir|
      app = FakeApp.write(dir)
      runtime = FakeRuntime.write(dir, LINUX)
      out = File.join(app, "dist")
      2.times { Fledge::Assembly.new(app: Fledge::App.at(app), platform: LINUX, runtime:, out:).call }

      assert_equal ["main.rb"], Dir.children(File.join(out, "hello-x86_64-linux/app"))
    end
  end

  def test_an_app_named_like_a_runtime_folder_is_refused_and_nothing_is_left
    Dir.mktmpdir do |dir|
      error = assert_raises(Fledge::Error) { assemble(dir, FakeApp.write(dir, "LIB")) }

      assert_equal "an app named LIB would collide with the runtime's lib. Rename the app's folder.", error.message
      assert_empty Dir.children(File.join(dir, "dist"))
    end
  end

  def test_an_app_named_app_is_refused
    Dir.mktmpdir do |dir|
      error = assert_raises(Fledge::Error) { assemble(dir, FakeApp.write(dir, "app")) }

      assert_equal "an app named app would collide with its own app folder. Rename the app's folder.", error.message
    end
  end

  def test_a_runtime_without_a_launcher_is_refused
    Dir.mktmpdir do |dir|
      runtime = File.join(dir, "empty.tar.gz")
      Fledge::TarGz.write(runtime) { |tar| tar.add(Fledge::Entry.directory("top")) }

      error = assert_raises(Fledge::Error) { assemble(dir, FakeApp.write(dir), runtime:) }
      assert_equal "#{runtime} is not a Fledge runtime: it has no launcher", error.message
    end
  end

  def test_a_runtime_with_two_top_folders_is_refused
    Dir.mktmpdir do |dir|
      runtime = File.join(dir, "two.tar.gz")
      Fledge::TarGz.write(runtime) do |tar|
        tar.add(Fledge::Entry.file("a/launcher", "", mode: 0o755))
        tar.add(Fledge::Entry.file("b/x", ""))
      end

      error = assert_raises(Fledge::Error) { assemble(dir, FakeApp.write(dir), runtime:) }
      assert_equal "#{runtime} is not a Fledge runtime: it holds both a/ and b", error.message
    end
  end

  def test_a_runtime_holding_an_app_is_refused
    Dir.mktmpdir do |dir|
      runtime = FakeRuntime.write(dir, LINUX, extra: [Fledge::Entry.file("app/main.rb", "")])

      error = assert_raises(Fledge::Error) { assemble(dir, FakeApp.write(dir), runtime:) }
      assert_equal "#{runtime} is not a Fledge runtime: it holds an app folder", error.message
    end
  end

  def test_the_base_name_is_name_dash_platform
    assembly = Fledge::Assembly.new(app: Fledge::App.new(root: "/x/hello"), platform: LINUX, runtime: "r", out: "/o")

    assert_equal "hello-x86_64-linux", assembly.base_name
  end
end
