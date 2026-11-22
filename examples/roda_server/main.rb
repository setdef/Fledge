# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT-0
#++

# Jot: a notes board in the browser, served from this computer to this
# computer only. Starting it prints its address and opens it in the
# browser; a note typed there is kept in the person's data folder
# (notes.rb) and is there the next time Jot starts.
#
#   Jot [--port N] [--no-browser]
#
#   --port N      listens on port N instead of 8765
#   --no-browser  prints the address and opens no browser
#   Ctrl-C        stops the server, which finishes the request it is
#                 answering, says so, and ends with status 0; so does TERM
#
# A server suits technical and internal users, at home with a terminal
# and a browser, as Jupyter's and Syncthing's are; people who expect a
# window are better served by a windowed app. Here the console window is
# the app: closing it stops Jot, and closing the browser's tab does not.
# If port 8765 is taken, Jot says so and ends with status 69
# (EX_UNAVAILABLE, sysexits.h), since a second Jot on another port would
# write the same notes file.
#
# The simplest server is WEBrick alone, with a block for each page. Jot is
# a Rack app instead, as most Ruby web apps are, so it would run unchanged
# on Puma or any other Rack server, and Roda gives it routes and HTML
# escaping with no gem but Rack. WEBrick serves it because WEBrick is
# plain Ruby, and one person on one computer needs no more; Puma compiles
# two C extensions on each system, and links its computer's OpenSSL.
#
# It listens on 127.0.0.1 alone, so nothing on the network can reach it.
# A page from any website the browser has open can still send requests
# to 127.0.0.1, so Jot answers only requests that name it by its own
# address, which a site cannot do through DNS rebinding, as Jupyter
# checks, and changes notes only for a form on its own page, by the
# browser's Sec-Fetch-Site and Origin headers, as Go's net/http
# CrossOriginProtection checks them.

require "optparse"
require "rackup/handler/webrick"
require "roda"
require "socket"
require_relative "notes"

# The notes board: one page that lists the notes and takes a new one.
class Jot < Roda
  plugin :default_headers, "content-type" => "text/html; charset=utf-8"
  plugin :h
  plugin :status_303

  route do |r|
    allowed = ["127.0.0.1:#{opts[:port]}", "localhost:#{opts[:port]}"]
    r.halt [421, { "content-type" => "text/plain" }, ["Jot answers at http://127.0.0.1:#{opts[:port]}/ only.\n"]] unless allowed.include?(r.host_with_port)

    r.root { page(opts[:notes].all) }

    r.post do
      site = r.get_header("HTTP_SEC_FETCH_SITE")
      origin = r.get_header("HTTP_ORIGIN")
      crossed = site ? !%w[same-origin none].include?(site) : origin && origin != "http://#{r.host_with_port}"
      r.halt [403, { "content-type" => "text/plain" }, ["Jot changes notes only from its own page.\n"]] if crossed

      r.is("notes") do
        opts[:notes].add(r.params["text"])
        r.redirect "/"
      end
      r.is("notes", Integer, "delete") do |id|
        opts[:notes].delete(id)
        r.redirect "/"
      end
    end
  end

  # The page, with the notes newest first.
  def page(notes)
    items = notes.map do |note|
      <<~HTML
        <li><p>#{h(note.text)}</p>
          <form method="post" action="/notes/#{note.id}/delete"><time datetime="#{note.at}">#{note.at.tr('T', ' ').chomp('Z')} UTC</time>
          <button>Delete</button></form></li>
      HTML
    end
    <<~HTML
      <!DOCTYPE html>
      <html lang="en">
      <head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>Jot</title>
      <style>
        body { font: 1rem/1.5 system-ui, sans-serif; max-width: 40rem; margin: 2rem auto; padding: 0 1rem; color-scheme: light dark; }
        textarea { width: 100%; box-sizing: border-box; font: inherit; }
        ul { list-style: none; padding: 0; } li { border-top: 1px solid #8884; padding: .5rem 0; }
        li p { margin: 0 0 .25rem; white-space: pre-wrap; } li form { display: flex; gap: 1rem; align-items: center; font-size: .875rem; opacity: .8; }
      </style></head>
      <body>
      <h1>Jot</h1>
      <form method="post" action="/notes"><label for="text">New note</label>
      <textarea id="text" name="text" rows="3" maxlength="#{Notes::LONGEST}" required autofocus></textarea>
      <button>Keep it</button></form>
      #{notes.empty? ? '<p>No notes yet.</p>' : "<ul>\n#{items.join}</ul>"}
      <p><small>Kept in #{h(opts[:notes].folder)}</small></p>
      </body></html>
    HTML
  end
end

# Opens +url+ in the person's browser, with the command each system has
# for it, and carries on if there is none, since the address is printed.
def open_browser(url)
  command = case RbConfig::CONFIG["host_os"]
            when /darwin/ then ["open", url]
            when /mingw|mswin/ then ["cmd.exe", "/c", "start", "", url]
            else ["xdg-open", url]
  end
  Process.detach(Process.spawn(*command, in: File::NULL, out: File::NULL, err: File::NULL))
rescue SystemCallError
  nil
end

# Listens on 127.0.0.1 at +port+, or raises Errno::EADDRINUSE when another
# program does. WEBrick would listen through Socket.tcp_server_sockets,
# which sets SO_REUSEADDR, and on Windows that option lets a second
# program listen on a port that is taken; SO_EXCLUSIVEADDRUSE refuses it,
# as SO_REUSEADDR already does on macOS and Linux, where it only lets Jot
# start again at once on the port it just left.
def listen(port)
  socket = Socket.new(:INET, :STREAM)
  option = Gem.win_platform? ? ~Socket::SO_REUSEADDR : Socket::SO_REUSEADDR
  socket.setsockopt(Socket::SOL_SOCKET, option, 1)
  socket.bind(Addrinfo.tcp("127.0.0.1", port))
  socket.listen(Socket::SOMAXCONN)
  socket.autoclose = false
  TCPServer.for_fd(socket.fileno)
end

if $PROGRAM_NAME == __FILE__
  port = 8765
  browser = true
  OptionParser.new do |options|
    options.banner = "Usage: Jot [--port N] [--no-browser]"
    options.on("--port N", Integer, "Listen on port N (default 8765)") { |n| port = n }
    options.on("--no-browser", "Open no browser") { browser = false }
  end.parse!

  url = "http://127.0.0.1:#{port}/"
  Jot.opts[:port] = port
  Jot.opts[:notes] = Notes.new(Notes.folder("Jot"))
  $stdout.sync = true
  begin
    listener = listen(port)
    Rackup::Handler::WEBrick.run(Jot.freeze.app, Host: "127.0.0.1", Port: port, DoNotListen: true, AccessLog: [],
      Logger: WEBrick::Log.new($stderr, WEBrick::Log::WARN)) do |server|
      server.listeners << listener
      %w[INT TERM].each { |signal| trap(signal) { server.shutdown } }
      puts "Jot is at #{url}", "Press Ctrl-C to stop it."
      open_browser(url) if browser
    end
  rescue Errno::EADDRINUSE
    warn "Jot cannot start: port #{port} is in use, perhaps by a Jot already running at #{url}"
    exit 69
  end
  puts "Jot stopped. Your notes are in #{Jot.opts[:notes].folder}"
end
