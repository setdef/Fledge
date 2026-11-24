# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "test_helper"

# Fledge::Bundle::GemfileData describes an evaluated Gemfile as data and
# makes a Bundler::Dsl from it again, with every option Bundler gave each
# dependency and source, so that Fledge::Bundle reads what the Gemfile
# built without running its code.
class BundleGemfileDataTest < Minitest::Test
  GEMFILE = <<~'RUBY'
    source "https://rubygems.org"
    git_source(:acme) { |repo| "https://git.example.com/#{repo}.git" }
    ruby ">= 3.1", "< 5"

    gem "rake", "~> 13.0", require: false
    gem "minitest", ">= 5", "< 7", group: :test
    gem "plain"
    gem "winonly", platforms: %i[windows jruby]
    gem "forced", force_ruby_platform: true
    gem "branching", git: "https://example.com/branching.git", branch: "main", glob: "gems/*.gemspec"
    gem "hub", github: "someone/hub", tag: "v1.2"
    gem "acme_gem", acme: "team/acme_gem"
    gem "local", path: "vendor/local"
    gem "other", source: "https://other.example.com"
    group :development, :test do
      gem "pry"
    end
    group :docs, optional: true do
      gem "yard"
    end
    platforms :ruby do
      gem "extension"
    end
    install_if -> { RUBY_ENGINE == "ruby" } do
      gem "installed"
    end
    install_if -> { false } do
      gem "not_installed"
    end
    source "https://third.example.com" do
      gem "third", "1.0"
    end
    git "https://example.com/many.git", branch: "dev" do
      gem "many_a"
      gem "many_b"
    end
    env "FLEDGE_GEMFILE_DATA_TEST" => /\Ayes/ do
      gem "envgem"
    end
  RUBY

  def setup
    @dir = File.realpath(Dir.mktmpdir)
    @gemfile = File.join(@dir, "Gemfile")
    File.write(@gemfile, GEMFILE)
    require "bundler"
  end

  def teardown
    FileUtils.rm_rf(@dir)
  end

  # What Bundler reads of a Dsl to choose gems: each dependency with its
  # groups, platforms, answers, and every option but its source, which is
  # compared as the source's own words, each source's options, the
  # global remotes, and the Gemfile's ruby and optional groups.
  def summary(dsl)
    sources = dsl.instance_variable_get(:@sources)
    ruby = dsl.to_definition(Pathname.new(File.join(@dir, "none.lock")), {}).ruby_version
    options = -> (dependency) { dependency.instance_variable_get(:@options).except("source").map { |key, value| [key, value.to_s] }.sort }
    dependencies = dsl.dependencies.map do |dependency|
      [
        dependency.to_lock,
        dependency.groups,
        dependency.platforms,
        dependency.should_include,
        dependency.env.to_s,
        dependency.source&.to_s,
        options.call(dependency),
]
    end
    {
dependencies:,
ruby: ruby&.to_s,
optional: dsl.instance_variable_get(:@optional_groups),
sources: sources.lock_sources.map { |source| [source.to_s, source.options.map { |key, value| [key, value.to_s] }.sort] },
global: sources.global_rubygems_source.remotes.map(&:to_s),
gemfiles: dsl.instance_variable_get(:@gemfiles),
}
  end

  def test_the_dsl_made_from_the_data_holds_what_the_gemfile_built
    built = Bundler::Dsl.new
    built.eval_gemfile(@gemfile)

    data = JSON.parse(JSON.generate(Fledge::Bundle::GemfileData.definition(@gemfile)))
    made = Fledge::Bundle::GemfileData.dsl(data)

    refute_empty built.dependencies
    assert_equal summary(built), summary(made)
  end

  def test_an_install_if_is_answered_where_the_gemfile_ran_and_its_gem_kept_or_left_out
    data = Fledge::Bundle::GemfileData.definition(@gemfile)
    made = Fledge::Bundle::GemfileData.dsl(JSON.parse(JSON.generate(data)))

    included = made.dependencies.to_h { |dependency| [dependency.name, dependency.should_include] }
    assert included.fetch("installed")
    refute included.fetch("not_installed")
  end

  def test_a_source_only_a_bundler_plugin_provides_is_refused
    sources = Bundler::SourceList.new
    sources.plugin_sources << Object.new
    dsl = Bundler::Dsl.new
    dsl.instance_variable_set(:@sources, sources)

    error = assert_raises(Fledge::Error) { Fledge::Bundle::GemfileData.__send__(:describe, dsl) }

    assert_equal "Fledge can't read a Gemfile source that a Bundler plugin provides.", error.message
  end

  def test_a_gemspec_is_evaluated_after_the_gemfile_and_carried_as_yaml
    File.write(File.join(@dir, "name.rb"), "GEMFILE_DATA_TEST_NAME = \"from_gemfile\"\n")
    File.write(@gemfile, "source \"https://rubygems.org\"\nrequire_relative \"name\"\n")
    path = File.join(@dir, "named.gemspec")
    File.write(path, "Gem::Specification.new { |s| s.name = GEMFILE_DATA_TEST_NAME; s.version = \"1.2.3\"; s.summary = \"s\"; s.authors = [\"a\"] }\n")

    yaml = Fledge::Bundle::GemfileData.gemspec(@gemfile, path)
    spec = Fledge::Bundle::GemfileData.specification(yaml, path)

    assert_equal ["from_gemfile", "1.2.3", path], [spec.name, spec.version.to_s, spec.loaded_from]
  ensure
    Object.__send__(:remove_const, :GEMFILE_DATA_TEST_NAME) if Object.const_defined?(:GEMFILE_DATA_TEST_NAME)
  end
end
