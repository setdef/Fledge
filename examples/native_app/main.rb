# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT-0
#++

# What fledge build compiles from source: redcarpet's C extension and
# ferro-idna's Rust one, from git; and spreadsheet, pure Ruby under the
# GPL, which writes an Excel workbook in memory and reads it back. Each
# part of the line comes from one of them.
require "redcarpet"
require "ferro/idna"
require "spreadsheet"
require "stringio"

html = Redcarpet::Markdown.new(Redcarpet::Render::HTML).render("**fledged**").strip
domain = Ferro::Idna.domain_to_ascii("bücher.example")
book = Spreadsheet::Workbook.new
book.create_worksheet(name: "app")[0, 0] = "fledged"
written = StringIO.new(+"")
book.write(written)
cell = Spreadsheet.open(StringIO.new(written.string)).worksheet(0)[0, 0]
puts "NativeApp renders #{html} through redcarpet #{Redcarpet::VERSION}, spells #{domain} through ferro-idna, " \
  "and reads #{cell} back through spreadsheet #{Spreadsheet::VERSION}"
exit Integer(ARGV.fetch(0, "0"))
