# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "../test_helper"
require_relative "../support/gems"
require_relative "../support/git_repos"
require_relative "../support/loopback_server"
require_relative "../support/short_path"
require "open3"
require "stringio"

# fledge build compiling a gem's C extension on this computer, for this
# computer's platform, against the real runtime's own Ruby and its
# build-only companion (ADR 006): a gem that publishes only its source,
# served by a real gem server, with build options from the project's
# .bundle/config, and the same gem from git. Then the built app runs.
#
# The runtime and its companion come from FLEDGE_RUNTIME_DIR, or from
# tmp/runtime, where rake runtime writes them. Without them the test
# skips, unless FLEDGE_REQUIRE_RUNTIME is set, as CI sets it.
class NativeBuildTest < Minitest::Test
  EXTCONF = <<~RUBY
    require "mkmf"
    greeting = arg_config("--with-greeting", "hello")
    $defs << %(-DGREETING=\\\\"\#{greeting}\\\\")
    create_makefile("greeter/greeter")
  RUBY

  SOURCE = <<~C
    #include <ruby.h>

    static VALUE greet(VALUE self) { return rb_str_new_cstr(GREETING); }

    void Init_greeter(void) { rb_define_singleton_method(rb_define_module("Greeter"), "greet", greet, 0); }
  C

  FILES = {
    "ext/greeter/extconf.rb" => EXTCONF,
    "ext/greeter/greeter.c" => SOURCE,
    "lib/greeter.rb" => "require \"greeter/greeter\"\n",
    "LICENSE" => "greeter is MIT\n",
  }.freeze

  def setup
    @platform = Fledge::Platform.local
    @runtimes = ENV.fetch("FLEDGE_RUNTIME_DIR", File.expand_path("../../tmp/runtime", __dir__))
    missing = [Fledge::Runtimes.file_name(@platform), Fledge::Runtimes.dev_file_name(@platform)]
      .reject { |name| File.file?(File.join(@runtimes, name)) }
    unless missing.empty?
      message = "no #{missing.join(' or ')} in #{@runtimes}; run bundle exec rake runtime"
      flunk message if ENV["FLEDGE_REQUIRE_RUNTIME"]
      skip message
    end
    @dir = Dir.mktmpdir
    FileUtils.mkdir_p(File.join(@dir, ".git"))
    @routes = {}
    @server = LoopbackServer.new(@routes)
  rescue Fledge::Error => e
    flunk e.message if ENV["FLEDGE_REQUIRE_RUNTIME"]
    skip e.message
  end

  def teardown
    @server&.stop
    FileUtils.rm_rf(@dir) if @dir
  end

  def build(root)
    out = StringIO.new
    err = StringIO.new
    env = ENV.to_h.merge("FLEDGE_RUNTIME_DIR" => @runtimes, "XDG_CACHE_HOME" => File.join(@dir, "cache"))
    status = Dir.chdir(@dir) { Fledge::CLI::Build.new(out:, err:, env:).call([File.join(root, "exe/my_app")]) }
    [status, err.string]
  end

  # Runs the built app with nothing of this computer's Ruby around it: on
  # Windows, which needs the rest of the environment, without the variables
  # bundle exec sets for the Ruby that runs the tests, which a Ruby the app
  # starts would otherwise load beside its own Bundler.
  def run_app
    folder = File.join(@dir, "dist", "MyApp-#{@platform}")
    scrubbed = ENV.keys.grep(Fledge::NativeBuild::SCRUBBED).to_h { |name| [name, nil] }
    out, status = Open3.capture2e({ "PATH" => ENV.fetch("PATH") }.merge(scrubbed), File.join(folder, @platform.executable("MyApp")),
      unsetenv_others: !Gem.win_platform?)
    [out, status, folder]
  end

  def program(root)
    File.write(File.join(root, "exe", "my_app"), "require \"greeter\"\nputs Greeter.greet\n")
  end

  # The app's gem folder, named for its Ruby's library (4.1.0+5).
  def gem_dir(folder)
    found = Dir.glob(File.join(folder, @platform.windows? ? "ruby/lib/ruby/gems/*" : "lib/ruby/gems/*"))
    assert_equal 1, found.size, "one gem folder in #{folder}"
    found.first.to_s
  end

  def test_a_gem_with_only_its_source_compiles_with_its_build_options_and_runs
    greeter = FakeGem.build(@dir, "greeter", "1.0.0", files: FILES, extensions: ["ext/greeter/extconf.rb"])
    @routes["/gems/#{greeter.file_name}"] = [200, {}, File.binread(greeter.path)]
    root = FakeProject.write(@dir, bundled_with: FakeProject.runtime_bundler, dependencies: { "greeter" => ">= 0" }, locked: [greeter], remote: @server.url("/"))
    program(root)
    FileUtils.mkdir_p(File.join(root, ".bundle"))
    File.write(File.join(root, ".bundle", "config"), "---\nBUNDLE_BUILD__GREETER: \"--with-greeting=bonjour\"\n")

    status, err = build(root)

    assert_equal 0, status, err
    out, ran, folder = run_app
    assert_predicate ran, :success?, out
    assert_equal "bonjour\n", out
    gems = gem_dir(folder)
    extensions = Dir.glob(File.join(gems, "extensions", "*", "*", "greeter-1.0.0"))
    assert_equal 1, extensions.size
    assert_path_exists File.join(extensions.first, "gem.build_complete")
    refute_path_exists File.join(extensions.first, "gem_make.out"), "the build's log holds the build machine's paths"
    assert_includes File.read(File.join(gems, "build_info", "greeter-1.0.0.info")), "--with-greeting=bonjour"
    refute(Dir.glob(File.join(gems, "gems/greeter-1.0.0/ext/greeter/*")).any? { |path| path.end_with?(".o", "Makefile") },
      "the build's own leftovers stay behind")
    refute_path_exists File.join(folder, "DEV-NOTICES.txt"), "nothing of the build-only companion ships"
    assert_equal 1, Dir.glob(File.join(folder, @platform.windows? ? "ruby/lib/*.dll.a" : "lib/libruby*-static.a")).size,
      "the runtime's own library to link against, which mkmf's checks read, ships as the runtime holds it"
    assert_path_exists File.join(folder, @platform.windows? ? "ruby/include" : "include"), "Ruby's headers ship, for require \"mkmf\""
    compiled = Dir.glob(File.join(gems, "gems/greeter-1.0.0/lib/greeter/greeter.*")).first.to_s
    return unless @platform.os == "darwin"

    minimum = Fledge::Binary.read([compiled], readers: Fledge::Binary::Readers.local("darwin")).fetch(compiled).macos_minimum
    assert_operator Gem::Version.new(minimum), :<=, Gem::Version.new("14.0")
  end

  # The build's work folder is named by its long names where TMPDIR names
  # it by its 8.3 name, as Windows' TMP does for a user folder whose name
  # is no 8.3 name: mini_portile2, which nokogiri's extconf.rb uses,
  # escapes a path for a POSIX shell and runs it through cmd.exe, where
  # the short name's escaped tilde names no file. This gem's extconf.rb
  # refuses a short name in the folder it runs in.
  def test_a_gem_compiles_in_a_folder_named_by_its_long_names_whatever_tmpdir_says
    long = File.join(@dir, "longtemporaryfolder")
    FileUtils.mkdir_p(long)
    short = ShortPath.of(long)
    skip "no 8.3 names here: off Windows, or 8.3 names are turned off on #{@dir}'s volume" unless short
    extconf = "abort \"compiled in \#{Dir.pwd}\" if Dir.pwd.match?(/~\\d/)\n#{EXTCONF}"
    greeter = FakeGem.build(@dir, "greeter", "1.0.0", files: FILES.merge("ext/greeter/extconf.rb" => extconf), extensions: ["ext/greeter/extconf.rb"])
    @routes["/gems/#{greeter.file_name}"] = [200, {}, File.binread(greeter.path)]
    root = FakeProject.write(@dir, bundled_with: FakeProject.runtime_bundler, dependencies: { "greeter" => ">= 0" }, locked: [greeter], remote: @server.url("/"))
    program(root)

    status, err = with_tmpdir(short) { build(root) }

    assert_equal 0, status, err
    out, ran, = run_app
    assert_predicate ran, :success?, out
    assert_equal "hello\n", out
  end

  def with_tmpdir(folder)
    previous = ENV.fetch("TMPDIR", nil)
    ENV["TMPDIR"] = folder
    yield
  ensure
    ENV["TMPDIR"] = previous
  end

  def test_a_git_gem_compiles_where_bundler_keeps_it_and_runs
    repo, revision = FakeRepo.write(@dir, "Greeters", gems: { "greeter" => FILES }, extensions: { "greeter" => ["ext/greeter/extconf.rb"] })
    root = FakeProject.write(@dir, bundled_with: FakeProject.runtime_bundler, dependencies: {}, locked: [], remote: @server.url("/"),
      gemfile: "gem \"greeter\", git: #{repo.inspect}, branch: \"trunk\", glob: \"gems/*/*.gemspec\"\n", lock_dependencies: ["greeter!"])
    lock = File.join(root, "Gemfile.lock")
    text = File.read(lock).sub("CHECKSUMS\n", "CHECKSUMS\n  greeter (1.0)\n")
    File.write(lock, "GIT\n  remote: #{repo}\n  revision: #{revision}\n  branch: trunk\n  glob: gems/*/*.gemspec\n  specs:\n" \
      "    greeter (1.0)\n\n#{text}")
    program(root)

    status, err = build(root)

    assert_equal 0, status, err
    out, ran, folder = run_app
    assert_predicate ran, :success?, out
    assert_equal "hello\n", out
    scope = "Greeters-#{revision[0, 12]}"
    built = Dir.glob(File.join(gem_dir(folder), "bundler/gems/extensions/*/*/#{scope}-greeter/gem.build_complete"))
    assert_equal 1, built.size, "Bundler's own extensions folder for a git gem"
  end

  # A project whose Gemfile takes greeter from the folder +path+ (relative
  # to the project), holding FILES at @dir/+folder+. +stale+ is a file the
  # developer compiled there for their own Ruby, in the gem's lib.
  def path_project(path:, folder:, stale: nil)
    source = File.join(@dir, folder)
    FILES.merge(stale || {}).each do |file, content|
      FileUtils.mkdir_p(File.dirname(File.join(source, file)))
      File.write(File.join(source, file), content)
    end
    File.write(File.join(source, "greeter.gemspec"), <<~GEMSPEC)
      Gem::Specification.new do |s|
        s.name = "greeter"
        s.version = "1.0"
        s.summary = "A path gem for Fledge's tests"
        s.authors = ["Fledge"]
        s.files = #{FILES.keys.inspect}
        s.extensions = ["ext/greeter/extconf.rb"]
      end
    GEMSPEC
    root = FakeProject.write(@dir, bundled_with: FakeProject.runtime_bundler, dependencies: {}, locked: [], gemfile: "gem \"greeter\", path: #{path.inspect}\n", lock_dependencies: ["greeter!"])
    lock = File.join(root, "Gemfile.lock")
    text = File.read(lock).sub("CHECKSUMS\n", "CHECKSUMS\n  greeter (1.0)\n")
    File.write(lock, "PATH\n  remote: #{path}\n  specs:\n    greeter (1.0)\n\n#{text}")
    program(root)
    root
  end

  # Bundler compiles no path gem's extension, so bundle exec loads what the
  # developer compiled; the built app has the runtime's Ruby, so Fledge
  # compiles it, and it ships in Bundler's place for a copy of a gem from
  # outside the project. The original folder is gone by the time it runs.
  def test_a_path_gem_outside_the_project_with_an_extension_compiles_and_ships_in_bundlers_copy
    root = path_project(path: "../greeter", folder: "greeter")

    status, err = build(root)

    assert_equal 0, status, err
    FileUtils.rm_rf(File.join(@dir, "greeter"))
    out, ran, folder = run_app
    assert_predicate ran, :success?, out
    assert_equal "hello\n", out
    copy = File.join(folder, "app", "vendor", "cache", "greeter")
    assert_path_exists File.join(copy, "ext/greeter/greeter.c")
    assert_includes File.read(File.join(copy, "greeter.gemspec")), "s.name = \"greeter\""
    refute_path_exists File.join(copy, "ext/greeter/Makefile"), "the build's own leftovers stay behind"
  end

  def test_a_path_gem_inside_the_project_with_an_extension_replaces_what_the_developer_compiled_for_their_ruby
    extension = RbConfig::CONFIG["DLEXT"]
    stale = "lib/greeter/greeter.#{extension}"
    root = path_project(path: "gems/greeter", folder: "my_app/gems/greeter", stale: { stale => "compiled for another Ruby" })

    status, err = build(root)

    assert_equal 0, status, err
    out, ran, folder = run_app
    assert_predicate ran, :success?, out
    assert_equal "hello\n", out
    refute_equal "compiled for another Ruby", File.binread(File.join(folder, "app", "gems", "greeter", stale))
  end

  # Under bundle exec a gem's executables are in the bundle's bin folder,
  # as RubyGems wrote them. A built app has them in the runtime's bin
  # folder, written by the runtime's own RubyGems like the runtime's own,
  # which find the runtime's ruby beside them.
  def test_a_gems_executables_ship_in_the_runtimes_bin_folder_and_run_without_ruby_on_path
    cli = FakeGem.build(@dir, "tool", "1.0.0", executables: ["tool-cli"],
      files: { "lib/tool.rb" => "module Tool; def self.name = 'tool'; end\n", "exe/tool-cli" => "#!/usr/bin/env ruby\nrequire 'tool'\nputs \"tool-cli says \#{Tool.name}\"\n" })
    @routes["/gems/#{cli.file_name}"] = [200, {}, File.binread(cli.path)]
    root = FakeProject.write(@dir, bundled_with: FakeProject.runtime_bundler, dependencies: { "tool" => ">= 0" }, locked: [cli], remote: @server.url("/"))
    File.write(File.join(root, "exe", "my_app"), "puts IO.popen([File.join(Gem.bindir, Gem.win_platform? ? 'tool-cli.bat' : 'tool-cli')], &:read)\n")

    status, err = build(root)

    assert_equal 0, status, err
    out, ran, folder = run_app
    assert_predicate ran, :success?, out
    assert_equal "tool-cli says tool\n", out
    stub = File.read(File.join(folder, @platform.windows? ? "ruby/bin" : "bin", "tool-cli"))
    refute_includes stub, @dir, "the build machine's paths stay behind"
    refute_match(/Successfully built RubyGem|^\s*File: tool-1\.0\.0\.gem$/, err, "RubyGems' report of packing the gem stays out of the build's log")
  end

  def test_a_path_gems_executables_ship_too_and_a_runtime_gems_stay_the_runtimes
    source = File.join(@dir, "my_app", "gems", "tool")
    FileUtils.mkdir_p(File.join(source, "exe"))
    File.write(File.join(source, "exe", "tool-cli"), "#!/usr/bin/env ruby\nputs 'from a path gem'\n")
    File.chmod(0o755, File.join(source, "exe", "tool-cli"))
    File.write(File.join(source, "tool.gemspec"), "Gem::Specification.new { |s| s.name = 'tool'; s.version = '1.0'; s.summary = 'x'; " \
      "s.authors = ['x']; s.files = ['exe/tool-cli']; s.bindir = 'exe'; s.executables = ['tool-cli', 'rake'] }\n")
    File.write(File.join(source, "exe", "rake"), "#!/usr/bin/env ruby\nputs 'not the runtime rake'\n")
    root = FakeProject.write(@dir, bundled_with: FakeProject.runtime_bundler, dependencies: {}, locked: [], gemfile: "gem \"tool\", path: \"gems/tool\"\n", lock_dependencies: ["tool!"])
    lock = File.join(root, "Gemfile.lock")
    File.write(lock, "PATH\n  remote: gems/tool\n  specs:\n    tool (1.0)\n\n#{File.read(lock).sub("CHECKSUMS\n", "CHECKSUMS\n  tool (1.0)\n")}")
    File.write(File.join(root, "exe", "my_app"), "puts IO.popen([File.join(Gem.bindir, Gem.win_platform? ? 'tool-cli.bat' : 'tool-cli')], &:read)\n")

    status, err = build(root)

    assert_equal 0, status, err
    out, ran, folder = run_app
    assert_predicate ran, :success?, out
    assert_equal "from a path gem\n", out
    refute_includes File.read(File.join(folder, @platform.windows? ? "ruby/bin" : "bin", "rake")), "not the runtime rake"
  end

  def test_a_git_gems_executables_ship_in_the_runtimes_bin_folder
    files = { "lib/tool.rb" => "", "exe/tool-cli" => "#!/usr/bin/env ruby\nputs 'from a git gem'\n" }
    repo, revision = FakeRepo.write(@dir, "Tools", gems: { "tool" => files }, executables: { "tool" => ["tool-cli"] })
    root = FakeProject.write(@dir, bundled_with: FakeProject.runtime_bundler, dependencies: {}, locked: [], remote: @server.url("/"),
      gemfile: "gem \"tool\", git: #{repo.inspect}, branch: \"trunk\", glob: \"gems/*/*.gemspec\"\n", lock_dependencies: ["tool!"])
    lock = File.join(root, "Gemfile.lock")
    text = File.read(lock).sub("CHECKSUMS\n", "CHECKSUMS\n  tool (1.0)\n")
    File.write(lock, "GIT\n  remote: #{repo}\n  revision: #{revision}\n  branch: trunk\n  glob: gems/*/*.gemspec\n  specs:\n" \
      "    tool (1.0)\n\n#{text}")
    File.write(File.join(root, "exe", "my_app"), "puts IO.popen([File.join(Gem.bindir, Gem.win_platform? ? 'tool-cli.bat' : 'tool-cli')], &:read)\n")

    status, err = build(root)

    assert_equal 0, status, err
    out, ran, = run_app
    assert_predicate ran, :success?, out
    assert_equal "from a git gem\n", out
  end
end
