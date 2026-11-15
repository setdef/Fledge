# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require "stringio"

# The fast check before a push (CONTRIBUTING.md, "Before a push"), which
# bin/check runs once the checkout is set up: the Provenance trailer of
# each commit about to be pushed (tasks/fast_check.rb), RuboCop on the
# Ruby files they change, REUSE, Steep when typed code changed, and the
# unit tests. It runs each and then fails if any failed. The gate
# (rake), on every system, is CI's, after the push.
desc "The fast check before a push, of the commits since BASE (default: the upstream, or origin/trunk); bin/check sets up and runs it"
task :check, [:base] do |_task, arguments|
  require_relative "fast_check"
  require "rubocop"

  check = FastCheck.new(root: File.expand_path("..", __dir__), base: arguments[:base])
  puts "Checking #{check.commits.size} commit(s) since #{check.base ? check.base[0, 12] : 'the last commit\'s parent'}"
  failures = check.unmarked.map { |commit| check.problem(commit) }
  failures.each { |failure| warn "❌ #{failure}" }

  listed = StringIO.new
  saved, $stdout = $stdout, listed
  RuboCop::CLI.new.run(["-L"])
  $stdout = saved
  ruby = check.ruby(listed.string.lines.map(&:chomp))
  unless ruby.empty?
    puts "RuboCop on #{ruby.size} changed file(s)"
    failures << "RuboCop" unless RuboCop::CLI.new.run(["--force-exclusion", *ruby]).zero?
  end

  steps = ["reuse:lint", *("steep" if check.typed?), "test"]
  steps.each do |step|
    Rake::Task[step].invoke
  rescue RuntimeError, SystemExit => e
    failures << "rake #{step}: #{e.message}"
  end

  abort "❌ bin/check failed:\n#{failures.map { |failure| "  #{failure}" }.join("\n")}" unless failures.empty?
  puts "✅ bin/check passed"
end
