# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT-0
#++

# Lectern: reads Markdown in a terminal. It draws headings,
# emphasis, lists, block quotes, tables, and code blocks with highlighting,
# wrapped to the terminal's width, and pages what is longer than the
# screen. It writes plain text when its output is a file or a pipe, and no
# colors when NO_COLOR is set.
#
#   ruby main.rb [OPTION]... [FILE]...     (built with Fledge: Lectern ...)

require_relative "lib/lectern"

$stdout.set_encoding(Encoding::UTF_8)
exit Lectern::Cli.new(ARGV).run
