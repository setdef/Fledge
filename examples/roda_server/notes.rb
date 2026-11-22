# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT-0
#++

require "fileutils"
require "json"
require "rbconfig"

# Jot's notes, kept in one JSON file in the person's data folder, never in
# the app's own folder: an app may sit where its user cannot write, as in
# /Applications or a Linux AppImage, and an update replaces that folder.
#
# Every change is written before the page answers, to a new file that then
# takes the old one's place, so a note is never half written and nothing
# waits for the server to stop: a closed console window on Windows ends
# the program at once, before any +ensure+ or +at_exit+ runs, under
# <tt>ruby main.rb</tt> as in the app.
class Notes
  # One note: its number, its text, and when it was written (ISO 8601, UTC).
  Note = Data.define(:id, :text, :at)

  # The longest note kept, in characters.
  LONGEST = 10_000

  # The folder each system keeps an app's data in: Application Support on
  # macOS (Apple's File System Programming Guide), the roaming AppData
  # folder on Windows, which follows a person to each computer they sign
  # in to, and the XDG data folder on Linux (XDG Base Directory
  # Specification, which ignores a relative +XDG_DATA_HOME+). These are the
  # folders Python's platformdirs gives as a user's data folder.
  def self.folder(name, os: RbConfig::CONFIG["host_os"], env: ENV, home: Dir.home)
    case os
    when /darwin/ then File.join(home, "Library", "Application Support", name)
    when /mingw|mswin/ then File.join(env.fetch("APPDATA") { File.join(home, "AppData", "Roaming") }.tr("\\", "/"), name)
    else
      data = env["XDG_DATA_HOME"].to_s
      data = File.join(home, ".local", "share") unless data.start_with?("/")
      File.join(data, name.downcase)
    end
  end

  # The folder the notes are in.
  attr_reader :folder

  # Reads the notes in +folder+, which need not exist until the first note.
  def initialize(folder)
    @folder = folder
    @file = File.join(folder, "notes.json")
    @lock = Mutex.new
    saved = File.exist?(@file) ? JSON.parse(File.read(@file, encoding: "UTF-8")) : {}
    @next = saved.fetch("next", 1)
    @notes = saved.fetch("notes", []).map { |note| Note.new(**note.transform_keys(&:to_sym)) }
  end

  # Every note, the newest first.
  def all
    @lock.synchronize { @notes.reverse }
  end

  # Keeps +text+ as a new note and returns it, or returns nil when the text
  # is blank. Text past LONGEST characters is cut there.
  def add(text, at: Time.now)
    text = text.to_s.strip[0, LONGEST]
    return if text.empty?

    @lock.synchronize do
      note = Note.new(id: @next, text:, at: at.utc.strftime("%FT%TZ"))
      @next += 1
      @notes << note
      save
      note
    end
  end

  # Forgets the note numbered +id+. A number is never given again.
  def delete(id)
    @lock.synchronize do
      @notes.reject! { |note| note.id == id }
      save
    end
  end

  private def save
    FileUtils.mkdir_p(@folder)
    fresh = "#{@file}.#{Process.pid}.new"
    File.write(fresh, JSON.pretty_generate({ "next" => @next, "notes" => @notes.map(&:to_h) }), encoding: "UTF-8")
    File.rename(fresh, @file)
  end
end
