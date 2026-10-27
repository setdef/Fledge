# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "../../lib/fledge/binary"

class LicenseAudit
  # What a compiled file links (Fledge::Binary), which the audit reads
  # for every file of a runtime, and fledge build for every compiled file
  # of an app's native gems (ADR 005).
  Binary = Fledge::Binary
end
