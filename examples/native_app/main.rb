# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: MIT-0
#++

# What fledge build compiles from source: redcarpet's C extension, and
# ferro-idna's Rust one, from git. Each line comes from compiled code.
require "redcarpet"
require "ferro/idna"

html = Redcarpet::Markdown.new(Redcarpet::Render::HTML).render("**fledged**").strip
domain = Ferro::Idna.domain_to_ascii("bücher.example")
puts "NativeApp renders #{html} through redcarpet #{Redcarpet::VERSION} and spells #{domain} through ferro-idna"
