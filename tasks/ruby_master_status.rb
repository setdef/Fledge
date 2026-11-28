# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require "json"

# What the nightly run against Ruby's master has found, kept in the body
# of one issue.
#
# Ruby's master breaks now and then, and stays broken until Ruby's
# committers fix it. A run that failed every night of such a week would
# send the maintainer a failure email every night, and teach everyone
# to read red as noise, while a job allowed to fail tells no one.
#
# This reads the state a body holds, records a night's result in it,
# and says whether that night is news: a job failed that had not been
# failing. The workflow fails only then, and the body always says the
# newest master Fledge passed on, and the range of commits since.
#
#   status = RubyMasterStatus.read(body).record(night)
#   status.body    # the issue's new body
#   status.news?   # whether the run fails
class RubyMasterStatus < Data.define(:passed, :failing, :news)
  # One night's run: the snapshot's revision and date, the jobs that
  # failed, and the run's URL.
  class Night < Data.define(:revision, :date, :failed, :run); end

  # The comment the state is kept in, in the body.
  MARK = "ruby-master-state"

  # The state the issue body +text+ holds, or none when a person
  # replaced it.
  def self.read(text)
    json = text[/<!-- #{MARK}: (.*?) -->/o, 1]
    state = json ? JSON.parse(json) : {}
    new(passed: state["passed"], failing: state["failing"], news: false)
  rescue JSON::ParserError
    new(passed: nil, failing: nil, news: false)
  end

  # The state after +night+.
  def record(night)
    seen = { "revision" => night.revision, "date" => night.date }
    return with(passed: seen.merge("run" => night.run), failing: nil, news: false) if night.failed.empty?

    known = failing ? failing.fetch("jobs") : []
    since = failing || seen.merge("run" => night.run)
    with(failing: since.merge("jobs" => (known | night.failed).sort), news: !(night.failed - known).empty?)
  end

  # Whether the night recorded was news, a job failing that had not been.
  def news?
    news
  end

  # The issue's body: what passed, what fails, and the state.
  def body
    [
      "Written by `.github/workflows/ruby-master.yml` each night; edit nothing below.",
      "",
      passed ? "Fledge last passed on Ruby's master of #{passed.fetch('date')}, #{passed.fetch('revision')} (#{passed.fetch('run')})." : "Fledge has not passed on Ruby's master yet.",
      "",
      *failing_lines,
      "<!-- #{MARK}: #{JSON.generate({ 'passed' => passed, 'failing' => failing })} -->",
      "",
    ].join("\n")
  end

  private def failing_lines
    return ["Nothing has failed since.", ""] unless failing

    range = passed ? "https://github.com/ruby/ruby/compare/#{passed.fetch('revision')}...#{failing.fetch('revision')}" : failing.fetch("revision")
    [
      "Failing since Ruby's master of #{failing.fetch('date')}, #{failing.fetch('revision')} (#{failing.fetch('run')}): " \
        "#{failing.fetch('jobs').join(', ')}.",
      "",
      "Ruby's commits that night brought in: #{range}",
      "",
    ]
  end
end

# ruby tasks/ruby_master_status.rb BODY REVISION DATE RUN [FAILED_JOB...]
# rewrites the file BODY and exits 3 when the night is news (1 is an
# exception's).
if $PROGRAM_NAME == __FILE__
  path, revision, date, run, *failed = ARGV
  status = RubyMasterStatus.read(File.exist?(path) ? File.read(path) : "").record(RubyMasterStatus::Night.new(revision:, date:, failed:, run:))
  File.write(path, status.body)
  puts status.body
  exit(status.news? ? 3 : 0)
end
