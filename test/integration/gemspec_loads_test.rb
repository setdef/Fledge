# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "../test_helper"
require_relative "../support/gems"
require "open3"
require "rbconfig"

# The files a gemspec's evaluation loads, which Fledge learns by
# evaluating it in a Ruby of its own after the Gemfile, as Bundler does
# (Fledge::Bundle::GemspecLoads), the collaborator Fledge::Bundle has
# unless it is given another; the unit tests give it one that starts no
# Ruby.
class GemspecLoadsTest < Minitest::Test
  # What a program sees under bundle exec of a project, once Bundler has
  # evaluated its Gemfile and gemspec: whether Greeter::VERSION is
  # defined, and the project's files in $LOADED_FEATURES.
  PROBE = <<~'RUBY'
    root = "#{Dir.pwd}/"
    p [defined?(Greeter::VERSION), $LOADED_FEATURES.select { |f| f.start_with?(root) }.map { |f| f.delete_prefix(root) }]
  RUBY

  def setup
    @dir = File.realpath(Dir.mktmpdir)
    FileUtils.mkdir_p(File.join(@dir, ".git"))
  end

  def teardown
    FileUtils.rm_rf(@dir)
  end

  # Under bundle exec, Bundler evaluates the project's gemspec at every
  # start, so the files it requires load before the program's first
  # line, in the order they finish loading; the shipped gemspec requires
  # the same files, and nothing from outside the project, and loading it
  # defines what the program reads.
  def test_the_evaluated_gemspec_requires_the_projects_files_its_evaluation_loaded
    root = FakeProject.write(@dir, name: "versioned_app")
    FileUtils.mkdir_p(File.join(root, "lib", "versioned_app"))
    File.write(File.join(root, "lib", "versioned_app", "edition.rb"), "module VersionedApp\n  EDITION = \"first\"\nend\n")
    File.write(File.join(root, "lib", "versioned_app", "version.rb"),
      "require_relative \"edition\"\nmodule VersionedApp\n  VERSION = \"0.1.0\"\nend\n")
    gemspec = File.join(root, "versioned_app.gemspec")
    File.write(gemspec, "require \"English\"\nrequire_relative \"lib/versioned_app/version\"\n#{File.read(gemspec)}")

    evaluated = Fledge::Bundle.new(Fledge::App.at(root)).app_files.fetch("versioned_app.gemspec")

    assert_includes evaluated, "\nrequire_relative \"lib/versioned_app/edition\"\nrequire_relative \"lib/versioned_app/version\"\n\n" \
      "Gem::Specification.new do |s|\n"
    refute_includes evaluated, "English"
    File.write(gemspec, evaluated)
    out, err, status = Open3.capture3(RbConfig.ruby, "-e", "load ARGV[0]; print VersionedApp::VERSION, VersionedApp::EDITION", gemspec)
    assert status.success?, err
    assert_equal "0.1.0first", out
  end

  # A gemspec a Ruby of its own cannot evaluate is refused with what that
  # Ruby said.
  def test_a_gemspec_a_ruby_of_its_own_cannot_evaluate_is_refused
    root = FakeProject.write(@dir, name: "broken")
    gemspec = File.join(root, "broken.gemspec")
    File.write(gemspec, "require_relative \"lib/missing\"\nGem::Specification.new { |s| s.name = \"broken\" }\n")

    error = assert_raises(Fledge::Error) { Fledge::Bundle::GemspecLoads.new.call(gemspec, gemfile: File.join(root, "Gemfile")) }

    assert_match(%r{\ARuby can't evaluate #{Regexp.escape(gemspec)}:\n.*lib/missing}m, error.message)
  end

  # What the Gemfile or the gemspec prints is not among the files the Ruby
  # of its own answers with.
  def test_what_the_gemfile_and_the_gemspec_print_does_not_reach_the_answer
    root = FakeProject.write(@dir, name: "chatty", gemfile: "puts \"gemfile\"\nsystem(\"echo child\")\n")
    gemspec = File.join(root, "chatty.gemspec")
    File.write(gemspec, "puts \"gemspec\"\n#{File.read(gemspec)}")

    assert_equal [], Fledge::Bundle::GemspecLoads.new.call(gemspec, gemfile: File.join(root, "Gemfile"))
  end

  # A gemspec that needs what the Gemfile defined before its gemspec line:
  # Bundler evaluates the Gemfile first, so bundle exec works.
  def test_a_gemspec_that_needs_what_the_gemfile_loaded_ships
    root = greeter("")
    File.write(File.join(root, "Gemfile"), "source \"https://rubygems.org/\"\n\nrequire_relative \"lib/greeter/version\"\ngemspec\n")

    assert_same_as_bundle_exec(root)
  end

  # Every way a gemspec loads a project file, as a program under bundle
  # exec then finds it loaded: Kernel#load, which leaves nothing in
  # $LOADED_FEATURES, and the ways around a list of method names an
  # earlier guard was found to miss.
  {
    "require_relative" => "require_relative \"lib/greeter/version\"\n",
    "load" => "load File.expand_path(\"lib/greeter/version.rb\", __dir__)\n",
    "load by send, from the gemspec's folder" => "Kernel.send(:load, \"lib/greeter/version.rb\")\n",
    "gem_original_require" => "gem_original_require File.expand_path(\"lib/greeter/version\", __dir__)\n",
    "an alias of require_relative" => "module Kernel\n  alias_method :fetch_file, :require_relative\nend\nfetch_file \"lib/greeter/version\"\n",
    "RubyGems' plugin loader" => "Gem.load_plugin_files([File.expand_path(\"lib/greeter/version.rb\", __dir__)])\n",
    "another gemspec Bundler evaluates" => "Bundler.load_gemspec_uncached(File.expand_path(\"support/other.spec\", __dir__))\n",
    "a load inside a required file" => "require_relative \"lib/greeter/loader\"\n",
  }.each do |way, head|
    define_method(:"test_a_gemspec_that_loads_by_#{way.tr(" ,'", '___')}_ships_what_bundle_exec_loads") do
      assert_same_as_bundle_exec(greeter(head))
    end
  end

  # A project whose gemspec begins with +head+ and names Greeter::VERSION,
  # which lib/greeter/version.rb defines.
  private def greeter(head)
    root = FakeProject.write(@dir, name: "greeter")
    FileUtils.mkdir_p([File.join(root, "lib", "greeter"), File.join(root, "support")])
    File.write(File.join(root, "lib", "greeter", "version.rb"), "module Greeter\n  VERSION = \"0.1.0\"\nend\n")
    File.write(File.join(root, "lib", "greeter", "loader.rb"), "load File.expand_path(\"version.rb\", __dir__)\n")
    File.write(File.join(root, "support", "other.spec"),
      "require_relative \"../lib/greeter/version\"\nGem::Specification.new { |s| s.name = \"other\"; s.version = \"1\" }\n")
    gemspec = File.join(root, "greeter.gemspec")
    File.write(gemspec, head + File.read(gemspec).sub('spec.version = "0.1.0"', "spec.version = Greeter::VERSION"))
    root
  end

  # What the program sees under bundle exec of the project at +root+ is
  # what it sees with the gemspec the app ships in place of the
  # developer's, as the app's own Bundler evaluates it, and neither
  # writes to standard error.
  private def assert_same_as_bundle_exec(root)
    developers = bundle_exec(root)
    assert_match(/\A\["constant", /, developers, "the premise: under bundle exec the program finds Greeter::VERSION")
    shipped = Fledge::Bundle.new(Fledge::App.at(File.join(root, "exe", "greeter"))).app_files.fetch("greeter.gemspec")
    File.write(File.join(root, "greeter.gemspec"), shipped)

    assert_equal developers, bundle_exec(root), shipped
  end

  private def bundle_exec(root)
    out, err, status = Bundler.with_unbundled_env do
      Open3.capture3({ "BUNDLE_GEMFILE" => File.join(root, "Gemfile") }, RbConfig.ruby, "-S", "bundle", "exec", "ruby", "-e", PROBE, chdir: root)
    end
    assert status.success?, err
    assert_empty err
    out
  end
end
