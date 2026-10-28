# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: MIT-0
#++

# What fledge build compiles from source, or takes precompiled where it
# can: redcarpet's C extension, ferro-idna's Rust one, from git, and
# ratatui_ruby's Rust one, which measures text as a terminal would and
# needs no terminal to. Each part of the line comes from compiled code.
require "redcarpet"
require "ferro/idna"
require "ratatui_ruby"

html = Redcarpet::Markdown.new(Redcarpet::Render::HTML).render("**fledged**").strip
domain = Ferro::Idna.domain_to_ascii("bücher.example")
cells = RatatuiRuby::Text.width("日本語 ok")
puts "NativeApp renders #{html} through redcarpet #{Redcarpet::VERSION}, spells #{domain} through ferro-idna, " \
  "and measures #{cells} cells through ratatui_ruby #{RatatuiRuby::VERSION}"
exit Integer(ARGV.fetch(0, "0"))
