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
    # The files evaluating a gemspec loads, as Bundler evaluates it under
    # <tt>bundle exec</tt>: after the Gemfile's own code, so that the
    # gemspec finds what the Gemfile defined (Bundler::Dsl#eval_gemfile,
    # whose +gemspec+ line calls Bundler.load_gemspec). The Gemfile and
    # gemspec are evaluated in a Ruby of its own, with none of the
    # developer's Ruby settings (NativeBuild::SCRUBBED), since the
    # process that asks may have loaded those files already, reading the
    # Gemfile. Fledge::Bundle takes it as a collaborator, so a test of
    # something else can pass one that starts no Ruby.
    class GemspecLoads
      # What that Ruby runs, with the Gemfile's path and the gemspec's as
      # its arguments, from the Gemfile's folder, where a developer runs
      # <tt>bundle exec</tt>. A required file is one that enters
      # <tt>$LOADED_FEATURES</tt> while Bundler evaluates the gemspec, in
      # the order it finished loading. A loaded one, which Kernel#load
      # leaves out of <tt>$LOADED_FEATURES</tt> however it is called, is
      # a file Ruby compiles then (TracePoint's +script_compiled+) that is
      # not a required one, unless a file compiled then is still running,
      # which loads it again wherever it runs. Each load comes before the
      # requires that finished after it began.
      SCRIPT = <<~RUBY
        require "bundler"
        require "json"
        gemfile, target = ARGV.map { |path| File.realpath(path) }
        Dir.chdir(File.dirname(gemfile))
        events = nil
        record = lambda do |&evaluate|
          events = []
          before = $LOADED_FEATURES.size
          compiled = Hash.new(0)
          loads = []
          trace = TracePoint.new(:script_compiled) do |tp|
            path = tp.instruction_sequence.absolute_path
            next if tp.eval_script || path.nil?

            nested = caller_locations.any? { |frame| compiled.key?(frame.absolute_path) }
            compiled[path] += 1
            loads << [path, $LOADED_FEATURES.size - before, compiled[path]] unless nested
          end
          begin
            trace.enable(&evaluate)
          ensure
            required = $LOADED_FEATURES.drop(before)
            loads.each { |path, at, count| events << [at, 0, "load", path] unless count == 1 && required.include?(path) }
            required.each_with_index { |path, at| events << [at, 1, "require", path] }
          end
        end
        Bundler.singleton_class.prepend(Module.new do
          define_method(:load_gemspec_uncached) do |file, validate = false|
            return super(file, validate) unless events.nil? && File.realpath(file) == target

            record.call { super(file, validate) }
          end
        end)
        Bundler::Dsl.new.eval_gemfile(gemfile)
        Bundler.load_gemspec(target) if events.nil?
        print JSON.generate(events.sort_by.with_index { |event, index| [event[0], event[1], index] }.map { |event| event.drop(2) })
      RUBY

      # Each file evaluating the gemspec at +path+ loads, after the
      # Gemfile at +gemfile+, as its kind, +require+ or +load+, and its
      # path, in an order in which a Ruby that does the same loads the
      # same files. Raises Fledge::Error when that Ruby cannot evaluate
      # them.
      def call(path, gemfile:)
        env = ENV.keys.grep(NativeBuild::SCRUBBED).to_h { |name| [name, nil] } # : Hash[String, String?]
        env["BUNDLE_GEMFILE"] = gemfile
        out, err, status = Open3.capture3(env, RbConfig.ruby, "-e", SCRIPT, gemfile, path)
        raise Error, "Ruby can't evaluate #{path}:\n#{err.rstrip}" unless status.success?

        JSON.parse(out)
      end
    end
  end
end
