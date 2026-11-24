# frozen_string_literal: true

# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT-0

require "json"

# Basket, a shopping list whose screen each phone's own widgets draw.
module Basket
  # The shopping list: its items, in the order they were added, kept as
  # JSON in a file of the app's own. A phone can stop an app in the
  # background without running at_exit, so each change saves at once.
  class List
    # The items, each a String.
    attr_reader :items

    # The list kept in the file at +path+, empty until it is first saved.
    def initialize(path)
      @path = path
      @items = File.exist?(path) ? JSON.parse(File.read(path)) : []
    end

    # Adds +text+, without the spaces around it, unless nothing is left,
    # and returns the item it added, or nil.
    def add(text)
      item = text.to_s.strip
      return if item.empty?

      @items << item
      save
      item
    end

    # Removes the item at +index+, and returns it.
    def remove(index)
      @items.delete_at(index).tap { save }
    end

    private def save
      File.write(@path, JSON.generate(@items))
    end
  end
end
