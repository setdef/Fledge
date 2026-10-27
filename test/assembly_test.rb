# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "test_helper"
require_relative "support/gems"
require_relative "support/zip_reader"

class AssemblyTest < Minitest::Test
  LINUX = Fledge::Platform.find("x86_64-linux")
  WINDOWS = Fledge::Platform.find("x64-mingw-ucrt")
  RUNTIME_FILES = %w[
    lib
    lib/current
    lib/ruby
    lib/ruby/4.0.0
    lib/ruby/4.0.0/fake-arch
    lib/ruby/4.0.0/fake-arch/rbconfig.rb
    lib/ruby/gems
    lib/ruby/gems/4.0.0
    lib/ruby/gems/4.0.0/specifications
    lib/ruby/gems/4.0.0/specifications/csv-3.3.5.gemspec
    lib/ruby/gems/4.0.0/specifications/default
    lib/ruby/gems/4.0.0/specifications/default/json-2.18.0.gemspec
    lib/ruby/stdlib.rb
  ].freeze

  def assemble(dir, app_root, platform: LINUX, runtime: FakeRuntime.write(dir, platform), app_files: {}, files: [])
    out = File.join(dir, "dist")
    Fledge::Assembly.new(app: Fledge::App.at(app_root), platform:, runtime:, out:, app_files:, files:).call
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

      assert_equal File.join(dir, "dist", "Hello-x86_64-linux.tar.gz"), archive
      folder = File.join(dir, "dist", "Hello-x86_64-linux")
      assert_equal %w[Hello app fledge.cfg lib], Dir.children(folder).sort
      assert_equal FakeRuntime::LAUNCHER, File.read(File.join(folder, "Hello"))
      assert_equal "puts 'hi'\n", File.read(File.join(folder, "app/main.rb"))
      assert_equal "ruby", File.readlink(File.join(folder, "lib/current")) unless Gem.win_platform?

      found = entries(archive)
      expected = ["", "/Hello", "/app", "/app/helper.rb", "/app/main.rb", "/fledge.cfg", *RUNTIME_FILES.map { |path| "/#{path}" }]
      assert_equal expected.map { |path| "Hello-x86_64-linux#{path}" }.sort, found.keys.sort
      assert_equal 0o755, found.fetch("Hello-x86_64-linux/Hello").mode
      assert_equal :symlink, found.fetch("Hello-x86_64-linux/lib/current").type
    end
  end

  # The launcher reads fledge.cfg, beside it, to learn what to run
  # (runtime/launcher/config.c).
  def test_fledge_cfg_names_the_entry_point_and_a_gemfile
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, ".git"))
      hello = FakeApp.write(dir)
      assemble(dir, hello)
      assert_equal "# Written by fledge build: what this app's program runs (ADR 005).\nentry = main.rb\n",
        File.read(File.join(dir, "dist/Hello-x86_64-linux/fledge.cfg"))

      project = FakeProject.write(dir, name: "my_cool_app")
      assemble(dir, File.join(project, "exe/my_cool_app"))
      assert_equal "# Written by fledge build: what this app's program runs (ADR 005).\nentry = exe/my_cool_app\ngemfile = Gemfile\n",
        File.read(File.join(dir, "dist/MyCoolApp-x86_64-linux/fledge.cfg"))
    end
  end

  def test_app_files_replace_or_join_the_projects_and_files_join_the_runtimes
    Dir.mktmpdir do |dir|
      app = FakeApp.write(dir)
      File.write(File.join(app, "hello.gemspec.txt"), "original\n")
      gem = Fledge::Entry.file("lib/ruby/gems/4.0.0/gems/foo-1.0.0/lib/foo.rb", "# foo\n")

      archive = assemble(dir, app, app_files: { "hello.gemspec.txt" => "evaluated\n", ".bundle/config" => "---\n" },
        files: [gem, Fledge::Entry.file("notices/GEMS.txt", "gems\n")])

      folder = File.join(dir, "dist", "Hello-x86_64-linux")
      assert_equal "evaluated\n", File.read(File.join(folder, "app/hello.gemspec.txt"))
      assert_equal "---\n", File.read(File.join(folder, "app/.bundle/config"))
      assert_equal "# foo\n", File.read(File.join(folder, gem.path))
      found = entries(archive)
      %w[app/.bundle lib/ruby/gems/4.0.0/gems lib/ruby/gems/4.0.0/gems/foo-1.0.0/lib notices].each do |parent|
        assert_equal :directory, found.fetch("Hello-x86_64-linux/#{parent}").type, parent
      end
      assert_equal 1, found.keys.count("Hello-x86_64-linux/lib/ruby/gems/4.0.0")
    end
  end

  def test_an_added_file_may_not_replace_the_runtimes_and_nothing_is_left
    Dir.mktmpdir do |dir|
      runtime = FakeRuntime.write(dir, LINUX)
      clash = Fledge::Entry.file("lib/ruby/gems/4.0.0/specifications/csv-3.3.5.gemspec", "# mine\n")

      error = assert_raises(Fledge::Error) { assemble(dir, FakeApp.write(dir), runtime:, files: [clash]) }

      assert_equal "#{clash.path} is in #{runtime} already, so the build can't add its own", error.message
      assert_empty Dir.children(File.join(dir, "dist"))
    end
  end

  # Windows' layout differs from Unix's (Ruby's own tree in ruby\, not
  # lib/ beside the launcher), but assembly does not care: it renames
  # launcher.exe and copies the rest as the runtime holds it.
  def test_a_windows_app_lands_in_a_folder_and_a_zip_with_the_exe_renamed
    Dir.mktmpdir do |dir|
      runtime = FakeRuntime.write(dir, WINDOWS, extra: [Fledge::Entry.file("ruby/bin/x64-ucrt-ruby400.dll", "MZ", mode: 0o755)])

      app = FakeApp.write(dir)
      archive = assemble(dir, app, platform: WINDOWS, runtime:)

      assert_equal File.join(dir, "dist", "Hello-x64-mingw-ucrt.zip"), archive
      folder = File.join(dir, "dist", "Hello-x64-mingw-ucrt")
      assert_equal %w[Hello.exe app fledge.cfg ruby], Dir.children(folder).sort
      assert_equal FakeRuntime::LAUNCHER, File.read(File.join(folder, "Hello.exe"))
      members = ZipReader.read(archive).to_h { |member| [member.name, member] }
      assert_includes members.keys, "Hello-x64-mingw-ucrt/ruby/bin/x64-ucrt-ruby400.dll"
      assert_includes members.keys, "Hello-x64-mingw-ucrt/fledge.cfg"
      assert_equal FakeRuntime::LAUNCHER, members.fetch("Hello-x64-mingw-ucrt/Hello.exe").data
      assert_equal File.binread(File.join(app, "main.rb")), members.fetch("Hello-x64-mingw-ucrt/app/main.rb").data
      refute_path_exists File.join(dir, "dist", "Hello-x64-mingw-ucrt.tar.gz")
    end
  end

  def test_a_windows_runtime_without_launcher_exe_is_refused
    Dir.mktmpdir do |dir|
      runtime = File.join(dir, "unix-launcher.tar.gz")
      Fledge::TarGz.write(runtime) { |tar| tar.add(Fledge::Entry.file("top/launcher", "", mode: 0o755)) }

      error = assert_raises(Fledge::Error) { assemble(dir, FakeApp.write(dir), platform: WINDOWS, runtime:) }
      assert_equal "#{runtime} is not a Fledge runtime: it has no launcher.exe", error.message
      assert_empty Dir.children(File.join(dir, "dist"))
    end
  end

  def test_a_symlink_in_an_app_for_windows_is_refused_and_nothing_is_left
    skip "symlinks need privileges on Windows" if Gem.win_platform?

    Dir.mktmpdir do |dir|
      app = FakeApp.write(dir)
      File.symlink("main.rb", File.join(app, "link.rb"))

      error = assert_raises(Fledge::Error) { assemble(dir, app, platform: WINDOWS) }

      assert_equal "Hello-x64-mingw-ucrt/app/link.rb is a symbolic link, which a .zip for Windows cannot hold. " \
        "Replace it with what it points to.", error.message
      assert_empty Dir.children(File.join(dir, "dist"))
    end
  end

  def test_the_launcher_stays_executable_in_the_archive_whatever_the_disk_keeps
    Dir.mktmpdir do |dir|
      archive = assemble(dir, FakeApp.write(dir))

      assert_equal 0o755, entries(archive).fetch("Hello-x86_64-linux/Hello").mode
    end
  end

  def test_a_build_replaces_the_previous_one
    Dir.mktmpdir do |dir|
      app = FakeApp.write(dir)
      assemble(dir, app)
      stale = File.join(dir, "dist/Hello-x86_64-linux/stale.txt")
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

      assert_equal ["main.rb"], Dir.children(File.join(out, "Hello-x86_64-linux/app"))
    end
  end

  def test_an_app_named_like_a_runtime_folder_is_refused_and_nothing_is_left
    Dir.mktmpdir do |dir|
      app = FakeApp.write(dir, "lib")
      File.write(File.join(app, "fledge.yml"), "name: LIB\n")

      error = assert_raises(Fledge::Error) { assemble(dir, app) }

      assert_equal "an app named LIB would collide with the runtime's lib. Give it another name.", error.message
      assert_empty Dir.children(File.join(dir, "dist"))
    end
  end

  def test_an_app_named_app_or_fledge_cfg_is_refused
    Dir.mktmpdir do |dir|
      { "App" => "its own app folder", "fledge.cfg" => "the file that says what it runs" }.each do |name, what|
        app = FakeApp.write(dir, "x#{name.size}")
        File.write(File.join(app, "fledge.yml"), "name: #{name}\n")

        error = assert_raises(Fledge::Error, name) { assemble(dir, app) }
        assert_equal "an app named #{name} would collide with #{what}. Give it another name.", error.message
      end
    end
  end

  def test_an_entry_point_fledge_cfg_cannot_hold_is_refused
    Dir.mktmpdir do |dir|
      app = FakeApp.write(dir)
      File.write(File.join(app, " spaced.rb"), "")

      error = assert_raises(Fledge::Error) { assemble(dir, File.join(app, " spaced.rb")) }
      assert_equal "\" spaced.rb\" can't be an app's program or Gemfile: its name begins or ends with a space, or holds a line break",
        error.message
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

  def test_a_runtime_holding_an_app_or_a_fledge_cfg_is_refused
    Dir.mktmpdir do |dir|
      { "app/main.rb" => "an app folder", "fledge.cfg" => "a fledge.cfg" }.each do |path, what|
        runtime = FakeRuntime.write(dir, LINUX, extra: [Fledge::Entry.file(path, "")])

        error = assert_raises(Fledge::Error, path) { assemble(dir, FakeApp.write(dir), runtime:) }
        assert_equal "#{runtime} is not a Fledge runtime: it holds #{what}", error.message
      end
    end
  end

  def test_the_base_name_is_name_dash_platform
    app = Fledge::App.new(root: "/x/hello", entry: "main.rb", name: "Hello", gemfile: nil, config: Fledge::Config.none)
    assembly = Fledge::Assembly.new(app:, platform: LINUX, runtime: "r", out: "/o")

    assert_equal "Hello-x86_64-linux", assembly.base_name
  end
end
