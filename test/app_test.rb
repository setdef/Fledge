# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "test_helper"
require_relative "support/gems"

class AppTest < Minitest::Test
  def setup
    @dir = Dir.mktmpdir
    # A folder that marks where a search for a project's root stops, as a
    # repository's top does, so nothing above the test's folder counts.
    FileUtils.mkdir_p(File.join(@dir, ".git"))
  end

  def teardown
    FileUtils.rm_rf(@dir)
  end

  def at(path, home: File.join(@dir, "home")) = Fledge::App.at(path, home:)

  def write(path, content = "")
    full = File.join(@dir, path)
    FileUtils.mkdir_p(File.dirname(full))
    File.write(full, content)
    full
  end

  def test_a_lone_script_is_a_project_of_its_own_folder_named_for_it_camelized
    script = write("my_game/main.rb", "puts 1\n")

    app = at(script)

    assert_equal File.join(@dir, "my_game"), app.root
    assert_equal ["main.rb", "MyGame", nil], [app.entry, app.name, app.gemfile]
  end

  def test_a_folder_means_its_main_rb
    write("hello/main.rb")
    app = at(File.join(@dir, "hello"))

    assert_equal ["main.rb", "Hello"], [app.entry, app.name]
  end

  def test_a_relative_path_becomes_absolute
    write("hello/main.rb")

    Dir.chdir(@dir) { assert_equal File.join(Dir.pwd, "hello"), at("hello/main.rb").root }
  end

  def test_the_executable_of_a_gem_shaped_project_is_relative_to_its_root
    root = FakeProject.write(@dir, name: "my_cool_app")

    app = at(File.join(root, "exe", "my_cool_app"))

    assert_equal [root, "exe/my_cool_app", "MyCoolApp", "Gemfile"], [app.root, app.entry, app.name, app.gemfile]
  end

  def test_a_gem_shaped_projects_folder_means_its_only_executable
    root = FakeProject.write(@dir, name: "my_cool_app")

    assert_equal "exe/my_cool_app", at(root).entry
  end

  def test_a_script_in_an_app_with_a_gemfile_belongs_to_the_app_named_for_its_folder
    write("server_app/Gemfile", "source \"https://rubygems.org\"\n")
    server = write("server_app/bin/server", "puts 1\n")

    app = at(server)

    assert_equal [File.join(@dir, "server_app"), "bin/server", "ServerApp", "Gemfile"], [app.root, app.entry, app.name, app.gemfile]
  end

  def test_gems_rb_is_a_gemfile_too
    write("tool/gems.rb")
    script = write("tool/bin/tool")

    assert_equal "gems.rb", at(script).gemfile
  end

  def test_a_fledge_yml_marks_a_root_and_may_name_the_app
    write("outer/Gemfile")
    write("outer/inner/fledge.yml", "name: Inner Game\n")
    script = write("outer/inner/main.rb")

    app = at(script)

    assert_equal [File.join(@dir, "outer/inner"), "Inner Game", nil], [app.root, app.name, app.gemfile]
  end

  def test_the_search_for_a_root_stops_at_a_repositorys_top
    write("Gemfile")
    FileUtils.mkdir_p(File.join(@dir, "repo/.git"))
    script = write("repo/scripts/tool.rb")

    assert_equal File.join(@dir, "repo/scripts"), at(script).root
  end

  def test_a_project_at_the_home_folder_is_refused
    home = File.join(@dir, "home")
    write("home/Gemfile")
    script = write("home/scripts/tool.rb")

    error = assert_raises(Fledge::Error) { at(script, home:) }
    assert_equal "#{script} would belong to a project at your home folder, #{home}, which Fledge won't ship. " \
      "Move the app into a folder of its own.", error.message
  end

  def test_a_missing_path_is_an_error
    error = assert_raises(Fledge::Error) { at(File.join(@dir, "nope")) }

    assert_equal "#{File.join(@dir, 'nope')} does not exist. Build the program you run, such as exe/my_app or main.rb.", error.message
  end

  def test_a_folder_without_one_program_says_what_to_build
    write("empty/README")
    error = assert_raises(Fledge::Error) { at(File.join(@dir, "empty")) }
    assert_equal "#{File.join(@dir, 'empty')} is a folder with no main.rb, and its project names no one program to ship. " \
      "Build the program you run, such as fledge build #{File.join(@dir, 'empty', 'exe', 'my_app')}.", error.message

    root = FakeProject.write(@dir, name: "two")
    gemspec = File.join(root, "two.gemspec")
    File.write(gemspec, File.read(gemspec).sub('spec.executables = ["two"]', "spec.executables = %w[one two]"))
    error = assert_raises(Fledge::Error) { at(root) }
    assert_equal "#{root} is a folder with no main.rb, and its project names no one program to ship. " \
      "Build the program you run, exe/one or exe/two.", error.message
  end

  def test_a_gemspec_without_a_gemfile_says_how_to_add_one
    root = FakeProject.write(@dir, name: "lonely")
    File.delete(File.join(root, "Gemfile"))

    error = assert_raises(Fledge::Error) { at(File.join(root, "exe/lonely")) }
    assert_equal "#{root} has a gemspec but no Gemfile. Fledge ships the gems Bundler locks: add a Gemfile holding " \
      "source \"https://rubygems.org\" and gemspec, run bundle lock, and build again.", error.message
  end

  def test_camelize_makes_a_name_as_bundler_names_a_gems_module
    {
      "my_cool_app" => "MyCoolApp",
      "rack-test" => "RackTest",
      "hello" => "Hello",
      "Ünïcödé app" => "ÜnïcödéApp",
      "x__y" => "XY",
      "camelCase" => "CamelCase",
    }.each { |name, expected| assert_equal expected, Fledge::App.camelize(name), name }
  end

  def test_names_no_system_can_hold_are_refused
    write("___/main.rb")
    error = assert_raises(Fledge::Error) { at(File.join(@dir, "___/main.rb")) }
    assert_equal "The app's name, \"\", made from \"___\", is empty. Give the app a name in fledge.yml, such as name: MyCoolApp.",
      error.message

    write("con/main.rb")
    error = assert_raises(Fledge::Error) { at(File.join(@dir, "con/main.rb")) }
    assert_match(/\AThe app's name, "Con", made from "con", is a name Windows keeps for itself\./, error.message)

    write("named/fledge.yml", "name: \"a:b\"\n")
    error = assert_raises(Fledge::Error) { at(write("named/main.rb")) }
    assert_equal "#{File.join(@dir, 'named', 'fledge.yml')} names the app \"a:b\", but that holds a character some systems' " \
      "file names cannot. Give the app a name in fledge.yml, such as name: MyCoolApp.", error.message
  end

  def test_entries_leave_out_git_bundlers_own_folders_and_skipped_paths
    write("app/main.rb")
    write("app/helper.rb")
    write("app/.env.example")
    %w[.git/HEAD .bundle/config vendor/bundle/ruby/x.rb vendor/cache/x.gem dist/old/x].each { |path| write("app/#{path}") }
    write("app/vendor/keep.rb")

    paths = at(File.join(@dir, "app")).entries(skip: [File.join(@dir, "app/dist")]).map(&:path)

    assert_equal %w[.env.example helper.rb main.rb vendor vendor/keep.rb], paths
  end
end
