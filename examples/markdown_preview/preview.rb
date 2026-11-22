# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT-0
#++

# Markdown Preview's windowed program: shows each Markdown file it is
# given in the browser, rendered, as a page written to the system's
# temporary folder. A double-click on a .md file starts it with that
# file, since fledge.yml lists Markdown under file_associations. Started
# with no file, from a menu or the Dock, it shows welcome.md, which says
# how to use it.
#
#   ruby preview.rb [FILE...]

require_relative "lib/markdown_preview"

sources = ARGV.empty? ? [File.join(__dir__, "welcome.md")] : ARGV
sources.each { |source| MarkdownPreview::Browser.open(MarkdownPreview.write(source)) }
