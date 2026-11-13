# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require "open3"
require "rbconfig"
require_relative "test_helper"

# Fledge's RubyGems defaults (runtime/rubygems/operating_system.rb), as
# a Ruby loads them when RubyGems starts, in a Ruby of their own.
class RubygemsDefaultsTest < Minitest::Test
  DEFAULTS = File.expand_path("../runtime/rubygems/operating_system.rb", __dir__)

  # A stand-in for RubyInstaller's library in site_ruby, whose methods
  # raise when called, as nothing of Fledge's may call them at boot.
  FAKE_RUBY_INSTALLER = <<~RUBY
    module RubyInstaller
      module Runtime
        def self.method_missing(name, *) = raise("RubyInstaller::Runtime.\#{name} was called")
        def self.respond_to_missing?(*) = true
      end
    end
  RUBY

  # What a Ruby prints for defined?(RubyInstaller) once it has loaded
  # the defaults, as Windows (+windows+ true) or another system.
  private def ruby_installer_after_boot(windows:)
    Dir.mktmpdir do |site_ruby|
      FileUtils.mkdir_p(File.join(site_ruby, "ruby_installer"))
      File.write(File.join(site_ruby, "ruby_installer", "runtime.rb"), FAKE_RUBY_INSTALLER)
      code = "def Gem.win_platform? = #{windows}; $LOAD_PATH.unshift(ARGV[0]); load ARGV[1]; print defined?(RubyInstaller).inspect"
      out, err, status = Open3.capture3(RbConfig.ruby, "-e", code, site_ruby, DEFAULTS)
      assert status.success?, err

      out
    end
  end

  def test_on_windows_rubyinstallers_library_is_loaded_and_nothing_of_it_runs
    assert_equal '"constant"', ruby_installer_after_boot(windows: true)
  end

  def test_elsewhere_rubyinstallers_library_is_not_looked_for
    assert_equal "nil", ruby_installer_after_boot(windows: false)
  end
end
