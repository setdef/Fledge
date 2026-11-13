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

  # A stand-in for RubyInstaller's library in site_ruby, shaped as
  # ruby_installer/runtime.rb and its autoloads are at RubyInstaller
  # 92a692c, whose methods raise when called, as nothing of Fledge's may
  # call them at boot. Ridk is an autoload RubyInstaller's start-up never
  # loads, so it must stay unloaded.
  FAKE_RUBY_INSTALLER = {
    "ruby_installer/runtime.rb" => <<~RUBY,
      module RubyInstaller
        module Runtime
          autoload :Colors, "ruby_installer/runtime/colors"
          autoload :DllDirectory, "ruby_installer/runtime/dll_directory"
          autoload :Msys2Installation, "ruby_installer/runtime/msys2_installation"
          autoload :Ridk, "ruby_installer/runtime/ridk"
          def self.method_missing(name, *) = raise("RubyInstaller::Runtime.\#{name} was called")
          def self.respond_to_missing?(*) = true
        end
      end
    RUBY
    "ruby_installer/runtime/colors.rb" => "module RubyInstaller::Runtime::Colors; end\n",
    "ruby_installer/runtime/dll_directory.rb" => <<~RUBY,
      require "win32/dll_directory"
      class RubyInstaller::Runtime::DllDirectory
        def self.method_missing(name, *) = raise("DllDirectory.\#{name} was called")
        def self.respond_to_missing?(*) = true
      end
    RUBY
    "ruby_installer/runtime/msys2_installation.rb" => <<~RUBY,
      class RubyInstaller::Runtime::Msys2Installation
        include RubyInstaller::Runtime::Colors
        def self.method_missing(name, *) = raise("Msys2Installation.\#{name} was called")
        def self.respond_to_missing?(*) = true
      end
    RUBY
    "ruby_installer/runtime/ridk.rb" => "raise 'ridk was loaded'\n",
    "win32/dll_directory.rb" => <<~RUBY,
      module Win32
        module DllDirectory
          def self.method_missing(name, *) = raise("Win32::DllDirectory.\#{name} was called")
          def self.respond_to_missing?(*) = true
        end
      end
    RUBY
  }.freeze

  # What a Ruby has loaded of the stand-in once it has loaded the
  # defaults, as Windows (+windows+ true) or another system: the files,
  # relative to site_ruby, then defined?(RubyInstaller),
  # defined?(Win32), and how many of Ruby's UTF-16LE encoding files it
  # has loaded, each on a line. That Ruby starts without
  # RubyGems and without the RUBYOPT bundle exec sets, so that a Ruby
  # from RubyInstaller, which loads RubyInstaller's own
  # operating_system.rb with RubyGems, defines nothing before the
  # defaults do; Gem is a stand-in that answers win_platform? as
  # +windows+ says.
  private def ruby_installer_after_boot(windows:)
    Dir.mktmpdir do |dir|
      site_ruby = File.realpath(dir)
      FAKE_RUBY_INSTALLER.each do |path, source|
        FileUtils.mkdir_p(File.dirname(File.join(site_ruby, path)))
        File.write(File.join(site_ruby, path), source)
      end
      code = "module Gem; def self.win_platform? = #{windows}; end; $LOAD_PATH.unshift(ARGV[0]); load ARGV[1]; " \
        "p $LOADED_FEATURES.filter_map { _1.dup.delete_prefix!(ARGV[0] + '/') }.sort, " \
        "defined?(RubyInstaller), defined?(Win32), $LOADED_FEATURES.grep(%r{/enc/utf_16le\\.[^/]+\\z}).size"
      out, err, status = Open3.capture3({ "RUBYOPT" => nil, "RUBYLIB" => nil }, RbConfig.ruby, "--disable-gems", "-e", code,
        site_ruby, DEFAULTS)
      assert status.success?, err

      out.lines(chomp: true)
    end
  end

  # RubyInstaller's own operating_system.rb calls
  # RubyInstaller::Runtime.enable_dll_search_paths, which loads these
  # files on its way to looking for MSYS2, and converts Ruby's archdir to
  # UTF-16LE for Windows; the defaults load the same files and the same
  # encoding, and call nothing.
  def test_on_windows_rubyinstallers_start_up_files_are_loaded_and_nothing_of_them_runs
    files, ruby_installer, win32, utf16le = ruby_installer_after_boot(windows: true)

    assert_equal %w[
      ruby_installer/runtime.rb
      ruby_installer/runtime/colors.rb
      ruby_installer/runtime/dll_directory.rb
      ruby_installer/runtime/msys2_installation.rb
      win32/dll_directory.rb
].inspect, files
    assert_equal '"constant"', ruby_installer
    assert_equal '"constant"', win32
    assert_equal "1", utf16le
  end

  def test_elsewhere_rubyinstallers_library_is_not_looked_for
    assert_equal ["[]", "nil", "nil", "0"], ruby_installer_after_boot(windows: false)
  end
end
