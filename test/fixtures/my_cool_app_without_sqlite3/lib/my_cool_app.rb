# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT-0
#++

require "i18n"
require_relative "my_cool_app/version"

# examples/my_cool_app without sqlite3: its greeting goes through i18n
# alone.
module MyCoolApp
  # The line the app prints, naming the gem it went through.
  def self.greeting
    I18n.backend.store_translations(:en, greeting: "%{app} says hello through %{i18n}")
    I18n.t(:greeting, locale: :en, app: "MyCoolApp #{VERSION}", i18n: "i18n #{I18n::VERSION}")
  end
end
