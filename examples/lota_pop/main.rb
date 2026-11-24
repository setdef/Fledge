# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT-0
#++

# Starts the game in game/, as a shipped game starts, which is how
# Lota's own fuser starts one. Lota opens the window, reads
# game/conf.rb, and runs game/main.rb. The game is Ruby, and so is this.
require "lota"

exit Lota::Boot.new(File.join(__dir__, "game"), ARGV, fused: true).call
