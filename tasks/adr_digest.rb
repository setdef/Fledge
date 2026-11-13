# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

# One ADR, read for its title, its problem, its decision drivers, and the
# option it chose, so the whole log can be read the way a review board
# reads it: does each problem, with its drivers, lead to that choice?
#
# The ADRs are MADR (the +adr+ skill; AGENTS.md): numbered options under
# "Considered Options", and "Chosen: option N" opening the outcome. A few
# options carry the lettered name the maintainer gave them, as ADR 005's
# "(b)" does, and the outcome names that letter instead.
#
#   bundle exec rake adr:digest
class AdrDigest
  SECTIONS = ["Context and Problem Statement", "Decision Drivers"].freeze

  def initialize(text)
    @text = text
  end

  def title = @text[/^# (.*)/, 1]

  def context = section("Context and Problem Statement")

  def drivers = section("Decision Drivers")

  # The text of option +number+, its wrapped lines joined.
  def option(number) = options[number]

  # The number of the option the outcome chose, or nil when it names none.
  def chosen
    named = section("Decision Outcome").to_s[/Chosen: option (\d+|\([a-z]\))/, 1]
    return unless named
    return named.to_i if named.match?(/\A\d+\z/)

    options.find { |_, text| text.start_with?(named) }&.first
  end

  def to_s
    lines = ["# #{title}"]
    SECTIONS.each { |name| lines << "\n#{name}:\n#{section(name) || 'missing'}" }
    lines << "\n#{chosen ? "Chosen, option #{chosen}: #{option(chosen)}" : 'Chosen: none named'}"
    lines.join("\n")
  end

  private def section(name)
    @text[/^## #{Regexp.escape(name)}[^\n]*\n(.*?)(?=^## |\z)/m, 1]&.strip
  end

  private def options
    @options ||= section("Considered Options").to_s.scan(/^(\d+)\. (.*(?:\n {3}.*)*)/).to_h do |number, text|
      [number.to_i, text.gsub(/\s*\n\s+/, " ")]
    end
  end
end

if $PROGRAM_NAME == __FILE__
  ARGV.each { |path| puts "#{AdrDigest.new(File.read(path))}\n\n" }
end
