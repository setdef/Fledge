# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# Experiment only (experiment/ruby-spec): the program of an app that runs
# ruby/spec with MSpec in its own process, as mspec-run does. ARGV is
# mspec-run's: options, then spec files or folders relative to spec/,
# which ships beside this file with mspec/.
#
# The mspec front end exports the Ruby under test as RUBY_EXE (its -t,
# "ruby" on PATH by default) and its -T flags as RUBY_FLAGS, which some
# fixtures read; here the Ruby under test is this process's own, so they
# name RbConfig.ruby, as MSpec's ruby_exe helper does by default.
require "rbconfig"
ENV["RUBY_EXE"] ||= RbConfig.ruby
ENV["RUBY_FLAGS"] ||= ""
here = __dir__
Dir.chdir(File.join(here, "spec"))
$LOAD_PATH.unshift(File.join(here, "mspec", "lib"))
require "mspec/commands/mspec-run"
MSpecRun.main
