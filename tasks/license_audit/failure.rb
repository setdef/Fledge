# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

class LicenseAudit
  # Raised by RuntimeBuilder when a runtime it built breaks the policy,
  # naming every violation, so that no such runtime is archived.
  class Failure < StandardError
    attr_reader :problems

    def initialize(platform, problems)
      @problems = problems
      super("the #{platform} runtime breaks Fledge's license policy (runtime/licenses.yml):\n#{problems.map { |problem| "  #{problem}" }.join("\n")}")
    end
  end
end
