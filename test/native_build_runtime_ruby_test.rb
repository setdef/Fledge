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
  def env(from, prefix: "/rubies/4.1.0")
    ruby = Fledge::NativeBuild::RuntimeRuby.new(platform: Fledge::Platform.find("x86_64-linux"), runtimes: Fledge::Runtimes.new(env: {}),
      work: "/work", log: StringIO.new, env: from, prefix:)
    ruby.env
  end

  # jdx/ruby's rbconfig.rb, mise's Ruby by default, puts its own
  # lib/pkgconfig first in PKG_CONFIG_PATH whenever it loads
  # (libexec/package.rb, rbconfig_portability_patch, at jdx/ruby
  # 09c4b6b), which it does in the process that runs fledge build; a
  # gem's pkg-config then found that Ruby's own static OpenSSL. What a
  # gem links must not depend on which Ruby ran the build.
  def test_the_folders_the_developers_ruby_adds_to_pkg_config_path_stay_out
    path = ["/opt/homebrew/lib/pkgconfig", "/usr/local/lib/pkgconfig"].join(File::PATH_SEPARATOR)
    under_jdx = env({ "PKG_CONFIG_PATH" => ["/rubies/4.1.0/lib/pkgconfig", path].join(File::PATH_SEPARATOR) })
    elsewhere = env({ "PKG_CONFIG_PATH" => path })

    assert_equal path, under_jdx.fetch("PKG_CONFIG_PATH")
    assert_equal elsewhere.fetch("PKG_CONFIG_PATH", path), under_jdx.fetch("PKG_CONFIG_PATH")
  end

  def test_a_pkg_config_path_of_only_the_developers_ruby_is_dropped
    found = env({ "PKG_CONFIG_PATH" => "/rubies/4.1.0/lib/pkgconfig" })

    assert_equal({ "PKG_CONFIG_PATH" => nil }, found.slice("PKG_CONFIG_PATH"))
  end

  # A folder whose name only begins with the prefix's is another one.
  def test_a_folder_beside_the_developers_ruby_stays
    path = "/rubies/4.1.0-other/lib/pkgconfig"

    assert_equal path, env({ "PKG_CONFIG_PATH" => path }).fetch("PKG_CONFIG_PATH", path)
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
