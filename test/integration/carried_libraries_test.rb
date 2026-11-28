# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "../test_helper"
require "bundler"
require "open3"

# A Mac app that carries libraries from the developer's computer
# (Fledge::CarriedLibraries). test/fixtures/carried_libraries's gem links
# libgreet, which needs libpunct; the test builds both with Xcode's clang
# into a folder of their own, as a package manager installs them:
# libgreet named by its absolute path, as Homebrew names its libraries,
# with an absolute run path to libpunct, which names itself by
# <tt>@rpath</tt>, as conda-forge's do. It shows the premise, the gem
# loading both under <tt>bundle exec</tt> with that folder present; the
# refusal without the setting, and with libpunct left out of it; and the
# app, built with both listed, loading its copies with the folder gone,
# from a terminal, as Finder starts it, from an app built --from it and
# signed ad hoc with the hardened runtime, and sealed in its disk image.
#
# It needs a Mac, Xcode's command line tools, and the runtime that
# BuiltAppTest needs (FLEDGE_RUNTIME_DIR, or tmp/runtime).
class CarriedLibrariesIntegrationTest < Minitest::Test
  FIXTURE = File.expand_path("../fixtures/carried_libraries", __dir__)
  EXE = File.expand_path("../../exe/fledge", __dir__)
  LIB = File.expand_path("../../lib", __dir__)
  NAME = "Carried Libraries Probe"
  LINE = "greet: hello from libgreet, by way of libpunct!\n"

  def setup
    skip "only a Mac app carries libraries from its computer" unless RUBY_PLATFORM.include?("darwin")
    @platform = Fledge::Platform.local
    @runtimes = ENV.fetch("FLEDGE_RUNTIME_DIR", File.expand_path("../../tmp/runtime", __dir__))
    return if File.file?(File.join(@runtimes, Fledge::Runtimes.file_name(@platform)))

    message = "no #{Fledge::Runtimes.file_name(@platform)} in #{@runtimes}; run bundle exec rake runtime"
    flunk message if ENV["FLEDGE_REQUIRE_RUNTIME"]
    skip message
  end

  def test_a_mac_app_carries_the_libraries_its_project_lists_and_loads_them_wherever_it_is
    Dir.mktmpdir do |dir|
      prefix = File.join(dir, "prefix")
      install_libraries(prefix)
      project = File.join(dir, "project")
      FileUtils.cp_r(FIXTURE, project)
      env = { "CPATH" => File.join(prefix, "include"), "LIBRARY_PATH" => File.join(prefix, "lib") }

      assert_equal LINE, under_bundle_exec(project, env, File.join(dir, "ext")), "the premise: the gem loads both libraries from the folder"

      listed = File.read(File.join(project, "fledge.yml"))
      File.write(File.join(project, "fledge.yml"), listed.sub(/^macos:\n.*\n/, ""))
      _, err, status = build(project, File.join(dir, "refused"), env)
      assert_equal 1, status.exitstatus
      assert_includes err, "needs #{prefix}/lib/libgreet.1.dylib, which neither darwin"
      assert_includes err, "list it in fledge.yml as macos: { carried_libraries: [libgreet.1.dylib] }"

      File.write(File.join(project, "fledge.yml"), listed.sub("libgreet.1.dylib, libpunct.1.dylib", "libgreet.1.dylib"))
      _, err, status = build(project, File.join(dir, "refused"), env)
      assert_equal 1, status.exitstatus
      assert_includes err, "libgreet.1.dylib, which the app carries from #{File.realpath(prefix)}/lib/libgreet.1.dylib, needs " \
        "@rpath/libpunct.1.dylib, which is #{File.realpath(prefix)}/lib/libpunct.1.dylib on this computer"
      assert_includes err, "macos: { carried_libraries: [libgreet.1.dylib, libpunct.1.dylib] }"

      File.write(File.join(project, "fledge.yml"), listed)
      out_dir = File.join(dir, "dist")
      _, err, status = build(project, out_dir, env)
      assert_predicate status, :success?, err
      assert_includes err, "Carrying libgreet.1.dylib from #{File.realpath(prefix)}/lib/libgreet.1.dylib\n"
      assert_path_exists File.join(out_dir, "#{NAME}-#{@platform}.dmg")

      FileUtils.mv(prefix, "#{prefix}-gone")
      bundle = File.join(dir, "elsewhere", "#{NAME}.app")
      FileUtils.mkdir_p(File.dirname(bundle))
      FileUtils.cp_r(File.join(out_dir, "#{NAME}-#{@platform}", "#{NAME}.app"), bundle)
      resources = File.join(bundle, "Contents", "Resources")
      assert_equal ["libgreet.1.dylib", "libpunct.1.dylib"], Dir.children(File.join(resources, Fledge::CarriedLibraries::FOLDER)).sort
      _, verify, status = Open3.capture3("codesign", "--verify", "--deep", "--strict", bundle)
      assert_predicate status, :success?, verify

      assert_equal [LINE, "", 0], run_app(File.join(bundle, "Contents", "MacOS", NAME)), "from a terminal, with the libraries' folder gone"
      assert_equal LINE, opened(bundle, File.join(dir, "opened.txt")), "as Finder starts it"

      assert_equal LINE, built_from(bundle, dir), "an app built --from it, signed ad hoc with the hardened runtime"
    end
  end

  # Builds libpunct and libgreet into +prefix+, with their headers, for
  # the app's oldest macOS, as a package manager installs a library.
  def install_libraries(prefix)
    sources = File.join(FIXTURE, "libraries")
    lib = File.join(prefix, "lib")
    FileUtils.mkdir_p([lib, File.join(prefix, "include")])
    FileUtils.cp(File.join(sources, "greet.h"), File.join(prefix, "include"))
    floor = "-mmacosx-version-min=#{@platform.macos_minimum}"
    clang(floor, "-dynamiclib", "-install_name", "@rpath/libpunct.1.dylib", File.join(sources, "punct.c"), "-o", File.join(lib, "libpunct.1.dylib"))
    clang(floor, "-dynamiclib", "-install_name", File.join(lib, "libgreet.1.dylib"), "-Wl,-rpath,#{lib}", File.join(sources, "greet.c"),
      File.join(lib, "libpunct.1.dylib"), "-o", File.join(lib, "libgreet.1.dylib"))
    File.symlink("libgreet.1.dylib", File.join(lib, "libgreet.dylib"))
  end

  def clang(*)
    output, status = Open3.capture2e("xcrun", "clang", *)
    assert_predicate status, :success?, output
  end

  # What main.rb prints under bundle exec, with the gem's extension
  # compiled for this Ruby in +work+ and put where the gem requires it,
  # as a developer builds a path gem's extension.
  def under_bundle_exec(project, env, work)
    FileUtils.mkdir_p(work)
    extconf = File.join(project, "gems", "greet", "ext", "greet", "extconf.rb")
    Bundler.with_unbundled_env do
      output, status = Open3.capture2e(env, RbConfig.ruby, extconf, chdir: work)
      assert_predicate status, :success?, output
      output, status = Open3.capture2e(env, "make", chdir: work)
      assert_predicate status, :success?, output
      FileUtils.mkdir_p(File.join(project, "gems", "greet", "lib", "greet"))
      FileUtils.cp(File.join(work, "greet.bundle"), File.join(project, "gems", "greet", "lib", "greet", "greet.bundle"))
      out, err, status = Open3.capture3({ "BUNDLE_GEMFILE" => File.join(project, "Gemfile") }, RbConfig.ruby, "-rbundler/setup", "main.rb",
        chdir: project)
      assert_predicate status, :success?, err
      out
    end
  end

  def build(project, out_dir, env, *options)
    Open3.capture3(env.merge("FLEDGE_RUNTIME_DIR" => @runtimes), RbConfig.ruby, "-I", LIB, EXE, "build", *options, "-o", out_dir, project)
  end

  def run_app(program)
    out, err, status = Open3.capture3({}, [program, program], unsetenv_others: true, chdir: "/")
    [out, err, status.exitstatus]
  end

  # What the app at +bundle+ writes to +report+ when open starts it, as
  # Finder does, through Launch Services.
  def opened(bundle, report)
    output, status = Open3.capture2e("open", "-n", "-W", bundle, "--args", report)
    assert_predicate status, :success?, output
    File.read(report)
  end

  # What a project with only a main.rb prints, built --from the app at
  # +bundle+, which takes its runtime and gems, carried libraries and
  # all, and signed ad hoc as a Developer ID is, with the hardened
  # runtime.
  def built_from(bundle, dir)
    project = File.join(dir, "from")
    FileUtils.mkdir_p(project)
    FileUtils.cp(File.join(FIXTURE, "main.rb"), project)
    File.write(File.join(project, "fledge.yml"), "name: From Carried\n")
    _, err, status = build(project, File.join(dir, "from-dist"), {}, "--from", bundle, "--sign", "-")
    assert_predicate status, :success?, err
    out, = run_app(File.join(dir, "from-dist", "From Carried-#{@platform}", "From Carried"))
    out
  end
end
