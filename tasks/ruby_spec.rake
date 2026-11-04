# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

desc "Run ruby/spec on stock Ruby and in a built app, and compare (tasks/ruby_spec.rb)"
task :ruby_spec do
  ruby "tasks/ruby_spec.rb"
end
