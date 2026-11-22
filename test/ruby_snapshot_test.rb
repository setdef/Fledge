# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require "rubygems/package"
require "stringio"
require "zlib"
require_relative "test_helper"
require_relative "../tasks/ruby_snapshot"

# The nightly run against Ruby's master moves the pins of the Rubies
# Fledge builds from source, and the license audit's evidence of Ruby's
# revision, to the day's snapshot, and leaves everything else as it is
# (doc/contributors/design/runtimes.md, "Testing against Ruby's master").
class RubySnapshotTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  SHA = "7b1d8b0094e8258360200ff6cdbd4ab3e181882fa4c5b02aba1bee2289a431f1"

  # snapshot-master.json as cache.ruby-lang.org served it on 2026-11-21,
  # less the sizes and the other digests.
  INDEX = <<~JSON
    [{"date":"2026-11-20","filename":{"gz":"snapshot-master.tar.gz","xz":"snapshot-master.tar.xz","zip":"snapshot-master.zip"},
      "sha256":{"gz":"#{SHA}","xz":"b273f67d267447af0a34f9f2f27f499e76e1f37132153500a6eb6abf327850f8"}}]
  JSON

  def snapshot
    RubySnapshot.parse(INDEX)
  end

  def test_reads_the_days_gzip_tarball_and_its_sha256_from_the_index
    assert_equal "2026-11-20", snapshot.date
    assert_equal "https://cache.ruby-lang.org/pub/ruby/snapshot/snapshot-master.tar.gz", snapshot.url
    assert_equal SHA, snapshot.sha256
  end

  def test_an_index_without_a_gzip_tarball_fails
    assert_raises(RubySnapshot::Error) { RubySnapshot.parse('[{"date":"2026-11-20","filename":{},"sha256":{}}]') }
    assert_raises(RubySnapshot::Error) { RubySnapshot.parse("[]") }
  end

  def test_reads_the_revision_from_the_tarballs_revision_h
    Dir.mktmpdir do |folder|
      tarball = File.join(folder, "snapshot-master.tar.gz")
      write_tarball(tarball, "snapshot-master/revision.h" => %(#define RUBY_REVISION "21ee43fb1e"\n#define RUBY_FULL_REVISION "21ee43fb1ea46e168a148b174ca1ce95c080e7cf"\n),
        "snapshot-master/ext/x/revision.h" => %(#define RUBY_REVISION "0000000000"\n))

      assert_equal "21ee43fb1e", RubySnapshot.revision(tarball)
    end
  end

  def test_a_tarball_without_revision_h_fails
    Dir.mktmpdir do |folder|
      tarball = File.join(folder, "snapshot-master.tar.gz")
      write_tarball(tarball, "snapshot-master/version.h" => "")

      assert_raises(RubySnapshot::Error) { RubySnapshot.revision(tarball) }
    end
  end

  # The real files, so a change to their shape fails here first.
  def test_moves_each_from_source_ruby_pin_to_the_snapshot_and_nothing_else
    before = File.read(File.join(ROOT, "runtime", "sources.yml"))
    after = snapshot.pin(before)
    pins = YAML.safe_load(after)

    RubySnapshot::FROM_SOURCE.each do |key|
      assert_equal snapshot.url, pins.dig(key, "ruby", "url")
      assert_equal SHA, pins.dig(key, "ruby", "sha256")
    end
    old = YAML.safe_load(before)
    assert_equal old.fetch("ruby"), pins.fetch("ruby")
    assert_equal old.except(*RubySnapshot::FROM_SOURCE), pins.except(*RubySnapshot::FROM_SOURCE)
    assert_equal before.lines.grep(/^\s*#/), after.lines.grep(/^\s*#/)
  end

  def test_moves_the_audits_evidence_of_the_from_source_rubys_revision
    before = File.read(File.join(ROOT, "runtime", "licenses.yml"))
    after = RubySnapshot.evidence(before, "21ee43fb1e")
    rubies = YAML.safe_load(after).fetch("components").select { |component| component.fetch("id") == "ruby" }
    android = rubies.find { |component| component.fetch("platforms").include?("android") }
    windows = YAML.safe_load(after).fetch("components").find { |component| component.fetch("id") == "ruby-windows" }

    assert_equal ["21ee43fb1e"], android.fetch("embedded").map { |embedded| embedded.fetch("evidence") }
    assert_equal YAML.safe_load(before).fetch("components").find { |c| c.fetch("id") == "ruby-windows" }, windows
    assert_equal before.lines.size, after.lines.size
  end

  private def write_tarball(path, files)
    io = StringIO.new
    Gem::Package::TarWriter.new(io) do |tar|
      files.each { |name, body| tar.add_file_simple(name, 0o644, body.bytesize) { |file| file.write(body) } }
    end
    Zlib::GzipWriter.open(path) { |gz| gz.write(io.string) }
  end
end
