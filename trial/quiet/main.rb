# frozen_string_literal: true

# Plays a tenth of a second of silence through OpenAL Soft and quits with
# status 3.
def Lota.load(_arguments)
  Lota::Audio::Source.new(Lota::Sound::SoundData.new(4410, 44_100, 16, 1)).play
  Trial.say "#{Lota::System.os}: #{Lota::Audio.active_source_count} source playing"
  Lota::Event.quit(3)
end
