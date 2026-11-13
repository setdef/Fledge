# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

namespace :adr do
  desc "Print each ADR's title, problem, decision drivers, and chosen option"
  task :digest do
    ruby "tasks/adr_digest.rb", *Dir["doc/contributors/adr/[0-9]*.md"], verbose: false
  end
end
