# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "test_helper"
require "stringio"

# The environment Fledge::NativeBuild runs the runtime's Ruby in, read
# by RubyGems' own path rules; no Ruby is started.
class NativeBuildRuntimeRubyTest < Minitest::Test
  def env(from)
    ruby = Fledge::NativeBuild::RuntimeRuby.new(platform: Fledge::Platform.find("x86_64-linux"), runtimes: Fledge::Runtimes.new(env: {}),
      work: "/work", log: StringIO.new, env: from)
    ruby.env
  end

  def test_the_developers_ruby_settings_stay_out
    found = env({ "RUBYOPT" => "-rbundler/setup", "GEM_PATH" => "/mine", "BUNDLE_GEMFILE" => "/Gemfile", "PATH" => "/bin" })

    assert_equal({ "RUBYOPT" => nil, "GEM_HOME" => "/work/gems", "BUNDLE_GEMFILE" => nil }, found.slice("RUBYOPT", "GEM_HOME", "BUNDLE_GEMFILE"))
    refute_includes found.values, "/mine"
  end

  # Gem::Ext::RakeBuilder runs the rake that Gem.bin_path finds, which a
  # Rakefile's gem need not lock (rake_builder.rb, lines 22 to 31, at
  # RubyGems 4.1.0.beta2); the runtime bundles one, as gem install on
  # the runtime's Ruby finds it.
  def test_rubygems_finds_the_builds_gems_first_and_then_the_runtimes_own
    found = env({})

    path = Gem::PathSupport.new(found.slice("GEM_HOME", "GEM_PATH")).path

    assert_equal "/work/gems", path.first
    assert_includes path, Gem.default_dir
  end

  # RubyGems 4.1 (4.1.0.beta2 and beta3) reads a packed gem's metadata
  # with its own YAML parser, which gives its names as BINARY strings;
  # Psych, which RUBYGEMS_USE_PSYCH chooses, gives them as UTF-8, as
  # RubyGems 4.0 did (gems.md, "Compiling native gems").
  def test_rubygems_reads_a_gems_metadata_with_psych_whatever_the_developer_set
    assert_equal "true", env({ "RUBYGEMS_USE_PSYCH" => "false" }).fetch("RUBYGEMS_USE_PSYCH")
  end
end
