# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

# A windowed project with no gems of its own, which the builder app turns
# into an app with fledge build --from. It writes its line to the path
# it is given, as an app writes what it opened, or prints it.
line = "Spiel says hello from #{File.basename(__dir__)}: #{File.read(File.join(__dir__, 'assets', 'hello.txt')).strip}"
ARGV.empty? ? puts(line) : File.write(ARGV.fetch(0), "#{line}\n")
