# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-FileComment: Adapted from tasks/license_audit/cli.rb on Fledge's
#   spike/permissive branch (58edf27d27912d062ccfa5c4960533a220c9eb24).
require "fileutils"
require "json"
require "optparse"
require "yaml"

class LicenseAudit
  # The command line:
  #
  #   ruby tasks/license_audit.rb --platform PLATFORM --tree DIR [--out DIR] [--write] [--expect FILE]
  #   ruby tasks/license_audit.rb --platform PLATFORM --sources DIR
  #
  # The first audits the tree, prints what it found, writes the SBOM and
  # NOTICES into --out (and with --write into the tree's notices/), and
  # exits 1 on any violation, or, with --expect, on any difference from
  # the violations that file lists. The second writes the platform's LGPL
  # source bundle into DIR.
  class CLI
    def initialize(arguments, out: $stdout)
      @arguments = arguments.dup
      @out = out
      @options = {}
    end

    def call
      parse
      return sources if @options[:sources]

      audit
    end

    private def parse
      OptionParser.new do |parser|
        parser.on("--platform NAME") { |value| @options[:platform] = value }
        parser.on("--tree DIR") { |value| @options[:tree] = value }
        parser.on("--out DIR") { |value| @options[:out] = value }
        parser.on("--write") { @options[:write] = true }
        parser.on("--expect FILE") { |value| @options[:expect] = value }
        parser.on("--sources DIR") { |value| @options[:sources] = value }
        parser.on("--version VERSION") { |value| @options[:version] = value }
      end.parse!(@arguments)
      raise OptionParser::MissingArgument, "--platform" unless @options[:platform]
    end

    private def version
      @options[:version] || File.read(File.join(ROOT, "lib", "fledge", "version.rb"))[/VERSION = "([^"]+)"/, 1].to_s
    end

    private def sources
      path = SourceBundle.new(platform: @options.fetch(:platform), version:).write(@options.fetch(:sources))
      @out.puts(path ? "Wrote #{path}" : "#{@options.fetch(:platform)} ships no LGPL library")
      0
    end

    private def audit
      tree = @options.fetch(:tree) { raise OptionParser::MissingArgument, "--tree" }
      audit = LicenseAudit.new(platform: @options.fetch(:platform), tree:, fledge_version: version)
      report = audit.call
      notices = Notices.new(report, version:, map: audit.map)
      outputs = { "sbom.spdx.json" => "#{JSON.pretty_generate(Spdx.new(report, version:).to_h)}\n", "NOTICES.txt" => notices.text }
      write(outputs, @options[:out]) if @options[:out]
      write(outputs, File.join(report.tree, "notices")) if @options[:write]
      summarize(report)
      verdict(LicenseAudit.problems(report, notices))
    end

    private def write(outputs, directory)
      FileUtils.mkdir_p(directory)
      outputs.each { |name, content| File.write(File.join(directory, name), content) }
    end

    private def summarize(report)
      present = report.present
      @out.puts "#{report.platform}: #{report.owners.size} files, #{report.binaries.size} compiled, #{present.size} components " \
        "(#{present.count(&:gem_dir)} gems)"
      present.reject(&:gem_dir).each { |component| @out.puts "  #{component.id} #{component.version}: #{component.license}" }
    end

    private def verdict(violations)
      if @options[:expect]
        expected = Array(YAML.safe_load_file(@options[:expect]))
        unexpected = violations.reject { |violation| expected.any? { |line| violation.start_with?(line) } }
        unmet = expected.reject { |line| violations.any? { |violation| violation.start_with?(line) } }
        violations.each { |violation| @out.puts "expected: #{violation}" unless unexpected.include?(violation) }
        unexpected.each { |violation| @out.puts "VIOLATION: #{violation}" }
        unmet.each { |line| @out.puts "EXPECTED BUT NOT FOUND: #{line}" }
        return (unexpected.empty? && unmet.empty?) ? 0 : 1
      end
      violations.each { |violation| @out.puts "VIOLATION: #{violation}" }
      @out.puts(violations.empty? ? "The runtime meets the license policy." : "#{violations.size} violations.")
      violations.empty? ? 0 : 1
    end
  end
end
