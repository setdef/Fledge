# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "test_helper"
require_relative "support/gems"
require_relative "support/git_repos"
require_relative "support/loopback_server"
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
    @runtimes = ENV.fetch("FLEDGE_RUNTIME_DIR", File.expand_path("../tmp/runtime", __dir__))
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

  # Runs the built app with nothing of this computer's Ruby around it.
  def run_app
    folder = File.join(@dir, "dist", "MyApp-#{@platform}")
    out, status = Open3.capture2e({ "PATH" => ENV.fetch("PATH") }, File.join(folder, @platform.executable("MyApp")), unsetenv_others: !Gem.win_platform?)
    [out, status, folder]
  end

  def program(root)
    File.write(File.join(root, "exe", "my_app"), "require \"greeter\"\nputs Greeter.greet\n")
  end

  def gem_dir(folder) = File.join(folder, @platform.windows? ? "ruby/lib/ruby/gems/4.0.0" : "lib/ruby/gems/4.0.0")

  def test_a_gem_with_only_its_source_compiles_with_its_build_options_and_runs
    greeter = FakeGem.build(@dir, "greeter", "1.0.0", files: FILES, extensions: ["ext/greeter/extconf.rb"])
    @routes["/gems/#{greeter.file_name}"] = [200, {}, File.binread(greeter.path)]
    root = FakeProject.write(@dir, dependencies: { "greeter" => ">= 0" }, locked: [greeter], remote: @server.url("/"))
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
    refute_path_exists File.join(folder, @platform.windows? ? "ruby/include" : "include"), "the runtime's headers never ship"
    compiled = Dir.glob(File.join(gems, "gems/greeter-1.0.0/lib/greeter/greeter.*")).first.to_s
    assert_operator Gem::Version.new(Fledge::Binary.macos_minimum(File.binread(compiled))), :<=, Gem::Version.new("14.0") if @platform.os == "darwin"
  end

  def test_a_git_gem_compiles_where_bundler_keeps_it_and_runs
    repo, revision = FakeRepo.write(@dir, "Greeters", gems: { "greeter" => FILES }, extensions: { "greeter" => ["ext/greeter/extconf.rb"] })
    root = FakeProject.write(@dir, dependencies: {}, locked: [], remote: @server.url("/"),
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
end
