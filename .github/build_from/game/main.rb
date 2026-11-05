# frozen_string_literal: true

# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: MIT-0

# Experiment only (experiment/build-from): a project with no gems of its
# own, built into an app with fledge build --from by the builder app.
puts "Spiel says hello from #{File.basename(__dir__)}: #{File.read(File.join(__dir__, 'assets', 'hello.txt')).strip}"
puts "RUBYOPT=#{ENV.fetch('RUBYOPT', '')}"
