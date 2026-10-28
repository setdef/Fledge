# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "json"

class Parity
  # What the probe reports, read, made comparable across two runs, and
  # compared: every fact that differs, and whether JUSTIFIED explains
  # each difference.
  module Reports
    # The JSON report in a probe's standard output.
    def self.report(output)
      line = output.lines.reverse.find { |candidate| candidate.start_with?("FLEDGE-PARITY ") }
      raise "the probe printed no report:\n#{output}" unless line

      JSON.parse(line.delete_prefix("FLEDGE-PARITY "))
    end

    # +report+ with every path it names relative to a placeholder: <app>
    # (the probe's own folder), <project> (its project's root, when that is
    # another), <prefix>, <home>, and <work> (+work+), with backslashes as
    # slashes.
    def self.normalize(report, work:)
      paths = report.fetch("paths")
      tokens = { paths.fetch("project", paths.fetch("app")) => "<project>" }
      tokens[paths.fetch("app")] = "<app>"
      tokens.merge!(paths.fetch("prefix") => "<prefix>", paths.fetch("home") => "<home>", work => "<work>")
      replacements = tokens.flat_map { |path, token| variants(path).map { |variant| [variant, token] } }.sort_by { |path, _| -path.size }
      rewrite(report.except("paths"), replacements)
    end

    def self.variants(path)
      [path, path.tr("\\", "/"), File.realpath(path).tr("\\", "/")].uniq
    rescue SystemCallError
      [path, path.tr("\\", "/")].uniq
    end

    def self.rewrite(value, replacements)
      case value
      when String then replacements.reduce(value.tr("\\", "/")) { |text, (path, token)| text.gsub(path.tr("\\", "/"), token) }
      when Array then value.map { |element| rewrite(element, replacements) }
      when Hash then value.to_h { |key, element| [rewrite(key, replacements), rewrite(element, replacements)] }
      else value
      end
    end

    # A fact as a list of strings to compare: each element of an Array, in
    # order, each KEY=VALUE of a Hash, sorted, or the one value of anything
    # else. A Hash's order is how the environment happened to be built (the
    # launcher puts the person's variables back after Ruby boots, and
    # Bundler adds its own), not something Ruby promises an app.
    def self.elements(value)
      case value
      when Array then value.map { |element| JSON.generate(element) }
      when Hash then value.map { |key, element| "#{JSON.generate(key)}=#{JSON.generate(element)}" }.sort
      else [JSON.generate(value)]
      end
    end

    # The facts that differ between two normalized reports, for the script
    # check or, with +check+ :bundle, the gem-shaped one. A difference is
    # justified when every element found on one side only is explained by
    # some justification for that fact, and the elements both sides share
    # come in the same order.
    def self.compare(reference, app, platform:, check: :script)
      (reference.keys | app.keys).filter_map do |fact|
        expected = elements(reference[fact])
        actual = elements(app[fact])
        next if expected == actual

        only_in_reference = expected - actual
        only_in_app = actual - expected
        applicable = JUSTIFIED.select { |candidate| candidate.applies?(fact, platform, check) }
        used = only_in_reference.map { |element| applicable.find { |candidate| candidate.explains?(element, :reference) } } +
          only_in_app.map { |element| applicable.find { |candidate| candidate.explains?(element, :app) } }
        justified = !used.empty? && used.none?(&:nil?) && (expected - only_in_reference) == (actual - only_in_app)
        Difference.new(fact:, only_in_reference:, only_in_app:, justifications: justified ? used.compact.uniq : [])
      end
    end
  end
end
