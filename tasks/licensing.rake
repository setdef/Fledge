# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

# doc/licensing.md comes from the license audit of all four runtimes,
# which only CI builds together, so this stays out of the gate; CI's
# "Licensing page is current" job runs the check, and uploads the page it
# expected when the check fails.
desc "Write doc/licensing.md from every platform's runtime archive in DIR (ADR 004)"
task :licensing, [:dir] do |_task, arguments|
  dir = arguments[:dir] or abort "usage: rake \"licensing[DIR]\", DIR holding fledge-runtime-*-PLATFORM.tar.gz for every platform"
  ruby "tasks/licensing_page.rb", dir
end
