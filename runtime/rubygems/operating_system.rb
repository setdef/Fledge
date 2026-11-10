# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
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
# The launcher hides GEM_HOME and GEM_PATH from Ruby's boot, and has
# RubyGems settle its paths before it puts them back (ADR 040), so this
# default is the whole path for the app, while the app's own child
# processes still see the person's variables. It works the same way on
# Windows, where a Fledge runtime ships this file too.
#--
# SPDX-SnippetBegin
# SPDX-License-Identifier: Ruby OR MIT
# SPDX-SnippetCopyrightText: Chad Fowler, Rich Kilmer, Jim Weirich and others
# SPDX-SnippetComment: Gem.default_path, adapted from RubyGems'
#   lib/rubygems/defaults.rb at Ruby v4.0.9 (3e93b23afc), keeping only its
#   default_dir, through the operating_system.rb hook RubyGems documents
#   there for packagers.
#++
module Gem
  # The runtime's own gem folder, and nothing else.
  def self.default_path
    [default_dir]
  end
end
#--
# SPDX-SnippetEnd
#++

# A bundled gem that the app's Gemfile does not name, such as irb for
# binding.irb, activates under Bundler as it does under bundle exec.
#
# Ruby's prelude.rb answers a binding.irb whose require "irb" fails with
# Gem::BUNDLED_GEMS.force_activate("irb"), which sets up a temporary
# bundle of the Gemfile's gems and irb, and never writes it to the
# lockfile (Definition.no_lock; prelude.rb lines 8 to 11 and
# bundled_gems.rb lines 214 to 259, at Ruby 4.0.9). In a frozen bundle
# that fails: Runtime#setup refuses a Gemfile with a gem the lockfile
# lacks ("You have added to the Gemfile: * irb"), and a frozen
# Definition#resolve takes only the lockfile's gems. A built app's
# .bundle/config freezes its bundle (Fledge::Bundle::SETTINGS), so that
# Bundler never touches the lockfile in a folder that may be read-only,
# where bundle exec on the developer's computer is not frozen. So while
# force_activate runs, and only on its thread, Bundler is told its bundle
# is not frozen; the temporary bundle is still never locked.
#
# The modules are anonymous, so an app sees no constant of Fledge's
# (ADR 003).
unfrozen = Module.new do
  def frozen_bundle?
    Thread.current[:__fledge_force_activate] ? false : super
  end
end
# bundled_gems.rb, which defines Gem::BUNDLED_GEMS, loads after this
# file, and reopens the module.
Gem.const_set(:BUNDLED_GEMS, Module.new) unless Gem.const_defined?(:BUNDLED_GEMS, false)
Gem::BUNDLED_GEMS.singleton_class.prepend(Module.new do
  define_method(:force_activate) do |gem|
    require "bundler"
    Bundler.singleton_class.prepend(unfrozen)
    Thread.current[:__fledge_force_activate] = true
    super(gem)
  ensure
    Thread.current[:__fledge_force_activate] = nil
  end
end)
