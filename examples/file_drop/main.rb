# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT-0
#++

# Drop: a file drop for the office or home network. Start it on one
# computer, open the address it prints on any phone or computer on the
# same network, sign in with the password it prints, and send files to
# the Drop folder in your home folder, or take the ones you put there.
#
#   ruby main.rb [-p PORT]     (built with Fledge: Drop [-p PORT])
#
# It listens on port 4567, Sinatra's, unless -p gives another.

require "sinatra"
require "fileutils"
require "securerandom"
require "socket"

# The folder Drop shares, in the home folder of whoever runs it.
FOLDER = File.join(Dir.home, "Drop")
# The password each device signs in with, new each time Drop starts:
# lower-case letters and digits, without l, o, 0 and 1, which are easy to
# misread.
PASSWORD = SecureRandom.alphanumeric(8, chars: [*"a".."z", *"2".."9"] - %w[l o])

$stdout.sync = true

# Sinatra listens on every address, 0.0.0.0, in production, so that other
# computers reach Drop; -o 127.0.0.1 keeps it to this computer.
set :environment, :production
set :quiet, true
set :server, "puma"
set :server_settings, Silent: true
set :protection, reaction: :deny

use Rack::Auth::Basic, "Drop" do |_name, password|
  Rack::Utils.secure_compare(password, PASSWORD)
end

on_start do
  FileUtils.mkdir_p(FOLDER)
  addresses = [settings.bind]
  addresses = Socket.ip_address_list.select(&:ipv4_private?).map(&:ip_address) if settings.bind == "0.0.0.0"
  addresses = ["localhost"] if addresses.empty?
  puts "Drop is sharing #{FOLDER}"
  puts "On a phone or computer on this network, open"
  addresses.each { |address| puts "  http://#{address}:#{settings.port}/" }
  puts "and sign in with the password #{PASSWORD} (any user name)."
  puts "Press Ctrl-C to stop."
end

helpers do
  def shared_files
    Dir.glob("*", base: FOLDER)
      .select { |name| File.file?(File.join(FOLDER, name)) }
      .sort_by { |name| -File.mtime(File.join(FOLDER, name)).to_f }
  end

  # Keeps an upload under the name it came with, made safe for any
  # system's files, and numbered beside a file of that name already
  # there, as browsers number a download.
  def keep(upload)
    name = File.basename(upload[:filename].tr("\\", "/")).gsub(/[\x00-\x1f<>:"|?*]/, "_").sub(/\A\.+/, "")
    name = "upload" if name.empty?
    extension = File.extname(name)
    1.step do |number|
      candidate = (number == 1) ? name : "#{File.basename(name, extension)} (#{number})#{extension}"
      File.open(File.join(FOLDER, candidate), "wbx") { |file| IO.copy_stream(upload[:tempfile], file) }
      return candidate
    rescue Errno::EEXIST
      next
    end
  end

  def size(bytes)
    units = %w[bytes KB MB GB TB]
    exponent = bytes.zero? ? 0 : [Math.log(bytes, 1024).floor, units.size - 1].min
    exponent.zero? ? "#{bytes} bytes" : format("%.1f %s", bytes / (1024.0 ** exponent), units[exponent])
  end

  def h(text)
    Rack::Utils.escape_html(text)
  end
end

get "/" do
  erb :index
end

post "/" do
  Array(params[:files]).compact.each { |upload| keep(upload) }
  redirect to("/")
end

get "/files/:name" do |name|
  halt 404 unless shared_files.include?(name)
  send_file File.join(FOLDER, name), disposition: :attachment
end
