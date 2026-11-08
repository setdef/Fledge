# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

desc "Compare a built app's Ruby with ruby main.rb on the runtime's own Ruby (ADR 003)"
task :parity do
  ruby "tasks/parity.rb"
end
