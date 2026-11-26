# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

# The rules that give a Ruby file's header its shape: frozen_string_literal
# first, then an empty line, then the SPDX lines between "#--" and "#++"
# (which RDoc leaves out of its output), then an empty line. The gate
# fixes a file that lacks the shape (rake reuse:normalize_ruby,
# tasks/lint.rake, by RubyHeader.fix), and the fast check before a push
# (rake check, tasks/check.rake; CONTRIBUTING.md, "Before a push")
# reports it by RubyHeader.check, which writes nothing. Both apply the
# same rules (RubyHeader.normalize), so they cannot disagree.
module RubyHeader
  # The extensions of the files the rules apply to.
  EXTENSIONS = %w[rb rake gemspec].freeze
  # The folders, and the dot-files, the rules leave alone.
  SKIPPED = %r{\A(?:vendor/|tmp/|dist/|\.)}
  # The command that fixes what the check reports.
  FIX = "mise x -- bundle exec rake reuse:normalize_ruby"
  # The SPDX lines of a header: from the copyright line to the license line.
  SPDX = /(# SPDX-FileCopyrightText:[^\n]+\n(?:#[^\n]*\n)*# SPDX-License-Identifier:[^\n]+\n)/m

  extend self

  # The paths in +paths+ the rules apply to.
  def among(paths)
    paths.select { |path| EXTENSIONS.include?(File.extname(path).delete(".")) && !path.match?(SKIPPED) }
  end

  # The Ruby files under +root+ the rules apply to, relative to it.
  def files(root)
    among(Dir.glob("**/*.{#{EXTENSIONS.join(',')}}", base: root))
  end

  # +content+ with its header in the shape, or +content+ itself when it
  # has no SPDX header.
  def normalize(content)
    return content unless content.match?(/# SPDX-/)

    spdx = content.match(SPDX)&.[](1)
    return content unless spdx

    rest = content
      .sub(/^# frozen_string_literal: true\n+/, "")
      .sub(/^#--\s*\n/, "")
      .sub(spdx, "")
      .sub(/^#\+\+\s*\n/, "")
      .sub(/\A\n+/, "")
    frozen = content.match?(/^# frozen_string_literal: true/) ? "# frozen_string_literal: true\n\n" : ""
    "#{frozen}#--\n#{spdx}#++\n\n#{rest}"
  end

  # What the rules would change in each of +paths+ under +root+, one
  # sentence for each, ending with the command that fixes it. Writes
  # nothing.
  def check(root, paths)
    among(paths).filter_map do |path|
      content = File.read(File.join(root, path))
      fixed = normalize(content)
      next if fixed == content

      "#{path}: #{difference(content, fixed)}; run #{FIX}"
    end
  end

  # Writes the rules' result to each of +paths+ under +root+ that
  # changes, and returns those paths.
  def fix(root, paths)
    among(paths).select do |path|
      file = File.join(root, path)
      content = File.read(file)
      fixed = normalize(content)
      next false if fixed == content

      File.write(file, fixed)
      true
    end
  end

  # The first line at which +content+ and +fixed+ part, as a sentence.
  private def difference(content, fixed)
    have = content.lines
    want = fixed.lines
    index = have.zip(want).index { |a, b| a != b } || [have.size, want.size].min
    "line #{index + 1} is #{have[index].to_s.chomp.inspect}, and the header's shape needs #{want[index].to_s.chomp.inspect} there"
  end
end
