# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

class LicenseAudit
  # What the audit found: the components present, which file each
  # component owns, what each compiled file links and has compiled in,
  # and every violation.
  class Report < Data.define(:platform, :tree, :components, :owners, :binaries, :links, :embeds, :violations)
    def owned(component)
      owners.select { |_path, owner| owner.equal?(component) }.keys.sort
    end

    def embedded_in(component)
      embeds.select { |_path, ids| ids.include?(component.id) }.keys.sort
    end

    def present
      components.select { |component| !owned(component).empty? || !embedded_in(component).empty? }
    end
  end
end
