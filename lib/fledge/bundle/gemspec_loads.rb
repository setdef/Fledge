# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require "json"
require "open3"
require "rbconfig"
require_relative "../error"
require_relative "../native_build"

module Fledge
  class Bundle
    # The files evaluating a gemspec loads, as Bundler evaluates it
    # (Bundler.load_gemspec), in the order they finish loading. The
    # gemspec is evaluated in a Ruby of its own, with none of the
    # developer's Ruby settings (NativeBuild::SCRUBBED), since the
    # process that asks may have loaded those files already, reading the
    # Gemfile. Fledge::Bundle takes it as a collaborator, so a test of
    # something else can pass one that starts no Ruby.
    class GemspecLoads
      # What that Ruby runs, with the gemspec's path as its argument.
      SCRIPT = <<~RUBY
        require "bundler"
        require "json"
        before = $LOADED_FEATURES.dup
        Bundler.load_gemspec(ARGV.fetch(0))
        print JSON.generate($LOADED_FEATURES - before)
      RUBY

      # The paths of the files evaluating the gemspec at +path+ loads, as
      # that Ruby's <tt>$LOADED_FEATURES</tt> names them. Raises
      # Fledge::Error when that Ruby cannot evaluate it.
      def call(path)
        env = ENV.keys.grep(NativeBuild::SCRUBBED).to_h { |name| [name, nil] } # : Hash[String, String?]
        out, err, status = Open3.capture3(env, RbConfig.ruby, "-e", SCRIPT, path)
        raise Error, "Ruby can't evaluate #{path}:\n#{err.rstrip}" unless status.success?

        JSON.parse(out)
      end
    end
  end
end
