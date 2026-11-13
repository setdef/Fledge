# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require "socket"

# A real HTTP server on the loopback interface, serving a fixed table of
# routes, so Fledge::Download is tested through Net::HTTP itself.
class LoopbackServer
  attr_reader :requests, :authorizations

  # +routes+ is the table of paths (as a Hash, or written inline), each to
  # [status, headers, body], or to something whose call returns one, for a
  # route whose answer changes from one request to the next. A route's
  # own Content-Length wins over the body's, so a route can promise more
  # than it sends and close, as a connection broken off does. A body that
  # responds to +call+ is called with the connection once the headers are
  # sent, so a route can send its body slowly, or stop sending, as a
  # stalled server does. Each connection is served on a thread of its own,
  # so a stalled one holds up no other. With +credentials+
  # ("user:password"), every request without that HTTP Basic login gets
  # 401, as a credentialed gem server answers.
  def initialize(routes = {}, credentials: nil, **inline)
    @routes = inline.empty? ? routes : routes.merge(inline)
    @credentials = credentials
    @authorizations = []
    @server = TCPServer.new("127.0.0.1", 0)
    @requests = []
    @clients = []
    @thread = Thread.new { loop { serve_on_its_own(@server.accept) } }
  end

  def url(path)
    "http://127.0.0.1:#{@server.addr[1]}#{path}"
  end

  def stop
    @thread.kill
    @clients.each(&:kill)
    @server.close
  end

  private def login
    "Basic #{[@credentials.to_s].pack('m0')}"
  end

  private def serve_on_its_own(client)
    @clients << Thread.new { serve(client) }
  end

  private def serve(client)
    path = client.gets.to_s.split[1].to_s
    @requests << path
    authorization = nil
    while (line = client.gets.to_s.chomp) && !line.empty?
      authorization = line.split(": ", 2).last if line.downcase.start_with?("authorization:")
    end
    @authorizations << authorization
    answer = @routes.fetch(path) { [404, {}, "missing"] }
    status, headers, body = answer.respond_to?(:call) ? answer.call : answer
    status, headers, body = [401, { "WWW-Authenticate" => "Basic realm=\"gems\"" }, "login"] if @credentials && authorization != login
    headers = { "Connection" => "close" }.merge(headers)
    headers = { "Content-Length" => body.bytesize.to_s }.merge(headers) unless body.respond_to?(:call)
    client.write("HTTP/1.1 #{status} X\r\n#{headers.map { |k, v| "#{k}: #{v}\r\n" }.join}\r\n")
    body.respond_to?(:call) ? body.call(client) : client.write(body)
  rescue IOError, SystemCallError
    nil
  ensure
    client.close
  end
end
