# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require "json"
require "net/http"
require "uri"

# Asks one repository's part of GitHub's REST API, as a workflow's
# steps can, with Net::HTTP alone.
#
# CI's own scripts read runs, jobs, and annotations from the API, and
# GitHub answers 502 now and then, and to some requests for 100 items a
# page every time. Each script asking on its own would repeat that
# lesson, or forget it.
#
# This class asks 50 items a page, follows the pages, and asks again
# after a pause while GitHub fails on its side, as CIRuns does with
# its own copy of the same lines. RunnerlessRuns asks through it, and
# CIRuns, which release.yml runs, can move onto it in a change of its
# own.
class GitHubAPI
  # GitHub's API answered something other than success.
  class Error < StandardError; end

  # Items asked for on each page. GitHub allows 100, but on 2026-11-03
  # it answered 502 to every request for 100 of the jobs of a run that
  # had been run again (41596806895), and answered 50 at once.
  PER_PAGE = 50

  # How many times a request is made when GitHub fails on its side (5xx).
  ATTEMPTS = 4

  # +pause+ is the seconds to wait before the first repeat of a request
  # GitHub failed on its side, doubled for each repeat after it.
  def initialize(repository:, token:, api: "https://api.github.com", pause: 5)
    @repository = repository
    @token = token
    @api = api.delete_suffix("/")
    @pause = pause
  end

  # Every item under +key+ on every page of the API's answer at +path+.
  def all(path, key, **query)
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
  def get(path, **query)
    JSON.parse(ask(Net::HTTP::Get, path, **query).body)
  end

  # Posts to +path+ with no body, asked again after a pause while GitHub
  # fails on its side.
  def post(path)
    ask(Net::HTTP::Post, path)
    nil
  end

  private def ask(verb, path, **query)
    uri = URI("#{@api}/repos/#{@repository}/#{path}#{"?#{URI.encode_www_form(query)}" unless query.empty?}")
    response = nil
    ATTEMPTS.times do |attempt|
      sleep(@pause * (2 ** (attempt - 1))) if attempt.positive?
      response = request(verb.new(uri))
      break unless response.is_a?(Net::HTTPServerError)
    end
    raise Error, "GitHub's API answered #{response.code} for #{verb::METHOD} #{uri}: #{response.body}" unless response.is_a?(Net::HTTPSuccess)

    response
  end

  private def request(request)
    request["Accept"] = "application/vnd.github+json"
    request["Authorization"] = "Bearer #{@token}"
    request["X-GitHub-Api-Version"] = "2022-11-28"
    uri = request.uri
    Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https") { |http| http.request(request) }
  end
end
