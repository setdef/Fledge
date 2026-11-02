# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: MIT-0
#++

# A gem the app takes from a folder outside its project, as a company's
# private gems often are, which fledge build copies where Bundler looks
# for a copy of a path gem (vendor/cache/NAME).
module Shared
  def self.greeting
    "shared from outside the project"
  end
end
