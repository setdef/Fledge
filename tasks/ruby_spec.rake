# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

desc "Run ruby/spec on stock Ruby and in a built app, and compare (tasks/ruby_spec.rb)"
task :ruby_spec do
  ruby "tasks/ruby_spec.rb"
end
