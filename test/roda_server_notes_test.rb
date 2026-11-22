# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "test_helper"
require_relative "../examples/roda_server/notes"
require "tmpdir"

# examples/roda_server's notes, apart from the server: where each system
# keeps them, and that each change is on disk before the page answers.
class RodaServerNotesTest < Minitest::Test
  def test_a_mac_keeps_the_notes_in_application_support
    folder = Notes.folder("Jot", os: "darwin25", env: {}, home: "/Users/ana")

    assert_equal "/Users/ana/Library/Application Support/Jot", folder
  end

  def test_windows_keeps_the_notes_in_the_roaming_app_data_folder
    folder = Notes.folder("Jot", os: "mingw32", env: { "APPDATA" => "C:\\Users\\ana\\AppData\\Roaming" }, home: "C:/Users/ana")

    assert_equal "C:/Users/ana/AppData/Roaming/Jot", folder
  end

  def test_linux_keeps_the_notes_in_the_xdg_data_home_or_its_default
    named = Notes.folder("Jot", os: "linux", env: { "XDG_DATA_HOME" => "/data/ana" }, home: "/home/ana")
    unnamed = Notes.folder("Jot", os: "linux-musl", env: {}, home: "/home/ana")

    assert_equal ["/data/ana/jot", "/home/ana/.local/share/jot"], [named, unnamed]
  end

  def test_a_relative_xdg_data_home_is_ignored_as_the_specification_says
    folder = Notes.folder("Jot", os: "linux", env: { "XDG_DATA_HOME" => "data" }, home: "/home/ana")

    assert_equal "/home/ana/.local/share/jot", folder
  end

  def test_a_new_folder_has_no_notes_and_no_file
    Dir.mktmpdir do |dir|
      notes = Notes.new(File.join(dir, "Jot"))

      assert_equal [[], false], [notes.all, File.exist?(File.join(dir, "Jot"))]
    end
  end

  def test_an_added_note_is_on_disk_for_the_next_start
    Dir.mktmpdir do |dir|
      Notes.new(dir).add("Call the printer people\n", at: Time.utc(2026, 11, 22, 9, 30))
      Notes.new(dir).add("Order toner", at: Time.utc(2026, 11, 22, 10))

      assert_equal [[2, "Order toner", "2026-11-22T10:00:00Z"], [1, "Call the printer people", "2026-11-22T09:30:00Z"]],
        Notes.new(dir).all.map { |note| [note.id, note.text, note.at] }
    end
  end

  def test_a_blank_note_is_not_kept
    Dir.mktmpdir do |dir|
      notes = Notes.new(dir)

      assert_nil notes.add(" \n\t")
      assert_empty notes.all
    end
  end

  def test_a_deleted_note_stays_deleted_and_its_number_is_not_reused
    Dir.mktmpdir do |dir|
      notes = Notes.new(dir)
      notes.add("one")
      notes.add("two")
      notes.delete(2)
      notes.add("three")

      assert_equal [[3, "three"], [1, "one"]], Notes.new(dir).all.map { |note| [note.id, note.text] }
    end
  end

  def test_saving_leaves_only_the_notes_file
    Dir.mktmpdir do |dir|
      Notes.new(dir).add("one")

      assert_equal ["notes.json"], Dir.children(dir)
    end
  end
end
