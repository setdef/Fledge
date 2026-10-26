# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "socket"

# A real HTTP server on the loopback interface, serving a fixed table of
# routes, so Fledge::Download is tested through Net::HTTP itself.
class LoopbackServer
  attr_reader :requests

  def initialize(routes)
    @routes = routes
    @server = TCPServer.new("127.0.0.1", 0)
    @requests = []
    @thread = Thread.new { loop { serve(@server.accept) } }
  end

  def url(path)
    "http://127.0.0.1:#{@server.addr[1]}#{path}"
  end

  def stop
    @thread.kill
    @server.close
  end

  private def serve(client)
    path = client.gets.to_s.split[1].to_s
    @requests << path
    nil until client.gets.to_s.chomp.empty?
    status, headers, body = @routes.fetch(path) { [404, {}, "missing"] }
    headers = headers.merge("Content-Length" => body.bytesize.to_s, "Connection" => "close")
    client.write("HTTP/1.1 #{status} X\r\n#{headers.map { |k, v| "#{k}: #{v}\r\n" }.join}\r\n#{body}")
  ensure
    client.close
  end
end
