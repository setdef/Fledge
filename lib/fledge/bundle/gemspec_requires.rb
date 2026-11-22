# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require "json"
require "open3"
require "prism"
require "rbconfig"
require_relative "../error"
require_relative "../native_build"

module Fledge
  class Bundle
    # The evaluated gemspec a built app ships for one of the project's
    # own gems, led by a require_relative of each file in the project
    # that evaluating the gemspec loads, in the order they finish
    # loading. Under <tt>bundle exec</tt> Bundler evaluates the gemspec
    # at every start, so what it requires (<tt>bundle gem</tt>'s
    # <tt>lib/NAME/version.rb</tt>, and the constant it defines) is loaded
    # before the program's first line; the app's Bundler evaluates the
    # shipped one at every start too, and loads the same files, by the
    # same paths, with no git.
    #
    # The gemspec is evaluated in a Ruby of its own, with none of the
    # developer's Ruby settings, since this process has usually loaded
    # those files already, reading the Gemfile. That Ruby is not started
    # for a gemspec whose source calls nothing that loads a file (#inert?):
    # code that names no such method can load only what RubyGems and
    # Bundler load for themselves, which is outside the project, so that
    # Ruby would report nothing.
    class GemspecRequires # :nodoc:
      # What a Ruby runs to report the files evaluating a gemspec loads,
      # as Bundler evaluates it (Bundler.load_gemspec), in the order they
      # finish loading.
      LOADS = <<~RUBY
        require "bundler"
        require "json"
        before = $LOADED_FEATURES.dup
        Bundler.load_gemspec(ARGV.fetch(0))
        print JSON.generate($LOADED_FEATURES - before)
      RUBY

      # The methods by which Ruby code loads a file, or calls a method
      # it names at run time: require and its kin, Bundler.load_gemspec and
      # Gem::Specification.load among them; eval and its kin; send and
      # its kin; method objects and to_proc; define_method; and const_get,
      # which can trigger an autoload.
      LOADING = %i[
        require
        require_relative
        load
        autoload
        load_gemspec
        eval
        instance_eval
        class_eval
        module_eval
        instance_exec
        class_exec
        module_exec
        send
        public_send
        __send__
        method
        public_method
        instance_method
        public_instance_method
        singleton_method
        to_proc
        define_method
        define_singleton_method
        const_get
      ].freeze

      # Whether the gemspec +source+ calls nothing that can load a file:
      # no method LOADING names, no block passed by anything but a literal
      # symbol it does not name, and no alias. A source
      # Prism cannot parse is never inert, so the Ruby that evaluates it
      # reports the error.
      def self.inert?(source)
        result = Prism.parse(source)
        result.success? && Inert.new.tap { |visitor| result.value.accept(visitor) }.inert
      end

      # Walks a parsed gemspec, and notes whether it found anything that
      # can load a file.
      class Inert < Prism::Visitor # :nodoc:
        attr_reader :inert

        def initialize
          super
          @inert = true
        end

        def visit_call_node(node)
          @inert = false if LOADING.include?(node.name)
          super
        end

        def visit_block_argument_node(node)
          symbol = node.expression
          @inert = false unless symbol.is_a?(Prism::SymbolNode) && !LOADING.include?(symbol.unescaped.to_sym)
          super
        end

        def visit_alias_method_node(node)
          @inert = false
          super
        end
      end

      # For the gemspec at +path+ of the project at +root+.
      def initialize(path, root:)
        @path = path
        @root = root
      end

      # The evaluated gemspec +ruby+, led by the requires. Raises
      # Fledge::Error when the Ruby cannot evaluate the gemspec.
      def call(ruby)
        return ruby if GemspecRequires.inert?(File.read(@path))

        requires = loaded.map { |feature| "require_relative #{relative(feature).inspect}\n" }.join
        requires.empty? ? ruby : ruby.sub(/^Gem::Specification\.new/) { "#{requires}\n#{Regexp.last_match(0)}" }
      end

      # The project's files evaluating the gemspec loads, by real path.
      private def loaded
        env = ENV.keys.grep(NativeBuild::SCRUBBED).to_h { |name| [name, nil] } # : Hash[String, String?]
        out, err, status = Open3.capture3(env, RbConfig.ruby, "-e", LOADS, @path)
        raise Error, "Ruby can't evaluate #{@path}:\n#{err.rstrip}" unless status.success?

        root = "#{File.realpath(@root)}/"
        JSON.parse(out).map { |feature| File.realpath(feature) }.select { |feature| feature.start_with?(root) }
      end

      # +path+ relative to the gemspec's folder, without its .rb, as
      # require_relative takes it.
      private def relative(path)
        folder = File.dirname(File.realpath(@path))
        Pathname.new(path).relative_path_from(Pathname.new(folder)).to_s.delete_suffix(".rb")
      end
    end
  end
end
