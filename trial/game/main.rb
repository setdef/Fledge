# frozen_string_literal: true

# Draws a square that moves and changes colour, and quits by itself
# after about three seconds.
def Lota.load(_arguments)
  @elapsed = 0.0
  @frames = 0
  puts "lota-trial: loaded, Ruby #{RUBY_VERSION}, Lota #{Lota::VERSION}"
  $stdout.flush
end

def Lota.update(dt)
  @elapsed += dt
  return unless @elapsed >= 3.0

  puts "lota-trial: #{@frames} frames in #{@elapsed.round(2)} s, quitting"
  $stdout.flush
  Lota::Event.quit
end

def Lota.draw
  @frames += 1
  t = @elapsed
  Lota::Graphics.color = [(Math.sin(t * 3) + 1) / 2, 0.4, 1 - t / 3.0]
  Lota::Graphics.rectangle(:fill, 20 + t * 80, 80, 60, 60)
  Lota::Graphics.color = [1, 1, 1]
  Lota::Graphics.print("frame #{@frames}", 10, 10)
  puts "lota-trial: frame #{@frames}" if (@frames % 60).zero?
end
