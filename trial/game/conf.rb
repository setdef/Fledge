# frozen_string_literal: true

def Lota.conf(t)
  t.identity = "LotaTrial"
  t.window.title = "Lota Trial"
  t.window.width = 320
  t.window.height = 240
  # The renderers to try, such as "vulkan", for a trial run; LÖVE's own
  # order otherwise.
  renderers = ENV.fetch("LOTA_TRIAL_RENDERERS", "")
  t.graphics.renderers = renderers.split(",").map(&:to_sym) unless renderers.empty?
end
