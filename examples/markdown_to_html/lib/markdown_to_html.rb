# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT-0
#++

require "kramdown"
require "kramdown-parser-gfm"
require_relative "markdown_to_html/notice"
require_relative "markdown_to_html/page"

# Markdown to HTML's two programs share this: markdown_to_html.rb, the
# droplet that Markdown files are dropped on or opened with, and
# bin/md2html, which a terminal runs.
module MarkdownToHtml
  # The HTML of +markdown+, read as GitHub-Flavored Markdown, the dialect kramdown's GFM parser reads.
  def self.to_html(markdown)
    Kramdown::Document.new(markdown, input: "GFM").to_html
  end

  # Writes the page for the Markdown file +source+ beside it, as its
  # name with .html in place of its extension, and returns the page's
  # path. A page already there is replaced. Raises SystemCallError when
  # the file cannot be read or the page cannot be written.
  def self.write(source)
    body = to_html(File.read(source, encoding: "bom|utf-8"))
    path = Page.path(source)
    File.write(path, Page.html(body, title: File.basename(source)))
    path
  end

  # What +error+, from opening a file, says, as cat says it: the file,
  # then what is wrong ("notes.md: No such file or directory").
  def self.reason(error)
    what, file = error.message.split(/ @ \w+ - /, 2)
    file ? "#{file}: #{what}" : what
  end
end
