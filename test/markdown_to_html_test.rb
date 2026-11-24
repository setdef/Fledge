# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "test_helper"
require_relative "../examples/markdown_to_html/lib/markdown_to_html/notice"
require_relative "../examples/markdown_to_html/lib/markdown_to_html/page"

# examples/markdown_to_html's page and notice, apart from kramdown, which
# only the example's own bundle has: where a page is written, how it
# looks, and how the droplet tells each system what it could not do.
class MarkdownToHtmlTest < Minitest::Test
  def test_a_page_is_written_beside_its_file_under_its_name
    assert_equal File.join("/home/me", "notes.html"), MarkdownToHtml::Page.path("/home/me/notes.md")
    assert_equal "./notes.html", MarkdownToHtml::Page.path("notes.markdown")
  end

  def test_the_page_holds_the_html_under_its_escaped_title
    page = MarkdownToHtml::Page.html("<p>hi</p>\n", title: "a<b>.md")

    assert_includes page, "<title>a&lt;b&gt;.md</title>"
    assert_includes page, "<body>\n<p>hi</p>\n</body>"
  end

  def test_each_system_tells_a_failure_its_own_way
    commands = %w[arm64-darwin27 x64-mingw-ucrt x86_64-linux-musl].map do |platform|
      MarkdownToHtml::Notice.command("Markdown to HTML", "notes.md: No such file", platform:).first
    end

    assert_equal %w[osascript powershell.exe notify-send], commands
  end

  def test_a_message_reaches_the_command_as_data_and_not_as_code
    hostile = %(x" & calc.exe; $(touch pwned) ')

    mac = MarkdownToHtml::Notice.command("T", hostile, platform: "arm64-darwin27")
    linux = MarkdownToHtml::Notice.command("T", hostile, platform: "aarch64-linux")
    windows = MarkdownToHtml::Notice.command("T", hostile, platform: "x64-mingw-ucrt")

    assert_equal hostile, mac.last
    assert_equal hostile, linux.last
    refute_includes windows.join, "calc.exe"
  end
end
