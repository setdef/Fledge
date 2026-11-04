# frozen_string_literal: true

# Starts a Lota game fused, as a shipped game is: the one in game/, which
# opens a window, draws, plays a tone, and quits by itself, or with the
# argument "quiet" the one in quiet/, which opens no window and plays a
# sound. Each line it says goes to standard output and, when
# LOTA_TRIAL_LOG names a file, to that file too, since a program Windows
# starts through its shell has no standard output anyone reads.
module Trial
  def self.say(line)
    line = "lota-trial: #{line}"
    $stdout.puts line
    $stdout.flush
    log = ENV.fetch("LOTA_TRIAL_LOG", "")
    File.open(log, "a") { |file| file.puts line } unless log.empty?
  end
end

Trial.say "starting #{File.basename($PROGRAM_NAME)} with #{ARGV.inspect}"
begin
  require "lota"
rescue LoadError => e
  Trial.say "require lota failed: #{e.class}: #{e.message}"
  raise
end

quiet = ARGV.first == "quiet"
folder = File.join(__dir__, quiet ? "quiet" : "game")
status = Lota::Boot.new(folder, quiet ? ARGV.drop(1) : ARGV, fused: true).call
Trial.say "exiting with #{status.inspect}"
exit(status)
