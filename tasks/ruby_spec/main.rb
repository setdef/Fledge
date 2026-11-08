# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# The program of the app the ruby/spec comparison builds
# (tasks/ruby_spec.rb), and of the project stock Ruby runs as ruby
# main.rb: it runs ruby/spec with MSpec in its own process, as mspec-run
# does. ARGV is mspec-run's: options, then spec files or folders
# relative to spec/, which ships beside this file with mspec/.
#
# MSpec's mspec front end exports the Ruby under test as RUBY_EXE and
# its flags as RUBY_FLAGS, which some fixtures read. Here the Ruby under
# test is this process's own, so they name RbConfig.ruby, as MSpec's
# ruby_exe helper does by default.
require "rbconfig"
ENV["RUBY_EXE"] ||= RbConfig.ruby
ENV["RUBY_FLAGS"] ||= ""
Dir.chdir(File.join(__dir__, "spec"))
$LOAD_PATH.unshift(File.join(__dir__, "mspec", "lib"))
require "mspec/commands/mspec-run"
MSpecRun.main
