# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT-0
#++

module Lectern
  # What the output carries of style: +:full+ is colors and attributes,
  # +:attributes+ is bold, italic, underline, and the rest without colors
  # (what NO_COLOR asks for, no-color.org), and +:none+ is plain text with
  # no escape sequence, for a file or a pipe.
  class Style < Data.define(:mode)
    # The SGR parameters (ECMA-48) of each style name.
    CODES = {
      bold: 1,
      dim: 2,
      italic: 3,
      underline: 4,
      strike: 9,
      red: 31,
      green: 32,
      yellow: 33,
      blue: 34,
      magenta: 35,
      cyan: 36,
      gray: 90,
      white: 97,
    }.freeze
    # The names that are not colors.
    ATTRIBUTES = %i[bold dim italic underline strike].freeze

    # The style the person asked for. +setting+ is "auto", "always", or
    # "never"; +terminal+ is whether the output is a terminal; +env+ holds
    # NO_COLOR and TERM.
    def self.choose(setting, terminal:, env:)
      case setting
      when "always" then new(:full)
      when "never" then new(:none)
      else
        if !terminal || env["TERM"] == "dumb" then new(:none)
        elsif env.fetch("NO_COLOR", "").empty? then new(:full)
        else new(:attributes)
        end
      end
    end

    # +text+ drawn in the styles named by +names+, as far as this style goes.
    def paint(text, names)
      codes = names.select { |name| mode == :full || (mode == :attributes && ATTRIBUTES.include?(name)) }
      return text if codes.empty? || text.empty?

      "\e[#{codes.map { |name| CODES.fetch(name) }.join(';')}m#{text}\e[0m"
    end

    # Whether this style writes escape sequences.
    def styled?
      mode != :none
    end
  end
end
