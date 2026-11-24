# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT-0
#++

# Markdown to HTML's windowless program, a droplet: it writes the HTML
# page of each Markdown file it is given beside the file. Dropped files
# and opened files reach it in ARGV, since fledge.yml lists Markdown
# under file_associations. It tells only what it could not do, by a
# notification or a message box (MarkdownToHtml::Notice); started with
# no file, from a menu or the Dock, it says how to use it.
#
#   ruby markdown_to_html.rb [FILE...]

require_relative "lib/markdown_to_html"

# The name the notices go under.
TITLE = "Markdown to HTML"

if ARGV.empty?
  MarkdownToHtml::Notice.show(TITLE, "Drop Markdown files on #{TITLE}, and it writes each one's HTML beside it.")
  exit
end

failures = ARGV.filter_map do |source|
  MarkdownToHtml.write(source)
  nil
rescue SystemCallError => e
  MarkdownToHtml.reason(e)
end
exit if failures.empty?

failures.each { |failure| warn "#{TITLE}: #{failure}" }
MarkdownToHtml::Notice.show(TITLE, "Could not write: #{failures.join('; ')}")
exit 66
