# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

desc "Compare a built app's Ruby with ruby main.rb on the runtime's own Ruby (ADR 003)"
task :parity do
  ruby "tasks/parity.rb"
end
