# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "test_helper"
require_relative "support/loopback_server"
require_relative "../tasks/github_api"

# How CI's scripts ask GitHub's API: again after GitHub fails on its
# side, as it answers 502 now and then, and never again after an answer
# that says the request itself is wrong. A loopback server stands in
# for GitHub, at its paths.
class GitHubAPITest < Minitest::Test
  RUN = "/repos/setdef/Fledge/actions/runs/1"

  def test_asks_again_while_github_fails_on_its_side
    answers = [[502, {}, "Bad Gateway"], [503, {}, "Unavailable"], [200, {}, '{"id":1}']]
    with_server(RUN => -> { answers.shift }) do |server, github|
      assert_equal({ "id" => 1 }, github.get("actions/runs/1"))
      assert_equal 3, server.requests.size
    end
  end

  def test_gives_up_after_its_attempts_and_says_what_github_answered
    with_server(RUN => [502, {}, "Bad Gateway"]) do |server, github|
      error = assert_raises(GitHubAPI::Error) { github.post("actions/runs/1") }
      assert_includes error.message, "502 for POST"
      assert_includes error.message, "Bad Gateway"
      assert_equal GitHubAPI::ATTEMPTS, server.requests.size
    end
  end

  def test_does_not_ask_again_when_the_request_is_wrong
    with_server(RUN => [403, {}, "rate limit exceeded"]) do |server, github|
      error = assert_raises(GitHubAPI::Error) { github.get("actions/runs/1") }
      assert_includes error.message, "403 for GET"
      assert_equal 1, server.requests.size
    end
  end

  def test_sends_the_token
    with_server(RUN => [200, {}, "{}"]) do |server, github|
      github.get("actions/runs/1")
      assert_equal ["Bearer secret"], server.authorizations
    end
  end

  private def with_server(routes)
    server = LoopbackServer.new(routes)
    yield server, GitHubAPI.new(repository: "setdef/Fledge", token: "secret", api: server.url(""), pause: 0)
  ensure
    server&.stop
  end
end
