# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT-0
#++

require "uri"

module MarkdownPreview
  # A preview's page: the HTML that kramdown made, in a document a
  # browser shows with a readable column of text, and where it is
  # written.
  module Page
    # The page's style: a column of text as wide as a book's, code on a
    # tinted ground, and tables ruled.
    STYLE = <<~CSS
      body { font: 16px/1.5 system-ui, sans-serif; max-width: 46em; margin: 2em auto; padding: 0 1em; color: #2b2a33; }
      pre, code { font-family: ui-monospace, monospace; background: #efeef4; border-radius: 4px; }
      pre { padding: 1em; overflow: auto; }
      code { padding: 0.1em 0.3em; }
      pre code { padding: 0; }
      table { border-collapse: collapse; }
      th, td { border: 1px solid #c9c6d6; padding: 0.3em 0.8em; }
      blockquote { margin-left: 0; padding-left: 1em; border-left: 4px solid #c9c6d6; color: #615d75; }
      img { max-width: 100%; }
    CSS

    # The page for +body+, HTML from a Markdown file called +title+,
    # whose relative links and images are taken from the folder +base+.
    def self.html(body, title:, base:)
      <<~HTML
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <base href="#{escape(base)}">
        <title>#{escape(title)}</title>
        <style>
        #{STYLE}</style>
        </head>
        <body>
        #{body}</body>
        </html>
      HTML
    end

    # Where the preview of the Markdown file +source+ is written, in
    # +folder+: one page for each file name, so a second preview of a
    # file replaces its first.
    def self.path(source, folder)
      File.join(folder, "markdown-preview", "#{File.basename(source, '.*')}.html")
    end

    # The file URL of the folder that holds +source+, which a page's
    # relative links are taken from, on Windows with its drive letter.
    def self.base(source)
      folder = File.dirname(File.expand_path(source))
      folder = "/#{folder}" unless folder.start_with?("/")
      "file://#{URI::RFC2396_PARSER.escape(folder.chomp('/'))}/"
    end

    # +text+ as HTML shows it.
    def self.escape(text)
      text.gsub(/[&<>"]/, "&" => "&amp;", "<" => "&lt;", ">" => "&gt;", '"' => "&quot;")
    end
  end
end
