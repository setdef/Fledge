# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "test_helper"

# Which gemspecs Fledge evaluates in a Ruby of their own to learn the
# project's files they load: every one that calls anything that can load
# a file. test/integration/gemspec_requires_test.rb evaluates them.
class GemspecRequiresTest < Minitest::Test
  PLAIN = "Gem::Specification.new do |s|\n  s.name = \"greeter\"\n  s.version = \"1.0\"\n" \
    "  s.files = IO.popen(%w[git ls-files -z], chdir: __dir__) { |ls| ls.readlines(\"\\x0\", chomp: true) }\n" \
    "  s.executables = s.files.grep(%r{\\Aexe/}).map { |file| File.basename(file) }\n" \
    "  s.add_dependency \"rake\", \"~> 13\"\nend\n"

  def test_a_gemspec_that_calls_nothing_that_loads_a_file_is_inert
    assert Fledge::Bundle::GemspecRequires.inert?(PLAIN)
  end

  def test_a_gemspec_that_can_load_a_file_is_not_inert
    [
      'require_relative "lib/greeter/version"',
      'require "greeter/version"',
      'Kernel.require "greeter/version"',
      'load "lib/greeter/version.rb"',
      'autoload :Greeter, "./lib/greeter"',
      'instance_eval File.read("lib/greeter/version.rb")',
      'binding.eval File.read("lib/greeter/version.rb")',
      "Object.instance_exec(&proc { 1 })",
      'Kernel.send(name, "greeter")',
      'Kernel.public_send(:require, "greeter")',
      'Kernel.__send__(:require, "greeter")',
      'Kernel.method(:require).call("greeter")',
      "Object.const_get(:Greeter)",
      '["greeter"].each(&:require)',
      'name = :require; ["greeter"].each(&name)',
      "alias fetch require",
      'Gem::Specification.load("other.gemspec")',
      'Bundler.load_gemspec("other.gemspec")',
    ].each do |line|
      refute Fledge::Bundle::GemspecRequires.inert?("#{line}\n#{PLAIN}"), line
    end
  end

  def test_a_block_passed_by_a_harmless_symbol_keeps_a_gemspec_inert
    assert Fledge::Bundle::GemspecRequires.inert?("%w[a b].map(&:upcase)\n#{PLAIN}")
  end

  def test_a_gemspec_prism_cannot_parse_is_not_inert
    refute Fledge::Bundle::GemspecRequires.inert?("Gem::Specification.new do |s|\n")
  end

  # An inert gemspec's evaluated Ruby ships as it is, with no Ruby
  # started: this one names a constant only the Gemfile's evaluation
  # defines, as under bundle exec, so a Ruby of its own would fail on it.
  def test_an_inert_gemspec_ships_as_evaluated
    Dir.mktmpdir do |dir|
      path = File.join(dir, "greeter.gemspec")
      File.write(path, PLAIN.sub('"1.0"', "Greeter::VERSION"))

      assert_equal "evaluated", Fledge::Bundle::GemspecRequires.new(path, root: dir).call("evaluated")
    end
  end
end
