# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: MIT-0
#++

require "i18n"
require_relative "mobile_app/version"

# The gem-shaped app Fledge's CI ships to phones (ADR 012): its gemspec
# names an executable, exe/mobile_app, and i18n, which needs
# concurrent-ruby, both pure Ruby, so a phone's project ships them as
# they are, set up by Bundler as bundle exec would set them up.
#
# Its greeting goes through both: concurrent-ruby's map holds the text,
# and i18n fills it in. CI checks the line it prints exactly, from the
# system log of the iOS Simulator and Android emulators, so it prints
# only when Bundler and both gems load and work there.
module MobileApp
  # The line the app prints, naming the gems it went through.
  #
  # === Example
  #
  #--
  # SPDX-SnippetBegin
  # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
  # SPDX-License-Identifier: MIT-0
  #++
  #   MobileApp.greeting
  #   # => "MobileApp 1.2.3 says hello through i18n 1.15.2 and concurrent-ruby 1.3.8, set up by Bundler"
  #--
  # SPDX-SnippetEnd
  #++
  def self.greeting
    texts = Concurrent::Map.new
    texts[:greeting] = "%{app} says hello through %{i18n} and %{concurrent}, set up by %{bundler}"
    I18n.backend.store_translations(:en, greeting: texts.fetch(:greeting))
    I18n.t(:greeting, locale: :en, app: "MobileApp #{VERSION}", i18n: "i18n #{I18n::VERSION}",
      concurrent: "concurrent-ruby #{Gem.loaded_specs.fetch('concurrent-ruby').version}",
      bundler: defined?(Bundler) ? "Bundler" : "nothing")
  end
end
