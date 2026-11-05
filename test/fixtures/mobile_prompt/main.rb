# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# experiment/phone-stdout: a line, 5 seconds of sleep, and another line,
# with no flush, so the log's timestamps show when each line left Ruby.
puts "Prompt before the sleep"
sleep 5
puts "Prompt after the sleep"
