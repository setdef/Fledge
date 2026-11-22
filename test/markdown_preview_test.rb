# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "test_helper"
require_relative "../examples/markdown_preview/lib/markdown_preview/browser"
require_relative "../examples/markdown_preview/lib/markdown_preview/page"

# examples/markdown_preview's page and browser, apart from kramdown,
# which only the example's own bundle has: where a preview is written,
# how it looks, and what opens it on each system.
class MarkdownPreviewTest < Minitest::Test
  def test_each_system_opens_the_page_with_its_own_opener
    commands = %w[arm64-darwin27 x64-mingw-ucrt x86_64-linux-musl].map do |platform|
      MarkdownPreview::Browser.command("/tmp/notes.html", env: {}, platform:)
    end

    assert_equal [%w[open /tmp/notes.html], ["explorer.exe", "\\tmp\\notes.html"], %w[xdg-open /tmp/notes.html]], commands
  end

  def test_browser_names_the_browser_first_in_its_list
    env = { "BROWSER" => ["firefox", "chromium"].join(File::PATH_SEPARATOR) }

    assert_equal %w[firefox /tmp/notes.html], MarkdownPreview::Browser.command("/tmp/notes.html", env:, platform: "arm64-darwin27")
  end

  def test_an_empty_browser_leaves_the_system_its_opener
    assert_equal %w[xdg-open /tmp/notes.html], MarkdownPreview::Browser.command("/tmp/notes.html", env: { "BROWSER" => "" }, platform: "aarch64-linux")
  end

  def test_a_preview_is_named_for_its_file_in_a_folder_of_previews
    assert_equal File.join("/tmp", "markdown-preview", "notes.html"), MarkdownPreview::Page.path("/home/me/notes.md", "/tmp")
  end

  def test_relative_links_are_taken_from_the_folder_of_the_file
    base = MarkdownPreview::Page.base(File.join(Dir.pwd, "my notes", "notes.md"))

    assert_match %r{\Afile:///}, base
    assert base.end_with?("/my%20notes/"), base
  end

  def test_the_page_holds_the_html_under_its_escaped_title
    page = MarkdownPreview::Page.html("<p>hi</p>\n", title: "a<b>.md", base: "file:///notes/")

    assert_includes page, "<title>a&lt;b&gt;.md</title>"
    assert_includes page, %(<base href="file:///notes/">)
    assert_includes page, "<body>\n<p>hi</p>\n</body>"
  end
end
