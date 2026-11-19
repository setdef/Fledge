# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require "stringio"

# The fast check before a push (CONTRIBUTING.md, "Before a push"), which
# bin/check runs once the checkout is set up: the Provenance trailer of
# each commit about to be pushed (tasks/fast_check.rb), and each lint of
# the gate's that reads a file they change, over the files it changes
# where the lint can be narrowed so: RuboCop (on every file when its
# configuration or version changes), shellcheck, actionlint, and
# clang-format; then REUSE, Steep and the RBS checks when typed code
# changes, RDoc's coverage when documented code changes, and the unit
# tests. It runs each and then fails if any failed. RubyCritic, which
# fails nothing, the package check, and the integration tests are the
# gate's (rake), on every system, which CI runs after the push.
desc "The fast check before a push, of the commits since BASE (default: the upstream, or origin/trunk); bin/check sets up and runs it"
task :check, [:base] do |_task, arguments|
  require_relative "fast_check"
  require_relative "lint_files"
  require "rubocop"

  root = File.expand_path("..", __dir__)
  check = FastCheck.new(root:, base: arguments[:base])
  puts "Checking #{check.commits.size} commit(s) since #{check.base ? check.base[0, 12] : 'the last commit\'s parent'}"
  failures = check.unmarked.map { |commit| check.problem(commit) }
  failures.each { |failure| warn "❌ #{failure}" }

  listed = StringIO.new
  saved, $stdout = $stdout, listed
  RuboCop::CLI.new.run(["-L"])
  $stdout = saved
  targets = listed.string.lines.map(&:chomp)
  ruby = check.restyled? ? targets : check.among(targets)
  unless ruby.empty?
    puts "RuboCop on #{ruby.size} changed file(s)"
    failures << "RuboCop" unless RuboCop::CLI.new.run(["--force-exclusion", *ruby]).zero?
  end

  # actionlint passes without a word when it finds no shellcheck, so a
  # missing shellcheck fails here, as it does in lint:workflows.
  shellcheck = LintFiles.which("shellcheck")
  {
    LintFiles.shell(root) => (shellcheck && [shellcheck]),
    LintFiles.workflows(root) => (shellcheck && ["actionlint", "-shellcheck=#{shellcheck}"]),
    LintFiles.c(root) => %w[clang-format --dry-run --Werror],
  }.each do |files, command|
    changed = check.among(files)
    next if changed.empty?
    next failures << "#{changed.join(' ')}: no shellcheck on PATH to check with; mise install puts it there" unless command

    sh(*command, *changed) do |ok, _status|
      failures << "#{File.basename(command.first)} on #{changed.join(' ')}" unless ok
    end
  end

  steps = [
    "reuse:lint",
    *(%w[steep rbs:validate rbs:parity] if check.typed?),
    *("lint:safe_rdoc_coverage" if check.documented?),
    "test",
  ]
  steps.each do |step|
    Rake::Task[step].invoke
  rescue RuntimeError, SystemExit => e
    failures << "rake #{step}: #{e.message}"
  end

  abort "❌ bin/check failed:\n#{failures.map { |failure| "  #{failure}" }.join("\n")}" unless failures.empty?
  puts "✅ bin/check passed"
end
