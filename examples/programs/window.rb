# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT-0
#++

# Shared Save's windowed program, which opens no window.
#
# A GUI on Lota or Tokra would show the save; this one is pure Ruby, and
# a windowed program has no terminal to print to, so it writes a report
# instead: as JSON, the save's entries as it found them, then adds its
# own entry to the save, as the console program does.
#
#   ruby window.rb SAVE REPORT

require_relative "lib/shared_save"

save, report = ARGV
abort "usage: window.rb SAVE REPORT" unless save && report
File.write(report, "#{JSON.generate('read' => SharedSave.entries(save))}\n")
SharedSave.record(save, "Shared Save")
