# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT-0
#++

require "kramdown"
require "kramdown-parser-gfm"
require_relative "text"
require_relative "style"
require_relative "highlight"
require_relative "table_layout"

module Lectern
  # Markdown as text for a terminal: kramdown parses it (GitHub-Flavored
  # Markdown), and each element becomes lines at most +width+ columns
  # wide, drawn in the +style+ the output allows.
  class Renderer
    # The styles of a heading, by its level.
    HEADINGS = {
      1 => %i[bold cyan],
      2 => %i[bold blue],
      3 => %i[bold magenta],
      4 => %i[bold yellow],
      5 => %i[bold],
      6 => %i[dim],
    }.freeze
    # What stands before a heading of each level. A level with no mark is
    # told by its style alone.
    HEADING_MARKS = { 3 => "▸ ", 4 => "▹ " }.freeze
    # What the line drawn under a heading of each level is made of.
    HEADING_RULES = { 1 => "═", 2 => "─" }.freeze
    # The styles that a space inside a span carries, so that an underline
    # or a strike runs on across it.
    SPACED = %i[underline strike].freeze
    # What kramdown's typographic elements read as.
    SYMBOLS = {
      ndash: "–",
      mdash: "—",
      hellip: "…",
      laquo: "«",
      raquo: "»",
      laquo_space: "« ",
      raquo_space: " »",
      lsquo: "‘",
      rsquo: "’",
      ldquo: "“",
      rdquo: "”",
    }.freeze
    # The elements that carry nothing to show.
    SKIPPED = %i[blank comment xml_comment eob xml_pi].freeze
    # The bullets of nested lists.
    BULLETS = %w[• ◦ ▪].freeze
    # A YAML front matter block, which a reader does not show.
    FRONT_MATTER = /\A---[ \t]*\n.*?\n(?:---|\.\.\.)[ \t]*(?:\n|\z)/m
    # The tags of inline HTML that only change how text looks.
    HTML_STYLES = {
      "del" => %i[strike],
      "s" => %i[strike],
      "strike" => %i[strike],
      "ins" => %i[underline],
      "u" => %i[underline],
      "b" => %i[bold],
      "strong" => %i[bold],
      "i" => %i[italic],
      "em" => %i[italic],
      "cite" => %i[italic],
      "code" => %i[yellow],
      "kbd" => %i[yellow],
      "tt" => %i[yellow],
    }.freeze

    # A renderer for +width+ columns, drawing in +style+ (a Style).
    def initialize(width:, style:)
      @width = width
      @style = style
      @depth = 0
    end

    # +markdown+ as the text a terminal shows, a line break ending each line.
    def render(markdown)
      source = markdown.delete_prefix("\u{FEFF}").gsub("\r\n", "\n").sub(FRONT_MATTER, "")
      root = Kramdown::Document.new(source, input: "GFM", hard_wrap: false).root
      lines = blocks(root.children, @width)
      lines.empty? ? "" : "#{lines.join("\n")}\n"
    end

    # The lines of +elements+, one block after another with a blank line
    # between, unless the block before is a list item's bare paragraph.
    private def blocks(elements, width)
      lines = []
      previous = nil
      elements.each do |element|
        next if SKIPPED.include?(element.type)

        block = block(element, width)
        next if block.empty?

        lines << "" if previous && !(previous.type == :p && previous.options[:transparent])
        lines.concat(block)
        previous = element
      end
      lines
    end

    private def block(element, width)
      case element.type
      when :p then paragraph(inline(element), width)
      when :header then heading(element, width)
      when :blockquote then quote(element, width)
      when :ul, :ol then list(element, width)
      when :dl then definitions(element, width)
      when :codeblock then code(Highlight.lines(element.value, element.options[:lang]), width)
      when :math then code(Highlight.lines(element.value, nil), width)
      when :hr then [paint("─" * width, %i[gray])]
      when :table then table(element, width)
      when :raw then paragraph(markup(element.value, []), width)
      when :html_element then html_block(element, width)
      else element.children.empty? ? [] : blocks(element.children, width)
      end
    end

    private def paragraph(pieces, width)
      Text.wrap(pieces, width).map { |line| draw(line) }.then { |lines| (lines == [""]) ? [] : lines }
    end

    private def heading(element, width)
      level = element.options.fetch(:level)
      styles = HEADINGS.fetch(level)
      pieces = inline(element, styles)
      pieces.unshift(Piece.new(HEADING_MARKS[level], styles, :word)) if HEADING_MARKS.key?(level)
      lines = Text.wrap(pieces, width)
      return [] if lines == [[]]

      rule = HEADING_RULES[level]
      lines.map { |line| draw(line) } + (rule ? [paint(rule * lines.map { |line| line.sum(&:width) }.max, %i[gray])] : [])
    end

    private def quote(element, width)
      bar = paint("┃ ", %i[gray])
      blocks(element.children, width - 2).map { |line| "#{bar}#{line}" }
    end

    private def list(element, width)
      items = element.children.select { |child| child.type == :li }
      start = (element.type == :ol) ? element.options[:first_list_marker].to_i : 0
      markers = items.each_index.map { |index| marker(element, items[index], start + index) }
      indent = markers.map { |text, _| Text.width(text) }.max || 0
      @depth += 1
      loose = items.any? { |item| item.children.any? { |child| child.type == :p && !child.options[:transparent] } }
      lines = items.zip(markers).flat_map do |item, (text, styles)|
        body = blocks(item.children, width - indent)
        gutter = " " * indent
        rows = body.each_with_index.map { |line, index| index.zero? ? "#{paint(text.ljust(indent), styles)}#{line}" : "#{gutter}#{line}" }
        rows = [paint(text, styles)] if rows.empty?
        loose ? rows + [""] : rows
      end
      @depth -= 1
      loose ? lines[0...-1] : lines
    end

    # The marker of a list's +item+, with the styles it is drawn in.
    private def marker(list, item, number)
      return ["", []] if item.attr["class"].to_s.include?("task-list-item")

      (list.type == :ol) ? ["#{number}. ", %i[cyan]] : ["#{BULLETS[@depth % BULLETS.size]} ", %i[cyan]]
    end

    private def definitions(element, width)
      lines = []
      element.children.each do |child|
        case child.type
        when :dt then lines.concat(paragraph(inline(child, %i[bold]), width))
        when :dd then lines.concat(blocks(child.children, width - 2).map { |line| "  #{line}" })
        end
      end
      lines
    end

    private def code(lines, width)
      lines.flat_map { |line| Text.hard(line, [width - 4, 1].max) }.map { |line| "    #{draw(line)}" }
    end

    private def html_block(element, width)
      if element.children.all? { |child| inline?(child) }
        paragraph(inline(element), width)
      else
        blocks(element.children, width)
      end
    end

    private def inline?(element)
      %i[text em strong codespan a img br smart_quote typographic_sym entity raw footnote_ref].include?(element.type) ||
        (element.type == :html_element && element.options[:category] == :span)
    end

    private def table(element, width)
      alignments = element.options[:alignment] || []
      rows = element.children.flat_map(&:children)
      head = (element.children.first.type == :thead) ? element.children.first.children.size : 0
      cells = rows.each_with_index.map do |row, index|
        row.children.map { |cell| inline(cell, (index < head) ? %i[bold] : []) }
      end
      columns = TableLayout.widths(cells, width)
      border = -> (left, middle, right) { paint(left + columns.map { |w| "─" * (w + 2) }.join(middle) + right, %i[gray]) }
      bar = paint("│", %i[gray])
      lines = [border.call("┌", "┬", "┐")]
      cells.each_with_index do |row, index|
        TableLayout.rows(row, columns, alignments).each do |line|
          lines << "#{bar} #{line.map { |cell| draw(cell) }.join(" #{bar} ")} #{bar}"
        end
        lines << border.call("├", "┼", "┤") if index == head - 1 && index < cells.size - 1
      end
      lines << border.call("└", "┴", "┘")
    end

    # The pieces of the inline elements inside +element+, in +styles+.
    private def inline(element, styles = [])
      element.children.flat_map { |child| span(child, styles) }
    end

    private def span(element, styles)
      case element.type
      when :text then words(element.value, styles)
      when :em then inline(element, styles + %i[italic])
      when :strong then inline(element, styles + %i[bold])
      when :codespan, :math then words(element.value, styles + %i[yellow])
      when :a then link(element, styles)
      when :img then image(element, styles)
      when :br then [Piece.new("", [], :break)]
      when :smart_quote, :typographic_sym then words(SYMBOLS.fetch(element.value, ""), styles)
      when :entity then words(element.value.char, styles)
      when :footnote_ref then words("[#{element.options[:name]}]", styles + %i[dim])
      when :raw then markup(element.value, styles)
      when :html_element then html_span(element, styles)
      else SKIPPED.include?(element.type) ? [] : inline(element, styles)
      end
    end

    private def html_span(element, styles)
      case element.value
      when "br" then [Piece.new("", [], :break)]
      when "input" then [Piece.new(element.attr.key?("checked") ? "[x]" : "[ ]", styles, :word), Piece.new(" ", [], :space)]
      when "img" then image(element, styles)
      else inline(element, styles + HTML_STYLES.fetch(element.value, []))
      end
    end

    private def link(element, styles)
      pieces = inline(element, styles + %i[underline blue])
      target = element.attr["href"].to_s
      return pieces if target.empty? || target.start_with?("#") || target == plain(pieces)

      pieces + words(" ", []) + words("(#{target})", %i[dim])
    end

    private def image(element, styles)
      alt = element.attr["alt"].to_s
      words("[picture: #{alt.empty? ? File.basename(element.attr['src'].to_s) : alt}]", styles + %i[italic]) +
        words(" ", []) + words("(#{element.attr['src']})", %i[dim])
    end

    # Text that raw HTML holds: its tags dropped, and its line breaks kept.
    private def markup(html, styles)
      html.split(%r{(<br\s*/?>)}i).flat_map do |part|
        part.match?(/\A<br/i) ? [Piece.new("", [], :break)] : words(part.gsub(/<[^>]*>/, ""), styles)
      end
    end

    private def plain(pieces)
      pieces.map(&:text).join
    end

    # +string+ as words and the spaces between them, in +styles+.
    private def words(string, styles)
      spaced = styles & SPACED
      string.split(/(\s+)/).reject(&:empty?).map do |part|
        part.match?(/\A\s/) ? Piece.new(" ", spaced, :space) : Piece.new(part, styles, :word)
      end
    end

    private def draw(pieces)
      pieces.map { |piece| paint(piece.text, piece.styles) }.join
    end

    private def paint(text, styles)
      @style.paint(text, styles)
    end
  end
end
