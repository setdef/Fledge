# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# Spike (experiment/path-probe only): summarizes drive.sh's and
# drive.ps1's results, ROOT standing for the app's folder.
#
#   ruby summarize.rb OUTDIR...

require "json"

KEYS = %w[executable __FILE__ __dir__ $0 $PROGRAM_NAME Process.argv0 RbConfig.ruby Gem.ruby prefix bindir libdir
          rubylibdir archdir Gem.dir Gem.default_dir Gem.bindir Dir.pwd].freeze

def show(value, root)
  case value
  when Hash
    return JSON.generate(value).then { |t| root ? t.gsub(root, "ROOT") : t } unless value.key?("absolute")

    text = value["value"].to_s
    text = text.gsub(root, "ROOT") if root
    flags = []
    flags << "RELATIVE" unless value["absolute"]
    flags << "MISSING" unless value["exists"]
    flags << value["encoding"] unless value["encoding"] == "UTF-8"
    flags.empty? ? text : "#{text} [#{flags.join(' ')}]"
  when Array then "[#{value.map { |v| show(v, root) }.join(', ')}]"
  when String then root ? value.gsub(root, "ROOT") : value
  else value.inspect
  end
end

ARGV.each do |dir|
  Dir[File.join(dir, "**", "*.result")].sort.each do |result|
    lines = File.read(result, encoding: "UTF-8").scrub.lines
    head = JSON.parse(lines.first)
    gens = File.exist?(result.sub(/\.result\z/, ".jsonl")) ? File.readlines(result.sub(/\.result\z/, ".jsonl")).map { |l| JSON.parse(l) } : []
    root = gens.first && gens.first.dig("__FILE__", "value")&.sub(%r{[/\\]app[/\\]main\.rb\z}, "")
    puts "=== #{File.basename(result, '.result')}: status #{head['status']}, generations #{gens.count { |g| g.key?('pid') }}"
    puts "    ROOT=#{root}"
    stderr = lines.drop(1).reject { |l| l.match?(/(csv|fiddle) used to be loaded|You can add (csv|fiddle)/) }.join.strip
    puts "    stderr: #{stderr.gsub(root.to_s, 'ROOT')[0, 600]}" unless stderr.empty?
    gens.each do |g|
      if g.key?("exec failed")
        puts "    gen #{g['gen']}: exec failed: #{show(g['exec failed'], root)}"
        next
      end
      puts "    gen #{g['gen']} pid #{g['pid']}:"
      KEYS.each { |k| puts "      #{k}: #{show(g[k], root)}" }
      puts "      Gem.path: #{show(g['Gem.path'], root)}"
      %w[ruby_install_name ARGV PATH require\ json require\ i18n require\ csv\ (bundled\ gem) Bundler bundler/setup\ loaded
         Bundler.original_env\ (RUBYOPT,\ GEM_HOME,\ BUNDLE_GEMFILE) Gem.loaded_specs Encoding.default_external
         locale_charmap env config_paths_outside_prefix cocoa lsappinfo windows\ console].each do |k|
        puts "      #{k}: #{show(g[k], root)}" if g.key?(k)
      end
    end
  end
end
