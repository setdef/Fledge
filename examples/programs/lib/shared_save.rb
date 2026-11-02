# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: MIT-0
#++

require "json"
require "rbconfig"

# The save both of Shared Save's programs open.
#
# A game with a GUI and a command line keeps one save, so a player who
# quits one can go on in the other. Here the save is a file of JSON
# lines, one for each time a program opened it, saying which program it
# was, where its project is, and where its Ruby's library is. Built by
# Fledge, both programs must say the same project and the same Ruby, from
# the one folder they ship in (ADR 024).
module SharedSave
  # What +program+ writes in the save: its name, and the real paths of
  # this project and of Ruby's standard library.
  def self.facts(program)
    {
      "by" => program,
      "project" => File.realpath(File.expand_path("..", __dir__)),
      "ruby" => File.realpath(RbConfig::CONFIG.fetch("rubylibdir")),
    }
  end

  # The entries in the save at +path+, oldest first, or none when there
  # is no save yet.
  def self.entries(path)
    File.file?(path) ? File.readlines(path, chomp: true).map { |line| JSON.parse(line) } : []
  end

  # Adds +program+'s facts to the save at +path+.
  def self.record(path, program)
    File.open(path, "a") { |file| file.puts(JSON.generate(facts(program))) }
  end
end
