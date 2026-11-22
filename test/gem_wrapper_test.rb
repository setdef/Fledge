# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "test_helper"
require "rubygems/installer"

# Fledge::GemWrapper writes RubyGems' wrapper for a gem's command without
# running a Ruby. Each test holds it to the text the RubyGems of the Ruby
# running the tests writes, which mise.toml pins to the Ruby the
# runtimes carry, for a wrapper as Fledge's runtimes have it written
# (Fledge::NativeBuild::STUBS): Gem.ruby is /usr/bin/env ruby, no
# custom_shebang, and a Ruby built with --enable-load-relative.
class GemWrapperTest < Minitest::Test
  def setup
    @dir = Dir.mktmpdir
  end

  def teardown
    FileUtils.rm_rf(@dir)
  end

  # The text RubyGems' own Gem::Installer writes for +program+ of the gem
  # +gem+ whose script holds +script+.
  def rubygems(gem, program, script)
    spec = Gem::Specification.new do |s|
      s.name = gem
      s.version = "1.0.0"
      s.bindir = "exe"
      s.executables = [program]
    end
    installer = LoadRelative.for_spec(spec, install_dir: @dir, env_shebang: false, wrappers: true)
    path = File.join(installer.gem_dir, "exe", program)
    FileUtils.mkdir_p(File.dirname(path))
    File.binwrite(path, script)
    as_runtimes_write { installer.app_script_text(program) }
  end

  # RubyGems' installer for a Ruby built with --enable-load-relative,
  # which the Ruby running the tests need not be.
  class LoadRelative < Gem::Installer
    def rb_config = RbConfig::CONFIG.merge("LIBRUBY_RELATIVE" => "yes")
  end

  # Runs the block with Gem.ruby as Fledge::NativeBuild::STUBS sets it,
  # and no custom_shebang from a .gemrc of this computer's.
  def as_runtimes_write
    ruby = Gem.instance_variable_get(:@ruby)
    configuration = Gem.configuration
    shebang = configuration[:custom_shebang]
    Gem.instance_variable_set(:@ruby, Fledge::GemWrapper::RUBY)
    configuration[:custom_shebang] = nil
    yield
  ensure
    Gem.instance_variable_set(:@ruby, ruby)
    configuration[:custom_shebang] = shebang if configuration
  end

  def assert_written_as_rubygems_writes(gem, program, script)
    expected = rubygems(gem, program, script)

    assert_equal expected, Fledge::GemWrapper.new(gem:, program:, script:).text
  end

  def test_a_command_whose_script_runs_ruby_plainly
    assert_written_as_rubygems_writes("rake", "rake", "#!/usr/bin/env ruby\nrequire 'rake'\n")
  end

  def test_the_options_on_the_scripts_line_are_kept
    assert_written_as_rubygems_writes("tool", "tool", "#!/usr/local/bin/ruby3.4 -w --disable-did_you_mean\r\nputs 1\n")
  end

  def test_a_script_without_a_shebang_line
    assert_written_as_rubygems_writes("tool", "tool-cli", "puts 'no line for the kernel'\n")
  end

  def test_an_empty_script
    assert_written_as_rubygems_writes("tool", "tool", "")
  end

  def test_a_name_with_a_quote_or_a_backslash_is_escaped
    assert_written_as_rubygems_writes("o'neil", "it's\\here", "#!/usr/bin/env ruby\n")
  end

  # Bundler's own wrapper loads no gemdeps, and passes a version given
  # as _VERSION_ on to Bundler.
  def test_bundlers_wrapper_is_bundlers
    assert_written_as_rubygems_writes("bundler", "bundle", "#!/usr/bin/env ruby\n")
  end
end
