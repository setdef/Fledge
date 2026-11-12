# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "test_helper"
require_relative "support/assembly"
require_relative "support/gems"

# Fledge::Assembly with fake runtimes, on the computer the tests run on:
# each platform's app is built on that platform (ADR 010), so a test of
# what only one platform's tools make runs only there, and CI runs the
# tests on every platform. test/integration/assembly_tools_test.rb has
# those tools make what only they make.
class AssemblyTest < Minitest::Test
  include AssemblyHelpers

  RUNTIME_FILES = %w[
    lib
    lib/current
    lib/ruby
    lib/ruby/4.1.0+5
    lib/ruby/4.1.0+5/fake-arch
    lib/ruby/4.1.0+5/fake-arch/rbconfig.rb
    lib/ruby/gems
    lib/ruby/gems/4.1.0+5
    lib/ruby/gems/4.1.0+5/plugins
    lib/ruby/gems/4.1.0+5/plugins/rdoc_plugin.rb
    lib/ruby/gems/4.1.0+5/specifications
    lib/ruby/gems/4.1.0+5/specifications/csv-3.3.5.gemspec
    lib/ruby/gems/4.1.0+5/specifications/default
    lib/ruby/gems/4.1.0+5/specifications/default/json-2.18.0.gemspec
    lib/ruby/gems/4.1.0+5/specifications/rdoc-7.0.4.gemspec
    lib/ruby/stdlib.rb
  ].freeze

  # What a runtime keeps for installers, in its installer folder.
  APPIMAGE_RUNTIME = Fledge::Entry.file("tools/appimage-runtime", "\x7FELF runtime".b, mode: 0o755)

  def test_the_runtime_and_app_land_in_a_folder_and_an_archive_with_the_launcher_renamed
    unix!
    Dir.mktmpdir do |dir|
      app = FakeApp.write(dir)
      File.write(File.join(app, "helper.rb"), "")

      archive = assemble(dir, app)

      assert_equal File.join(dir, "dist", "Hello-x86_64-linux.tar.gz"), archive
      folder = File.join(dir, "dist", "Hello-x86_64-linux")
      assert_equal %w[Hello app fledge.cfg lib], Dir.children(folder).sort
      assert_equal FakeRuntime::LAUNCHER, File.read(File.join(folder, "Hello"))
      assert_equal "puts 'hi'\n", File.read(File.join(folder, "app/main.rb"))
      assert_equal "ruby", File.readlink(File.join(folder, "lib/current"))
      assert_equal ["Hello-x86_64-linux"], left_in(dir) - [File.basename(archive)], "no work folder is left"
      assert Fledge::CacheTag.tagged?(File.join(dir, "dist")), "the folder the build made is tagged"

      place = unpacked(dir, archive)
      top = File.join(place, "Hello-x86_64-linux")
      assert_equal ["Hello", "app", "app/helper.rb", "app/main.rb", "fledge.cfg", *RUNTIME_FILES].sort, tree(top)
      assert_equal 0o755, File.stat(File.join(top, "Hello")).mode & 0o777
      assert File.symlink?(File.join(top, "lib/current"))
    end
  end

  # The launcher reads fledge.cfg, beside it, to learn what to run
  # (runtime/launcher/config.c).
  def test_fledge_cfg_names_the_entry_point_and_a_gemfile
    unix!
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, ".git"))
      hello = FakeApp.write(dir)
      assemble(dir, hello)
      assert_equal "# Written by fledge build #{Fledge::VERSION} for x86_64-linux: what this app's program runs (ADR 005).\nentry = main.rb\n",
        File.read(File.join(dir, "dist/Hello-x86_64-linux/fledge.cfg"))

      project = FakeProject.write(dir, name: "my_cool_app")
      assemble(dir, File.join(project, "exe/my_cool_app"))
      assert_equal "# Written by fledge build #{Fledge::VERSION} for x86_64-linux: what this app's program runs (ADR 005).\n" \
        "entry = exe/my_cool_app\ngemfile = Gemfile\n", File.read(File.join(dir, "dist/MyCoolApp-x86_64-linux/fledge.cfg"))
    end
  end

  def test_app_files_replace_or_join_the_projects_and_files_join_the_runtimes
    unix!
    Dir.mktmpdir do |dir|
      app = FakeApp.write(dir)
      File.write(File.join(app, "hello.gemspec.txt"), "original\n")
      gem = Fledge::Entry.file("lib/ruby/gems/4.1.0+5/gems/foo-1.0.0/lib/foo.rb", "# foo\n")
      info = Fledge::Entry.file("lib/ruby/gems/4.1.0+5/build_info/foo-1.0.0.info", "--with-foo\n")

      archive = assemble(dir, app, app_files: { "hello.gemspec.txt" => "evaluated\n", ".bundle/config" => "---\n" },
        files: [gem, Fledge::Entry.directory("lib/ruby/gems/4.1.0+5"), info])

      folder = File.join(dir, "dist", "Hello-x86_64-linux")
      assert_equal "evaluated\n", File.read(File.join(folder, "app/hello.gemspec.txt"))
      assert_equal "---\n", File.read(File.join(folder, "app/.bundle/config"))
      assert_equal "# foo\n", File.read(File.join(folder, gem.path))
      top = File.join(unpacked(dir, archive), "Hello-x86_64-linux")
      assert_equal "# foo\n", File.read(File.join(top, gem.path))
      assert_equal "--with-foo\n", File.read(File.join(top, info.path))
    end
  end

  def test_an_added_file_may_not_replace_the_runtimes_and_nothing_is_left
    unix!
    Dir.mktmpdir do |dir|
      runtime = FakeRuntime.write(dir, LINUX)
      clash = Fledge::Entry.file("lib/ruby/gems/4.1.0+5/specifications/csv-3.3.5.gemspec", "# mine\n")

      error = assert_raises(Fledge::Error) { assemble(dir, FakeApp.write(dir), runtime:, files: [clash]) }

      assert_equal "#{clash.path} is in #{runtime} already, so the build can't add its own", error.message
      assert_empty left_in(dir)
    end
  end

  # Each program is a copy of the launcher in the one folder, beside one
  # runtime and one app folder, and fledge.cfg gives each its section.
  def test_several_programs_share_one_folder_runtime_and_project
    unix!
    Dir.mktmpdir do |dir|
      archive = assemble(dir, Programs.write(dir))

      folder = File.join(dir, "dist", "Game-x86_64-linux")
      assert_equal File.join(dir, "dist", "Game-x86_64-linux.tar.gz"), archive
      assert_equal ["Play Game", "app", "com.example.Game.desktop", "fledge.cfg", "game-cli", "lib", "share", "tui"], Dir.children(folder).sort
      ["Play Game", "game-cli", "tui"].each do |program|
        assert_equal FakeRuntime::LAUNCHER, File.read(File.join(folder, program)), program
        assert_equal 0o755, File.stat(File.join(folder, program)).mode & 0o777, program
      end
      assert_includes File.read(File.join(folder, "com.example.Game.desktop")), "Exec=\"Play Game\"\n"
      assert_equal <<~CFG, File.read(File.join(folder, "fledge.cfg"))
        # Written by fledge build #{Fledge::VERSION} for x86_64-linux: what this app's programs run (ADR 024).
        [Play Game]
        entry = gui.rb
        identifier = com.example.Game

        [game-cli]
        entry = bin/cli

        [tui]
        entry = bin/tui
        identifier = com.example.GameTui
      CFG
      assert_equal ["Play Game", "app", "com.example.Game.desktop", "fledge.cfg", "game-cli", "lib", "share", "tui"],
        Dir.children(File.join(unpacked(dir, archive), "Game-x86_64-linux")).sort
    end
  end

  # The Gemfile all the programs share stays above their sections.
  def test_several_programs_share_one_gemfile
    Dir.mktmpdir do |dir|
      root = Programs.write(dir)
      File.write(File.join(root, "Gemfile"), "")

      text = Fledge::Assembly.launch_config(Fledge::App.at(root))
      assert text.start_with?("# Written by fledge build: what this app's programs run (ADR 024).\ngemfile = Gemfile\n\n[Play Game]\n"), text
      assert_equal 1, text.scan("gemfile").size
      text = Fledge::Assembly.launch_config(Fledge::App.at(root), bundler: "4.0.19")
      assert text.start_with?("# Written by fledge build: what this app's programs run (ADR 024).\ngemfile = Gemfile\nbundler = 4.0.19\n\n" \
        "[Play Game]\n"), text
    end
  end

  # The Bundler the app runs in place of the runtime's own (ADR 063)
  # follows its Gemfile, for the launcher; an app without one runs no
  # Bundler, so names none.
  def test_fledge_cfg_names_the_bundler_beside_the_gemfile
    Dir.mktmpdir do |dir|
      hello = FakeApp.write(dir)
      assert_equal "# Written by fledge build: what this app's program runs (ADR 005).\nentry = main.rb\n",
        Fledge::Assembly.launch_config(Fledge::App.at(hello), bundler: "4.0.19")
      File.write(File.join(hello, "Gemfile"), "")
      assert_equal "# Written by fledge build: what this app's program runs (ADR 005).\nentry = main.rb\ngemfile = Gemfile\nbundler = 4.0.19\n",
        Fledge::Assembly.launch_config(Fledge::App.at(hello), bundler: "4.0.19")
    end
  end

  # The libraries fledge.yml lists as the Linux distribution's (ADR 030)
  # reach a Linux launcher, which says which one a computer lacks before
  # Ruby starts, once for all the programs; other systems' launchers are
  # not told.
  def test_a_linux_launcher_is_told_the_system_libraries_the_gems_load
    unix!
    Dir.mktmpdir do |dir|
      hello = FakeApp.write(dir)
      File.write(File.join(hello, "fledge.yml"), "linux:\n  system_libraries: [libgtk-3.so.0, libwebkit2gtk-4.1.so.0]\n")
      assemble(dir, hello)
      assert_equal "# Written by fledge build #{Fledge::VERSION} for x86_64-linux: what this app's program runs (ADR 005).\nentry = main.rb\n" \
        "system_libraries = libgtk-3.so.0 libwebkit2gtk-4.1.so.0\n", File.read(File.join(dir, "dist/Hello-x86_64-linux/fledge.cfg"))
      assert_equal "# Written by fledge build: what this app's program runs (ADR 005).\nentry = main.rb\n",
        Fledge::Assembly.launch_config(Fledge::App.at(hello))

      root = Programs.write(dir)
      File.write(File.join(root, "Gemfile"), "")
      File.write(File.join(root, "fledge.yml"), "#{File.read(File.join(root, 'fledge.yml'))}linux:\n  system_libraries: [libgtk-3.so.0]\n")
      text = Fledge::Assembly.launch_config(Fledge::App.at(root), system_libraries: ["libgtk-3.so.0"])
      assert text.start_with?("# Written by fledge build: what this app's programs run (ADR 024).\ngemfile = Gemfile\n" \
        "system_libraries = libgtk-3.so.0\n\n[Play Game]\n"), text
    end
  end

  # One of the programs, built on its own, is an app of one program, as
  # a project with no programs builds.
  def test_one_of_several_programs_builds_alone
    unix!
    Dir.mktmpdir do |dir|
      assemble(dir, File.join(Programs.write(dir), "bin/cli"))

      folder = File.join(dir, "dist", "game-cli-x86_64-linux")
      assert_equal %w[app fledge.cfg game-cli lib], Dir.children(folder).sort
      assert_equal "# Written by fledge build #{Fledge::VERSION} for x86_64-linux: what this app's program runs (ADR 005).\nentry = bin/cli\n",
        File.read(File.join(folder, "fledge.cfg"))
    end
  end

  # No program may take a name the runtime holds.
  def test_a_program_named_as_the_runtimes_files_is_refused
    unix!
    Dir.mktmpdir do |dir|
      root = Programs.write(dir)
      File.write(File.join(root, "fledge.yml"), File.read(File.join(root, "fledge.yml")).sub("name: game-cli", "name: Lib"))

      error = assert_raises(Fledge::Error) { assemble(dir, root) }
      assert_equal "an app named Lib would collide with the runtime's lib. Give it another name.", error.message
      assert_empty left_in(dir)
    end
  end

  # A windowed app on Linux keeps the folder, with a desktop entry beside
  # the program and its icons in the hicolor theme's folders.
  def test_a_windowed_linux_app_has_a_desktop_entry_and_icons
    unix!
    Dir.mktmpdir do |dir|
      assemble(dir, WindowedApp.write(dir))

      folder = File.join(dir, "dist", "Hello Window-x86_64-linux")
      assert_equal ["Hello Window", "app", "com.example.HelloWindow.desktop", "fledge.cfg", "lib", "share"], Dir.children(folder).sort
      assert_includes File.read(File.join(folder, "com.example.HelloWindow.desktop")), "Exec=\"Hello Window\"\n"
      assert_path_exists File.join(folder, "share/icons/hicolor/512x512/apps/com.example.HelloWindow.png")
      assert_equal FakeRuntime::LAUNCHER, File.read(File.join(folder, "Hello Window"))
    end
  end

  # A windowed Linux app takes the icon sizes its project has, at least
  # one, and the build names the rest on its log; with all six it says
  # nothing, and with none it fails as a missing icon does.
  def test_a_windowed_linux_app_takes_the_icon_sizes_there_are
    unix!
    Dir.mktmpdir do |dir|
      root = WindowedApp.write(dir)
      log = StringIO.new
      Fledge::Assembly.new(app: Fledge::App.at(root), platform: LINUX, runtime: FakeRuntime.write(dir, LINUX), out: File.join(dir, "dist"), log:).call
      assert_equal "", log.string

      [16, 64, 512].each { |size| File.delete(File.join(root, "art-#{size}.png")) }
      Fledge::Assembly.new(app: Fledge::App.at(root), platform: LINUX, runtime: FakeRuntime.write(dir, LINUX), out: File.join(dir, "dist"), log:).call
      assert_equal "fledge build: warning: the icon has no art-16.png, art-64.png, art-512.png, so Linux desktops scale the nearest size there is\n",
        log.string
      icons = File.join(dir, "dist", "Hello Window-x86_64-linux", "share/icons/hicolor")
      assert_equal %w[128x128 256x256 32x32], Dir.children(icons).sort

      Dir.glob(File.join(root, "art-*.png")).each { |png| File.delete(png) }
      error = assert_raises(Fledge::Error) { assemble(dir, root) }
      assert_includes error.message, "the icon art-16.png does not exist."
    end
  end

  # A windowed app gets its platform's installer by default (ADR 009),
  # written beside its archive from its folder and the runtime's tools
  # folder, which neither the folder nor the archive holds.
  def test_a_windowed_linux_app_gets_an_appimage_from_the_runtimes_tools_folder
    appimage!
    Dir.mktmpdir do |dir|
      runtime = FakeRuntime.write(dir, LINUX, extra: [APPIMAGE_RUNTIME])
      app = Fledge::App.at(WindowedApp.write(dir, installers: nil))
      assembly = Fledge::Assembly.new(app:, platform: LINUX, runtime:, out: File.join(dir, "dist"))
      archive = assembly.call

      image = File.join(dir, "dist", "Hello Window-x86_64-linux.AppImage")
      assert_equal [image], assembly.installers
      assert_equal APPIMAGE_RUNTIME.content, File.binread(image, APPIMAGE_RUNTIME.content.bytesize)
      refute_path_exists File.join(dir, "dist", "Hello Window-x86_64-linux", "tools")
      assert(tree(unpacked(dir, archive)).none? { |path| path.include?("tools") })
    end
  end

  def test_a_build_without_the_runtimes_tools_fails_and_leaves_nothing
    unix!
    Dir.mktmpdir do |dir|
      error = assert_raises(Fledge::Error) { assemble(dir, WindowedApp.write(dir, installers: nil)) }

      assert_includes error.message, "the runtime has no tools/appimage-runtime"
      assert_empty left_in(dir)
    end
  end

  # A console app on macOS stays a folder with the launcher as it came.
  def test_a_console_macos_app_is_a_folder
    unix!
    Dir.mktmpdir do |dir|
      assemble(dir, FakeApp.write(dir), platform: MACOS)

      assert_equal FakeRuntime::LAUNCHER, File.read(File.join(dir, "dist", "Hello-arm64-darwin", "Hello"))
    end
  end

  # A .zip for Windows holds no symbolic links, and Windows makes them
  # only with privileges, so an app with one is refused.
  def test_a_symlink_in_an_app_for_windows_is_refused_and_nothing_is_left
    unix!
    Dir.mktmpdir do |dir|
      app = FakeApp.write(dir)
      File.symlink("main.rb", File.join(app, "link.rb"))

      error = assert_raises(Fledge::Error) { assemble(dir, app, platform: WINDOWS) }

      assert_equal "Hello-x64-mingw-ucrt/app/link.rb is a symbolic link, which a .zip for Windows cannot hold. " \
        "Replace it with what it points to.", error.message
      assert_empty left_in(dir)
    end
  end

  def test_a_build_replaces_the_previous_one
    unix!
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
    unix!
    Dir.mktmpdir do |dir|
      app = FakeApp.write(dir)
      runtime = FakeRuntime.write(dir, LINUX)
      out = File.join(app, "dist")
      2.times { Fledge::Assembly.new(app: Fledge::App.at(app), platform: LINUX, runtime:, out:).call }

      assert_equal ["main.rb"], Dir.children(File.join(out, "Hello-x86_64-linux/app"))
    end
  end

  # The names of what +archive+ holds, as the system's tar lists them.
  def archived(archive)
    out, status = Open3.capture2e(Fledge::Archive.tar, "-tzf", archive)
    assert_predicate status, :success?, out
    out.lines.map { |line| line.chomp.delete_suffix("/") }
  end

  # A build into dist, and then one into out, a folder of its own, ships
  # the project, not the first build
  # (doc/contributors/design/desktop-apps.md, "The project and its
  # name").
  def test_a_build_into_another_folder_leaves_out_the_earlier_builds
    unix!
    Dir.mktmpdir do |dir|
      app = FakeApp.write(dir)
      runtime = FakeRuntime.write(dir, LINUX)
      first = Fledge::Assembly.new(app: Fledge::App.at(app), platform: LINUX, runtime:, out: File.join(app, "dist")).call

      second = Fledge::Assembly.new(app: Fledge::App.at(app), platform: LINUX, runtime:, out: File.join(app, "out")).call

      assert_equal ["main.rb"], Dir.children(File.join(app, "out/Hello-x86_64-linux/app"))
      assert_equal %w[Hello-x86_64-linux/app Hello-x86_64-linux/app/main.rb], archived(second).grep(%r{\AHello-x86_64-linux/app(/|\z)})
      assert_equal archived(first).sort, archived(second).sort
      assert_in_delta File.size(first), File.size(second), File.size(first) * 0.05
    end
  end

  def test_builds_into_two_new_folders_ship_neither_in_the_other
    unix!
    Dir.mktmpdir do |dir|
      app = FakeApp.write(dir)
      runtime = FakeRuntime.write(dir, LINUX)
      %w[dist-deb dist-appimage dist-deb].each do |out|
        Fledge::Assembly.new(app: Fledge::App.at(app), platform: LINUX, runtime:, out: File.join(app, out)).call
      end

      %w[dist-deb dist-appimage].each do |out|
        assert_equal ["main.rb"], Dir.children(File.join(app, out, "Hello-x86_64-linux/app")), out
        assert_equal %w[CACHEDIR.TAG Hello-x86_64-linux Hello-x86_64-linux.tar.gz], Dir.children(File.join(app, out)).sort, out
      end
    end
  end

  # A dist folder of the project's own, which no build went to, ships as
  # any other folder does when the build goes elsewhere.
  def test_a_folder_named_dist_that_holds_no_build_ships
    unix!
    Dir.mktmpdir do |dir|
      app = FakeApp.write(dir)
      FileUtils.mkdir_p(File.join(app, "dist"))
      File.write(File.join(app, "dist/index.html"), "the app's own")
      runtime = FakeRuntime.write(dir, LINUX)

      Fledge::Assembly.new(app: Fledge::App.at(app), platform: LINUX, runtime:, out: File.join(dir, "builds")).call

      assert_equal "the app's own", File.read(File.join(dir, "builds/Hello-x86_64-linux/app/dist/index.html"))
      refute_path_exists File.join(app, "dist/CACHEDIR.TAG")
    end
  end

  def test_an_app_named_like_a_runtime_folder_is_refused_and_nothing_is_left
    unix!
    Dir.mktmpdir do |dir|
      app = FakeApp.write(dir, "lib")
      File.write(File.join(app, "fledge.yml"), "name: LIB\n")

      error = assert_raises(Fledge::Error) { assemble(dir, app) }

      assert_equal "an app named LIB would collide with the runtime's lib. Give it another name.", error.message
      assert_empty left_in(dir)
    end
  end

  def test_an_app_named_app_or_fledge_cfg_is_refused
    Dir.mktmpdir do |dir|
      { "App" => "its own app folder", "fledge.cfg" => "the file that says what it runs" }.each do |name, what|
        app = FakeApp.write(dir, "x#{name.size}")
        File.write(File.join(app, "fledge.yml"), "name: #{name}\n")

        error = assert_raises(Fledge::Error, name) { assemble(dir, app, runtime: "unused.tar.gz") }
        assert_equal "an app named #{name} would collide with #{what}. Give it another name.", error.message
      end
    end
  end

  def test_an_entry_point_fledge_cfg_cannot_hold_is_refused
    unix!
    Dir.mktmpdir do |dir|
      app = FakeApp.write(dir)
      File.write(File.join(app, " spaced.rb"), "")

      error = assert_raises(Fledge::Error) { assemble(dir, File.join(app, " spaced.rb")) }
      assert_equal "\" spaced.rb\" can't be an app's program or Gemfile: its name begins or ends with a space, or holds a line break",
        error.message
    end
  end

  def test_a_runtime_without_a_launcher_is_refused
    unix!
    Dir.mktmpdir do |dir|
      runtime = FakeRuntime.pack(File.join(dir, "empty.tar.gz"), "top", [Fledge::Entry.file("README", "")])

      error = assert_raises(Fledge::Error) { assemble(dir, FakeApp.write(dir), runtime:) }
      assert_equal "#{runtime} is not a Fledge runtime: it has no launcher", error.message
    end
  end

  def test_a_runtime_with_two_top_folders_is_refused
    unix!
    Dir.mktmpdir do |dir|
      stage = File.join(dir, "stage")
      Fledge::Entry.file("a/launcher", "", mode: 0o755).write_into(stage)
      Fledge::Entry.file("b/x", "").write_into(stage)
      runtime = File.join(dir, "two.tar.gz")
      out, status = Open3.capture2e("tar", "-czf", runtime, "-C", stage, "a", "b")
      assert_predicate status, :success?, out

      error = assert_raises(Fledge::Error) { assemble(dir, FakeApp.write(dir), runtime:) }
      assert_equal "#{runtime} is not a Fledge runtime: it holds both a/ and b", error.message
    end
  end

  def test_a_runtime_holding_an_app_or_a_fledge_cfg_is_refused
    unix!
    Dir.mktmpdir do |dir|
      { "app/main.rb" => "an app folder", "fledge.cfg" => "a fledge.cfg" }.each do |path, what|
        runtime = FakeRuntime.write(dir, LINUX, extra: [Fledge::Entry.file(path, "")])

        error = assert_raises(Fledge::Error, path) { assemble(dir, FakeApp.write(dir), runtime:) }
        assert_equal "#{runtime} is not a Fledge runtime: it holds #{what}", error.message
      end
    end
  end

  def test_the_base_name_is_name_dash_platform
    Dir.mktmpdir do |dir|
      assembly = Fledge::Assembly.new(app: Fledge::App.at(FakeApp.write(dir)), platform: LINUX, runtime: "r", out: "/o")

      assert_equal "Hello-x86_64-linux", assembly.base_name
    end
  end
end
