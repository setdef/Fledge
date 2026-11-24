# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT-0
#++

module MarkdownToHtml
  # A written page: the HTML that kramdown made, in a document a browser
  # shows with a readable column of text, and where it is written.
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

    # The page for +body+, HTML from a Markdown file called +title+.
    def self.html(body, title:)
      <<~HTML
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <title>#{escape(title)}</title>
        <style>
        #{STYLE}</style>
        </head>
        <body>
        #{body}</body>
        </html>
      HTML
    end

    # Where the page for the Markdown file +source+ is written: beside
    # it, so its relative links and images still reach what they name.
    def self.path(source)
      File.join(File.dirname(source), "#{File.basename(source, '.*')}.html")
    end

    # +text+ as HTML shows it.
    def self.escape(text)
      text.gsub(/[&<>"]/, "&" => "&amp;", "<" => "&lt;", ">" => "&gt;", '"' => "&quot;")
    end
  end
end
