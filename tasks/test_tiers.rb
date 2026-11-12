# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

# The two tiers of Fledge's tests (CONTRIBUTING.md, "The tests"). Every
# test file under test/integration is an integration test: it builds or
# runs a real runtime or app, compiles code, starts Ruby or a script, or
# reaches past this computer, and may take seconds. Every other test
# file under test is a unit test, which takes milliseconds anywhere.
# Rails draws the same line by folder: "rails test" runs every test but
# those in test/system, unless it is named, "rails test:system" runs
# those, and "rails test:all" runs both (Rails v8.1.1,
# railties/lib/rails/test_unit/runner.rb, lines 116-137, and
# railties/lib/rails/test_unit/testing.rake). Hanami and dry-rb keep
# spec/unit apart from spec/integration.
module TestTiers
  # The integration tier's folder, relative to the repository.
  INTEGRATION = "test/integration/"

  # Every test file, relative to +root+, sorted.
  def self.all(root)
    Dir.glob("test/**/*_test.rb", base: root).sort
  end

  # The test files of +tier+ (:unit, :integration or :all), relative to
  # +root+, sorted.
  def self.files(tier, root)
    integration, unit = all(root).partition { |path| path.start_with?(INTEGRATION) }
    { unit:, integration:, all: unit + integration }.fetch(tier)
  end

  # What a test task runs: the files +named+ lists, comma-separated
  # paths or globs, when it lists any, whatever their tier, as
  # "rake test TEST=test/foo_test.rb" runs just that file under
  # Rake::TestTask (rake 13.4.2, lib/rake/testtask.rb, lines 18-31 and
  # 165-167) and "rails test PATH" runs PATH; or else +tier+'s files.
  # Minitest::TestTask reads N, X, TESTOPTS and A but not TEST
  # (minitest 6.0.6, lib/minitest/test_task.rb, lines 166-181).
  def self.globs(tier, root, named: nil)
    (named.nil? || named.empty?) ? files(tier, root) : named.split(",")
  end
end
