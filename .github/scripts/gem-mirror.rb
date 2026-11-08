#!/usr/bin/env ruby
# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# A credentialed mirror of RubyGems.org on the loopback interface, for the
# job that builds examples/real_gems: Bundler's own mirror setting
# (BUNDLE_MIRROR__HTTPS://RUBYGEMS__ORG/) points the example's Bundler and
# Fledge at it, and its login setting (BUNDLE_127__0__0__1) gives them the
# password it asks for. It answers 401 to a request without that HTTP Basic
# login, forwards any other GET to RubyGems.org, and appends a line to its
# log for each request it served, so the job can check that the gems came
# through it.
#
#   gem-mirror.rb PORT USER:PASSWORD LOG

require "net/http"
require "socket"

port, login, log = ARGV.fetch(0), ARGV.fetch(1), ARGV.fetch(2)
expected = "Basic #{[login].pack("m0")}"
server = TCPServer.new("127.0.0.1", Integer(port))
$stdout.sync = true
puts "mirror listening on 127.0.0.1:#{port}"

def forward(path)
  uri = URI("https://rubygems.org#{path}")
  5.times do
    response = Net::HTTP.get_response(uri)
    return response unless response.is_a?(Net::HTTPRedirection)

    uri = URI.join(uri.to_s, response["location"])
  end
  raise "too many redirects for #{path}"
end

loop do
  Thread.start(server.accept) do |client|
    request = client.gets.to_s
    authorization = nil
    while (line = client.gets.to_s.chomp) && !line.empty?
      authorization = line.split(": ", 2).last if line.downcase.start_with?("authorization:")
    end
    path = request.split[1].to_s
    if authorization == expected
      response = forward(path)
      body = response.body.to_s
      headers = { "Content-Type" => response["content-type"].to_s, "Content-Length" => body.bytesize.to_s, "Connection" => "close" }
      client.write("HTTP/1.1 #{response.code} #{response.message}\r\n#{headers.map { |k, v| "#{k}: #{v}\r\n" }.join}\r\n#{body}")
      File.write(log, "#{request.split.first} #{path} #{response.code}\n", mode: "a")
    else
      client.write("HTTP/1.1 401 Unauthorized\r\nWWW-Authenticate: Basic realm=\"mirror\"\r\nContent-Length: 0\r\nConnection: close\r\n\r\n")
      File.write(log, "#{request.split.first} #{path} 401\n", mode: "a")
    end
  rescue StandardError => e
    warn "mirror: #{e.class}: #{e.message}"
  ensure
    client.close
  end
end
