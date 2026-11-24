# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT-0
#++

require "kramdown"
require "kramdown-parser-gfm"
require "tmpdir"
require_relative "markdown_preview/browser"
require_relative "markdown_preview/page"

# Markdown Preview's two programs share this: preview.rb, which a
# double-click on a Markdown file starts, and bin/md2html, which a
# terminal runs.
module MarkdownPreview
  # The HTML of +markdown+, read as GitHub-Flavored Markdown, the dialect kramdown's GFM parser reads.
  def self.to_html(markdown)
    Kramdown::Document.new(markdown, input: "GFM").to_html
  end

  # Writes the preview of the Markdown file +source+ into +folder+ and
  # returns its path. A file that cannot be read previews as a page that
  # says why.
  def self.write(source, folder: Dir.tmpdir)
    title = File.basename(source)
    body = begin
      to_html(File.read(source, encoding: "bom|utf-8"))
    rescue SystemCallError => e
      "<p>Markdown Preview could not read #{Page.escape(reason(e))}.</p>\n"
    end
    path = Page.path(source, folder)
    Dir.mkdir(File.dirname(path)) unless File.directory?(File.dirname(path))
    File.write(path, Page.html(body, title:, base: Page.base(source)))
    path
  end

  # What +error+, from opening a file, says, as cat says it: the file,
  # then what is wrong ("notes.md: No such file or directory").
  def self.reason(error)
    what, file = error.message.split(/ @ \w+ - /, 2)
    file ? "#{file}: #{what}" : what
  end
end
