# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: MIT-0
#++

# What fledge build compiles from source, or takes precompiled where it
# can: redcarpet's C extension, ferro-idna's Rust one, from git, and
# ratatui_ruby's Rust one, which measures text as a terminal would and
# needs no terminal to; and spreadsheet, pure Ruby under the GPL, which
# writes an Excel workbook in memory and reads it back. Each part of the
# line comes from one of them.
require "redcarpet"
require "ferro/idna"
require "ratatui_ruby"
require "spreadsheet"
require "stringio"

html = Redcarpet::Markdown.new(Redcarpet::Render::HTML).render("**fledged**").strip
domain = Ferro::Idna.domain_to_ascii("bücher.example")
cells = RatatuiRuby::Text.width("日本語 ok")
book = Spreadsheet::Workbook.new
book.create_worksheet(name: "app")[0, 0] = "fledged"
written = StringIO.new(+"")
book.write(written)
cell = Spreadsheet.open(StringIO.new(written.string)).worksheet(0)[0, 0]
puts "NativeApp renders #{html} through redcarpet #{Redcarpet::VERSION}, spells #{domain} through ferro-idna, " \
  "measures #{cells} cells through ratatui_ruby #{RatatuiRuby::VERSION}, and reads #{cell} back through spreadsheet " \
  "#{Spreadsheet::VERSION}"
exit Integer(ARGV.fetch(0, "0"))
