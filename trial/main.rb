# frozen_string_literal: true

# Starts the Lota game in game/, as `lota run game` would, but fused,
# as a shipped game is.
require "lota"

boot = Lota::Boot.new(File.join(__dir__, "game"), ARGV, fused: true)
status = boot.call
warn "lota-trial: exiting with #{status}"
exit(status)
