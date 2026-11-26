# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "test_helper"
require "open3"

# Every citation of an ADR names one that doc/contributors/adr/ still
# holds. An ADR that no longer passes is deleted and its reasons move
# into the design document for its subject, so a citation left behind
# sends its reader to nothing; this test is what notices one
# (doc/contributors/design/architecture.md, "Architecture Decision
# Records").
class AdrCitationsTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  # What may come between ADR and its number, and between the numbers of
  # a list: spaces, or a line break with the next line's comment marker,
  # so a citation wrapped across comment lines is still one citation.
  GAP = %r{(?:[ \t]*\n[ \t]*(?:\#+|//|\*|--|;|>)?[ \t]*|[ \t]+)}
  CITATION = /\bADRs?#{GAP}(\d{3}(?:(?:,#{GAP}(?:and#{GAP})?|#{GAP}(?:and|to)#{GAP})\d{3})*)\b/
  LINK = %r{\badr/(\d{3})\.md\b}

  # Files kept as they stood on their dates, which cite ADRs as they
  # were then and are never edited (architecture.md, "Architecture
  # Decision Records"); and one test whose fixtures are ADRs of its own.
  EXEMPT = {
    "doc/contributors/research/" => "dated research",
    "doc/contributors/plan/001.md" => "a finished plan",
    "doc/contributors/plan/002.md" => "a finished plan",
    "doc/contributors/drafts/tokra.md" => "a dated draft to Tokra, never sent",
    "doc/contributors/decisions.md" => "the decision log, frozen, whose Applied-in pointers name ADRs as they stood",
    "test/adr_digest_test.rb" => "its fixtures are ADRs numbered past any real one",
  }.freeze

  # Another of setdef's projects, whose ADRs have numbers of their own:
  # "Lota's ADR 002", "(setdef/lota, ADR 002)".
  ANOTHER_PROJECT = %r{(?:(?:Lota|Tokra|Rooibos)'s|setdef/(?:lota|tokra|rooibos)\b)[^.]{0,40}\z}

  def adrs
    @adrs ||= Dir.children(File.join(ROOT, "doc/contributors/adr")).grep(/\A\d{3}\.md\z/).map { |name| name[0, 3] }
  end

  def tracked
    out, status = Open3.capture2("git", "ls-files", "-z", chdir: ROOT)
    assert_predicate status, :success?
    out.split("\0")
  end

  # The text of a file that a citation in must name an ADR that exists:
  # CHANGELOG.md's Unreleased section and not the released ones, which
  # are never edited.
  def checked_text(path, text)
    return text unless path == "CHANGELOG.md"

    text[/\A.*?^## \[Unreleased\].*?(?=^## \[|\z)/m].to_s
  end

  # Each [line, number] the text cites that has no ADR. In an ADR, the
  # line that says which ADRs it supersedes names them as gone, as a
  # record of what it replaced.
  def missing(path, text)
    text = checked_text(path, text)
    found = []
    [CITATION, LINK].each do |pattern|
      text.to_enum(:scan, pattern).each do
        match = Regexp.last_match
        before = text[0, match.begin(0)]
        line = before.count("\n") + 1
        next if before[-[before.size, 80].min, 80].match?(ANOTHER_PROJECT)
        next if path.start_with?("doc/contributors/adr/") && text.lines[line - 1].match?(/\bsupersede/)

        match[1].scan(/\d{3}/).each { |number| found << [line, number] unless adrs.include?(number) }
      end
    end
    found
  end

  # The text of a tracked file that could cite an ADR, or nil for a
  # binary file, a deleted one, or one that names none.
  def read(path)
    full = File.join(ROOT, path)
    return unless File.file?(full)

    text = File.binread(full)
    return if text.include?("\0") || !(text.include?("ADR") || text.include?("adr/"))

    text.force_encoding(Encoding::UTF_8).scrub
  end

  def test_every_citation_names_an_adr_that_exists
    problems = tracked.reject { |path| EXEMPT.keys.any? { |exempt| path.start_with?(exempt) } }.flat_map do |path|
      text = read(path) or next []
      missing(path, text).map do |line, number|
        "#{path}:#{line} cites ADR #{number}, which doc/contributors/adr/ does not hold. Cite instead the " \
          "design document and section its reason moved to (git log --diff-filter=D -- " \
          "doc/contributors/adr/#{number}.md shows where), or an ADR that exists."
      end
    end

    assert_empty problems, problems.join("\n")
  end

  def test_each_exemption_names_a_tracked_file_or_folder
    files = tracked
    EXEMPT.each_key { |path| assert files.any? { |file| file.start_with?(path) }, "#{path} is exempt but not tracked" }
  end

  # The cases below plant a citation of a number no ADR has; the
  # interpolation keeps this file's own source from citing it.
  NONE = "999"
  OTHER = "998"

  def test_finds_a_citation_wrapped_across_comment_lines
    assert_equal [[1, NONE]], missing("lib/x.rb", "# as the launcher does (ADR\n  # #{NONE}).\n")
    assert_equal [[1, NONE]], missing("a.c", " * see ADRs 001 and\n *   #{NONE}\n")
    assert_equal [[1, NONE]], missing("a.md", "[it](../adr/#{NONE}.md)")
  end

  def test_finds_every_number_of_a_list
    assert_equal [[1, NONE], [1, OTHER]], missing("a.md", "ADRs 001, #{NONE}, and #{OTHER}")
  end

  def test_leaves_another_projects_adrs_alone
    assert_empty missing("a.c", "as Lota's launcher spike first did (setdef/lota, ADR #{NONE})")
    assert_empty missing("a.md", "Lota's ADR #{NONE} (`setdef/lota`, `doc/contributors/adr/#{NONE}.md`)")
  end

  def test_leaves_what_an_adr_supersedes_alone_in_an_adr_only
    line = "- This supersedes ADR #{NONE}, which it restates."
    assert_empty missing("doc/contributors/adr/001.md", line)
    assert_equal [[1, NONE]], missing("doc/contributors/design/x.md", line)
  end

  def test_reads_the_changelogs_unreleased_section_and_not_the_released_ones
    changelog = "# Changelog\n\n## [Unreleased]\n\n- A (ADR #{NONE})\n\n## [0.1.0] - 2026-01-01\n\n- B (ADR #{OTHER})\n"
    assert_equal [[5, NONE]], missing("CHANGELOG.md", changelog)
  end
end
