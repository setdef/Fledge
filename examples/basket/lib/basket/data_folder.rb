# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT-0
#++

require "etcetera"

# Basket, a shopping list whose screen each system's widgets draw.
module Basket
  # Where Basket keeps its list: the folder its system keeps an app's data
  # in, as Etcetera finds it, which is $XDG_DATA_HOME (or ~/.local/share)
  # on Linux, ~/Library/Application Support on iOS, Windows' Roaming
  # AppData folder, and, on Android, the same under HOME, which Android's
  # files folder is.
  module DataFolder
    # Etcetera's native strategy, which follows each system's
    # convention: Apple's on iOS and macOS, Windows' on Windows, and XDG's
    # everywhere else, Android among them. Its arguments make the folder
    # setdef\Basket\data on Windows, com.setdef.Basket on iOS and macOS,
    # and basket elsewhere.
    STRATEGY = Etcetera::AppStrategy.choose_native_strategy(
      Etcetera::AppStrategyArgs.new(top_level_domain: "com", author: "setdef", app_name: "Basket")
    )

    # The path of Basket's list: basket.json in its data folder, which the
    # list makes when it first saves, since a system leaves it out until
    # an app makes it.
    def self.list_path
      STRATEGY.in_data_dir("basket.json").to_s
    end
  end
end
