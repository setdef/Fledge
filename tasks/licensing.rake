# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# doc/licensing.md comes from the license audit of all four runtimes,
# which only CI builds together, so this stays out of the gate; CI's
# "Licensing page is current" job runs the check, and uploads the page it
# expected when the check fails.
desc "Write doc/licensing.md from the four runtime archives in DIR (ADR 004)"
task :licensing, [:dir] do |_task, arguments|
  dir = arguments[:dir] or abort "usage: rake \"licensing[DIR]\", DIR holding fledge-runtime-*-PLATFORM.tar.gz for every platform"
  ruby "tasks/licensing_page.rb", dir
end
