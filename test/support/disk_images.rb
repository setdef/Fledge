# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "fileutils"
require "open3"
require "tmpdir"

# Opens a disk image as a Mac opens one, with Apple's hdiutil.
module DiskImages
  # Attaches the image at +path+ read-only at a folder of its own, yields
  # that folder, and detaches it.
  def self.mounted(path)
    mount = Dir.mktmpdir("fledge-mount")
    out, status = Open3.capture2e("hdiutil", "attach", "-readonly", "-nobrowse", "-mountpoint", mount, path)
    raise "hdiutil attach failed: #{out}" unless status.success?

    begin
      yield mount
    ensure
      system("hdiutil", "detach", "-quiet", mount)
      FileUtils.rm_rf(mount)
    end
  end
end
