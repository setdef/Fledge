# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT-0
#++

# Basket: a shopping list. Add what you need, tick it off in the shop,
# and clear the ticked items once you are home. The list is kept in
# basket.json in your home folder, saved at each change, since a phone
# may stop an app in the background without warning.
#
# This program is the list; the screen is the phone's own. On iOS the
# host in host/ios draws it with UIKit, and on Android the host in
# host/android with Android's views. The host passes this program the
# two ends of a pair of pipes, sends it a command a line, and draws the
# list it answers with. In a terminal it reads the commands you type:
#
#   ruby main.rb [--in FD --out FD]
#
#   add NAME    adds NAME to the list
#   tick ID     ticks the item ID, or unticks it
#   clear       removes the ticked items
#   list        changes nothing
#
# It answers each command, and starts, with the whole list as a line of
# JSON: [{"id":"4f1c2a9e","name":"Milk","done":false}, ...].

require "json"
require "optparse"
require "securerandom"

# The list, with the file it is kept in.
class Basket
  # The items, each a Hash of its "id", "name", and whether it is "done".
  attr_reader :items

  # The list kept in the file at +path+, or a new one if it has none.
  def initialize(path)
    @path = path
    @items = File.exist?(path) ? JSON.parse(File.read(path)) : []
  end

  # Does what +line+ says, and saves the list.
  def call(line)
    command, argument = line.chomp.split(" ", 2)
    case command
    when "add" then add(argument.to_s.strip)
    when "tick" then @items.find { |item| item["id"] == argument }&.then { |item| item["done"] = !item["done"] }
    when "clear" then @items.reject! { |item| item["done"] }
    when "list" then nil
    else warn "Basket knows no command #{line.chomp.inspect}"
    end
    save
  end

  private def add(name)
    @items << { "id" => SecureRandom.hex(4), "name" => name, "done" => false } unless name.empty?
  end

  # Writes the list beside its file, then puts it in the file's place, so
  # that an app stopped as it writes leaves the list as it was.
  private def save
    File.write("#{@path}.new", JSON.pretty_generate(@items))
    File.rename("#{@path}.new", @path)
  end
end

input = $stdin
output = $stdout
OptionParser.new do |options|
  options.on("--in FD", Integer, "read commands from the file descriptor FD") { |fd| input = IO.for_fd(fd, "r") }
  options.on("--out FD", Integer, "write the list to the file descriptor FD") { |fd| output = IO.for_fd(fd, "w") }
end.parse!
output.sync = true

basket = Basket.new(File.join(Dir.home, "basket.json"))
output.puts JSON.generate(basket.items)
input.each_line do |line|
  basket.call(line)
  output.puts JSON.generate(basket.items)
end
