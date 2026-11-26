# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
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

  def test_a_lone_script_is_a_project_of_its_own_folder_named_for_it
    script = write("my_game/main.rb", "puts 1\n")

    app = at(script)

    assert_equal File.join(@dir, "my_game"), app.root
    assert_equal ["main.rb", "my_game", nil], [app.entry, app.name, app.gemfile]
  end

  def test_a_folder_means_its_main_rb
    write("hello/main.rb")
    app = at(File.join(@dir, "hello"))

    assert_equal ["main.rb", "hello"], [app.entry, app.name]
  end

  def test_a_relative_path_becomes_absolute
    write("hello/main.rb")

    Dir.chdir(@dir) { assert_equal File.join(Dir.pwd, "hello"), at("hello/main.rb").root }
  end

  def test_the_executable_of_a_gem_shaped_project_is_relative_to_its_root
    root = FakeProject.write(@dir, name: "my_cool_app")

    app = at(File.join(root, "exe", "my_cool_app"))

    assert_equal [root, "exe/my_cool_app", "my_cool_app", "Gemfile"], [app.root, app.entry, app.name, app.gemfile]
  end

  def test_a_gem_shaped_projects_folder_means_its_only_executable
    root = FakeProject.write(@dir, name: "my_cool_app")

    assert_equal "exe/my_cool_app", at(root).entry
  end

  def test_a_script_in_an_app_with_a_gemfile_belongs_to_the_app_named_for_the_script
    write("server_app/Gemfile", "source \"https://rubygems.org\"\n")
    server = write("server_app/bin/server", "puts 1\n")

    app = at(server)

    assert_equal [File.join(@dir, "server_app"), "bin/server", "server", "Gemfile"], [app.root, app.entry, app.name, app.gemfile]
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

  # Bundler evaluates a gemspec after the Gemfile, which finds the
  # project as Bundler.root, and from the gemspec's own folder, so one
  # that names a constant the Gemfile's code defined, or
  # loads a file by a path from that folder, works under bundle exec; its
  # program and version are the app's.
  def test_a_gemspec_is_read_as_bundler_reads_it
    root = FakeProject.write(@dir, name: "after_gemfile")
    write("after_gemfile/lib/after_gemfile/version.rb", "module AfterGemfileApp\n  VERSION = \"2.3.4\"\nend\n")
    File.write(File.join(root, "Gemfile"),
      "source \"https://rubygems.org/\"\n\nrequire Bundler.root.join(\"lib/after_gemfile/version\").to_s\ngemspec\n")
    gemspec = File.join(root, "after_gemfile.gemspec")
    File.write(gemspec, File.read(gemspec).sub('spec.version = "0.1.0"', "spec.version = AfterGemfileApp::VERSION"))

    app = at(root)

    assert_equal "exe/after_gemfile", app.entry
    assert_equal "2.3.4", app.identity.version

    root = FakeProject.write(@dir, name: "relative_load")
    write("relative_load/lib/relative_load/version.rb", "module RelativeLoadApp\n  VERSION = \"3.4.5\"\nend\n")
    gemspec = File.join(root, "relative_load.gemspec")
    File.write(gemspec, "load \"lib/relative_load/version.rb\"\n" \
      "#{File.read(gemspec).sub('spec.version = "0.1.0"', 'spec.version = RelativeLoadApp::VERSION')}")

    assert_equal "3.4.5", at(root).identity.version
  end

  def test_a_gemspec_without_a_gemfile_says_how_to_add_one
    root = FakeProject.write(@dir, name: "lonely")
    File.delete(File.join(root, "Gemfile"))

    error = assert_raises(Fledge::Error) { at(File.join(root, "exe/lonely")) }
    assert_equal "#{root} has a gemspec but no Gemfile. Fledge ships the gems Bundler locks: add a Gemfile holding " \
      "source \"https://rubygems.org\" and gemspec, run bundle lock, and build again.", error.message
  end

  # A console app is a command someone types, so with no name in
  # fledge.yml it takes its entry point's file name less the extension,
  # as a console program under programs does (bin/cli is cli).
  def test_a_console_app_is_named_for_its_entry_points_file
    write("greet_app/Gemfile", "source \"https://rubygems.org\"\n")

    app = at(write("greet_app/exe/greet"))
    assert_equal ["exe/greet", "greet", "greet", "greet"], [app.entry, app.name, app.main.name, app.identity.name]

    app = at(write("greet_app/bin/greet.rb"))
    assert_equal ["bin/greet.rb", "greet"], [app.entry, app.name]

    assert_equal "My-Tool", at(write("greet_app/bin/My-Tool")).name, "as written, never camelized"
  end

  # An entry point named main.rb says nothing of the command, so the
  # name is the one the project gives: the gemspec's, or else the root
  # folder's, as written and lowercased.
  def test_a_console_app_whose_entry_is_main_rb_is_named_for_its_project_lowercased
    write("my_cool_app/main.rb")
    assert_equal "my_cool_app", at(File.join(@dir, "my_cool_app")).name
    assert_equal "my_cool_app", at(File.join(@dir, "my_cool_app/main.rb")).name
    write("Rack-Test/main.rb")
    assert_equal "rack-test", at(File.join(@dir, "Rack-Test")).name
  end

  def test_a_console_app_whose_entry_is_main_rb_and_has_a_gemspec_is_named_for_the_gemspec_lowercased
    write("Other-Folder/main.rb", "puts 1\n")
    write("Other-Folder/Gemfile", "source \"https://rubygems.org\"\n\ngemspec\n")
    write("Other-Folder/gem_name.gemspec",
      "Gem::Specification.new { |spec| spec.name = \"Gem-Name\"; spec.version = \"0.1.0\"; spec.authors = [\"Fledge\"]; spec.summary = \"x\" }\n")

    app = at(File.join(@dir, "Other-Folder", "main.rb"))

    assert_equal ["main.rb", "gem-name"], [app.entry, app.name]
    assert_equal "gem-name", at(File.join(@dir, "Other-Folder")).name
  end

  def test_a_name_in_fledge_yml_is_used_as_written
    write("tool/fledge.yml", "name: Tool Box\n")

    assert_equal "Tool Box", at(write("tool/exe/greet")).name
    assert_equal "Tool Box", at(write("tool/main.rb")).name
  end

  def test_a_windowed_app_keeps_the_project_name_camelized
    write("my_game/fledge.yml", "kind: windowed\nidentifier: com.example.MyGame\n")

    assert_equal "MyGame", at(write("my_game/main.rb")).name
    app = at(write("my_game/exe/play"))
    assert_equal ["MyGame", "MyGame"], [app.name, app.identity.name]
  end

  def test_a_phones_app_keeps_the_project_name_camelized
    write("greet_app/Gemfile", "source \"https://rubygems.org\"\n")

    app = Fledge::App.at(write("greet_app/exe/greet"), home: File.join(@dir, "home"), phone: true)

    assert_equal ["GreetApp", "GreetApp"], [app.name, app.main.name]
  end

  def test_a_console_name_no_system_can_hold_is_refused
    write("odd/Gemfile")

    error = assert_raises(Fledge::Error) { at(write("odd/exe/con")) }
    assert_match(%r{\AThe app's name, "con", made from "exe/con", is a name Windows keeps for itself\.}, error.message)
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
    write("___/fledge.yml", "kind: windowed\nidentifier: com.example.X\n")
    write("___/main.rb")
    error = assert_raises(Fledge::Error) { at(File.join(@dir, "___/main.rb")) }
    assert_equal "The app's name, \"\", made from \"___\", is empty. Give the app a name in fledge.yml, such as name: MyCoolApp.",
      error.message

    write("con/main.rb")
    error = assert_raises(Fledge::Error) { at(File.join(@dir, "con/main.rb")) }
    assert_match(/\AThe app's name, "con", made from "con", is a name Windows keeps for itself\./, error.message)

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

  # A folder a build went to holds a cache directory tag, and stays out
  # of every later build, wherever that one goes
  # (doc/contributors/design/desktop-apps.md, "The project and its
  # name").
  def test_entries_leave_out_each_folder_a_cache_directory_tag_marks
    write("app/main.rb")
    write("app/dist/index.html", "the app's own")
    write("app/dist-deb/CACHEDIR.TAG", "Signature: 8a477f597d28d172789f06886806bc55\n")
    write("app/dist-deb/App-x86_64-linux.deb")
    write("app/tmp/builds/CACHEDIR.TAG", "Signature: 8a477f597d28d172789f06886806bc55\n")
    write("app/tmp/builds/App-x86_64-linux/fledge.cfg")
    write("app/notes/CACHEDIR.TAG", "not a tag\n")

    paths = at(File.join(@dir, "app")).entries.map(&:path)

    assert_equal %w[dist dist/index.html main.rb notes notes/CACHEDIR.TAG tmp], paths
  end

  # A project of several programs: a console one and a
  # windowed one, each with its own entry and identity, and the project's
  # version and publisher.
  def write_programs
    write("game/fledge.yml", <<~YAML)
      name: MyGame
      version: "1.2.0"
      publisher: Example
      programs:
        - path: bin/cli
        - path: gui/main.rb
          name: MyGame
          kind: windowed
          identifier: com.example.MyGame
    YAML
    write("game/bin/cli")
    write("game/gui/main.rb")
    write("game/bin/protocol")
    File.join(@dir, "game")
  end

  def test_a_folder_of_a_project_with_programs_means_all_of_them
    app = at(write_programs)

    assert_equal "MyGame", app.name
    assert_equal [%w[cli bin/cli console], %w[MyGame gui/main.rb windowed]],
      app.programs.map { |program| [program.name, program.entry, program.identity.kind] }
    assert_equal [nil, "com.example.MyGame"], app.programs.map { |program| program.identity.identifier }
    assert_equal [%w[1.2.0 Example]] * 2, app.programs.map { |program| [program.identity.version, program.identity.publisher] }
    assert_equal ["MyGame", "gui/main.rb", "MyGame"], [app.main.name, app.entry, app.identity.name]
    assert_equal "MyGame", at(File.join(@dir, "game", "bin")).name, "any folder of the project means the project"
  end

  # A windowed program is what a person sees in the Dock, the Start
  # menu, and the window list, so with no name of its own it takes the
  # project's (decision 5's camelized folder or gemspec name, or
  # fledge.yml's), as an app of one program does, not its file's: a
  # gui/main.rb is not "main". A console program keeps its file's name,
  # the command someone types.
  def test_a_windowed_program_with_no_name_takes_the_projects
    write("my_game/fledge.yml", "programs:\n  - path: gui/main.rb\n    kind: windowed\n    identifier: com.example.MyGame\n  - path: bin/cli\n")
    write("my_game/gui/main.rb")
    write("my_game/bin/cli")
    root = File.join(@dir, "my_game")

    assert_equal [%w[MyGame gui/main.rb], %w[cli bin/cli]], at(root).programs.map { |program| [program.name, program.entry] }
    assert_equal %w[MyGame MyGame], [at(root).identity.name, at(File.join(root, "gui/main.rb")).name]
    write("my_game/fledge.yml", "name: My Game\nprograms:\n  - path: gui/main.rb\n    kind: windowed\n    identifier: com.example.MyGame\n")
    assert_equal ["My Game", "My Game"], [at(root).main.name, at(File.join(root, "gui/main.rb")).name]
  end

  # The project's name, taken by the windowed program, still may not be
  # another program's, ignoring case.
  def test_a_windowed_program_named_for_the_project_may_not_share_a_name
    write("cli/fledge.yml", "programs:\n  - path: gui.rb\n    kind: windowed\n    identifier: com.example.Cli\n  - path: bin/cli\n")
    write("cli/gui.rb")
    write("cli/bin/cli")

    error = assert_raises(Fledge::Error) { at(File.join(@dir, "cli")) }
    assert_equal "#{File.join(@dir, 'cli', 'fledge.yml')}: gui.rb and bin/cli are both named Cli; give each its own", error.message
  end

  # Without a windowed program, the first is the one a phone runs.
  def test_the_main_program_is_the_windowed_one_or_else_the_first
    write("tools/fledge.yml", "programs:\n  - path: b.rb\n  - path: a.rb\n")
    write("tools/a.rb")
    write("tools/b.rb")

    app = at(File.join(@dir, "tools"))

    assert_equal %w[b a], app.programs.map(&:name)
    assert_equal ["b", "Tools"], [app.main.name, app.name]
  end

  # A path that names one of the programs builds it alone, as an app of
  # one program named after it.
  def test_a_file_one_of_the_programs_names_is_that_program_alone
    root = write_programs

    app = at(File.join(root, "gui/main.rb"))

    assert_equal ["MyGame", ["MyGame"], "com.example.MyGame"], [app.name, app.programs.map(&:name), app.identity.identifier]
    assert_equal "windowed", app.config.kind
    assert_nil app.config.programs
    cli = at(File.join(root, "bin/cli"))
    assert_equal ["cli", "bin/cli", "console", "1.2.0"], [cli.name, cli.entry, cli.identity.kind, cli.identity.version]
  end

  def test_a_file_the_programs_do_not_name_is_refused
    root = write_programs

    error = assert_raises(Fledge::Error) { at(File.join(root, "bin/protocol")) }
    assert_equal "#{File.join(root, 'bin/protocol')} is not one of the programs #{File.join(root, 'fledge.yml')} lists. " \
      "Build the project, or one of bin/cli, gui/main.rb.", error.message
  end

  def test_a_program_with_no_file_is_refused
    root = write_programs
    File.delete(File.join(root, "bin/cli"))

    error = assert_raises(Fledge::Error) { at(root) }
    assert_equal "#{File.join(root, 'fledge.yml')} lists the program bin/cli, but the project has no such file. " \
      "List the program you run, such as path: bin/cli.", error.message
  end

  def test_a_program_with_a_name_no_system_can_hold_is_refused
    write("odd/fledge.yml", "programs:\n  - path: main.rb\n    name: con\n")
    write("odd/main.rb")

    error = assert_raises(Fledge::Error) { at(File.join(@dir, "odd")) }
    assert_match(/names the program main\.rb "con", but that is a name Windows keeps for itself/, error.message)
  end

  def test_a_windowed_program_needs_an_identifier
    write("win/fledge.yml", "programs:\n  - path: main.rb\n    kind: windowed\n")
    write("win/main.rb")

    error = assert_raises(Fledge::Error) { at(File.join(@dir, "win")) }
    assert_match(/a windowed app needs an identifier/, error.message)
  end
end
