# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "test_helper"
require_relative "support/disk_images"
require "open3"

# Fledge::Dmg: the app's bundle and a link to Applications, in a volume
# named after the app, in a compressed disk image, which a Mac attaches.
class DmgTest < Minitest::Test
  def write(dir, name: "My App")
    path = File.join(dir, "#{name}-arm64-darwin.dmg")
    dmg = Fledge::Dmg.new(name:, to: path, mtime: 1_700_000_000)
    dmg.add(Fledge::Entry.directory("#{name}.app"))
    dmg.add(Fledge::Entry.file("#{name}.app/Contents/MacOS/#{name}", "#!/bin/sh\n", mode: 0o755))
    [dmg, path]
  end

  def test_the_image_holds_the_bundle_and_a_link_to_applications
    Dir.mktmpdir do |dir|
      dmg, path = write(dir)
      assert_equal path, dmg.finish({})

      hfs = DiskImages::Hfs.new(DiskImages.udif(path)[:volume])
      assert_equal ["", "Applications", "My App.app", "My App.app/Contents", "My App.app/Contents/MacOS", "My App.app/Contents/MacOS/My App"],
        hfs.items.keys.sort
      assert_equal "/Applications", hfs.items.fetch("Applications")[:content]
      assert_equal "My App", hfs.keys.find { |parent, _| parent == 1 }&.last
      assert_includes DiskImages.udif(path)[:xml], "Apple_HFSX"
    end
  end

  def test_a_build_that_failed_leaves_no_image
    Dir.mktmpdir do |dir|
      dmg, path = write(dir)
      File.write(path, "partial")
      dmg.abort

      refute_path_exists path
    end
  end

  def test_a_mac_opens_the_image
    skip "hdiutil is macOS's" unless RUBY_PLATFORM.include?("darwin")

    Dir.mktmpdir do |dir|
      dmg, path = write(dir, name: "Ünïcödé App")
      dmg.finish

      out, status = Open3.capture2e("hdiutil", "verify", path)
      assert_predicate status, :success?, out
      DiskImages.mounted(path) do |mount|
        assert_equal "/Applications", File.readlink(File.join(mount, "Applications"))
        assert File.executable?(File.join(mount, "Ünïcödé App.app/Contents/MacOS/Ünïcödé App"))
      end
    end
  end
end
