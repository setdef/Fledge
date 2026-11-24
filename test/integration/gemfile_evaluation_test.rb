# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "../test_helper"
require_relative "../support/gem_app_build"

# A Gemfile is Ruby. fledge build has a Ruby of its own evaluate it, as
# the app's own process does under bundle exec, and reads what it says as
# data (Fledge::Bundle::Evaluation), so that what the Gemfile does stays
# out of the build's process. The unit tests give Fledge::Bundle and
# Fledge::App an evaluation that starts no Ruby.
class GemfileEvaluationTest < Minitest::Test
  include GemAppBuild

  EFFECTS = <<~RUBY

    ENV["FLEDGE_GEMFILE_EFFECT"] = "set by the Gemfile"
    $stdout.puts "printed by the Gemfile"
    File.write(ENV.fetch("FLEDGE_GEMFILE_MARKER"), JSON.generate([Process.pid, RUBY_VERSION, defined?(Fledge::CLI)]))
  RUBY

  def with_marker
    marker = File.join(@dir, "marker.txt")
    ENV["FLEDGE_GEMFILE_MARKER"] = marker
    yield marker
  ensure
    ENV.delete("FLEDGE_GEMFILE_MARKER")
    ENV.delete("FLEDGE_GEMFILE_EFFECT")
  end

  # What the Gemfile does (sets ENV, prints, and writes a file that says
  # which process ran it, and whether Fledge's CLI was loaded there) happens in
  # a Ruby of its own: the process of fledge build keeps its ENV, its
  # output is the archive's name alone, and the build succeeds.
  def test_what_a_gemfile_does_stays_out_of_the_process_that_builds
    root = project(dependencies: {}, locked: [], gemfile: EFFECTS)

    with_marker do |marker|
      out, err, status = build(File.join(root, "exe/my_app"), evaluation: Fledge::Bundle::Evaluation.new)

      assert_equal [0, "dist/MyApp-x86_64-linux.tar.gz\n"], [status, out], err
      assert_nil ENV.fetch("FLEDGE_GEMFILE_EFFECT", nil)
      refute_includes err, "printed by the Gemfile"
      pid, version, cli = JSON.parse(File.read(marker))
      refute_equal Process.pid, pid
      assert_equal [RUBY_VERSION, nil], [version, cli]
    end
  end

  # The Ruby of its own is given none of the developer's Ruby settings,
  # as GemspecLoads' is not.
  def test_the_ruby_of_its_own_has_none_of_the_developers_ruby_settings
    root = project(dependencies: {}, locked: [], gemfile: "\nFile.write(ENV.fetch(\"FLEDGE_GEMFILE_MARKER\"), ENV.fetch(\"RUBYOPT\", \"none\"))\n")

    with_marker do |marker|
      ENV["RUBYOPT"] = "-W0"
      begin
        _, err, status = build(File.join(root, "exe/my_app"), evaluation: Fledge::Bundle::Evaluation.new)
      ensure
        ENV.delete("RUBYOPT")
      end

      assert_equal 0, status, err
      assert_equal "none", File.read(marker)
    end
  end

  # A Gemfile Bundler does not accept is refused with Bundler's own
  # words, as it is under bundle exec.
  def test_a_gemfile_bundler_does_not_accept_is_refused_with_bundlers_words
    root = project(dependencies: {}, locked: [], gemfile: "\ngem \"zzz\", unknown_option: 1\n")

    _, err, status = build(File.join(root, "exe/my_app"), evaluation: Fledge::Bundle::Evaluation.new)

    assert_equal 1, status
    assert_match(/Bundler can't evaluate .*Gemfile and .*my_app\.gemspec:.*unknown_option/m, err)
  end

  # A Gemfile that raises something Bundler does not know is refused, with
  # what it said and where.
  def test_a_gemfile_that_raises_is_refused_with_what_the_ruby_said
    root = project(dependencies: {}, locked: [], gemfile: "\nraise \"the Gemfile gave up\"\n")

    _, err, status = build(File.join(root, "exe/my_app"), evaluation: Fledge::Bundle::Evaluation.new)

    assert_equal 1, status
    assert_includes err, "the Gemfile gave up"
  end

  # What the Ruby of its own answers is what this process would have
  # made of the Gemfile itself.
  def test_the_answer_of_the_ruby_of_its_own_is_the_answer_of_this_one
    root = project(dependencies: {}, locked: [], gemfile: "\ngem \"extra\", group: :test, platforms: :ruby\nruby \">= 3.1\"\n")
    gemfile = File.join(root, "Gemfile")

    answered = Fledge::Bundle::Evaluation.new.definition(gemfile)

    assert_equal JSON.parse(JSON.generate(Fledge::Bundle::GemfileData.definition(gemfile))), answered
  end
end
