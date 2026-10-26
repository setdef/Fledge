# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# Fledge's RubyGems defaults for a built app.
#
# RubyGems loads rubygems/defaults/operating_system.rb, when one exists,
# so that whoever packages Ruby can change its defaults (rubygems.rb
# lines 58 to 59 and 1422 to 1434 at Ruby 4.0.9). Debian and
# RubyInstaller ship one; rv-ruby does not.
#
# Left alone, Gem.default_path puts Gem.user_dir (~/.gem/ruby/4.0.0, or
# ~/.local/share/gem/ruby/4.0.0) first whenever the person's home folder
# exists (rubygems/defaults.rb, Gem.default_path), so a gem they installed
# with their own Ruby 4.0 would shadow a gem the app ships, json
# included. Here the app's gems come from the runtime and nowhere else.
#
# The launcher removes GEM_HOME and GEM_PATH before Ruby starts, so this
# default is the whole path. Setting it here rather than pinning those
# variables in the launcher keeps them out of the environment the app's
# own child processes inherit, and works the same way on Windows, where
# a Fledge runtime ships this file too.
module Gem
  # The runtime's own gem folder, and nothing else.
  def self.default_path
    [default_dir]
  end
end
