# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT-0
#++

# What fledge build compiles from source: redcarpet's C extension and
# ferro-idna's Rust one, from git, everywhere but Windows, where the
# Gemfile leaves it out; libusb, precompiled on Windows and compiled
# everywhere else, which names the build the app shipped; and
# spreadsheet, pure Ruby under the GPL, which writes an Excel workbook in
# memory and reads it back. Each part of the line comes from one of them.
require "redcarpet"
require "ferro/idna" if Gem.loaded_specs.key?("ferro-idna")
require "libusb"
require "spreadsheet"
require "stringio"

html = Redcarpet::Markdown.new(Redcarpet::Render::HTML).render("**fledged**").strip
idna = defined?(Ferro::Idna) ? ", spells #{Ferro::Idna.domain_to_ascii('bücher.example')} through ferro-idna" : ""
book = Spreadsheet::Workbook.new
book.create_worksheet(name: "app")[0, 0] = "fledged"
written = StringIO.new(+"")
book.write(written)
cell = Spreadsheet.open(StringIO.new(written.string)).worksheet(0)[0, 0]
usb = "libusb #{LIBUSB.version} from its #{Gem.loaded_specs.fetch('libusb').platform} build"
puts "NativeApp renders #{html} through redcarpet #{Redcarpet::VERSION}#{idna}, " \
  "loads #{usb}, and reads #{cell} back through spreadsheet #{Spreadsheet::VERSION}"
exit Integer(ARGV.fetch(0, "0"))
