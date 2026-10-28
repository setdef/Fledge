# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: MIT-0
#++

# nokogiri, compiled from source by fledge build, parsing and searching.
require "nokogiri"

text = Nokogiri::XML("<app><name>fledged</name></app>").at("name").text
puts "NokogiriApp found #{text} through nokogiri #{Nokogiri::VERSION} and libxml2 #{Nokogiri::VERSION_INFO.dig('libxml', 'loaded')}"
exit Integer(ARGV.fetch(0, "0"))
