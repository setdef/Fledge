# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT-0
#++

require "rouge"

module Lectern
  # Code colored by Rouge's lexers, which are pure Ruby, in the sixteen
  # colors every terminal has, so that a person's own palette decides how
  # they look.
  module Highlight
    # The styles of a token whose name (Rouge's qualified name, such as
    # +Literal.String.Double+) matches, first match first.
    TOKENS = [
      [/\AComment/, %i[gray italic]],
      [/\ALiteral\.String\.(Regex|Symbol)/, %i[yellow]],
      [/\ALiteral\.String/, %i[green]],
      [/\ALiteral/, %i[cyan]],
      [/\AKeyword/, %i[magenta]],
      [/\AName\.(Function|Class|Namespace|Decorator|Tag)/, %i[blue bold]],
      [/\AName\.(Builtin|Constant|Variable|Attribute)/, %i[cyan]],
      [/\AGeneric\.(Deleted|Error)/, %i[red]],
      [/\AGeneric\.Inserted/, %i[green]],
      [/\AGeneric\.(Heading|Subheading|Strong)/, %i[bold]],
      [/\AError/, %i[red]],
    ].freeze

    # The lines of +code+, each as pieces, colored as the language +lang+
    # is, or uncolored when Rouge knows no such language.
    def self.lines(code, lang)
      lexer = lang && Rouge::Lexer.find(lang.to_s.downcase)
      tokens = lexer ? lexer.lex(code) : [[Rouge::Token::Tokens::Text, code]]
      lines = [[]]
      tokens.each do |token, value|
        styles = TOKENS.find { |pattern, _| pattern.match?(token.qualname) }&.last || []
        value.split("\n", -1).each_with_index do |part, index|
          lines << [] if index.positive?
          lines.last << Piece.new(part.gsub("\t", "    "), styles, :word) unless part.empty?
        end
      end
      lines.pop if lines.size > 1 && lines.last.empty?
      lines
    end
  end
end
