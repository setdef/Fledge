# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

class LicenseAudit
  # One way the tree breaks the policy.
  class Violation < Data.define(:rule, :path, :message)
    def to_s
      "#{rule}: #{path.empty? ? '' : "#{path}: "}#{message}"
    end
  end
end
