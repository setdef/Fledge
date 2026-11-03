# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "json"
require "net/http"
require "uri"

# Finds a commit's green run of ci.yml on a push to trunk, from GitHub's
# REST API.
#
# A release tags a commit only once CI has passed on it (AGENTS.md,
# Releasing), and publishes the runtimes CI built from that commit's
# parent (ADR 014). Running all of CI again on the tag proves nothing
# the push already proved, takes half an hour, and draws every flaky
# mirror and runner a second time; 0.2.0 was never published because
# that second run failed on a download unrelated to its runtimes.
#
# This class looks the push's run up instead. A run counts when it has
# finished and the latest attempt of every one of its jobs passed, or,
# where allowed, was skipped, so a run whose failed jobs were run again
# counts once they pass. release.yml and the pin commit's CI ask it for
# the run whose runtimes they check against the pins, and rake
# runtime:pin asks it for the run whose runtimes it pins, so all three
# take the same one.
#
#   ruby tasks/ci_runs.rb green COMMIT [--every-job] [--branch BRANCH]
#
# prints the run's ID, or fails saying which run is not green and why.
# It reads GITHUB_REPOSITORY, GITHUB_API_URL, and GH_TOKEN or
# GITHUB_TOKEN, as a workflow's steps have them.
class CIRuns
  # GitHub's API answered something other than success.
  class Error < StandardError; end

  # The commit has no run of the workflow that is green.
  class NotGreen < Error; end

  # The workflow whose runs count.
  WORKFLOW = "ci.yml"

  # Items asked for on each page. GitHub allows 100, but on 2026-11-03
  # it answered 502 to every request for 100 of the jobs of a run that
  # had been run again (41596806895), and answered 50 at once.
  PER_PAGE = 50

  # How many times a request is made when GitHub fails on its side (5xx).
  ATTEMPTS = 4

  # +pause+ is the seconds to wait before the first repeat of a request
  # GitHub failed on its side, doubled for each repeat after it.
  def initialize(repository:, token:, api: "https://api.github.com", branch: "trunk", pause: 5)
    @repository = repository
    @token = token
    @api = api.delete_suffix("/")
    @branch = branch
    @pause = pause
    @problems = {}
  end

  # The ID of the newest run of ci.yml on a push of +commit+ to the
  # branch that finished with every job's latest attempt a success, or
  # with +skipped+, a success or skipped. Raises NotGreen naming the
  # newest run and what is wrong with it when no run is green.
  def green(commit, skipped: true)
    runs = all("actions/workflows/#{WORKFLOW}/runs", "workflow_runs", head_sha: commit, branch: @branch, event: "push")
    raise NotGreen, "#{commit} has no run of #{WORKFLOW} on a push to #{@branch}: push it there and wait for CI to pass" if runs.empty?

    runs = runs.sort_by { |run| -run.fetch("id") }
    found = runs.find { |run| problems(run, skipped:).empty? }
    return found.fetch("id") if found

    newest = runs.first
    raise NotGreen, "CI run #{newest.fetch('html_url')} of #{commit} is not green: #{problems(newest, skipped:).join('; ')}"
  end

  # What keeps +run+ from counting: that it has not finished, and each
  # job whose latest attempt neither passed nor, with +skipped+, was
  # skipped.
  private def problems(run, skipped:)
    @problems[[run.fetch("id"), skipped]] ||= begin
      allowed = skipped ? %w[success skipped] : %w[success]
      if run.fetch("status") == "completed"
        jobs = all("actions/runs/#{run.fetch('id')}/jobs", "jobs", filter: "latest")
        failed = jobs.reject { |job| job.fetch("status") == "completed" && allowed.include?(job["conclusion"]) }
        list = failed.map { |job| "#{job.fetch('name')}: #{job['conclusion'] || job.fetch('status')}" }
        list << "the run's conclusion is #{run['conclusion']}" if list.empty? && run["conclusion"] != "success"
        list << "the run has no jobs" if jobs.empty?
        list
      else
        ["the run is #{run.fetch('status')}; wait for it to finish, then try again"]
      end
    end
  end

  # Every item under +key+ on every page of the API's answer at +path+.
  private def all(path, key, **query)
    items = []
    (1..).each do |page|
      answer = get(path, **query, per_page: PER_PAGE, page:)
      batch = answer.fetch(key)
      items.concat(batch)
      return items if batch.size < PER_PAGE || items.size >= answer.fetch("total_count")
    end
    items
  end

  # The API's answer at +path+, asked again after a pause while GitHub
  # fails on its side.
  private def get(path, **query)
    uri = URI("#{@api}/repos/#{@repository}/#{path}?#{URI.encode_www_form(query)}")
    response = nil
    ATTEMPTS.times do |attempt|
      sleep(@pause * (2 ** (attempt - 1))) if attempt.positive?
      response = request(uri)
      break unless response.is_a?(Net::HTTPServerError)
    end
    raise Error, "GitHub's API answered #{response.code} for #{uri}: #{response.body}" unless response.is_a?(Net::HTTPSuccess)

    JSON.parse(response.body)
  end

  private def request(uri)
    request = Net::HTTP::Get.new(uri)
    request["Accept"] = "application/vnd.github+json"
    request["Authorization"] = "Bearer #{@token}"
    request["X-GitHub-Api-Version"] = "2022-11-28"
    Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https") { |http| http.request(request) }
  end
end

if $PROGRAM_NAME == __FILE__
  command, commit = ARGV.shift(2)
  abort "usage: ruby tasks/ci_runs.rb green COMMIT [--every-job] [--branch BRANCH]" unless command == "green" && commit
  every = ARGV.delete("--every-job")
  branch = ARGV.include?("--branch") ? ARGV[ARGV.index("--branch") + 1] : "trunk"
  token = ENV["GH_TOKEN"] || ENV.fetch("GITHUB_TOKEN")
  runs = CIRuns.new(repository: ENV.fetch("GITHUB_REPOSITORY"), token:, api: ENV.fetch("GITHUB_API_URL", "https://api.github.com"), branch:)
  begin
    puts runs.green(commit, skipped: !every)
  rescue CIRuns::Error => e
    abort "#{'::error::' if ENV['GITHUB_ACTIONS']}#{e.message}"
  end
end
