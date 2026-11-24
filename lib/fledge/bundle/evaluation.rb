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
    # Evaluates a project's Gemfile, which is Ruby, in a Ruby of its own,
    # as the app's process evaluates it under <tt>bundle exec</tt>, and
    # answers what it says as data (Fledge::Bundle::GemfileData), so that
    # nothing the Gemfile does (a branch on RUBY_VERSION, a change to ENV,
    # a +require+, a +puts+) reaches the process that runs <tt>fledge
    # build</tt>. That Ruby is the one that runs Fledge, with none of the
    # developer's Ruby settings (NativeBuild::SCRUBBED), started in the
    # Gemfile's folder with BUNDLE_GEMFILE naming the Gemfile, where a
    # developer runs <tt>bundle exec</tt>. Fledge::Bundle and Fledge::App
    # take it as a collaborator, so a test of something else can pass one
    # that starts no Ruby.
    #
    # Whatever the Gemfile prints is the Ruby's own, kept apart from the
    # answer, and shown only with an error.
    class Evaluation
      # The file the Ruby of its own loads to describe the Gemfile
      # (Fledge::Bundle::GemfileData).
      GEMFILE_DATA = File.join(File.dirname(__FILE__), "gemfile_data.rb")

      # What that Ruby runs: the Gemfile's path, then +definition+ or
      # +gemspec+ and the gemspec's path, as its arguments. It answers on
      # the stream it started with, and gives the Gemfile's own output
      # the error stream, so that a Gemfile that prints cannot spoil the
      # answer. A Bundler error is the answer, as the error's message.
      SCRIPT = <<~RUBY
        answer = $stdout.dup
        $stdout.reopen($stderr)
        load ARGV.shift
        gemfile, command, path = ARGV
        begin
          result = (command == "gemspec") ? Fledge::Bundle::GemfileData.gemspec(gemfile, path) : Fledge::Bundle::GemfileData.definition(gemfile)
          answer.print JSON.generate("answer" => result)
        rescue Bundler::BundlerError => e
          answer.print JSON.generate("bundler" => e.message)
        end
      RUBY

      # The Gemfile at +gemfile+ as data, for
      # Fledge::Bundle::GemfileData.dsl. Raises Bundler::GemfileError, a
      # Bundler::BundlerError, with the message Bundler gave when it does
      # not accept the Gemfile, and Fledge::Error when the Ruby cannot
      # evaluate it.
      def definition(gemfile)
        answer = run(gemfile, "definition")
        answer.is_a?(Hash) ? answer : {}
      end

      # The YAML of the gemspec at +path+ evaluated after the Gemfile at
      # +gemfile+, for Fledge::Bundle::GemfileData.specification, or +nil+
      # when Bundler finds none.
      def gemspec(gemfile, path)
        answer = run(gemfile, "gemspec", path)
        answer.is_a?(String) ? answer : nil
      end

      private def run(gemfile, command, path = nil)
        env = ENV.keys.grep(NativeBuild::SCRUBBED).to_h { |name| [name, nil] } # : Hash[String, String?]
        env["BUNDLE_GEMFILE"] = gemfile
        arguments = [GEMFILE_DATA, gemfile, command, path].compact
        out, err, status = Open3.capture3(env, RbConfig.ruby, "-rbundler", "-rjson", "-e", SCRIPT, *arguments, chdir: File.dirname(gemfile))
        raise Error, "Ruby can't evaluate #{gemfile}:\n#{err.rstrip}" unless status.success?

        require "bundler"
        answer = JSON.parse(out)
        raise Bundler::GemfileError, answer.fetch("bundler") if answer.key?("bundler")

        answer.fetch("answer")
      end
    end
  end
end
