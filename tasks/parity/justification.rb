# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

class Parity
  # The name of the folders a Ruby keeps its library and gems in, as a
  # pattern for a justification: its ruby_version, MAJOR.MINOR.0 for a
  # release, with its ABI version for a preview or a snapshot of master
  # (4.1.0+5), as the runtime's own tree names them
  # (RuntimeBuilder.ruby_abi).
  ABI = '\d+\.\d+\.0(?:\+\d+)?'

  # One difference parity allows, and why. +reference+ and +app+ are
  # patterns: an element found only in the reference run is justified
  # when it matches one of +reference+, and one found only in the app
  # when it matches one of +app+. +platforms+, when given, limits it to
  # those platforms, and +checks+ to the script check (:script, against
  # ruby main.rb), the gem-shaped one (:bundle, against bundle exec), or
  # the script check run with no locale at all (:no_locale), which also
  # allows whatever the script check allows.
  class Justification < Data.define(:fact, :reference, :app, :reason, :platforms, :checks)
    def self.new(fact:, reason:, reference: [], app: [], platforms: nil, checks: %i[script bundle])
      super
    end

    def applies?(fact_name, platform, check)
      fact == fact_name && (platforms.nil? || platforms.include?(platform)) &&
        (checks.include?(check) || (check == :no_locale && checks.include?(:script)))
    end

    def explains?(element, side)
      ((side == :reference) ? reference : app).any? { |pattern| pattern.match?(element) }
    end
  end
end
