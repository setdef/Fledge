# frozen_string_literal: true

# Opens a 320x240 window on a blue background, draws an orange square in
# its middle and a line of text, plays half a second of a 440 Hz tone,
# reads back the frame it drew at frame 30, and quits by itself after
# four seconds with status 0.
def Lota.load(_arguments)
  @elapsed = 0.0
  @frames = 0
  name, version, vendor, device = Lota::Graphics.renderer_info
  Trial.say "loaded: Ruby #{RUBY_VERSION}, Lota #{Lota::VERSION}, #{Lota::System.os}"
  Trial.say "renderer: #{name} #{version} / #{vendor} / #{device}"
  Trial.say "save directory: #{Lota::Filesystem.save_directory}"
  Lota::Graphics.background_color = [0.1, 0.2, 0.6]
  tone = Lota::Sound::SoundData.new(22_050, 44_100, 16, 1)
  22_050.times { |i| tone.sample = i, 0.2 * Math.sin(2 * Math::PI * 440 * i / 44_100.0) }
  @tone = Lota::Audio::Source.new(tone)
  @tone.play
  Trial.say "audio: #{Lota::Audio.active_source_count} source playing"
end

def Lota.update(dt)
  @elapsed += dt
  if @frames >= 30 && !@captured
    @captured = true
    Lota::Graphics.capture_screenshot do |image|
      Trial.say "frame #{@frames}: #{image.width}x#{image.height}, " \
                "centre #{image.pixel(160, 120).map { |c| c.round(2) }}, corner #{image.pixel(300, 220).map { |c| c.round(2) }}"
      image.encode(:png, "frame.png")
      Trial.say "wrote frame.png"
    end
  end
  return unless @elapsed >= 4.0

  Trial.say "#{@frames} frames in #{@elapsed.round(2)} s, quitting"
  Lota::Event.quit(0)
end

def Lota.draw
  @frames += 1
  Lota::Graphics.color = [1, 0.5, 0]
  Lota::Graphics.rectangle(:fill, 110, 70, 100, 100)
  Lota::Graphics.color = [1, 1, 1]
  Lota::Graphics.print("Lota on Fledge, frame #{@frames}", 10, 10)
end
