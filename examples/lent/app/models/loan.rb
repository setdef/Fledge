# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT-0
#++

# A thing lent: what, to whom, since when, and when it came back.
#
# Its days are the person's own: Date.today, from this computer's clock
# and time zone. Date.current is the day in Rails' Time.zone, UTC unless
# configured, which suits a server whose users are anywhere; here, in an
# evening in the Americas, it would already be tomorrow.
class Loan < ActiveRecord::Base
  validates :thing, :borrower, :lent_on, presence: true
  validate :lent_on_not_ahead

  scope :out, -> { where(returned_on: nil).order(:lent_on, :id) }
  scope :back, -> { where.not(returned_on: nil).order(returned_on: :desc, id: :desc) }

  # How many days it has been away.
  def days_out
    ((returned_on || Date.today) - lent_on).to_i
  end

  # Marks it come back today.
  def return!
    update!(returned_on: Date.today)
  end

  private def lent_on_not_ahead
    errors.add(:lent_on, "can't be later than today") if lent_on && lent_on > Date.today
  end
end
