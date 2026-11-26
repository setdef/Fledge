# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "test_helper"
require_relative "support/gems"
require "tmpdir"

# The Gemfile and the gemspecs run in fledge build's own process, as they
# do in bundle install's, and what they print goes to standard error, so
# that standard output holds only the paths the command prints
# (Fledge::Evaluation).
class EvaluationTest < Minitest::Test
  def setup
    @dir = File.realpath(Dir.mktmpdir)
    FileUtils.mkdir_p(File.join(@dir, ".git"))
  end

  def teardown
    FileUtils.rm_rf(@dir)
  end

  # What the block writes to file descriptors 1 and 2, as a child
  # process or a C extension would write it: the descriptors themselves,
  # pointed at files for the block.
  def descriptors
    out = File.join(@dir, "stdout")
    err = File.join(@dir, "stderr")
    saved = [STDOUT.dup, STDERR.dup]
    STDOUT.reopen(out, "w")
    STDERR.reopen(err, "w")
    begin
      yield
    ensure
      STDOUT.flush
      STDERR.flush
      STDOUT.reopen(saved[0])
      STDERR.reopen(saved[1])
      saved.each(&:close)
    end
    [File.read(out), File.read(err)]
  end

  def test_what_the_block_prints_and_what_a_child_prints_go_to_standard_error
    out, err = descriptors do
      Fledge::Evaluation.to_stderr do
        puts "from ruby"
        system("echo from a child")
      end
      puts "after"
    end

    assert_equal "after\n", out
    assert_equal ["from a child", "from ruby"], err.lines.map(&:chomp).sort
  end

  def test_standard_output_is_restored_when_the_block_raises
    out, err = descriptors do
      assert_raises(RuntimeError) { Fledge::Evaluation.to_stderr { raise "no" } }
      puts "after"
    end

    assert_equal "after\n", out
    assert_empty err
  end

  def test_the_value_of_the_block_is_returned
    assert_equal 3, Fledge::Evaluation.to_stderr { 3 }
  end

  # Each place fledge build evaluates what the developer wrote: the
  # project's gemspec, by Fledge::App.at; the Gemfile, the path gems'
  # gemspecs, and the project's own, by Fledge::Bundle.
  def test_a_projects_gemfile_and_gemspecs_print_to_standard_error
    root = FakeProject.write(@dir, gemfile: "puts \"gemfile says hi\"\nsystem(\"echo gemfile child\")\n")
    gemspec = File.join(root, "my_app.gemspec")
    File.write(gemspec, "puts \"gemspec says hi\"\n#{File.read(gemspec)}")
    out, err = descriptors do
      Fledge::Bundle.new(Fledge::App.at(root), gemspec_loads: NO_GEMSPEC_LOADS).app_files
    end

    assert_empty out
    ["gemfile says hi", "gemfile child", "gemspec says hi"].each { |line| assert_includes err.lines.map(&:chomp), line }
  end

  # A path gem's gemspec, which Bundler evaluates when it reads the path
  # source's specifications, and Fledge when it finds the gem's folder.
  def test_a_path_gems_gemspec_prints_to_standard_error
    FileUtils.mkdir_p(File.join(@dir, "elsewhere"))
    File.write(File.join(@dir, "elsewhere", "elsewhere.gemspec"),
      "puts \"path gemspec says hi\"\n" \
        "Gem::Specification.new { |s| s.name = 'elsewhere'; s.version = '1.0'; s.summary = 'x'; s.authors = ['x']; s.files = [] }\n")
    root = FakeProject.write(@dir, gemfile: "gem \"elsewhere\", path: \"../elsewhere\"\n", lock_dependencies: ["elsewhere!"])
    lock = File.join(root, "Gemfile.lock")
    File.write(lock, "PATH\n  remote: ../elsewhere\n  specs:\n    elsewhere (1.0)\n\n" \
      "#{File.read(lock).sub("CHECKSUMS\n", "CHECKSUMS\n  elsewhere (1.0)\n")}")
    out, err = descriptors do
      bundle = Fledge::Bundle.new(Fledge::App.at(root), gemspec_loads: NO_GEMSPEC_LOADS)
      bundle.gems_for(Fledge::Platform.find("x86_64-linux"), ruby_version: "4.0.9", patchlevel: "9", bundler: "4.0.20", arch: "x86_64-linux")
    end

    assert_empty out
    assert_includes err.lines.map(&:chomp), "path gemspec says hi"
  end
end
