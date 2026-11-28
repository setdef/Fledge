# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

# docs/reference/licensing.md comes from the license audit of every platform's
# runtime, which only CI builds together. runtime/audited.yml records
# what the page reads of those runtimes, so without DIR this writes the
# page in a moment from that record and the repository, which a unit test
# checks before every push. With DIR it audits the runtimes there and
# writes both files, as CI's "Licensing page is current" job checks they
# match, uploading the files it expected when they do not.
desc "Write docs/reference/licensing.md (and runtime/audited.yml, from every platform's runtime archive in DIR, if given)"
task :licensing, [:dir] do |_task, arguments|
  ruby "tasks/licensing_page.rb", *arguments[:dir]
end
