# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

class Parity
  # One difference parity allows, and why. +reference+ and +app+ are
  # patterns: an element found only in the reference run is justified
  # when it matches one of +reference+, and one found only in the app
  # when it matches one of +app+. +platforms+, when given, limits it to
  # those platforms, and +checks+ to the script check (:script, against
  # ruby main.rb) or the gem-shaped one (:bundle, against bundle exec).
  class Justification < Data.define(:fact, :reference, :app, :reason, :platforms, :checks)
    def self.new(fact:, reason:, reference: [], app: [], platforms: nil, checks: %i[script bundle])
      super
    end

    def applies?(fact_name, platform, check)
      fact == fact_name && (platforms.nil? || platforms.include?(platform)) && checks.include?(check)
    end

    def explains?(element, side)
      ((side == :reference) ? reference : app).any? { |pattern| pattern.match?(element) }
    end
  end
end
