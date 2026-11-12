# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require "minitest/test_task"
require_relative "test_tiers"

# Clear the default test task created by Minitest::TestTask if it exists
Rake::Task["test"].clear if Rake::Task.task_defined?("test")

# rake test runs the unit tier, rake test:integration the integration
# tier, and rake test:all both, as the gate does (tasks/test_tiers.rb).
# TEST names files to run instead, of either tier. Every test runs with
# Ruby's warnings on, so a warning shows in the gate's output instead of
# in a user's terminal.
{
  unit: "test",
  integration: "test:integration",
  all: "test:all",
}.each do |tier, name|
  Minitest::TestTask.create(name) do |t|
    t.test_globs = TestTiers.globs(tier, File.expand_path("..", __dir__), named: ENV.fetch("TEST", nil))
    t.warning = true
  end
end

{
  "test" => "Run the unit tests, or the files TEST names",
  "test:integration" => "Run the integration tests, or the files TEST names",
  "test:all" => "Run every test, as the gate does, or the files TEST names",
}.each do |name, comment|
  Rake::Task[name].clear_comments
  Rake::Task[name].comment = comment
end
