# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require "yaml"
require_relative "github_api"

# Enables each of the repository's scheduled workflows again, so that
# GitHub, which disables a public repository's scheduled workflows after
# 60 days in which nothing happened in it, never finds one to disable: a
# quiet repository is the pin watch's happy path, and a disabled schedule
# fails no run, so nobody would hear of it
# (doc/contributors/design/runtimes.md, "A quiet repository"). It takes
# the step liskin/gh-workflow-keepalive takes, one PUT to a workflow's
# enable endpoint, for every scheduled workflow, not only the one that
# runs it.
#
#   KeepSchedules.new(github, dry_run: false).call(KeepSchedules.scheduled("."))
#   # => ["pin-watch.yml: active; enabled again", ...]
#
# A workflow a person disabled (disabled_manually) is left as it is. One
# GitHub disabled for inactivity is enabled, and its line begins with
# ::warning::, which GitHub shows on the run.
class KeepSchedules
  # The states of a workflow GitHub's API gives that the job enables: an
  # active one keeps its schedule by being enabled again, and one GitHub
  # disabled for inactivity gets it back.
  ENABLED = %w[active disabled_inactivity].freeze

  # The file names of the workflows under +root+ that a schedule starts.
  def self.scheduled(root)
    Dir[File.join(root, ".github/workflows/*.yml")].select do |path|
      workflow = YAML.load_file(path, aliases: true)
      triggers = workflow.fetch(true) { workflow["on"] }
      triggers.is_a?(Hash) && triggers.key?("schedule")
    end.map { |path| File.basename(path) }
  end

  # +github+ is a GitHubAPI for the repository; with +dry_run+, the states
  # are read and nothing is enabled.
  def initialize(github, dry_run:)
    @github = github
    @dry_run = dry_run
  end

  # Enables each workflow of +files+ that ENABLED holds, and returns a
  # line for each that says what was found and done.
  def call(files)
    files.map do |file|
      path = "actions/workflows/#{file}"
      state = @github.get(path).fetch("state")
      next "#{file}: #{state}, a person's choice; left as it is" unless ENABLED.include?(state)

      @github.put("#{path}/enable") unless @dry_run
      done = @dry_run ? "would be enabled again (dry run)" : "enabled again"
      (state == "active") ? "#{file}: active; #{done}" : "::warning::#{file}: GitHub had disabled it for inactivity; #{done}"
    end
  end
end

# ruby tasks/keep_schedules.rb [--dry-run]
# with GITHUB_REPOSITORY and GH_TOKEN, as a workflow's step has them.
# Exits nonzero only when GitHub's API refuses, so the failed run calls
# a person.
if $PROGRAM_NAME == __FILE__
  github = GitHubAPI.new(repository: ENV.fetch("GITHUB_REPOSITORY"), token: ENV.fetch("GH_TOKEN"))
  begin
    puts KeepSchedules.new(github, dry_run: ARGV.include?("--dry-run")).call(KeepSchedules.scheduled(File.expand_path("..", __dir__)))
  rescue GitHubAPI::Error => e
    abort "keep_schedules: #{e.message}"
  end
end
