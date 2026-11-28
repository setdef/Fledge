# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "../test_helper"
require "open3"

# A real gem that loads a typelib by name while the app runs:
# test/fixtures/typelib, over ruby-gnome's gdk_pixbuf2, whose
# extensions fledge build compiles here from source, as bundle install
# does. Its fledge.yml lists GDK-PixBuf's typelib under linux:
# system_typelibs, and the test shows the premise and the failure before
# the fix: the program runs under bundle exec, and in the built app, where
# libgirepository finds the typelib; and without the launcher's check, a
# computer that lacks it meets Ruby's
# GObjectIntrospection::RepositoryError from inside the gem. With the
# check, the app names the typelib and exits with EX_OSFILE before Ruby
# starts.
#
# It needs GLib's and GObject introspection's development files, which
# pkg-config finds, and the typelib somewhere only GI_TYPELIB_PATH
# leads: Ubuntu 24.04 with libgdk-pixbuf-2.0-0 and without
# gir1.2-gdkpixbuf-2.0, and that package unpacked into a folder
# GI_TYPELIB_PATH names, is such a computer. Elsewhere it skips, saying
# what it lacks, unless FLEDGE_REQUIRE_TYPELIBS is set, as CI sets it on
# Linux, and then it fails. The runtime comes from FLEDGE_RUNTIME_DIR, or from
# tmp/runtime, where rake runtime writes it.
class TypelibTest < Minitest::Test
  FIXTURE = File.expand_path("../fixtures/typelib", __dir__)
  EXE = File.expand_path("../../exe/fledge", __dir__)
  LIB = File.expand_path("../../lib", __dir__)
  EXPECTED = "GdkPixbuf 2x3, 4 channels\n"

  def setup
    @platform = Fledge::Platform.local
    skip "only a Linux app's gems load typelibs from its distribution" unless @platform.os == "linux"
    @runtimes = ENV.fetch("FLEDGE_RUNTIME_DIR", File.expand_path("../../tmp/runtime", __dir__))
    unless File.file?(File.join(@runtimes, Fledge::Runtimes.file_name(@platform)))
      message = "no #{Fledge::Runtimes.file_name(@platform)} in #{@runtimes}; run bundle exec rake runtime"
      flunk message if ENV["FLEDGE_REQUIRE_RUNTIME"]
      skip message
    end
    packages = %w[gobject-introspection-1.0 gio-2.0]
    unless system("pkg-config", "--exists", *packages)
      lacking "pkg-config finds no #{packages.join(' or ')}, whose development files the fixture's gems compile against"
    end
    @dir = Dir.mktmpdir
  rescue Fledge::Error => e
    flunk e.message if ENV["FLEDGE_REQUIRE_RUNTIME"]
    skip e.message
  end

  def teardown
    FileUtils.rm_rf(@dir) if @dir
  end

  def test_a_typelib_the_computer_lacks_is_named_before_ruby_starts_and_one_it_finds_loads
    out, status = bundle_exec
    assert_equal [EXPECTED, 0], [out, status.exitstatus], "the premise: the program runs under bundle exec"

    out, err, status = Open3.capture3({ "FLEDGE_RUNTIME_DIR" => @runtimes, "FLEDGE_RUNTIME_DIR_UNCHECKED" => "1" }, RbConfig.ruby, "-I", LIB, EXE,
      "build", "-o", @dir, FIXTURE)
    assert_predicate status, :success?, "#{out}#{err}"
    folder = Dir.glob(File.join(@dir, "*-#{@platform}")).find { |path| File.directory?(path) }.to_s
    config = File.join(folder, "fledge.cfg")
    original = File.read(config)
    assert_includes original.lines, "system_typelibs = GdkPixbuf-2.0\n"

    found = ENV.slice("GI_TYPELIB_PATH")
    assert_equal [EXPECTED, "", 0], run_app(folder, found), "where libgirepository finds the typelib (GI_TYPELIB_PATH: #{found})"

    File.write(config, original.lines.grep_v(/\Asystem_typelibs = /).join)
    out, err, status = run_app(folder, {})
    lacking "this computer has GdkPixbuf-2.0.typelib where libgirepository looks without GI_TYPELIB_PATH, so it cannot lack it" if status.zero?
    assert_equal ["", 1], [out, status], "without the check"
    assert_includes err, "Typelib file for namespace 'GdkPixbuf'"
    assert_includes err, "(GObjectIntrospection::RepositoryError::TypelibNotFound)"
    assert_includes err, "gdk_pixbuf2-4.4.0/lib/gdk_pixbuf2.rb"

    File.write(config, original)
    message = "Typelib Probe: this app needs GdkPixbuf-2.0.typelib, which this computer does not have (Typelib file for namespace " \
      "'GdkPixbuf', version '2.0' not found). Install it from your Linux distribution's packages, then run the app again\n"
    assert_equal ["", message, 72], run_app(folder, {})
  end

  # Skips for want of what +message+ names, or fails where
  # FLEDGE_REQUIRE_TYPELIBS says this computer was set up for the test,
  # as CI's Linux Test jobs are.
  private def lacking(message)
    ENV["FLEDGE_REQUIRE_TYPELIBS"] ? flunk(message) : skip(message)
  end

  # The fixture's program under bundle exec, with its gems installed
  # into this test's folder, in this test's environment but for the
  # Bundler settings of the Ruby that runs the tests.
  private def bundle_exec
    project = File.join(@dir, "typelib")
    FileUtils.cp_r(FIXTURE, project)
    env = { "BUNDLE_GEMFILE" => File.join(project, "Gemfile"), "BUNDLE_PATH" => File.join(@dir, "bundle"), "BUNDLE_FROZEN" => "true" }
    Bundler.with_unbundled_env do
      out, status = Open3.capture2e(env, RbConfig.ruby, "-S", "bundle", "install", chdir: project)
      return [out, status] unless status.success?

      Open3.capture2e(env, RbConfig.ruby, "-S", "bundle", "exec", "ruby", "main.rb", chdir: project)
    end
  end

  # The built app in +folder+, as a person runs it: with nothing in its
  # environment but PATH and +env+. The program is named as an array,
  # since Ruby splits a lone string at its space.
  private def run_app(folder, env)
    program = File.join(folder, "Typelib Probe")
    out, err, status = Open3.capture3({ "PATH" => "/usr/bin:/bin" }.merge(env), [program, program], unsetenv_others: true)
    [out, err, status.exitstatus]
  end
end
