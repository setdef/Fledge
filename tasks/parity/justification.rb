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
  # allows whatever the script check allows, or the gem-shaped check run
  # on Windows with Bundler's variables spelled otherwise (:spelled),
  # which also allows whatever the gem-shaped check allows.
  #
  # When patterns on both sides name groups, the justification pairs
  # the elements it explains: what the groups capture from those found
  # in the reference only must be what they capture from those found in
  # the app only, one for one, so that a folder or a feature renamed is
  # allowed and one missing from either side is not.
  class Justification < Data.define(:fact, :reference, :app, :reason, :platforms, :checks)
    def self.new(fact:, reason:, reference: [], app: [], platforms: nil, checks: %i[script bundle])
      super
    end

    def applies?(fact_name, platform, check)
      fact == fact_name && (platforms.nil? || platforms.include?(platform)) &&
        (checks.include?(check) || checks.include?({ no_locale: :script, spelled: :bundle }[check]))
    end

    def explains?(element, side)
      patterns(side).any? { |pattern| pattern.match?(element) }
    end

    def paired?
      [reference, app].all? { |patterns| patterns.any? { |pattern| !pattern.names.empty? } }
    end

    # What the named groups of the first of +side+'s patterns that
    # matches +element+ capture.
    def captures(element, side)
      patterns(side).lazy.filter_map { |pattern| pattern.match(element) }.first&.named_captures
    end

    private def patterns(side)
      (side == :reference) ? reference : app
    end
  end
end
