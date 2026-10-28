# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# The parity probe: an app that reports what Ruby looks like from
# inside it.
#
# An app's Ruby code should run under Fledge exactly as it runs under
# ruby main.rb (ADR 003). tasks/parity.rb builds this app with fledge
# build, runs it, runs the same file with the Ruby the runtime came from
# as ruby main.rb, and compares the two reports.
#
# With no command, it prints one line, "FLEDGE-PARITY " followed by a
# JSON object of facts: the globals an app sees, what is loaded and
# loadable, RubyGems' paths, the encodings, the environment, and what a
# child Ruby sees. Under Bundler (bundle exec, or a built app with a
# Gemfile) it also reports the environment Bundler recorded as the one it
# started from, and what a child Ruby sees inside
# Bundler.with_original_env and Bundler.with_unbundled_env, which is how
# a Bundler app starts a person's own tools. Paths are raw; the
# comparison normalizes them. The arguments it was given are among the
# facts.
#
# Delivery, which has no Ruby to compare with, asks it one thing at a
# time instead:
#
#   parity child-env NAME   prints ENV[NAME] as a child Ruby started
#                           through RbConfig.ruby sees it, or (unset)
#   parity original-child-env NAME
#   parity unbundled-child-env NAME
#                           the same, for a child Ruby started inside
#                           Bundler.with_original_env or
#                           Bundler.with_unbundled_env, or (no Bundler)
#   parity gem-path         prints Gem.path, one folder per line
#
# It uses nothing but Ruby's standard library, so it runs under any Ruby
# 4.0.

require "json"
require "rbconfig"

# What a child Ruby, started as an app would start one, prints for
# +code+.
def child_ruby(code)
  IO.popen([RbConfig.ruby, "-e", code], err: File::NULL, &:read)
rescue SystemCallError => e
  "#{e.class}: #{e.message}"
end

# What a child Ruby prints for +code+ when Bundler's +method+
# (with_original_env or with_unbundled_env) starts it, or nil without
# Bundler.
def bundler_child_ruby(method, code)
  Bundler.public_send(method) { child_ruby(code) } if defined?(Bundler)
end

# The child's ENV as a Hash, through +start+, a method that runs code in
# a child Ruby, or nil when it ran none, or what went wrong when no child
# could start, as on a phone, where an app starts no programs.
def child_env(start, *)
  output = method(start).call(*, "require 'json'; print JSON.generate(ENV.to_h)")
  output && JSON.parse(output)
rescue JSON::ParserError
  output
end

# The features each gem's own files provide, so a gem named io-console
# is required as io/console and english as English.
def feature_of(spec)
  features = spec.files.filter_map { |file| file.sub(%r{\A(?:lib|ext/[^/]+)/}, "")[/\A(.+)\.(?:rb|so|bundle)\z/, 1] }
  candidates = [spec.name, spec.name.tr("-", "/")]
  candidates.each do |candidate|
    found = features.find { |feature| feature.casecmp?(candidate) }
    return found if found
  end
  candidates.last
end

# Gems whose require does more than load code: debug starts a debugger
# session, and test/unit runs every test case at exit. For these, the
# probe only checks that RubyGems can find the file.
RESOLVE_ONLY = %w[debug test-unit].freeze

def requireable(spec)
  feature = feature_of(spec)
  if RESOLVE_ONLY.include?(spec.name)
    return (Gem.find_files(feature).empty? && !$LOAD_PATH.resolve_feature_path(feature)) ? "missing" : "found"
  end

  require feature
  "loads"
rescue LoadError, StandardError => e
  "#{e.class}: #{e.message.lines.first.to_s.chomp}"
end

# The root of the project the probe runs in: Bundler's, when Bundler set
# it up (bundle exec, or a built gem-shaped app), and the probe's own
# folder otherwise.
def project_root
  (defined?(Bundler) && Bundler.respond_to?(:root)) ? Bundler.root.to_s : __dir__
end

def facts
  {
    "paths" => { "app" => __dir__, "project" => project_root, "prefix" => RbConfig::TOPDIR, "home" => Dir.home },
    "$0" => $0,
    "__FILE__" => __FILE__,
    "__dir__" => __dir__,
    "$PROGRAM_NAME" => $PROGRAM_NAME,
    "ARGV" => ARGV,
    "$LOAD_PATH" => $LOAD_PATH.map(&:to_s),
    "$LOADED_FEATURES" => $LOADED_FEATURES.sort,
    "RbConfig.ruby" => RbConfig.ruby,
    "RbConfig.ruby is a program" => File.file?(RbConfig.ruby) && File.executable?(RbConfig.ruby),
    "RbConfig.ruby runs" => child_ruby("print 6 * 7"),
    "Gem.ruby" => Gem.ruby,
    "Gem.path" => Gem.path,
    "Gem.dir" => Gem.dir,
    "gems" => Gem::Specification.map { |spec| "#{spec.name} #{spec.version}#{' (default)' if spec.default_gem?}" }.sort,
    "Encoding.default_external" => Encoding.default_external.name,
    "Encoding.default_internal" => Encoding.default_internal&.name,
    "Encoding.find('locale')" => Encoding.find("locale").name,
    "Encoding.find('filesystem')" => Encoding.find("filesystem").name,
    "$stdout.sync" => $stdout.sync,
    "$stderr.sync" => $stderr.sync,
    "$stdin.sync" => $stdin.sync,
    "$stdout.external_encoding" => $stdout.external_encoding&.name,
    "$VERBOSE" => $VERBOSE,
    "$DEBUG" => $DEBUG,
    "ENV" => ENV.to_h,
    "child ENV" => child_env(:child_ruby),
    "Bundler.original_env" => defined?(Bundler) ? Bundler.original_env : nil,
    "Bundler.unbundled_env" => defined?(Bundler) ? Bundler.unbundled_env : nil,
    "original child ENV" => child_env(:bundler_child_ruby, :with_original_env),
    "unbundled child ENV" => child_env(:bundler_child_ruby, :with_unbundled_env),
    "RUBY_PLATFORM" => RUBY_PLATFORM,
    "RUBY_DESCRIPTION" => RUBY_DESCRIPTION,
    "RubyVM::YJIT.enabled?" => defined?(RubyVM::YJIT) ? RubyVM::YJIT.enabled? : nil,
  }
end

case ARGV.first
when "child-env"
  puts child_ruby("print ENV.fetch(#{ARGV.fetch(1).inspect}, '(unset)')")
when "original-child-env", "unbundled-child-env"
  method = (ARGV.first == "original-child-env") ? :with_original_env : :with_unbundled_env
  puts bundler_child_ruby(method, "print ENV.fetch(#{ARGV.fetch(1).inspect}, '(unset)')") || "(no Bundler)"
when "gem-path"
  puts Gem.path
else
  report = facts
  # Last, since requiring changes $LOADED_FEATURES.
  report["requireable"] = Gem::Specification.to_h { |spec| [spec.name, requireable(spec)] }.sort.to_h
  puts "FLEDGE-PARITY #{JSON.generate(report)}"
end
