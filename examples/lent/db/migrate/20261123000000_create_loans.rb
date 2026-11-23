# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT-0
#++

# Lent's first table, the things lent (app/models/loan.rb).
class CreateLoans < ActiveRecord::Migration[8.1]
  # Makes the table, or, rolled back, drops it.
  def change
    create_table :loans do |t|
      t.string :thing, null: false
      t.string :borrower, null: false
      t.date :lent_on, null: false
      t.date :returned_on
      t.text :note
      t.timestamps
    end
  end
end
