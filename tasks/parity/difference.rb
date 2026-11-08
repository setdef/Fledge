# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

class Parity
  # A fact that differs between the two runs, and the justifications
  # that explain every element of the difference, or none.
  class Difference < Data.define(:fact, :only_in_reference, :only_in_app, :justifications)
    def justified?
      !justifications.empty?
    end

    def to_s
      lines = ["#{justified? ? 'justified' : 'DIFFERENT'}: #{fact}"]
      only_in_reference.each { |element| lines << "    reference only: #{element}" }
      only_in_app.each { |element| lines << "    built app only: #{element}" }
      lines << "    order differs" if only_in_reference.empty? && only_in_app.empty?
      justifications.each { |justification| lines << "    why: #{justification.reason}" }
      lines.join("\n")
    end
  end
end
