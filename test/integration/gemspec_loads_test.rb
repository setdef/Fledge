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
# evaluating it in a Ruby of its own (Fledge::Bundle::GemspecLoads), the
# collaborator Fledge::Bundle has unless it is given another; the unit
# tests give it one that starts no Ruby.
class GemspecLoadsTest < Minitest::Test
  def setup
    @dir = Dir.mktmpdir
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
    gemspec = File.join(@dir, "broken.gemspec")
    File.write(gemspec, "require_relative \"lib/missing\"\nGem::Specification.new { |s| s.name = \"broken\" }\n")

    error = assert_raises(Fledge::Error) { Fledge::Bundle::GemspecLoads.new.call(gemspec) }

    assert_match(%r{\ARuby can't evaluate #{Regexp.escape(gemspec)}:\n.*lib/missing}m, error.message)
  end
end
