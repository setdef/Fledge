# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

class LicenseAudit
  # One way the tree breaks the policy.
  class Violation < Data.define(:rule, :path, :message)
    def to_s
      "#{rule}: #{path.empty? ? '' : "#{path}: "}#{message}"
    end
  end
end
