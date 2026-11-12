# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
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
#
# A phone app takes no arguments. When there are none, and
# arguments.txt is beside this file, as the phones' comparison writes it
# (tasks/ruby_spec/phone.rb), its lines are the arguments, and MSpec's
# temporary files go to a short folder of /tmp where the app may write
# there, as in the iOS Simulator, or else under Dir.tmpdir, unless
# SPEC_TEMP_DIR says where: by default MSpec writes them under the
# working folder, which is in the app's bundle, read-only on a device,
# and a UNIX socket's path, which MSpec makes there, holds at most 104
# bytes on Apple's systems, fewer than an app container's tmp folder
# leaves, as the desktop's comparison keeps them short too.
require "rbconfig"
arguments = File.join(__dir__, "arguments.txt")
if ARGV.empty? && File.file?(arguments)
  require "tmpdir"
  ARGV.replace(File.readlines(arguments, chomp: true))
  ENV["SPEC_TEMP_DIR"] ||= File.writable?("/tmp") ? "/tmp/fledge-rs-#{Process.pid}" : File.join(Dir.tmpdir, "rs-#{Process.pid}")
  # MSpec's ruby_exe helper refuses to load unless the Ruby it would
  # start exists, as on a phone it does not (RbConfig.ruby names where
  # bin/ruby would be). RUBY_EXE, when defined, is the one it takes,
  # and RbConfig.ruby is what it finds where it exists, so stock Ruby
  # runs the same; on a phone, phone_config.rb skips what would start it.
  RUBY_EXE = RbConfig.ruby
end
ENV["RUBY_EXE"] ||= RbConfig.ruby
ENV["RUBY_FLAGS"] ||= ""
Dir.chdir(File.join(__dir__, "spec"))
$LOAD_PATH.unshift(File.join(__dir__, "mspec", "lib"))
require "mspec/commands/mspec-run"
MSpecRun.main
