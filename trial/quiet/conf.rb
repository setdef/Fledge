# frozen_string_literal: true

# No window, as Lota's own Windows CI runs a game: the modules that need
# one are off.
def Lota.conf(t)
  t.identity = "LotaTrial"
  %i[window graphics image font keyboard mouse].each { |name| t.modules.public_send(:"#{name}=", false) }
end
