# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "test_helper"
require "open3"

class PlistTest < Minitest::Test
  def test_writes_each_kind_of_value
    plist = Fledge::Plist.write({ "b" => [1, 2.5, false], "a" => "x & <y>", "c" => true, "d" => Fledge::Plist::Bytes.new(bytes: "\x00\xFF".b) })
    assert_equal <<~XML, plist
      <?xml version="1.0" encoding="UTF-8"?>
      <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
      <plist version="1.0">
      <dict>
      \t<key>a</key>
      \t<string>x &amp; &lt;y&gt;</string>
      \t<key>b</key>
      \t<array>
      \t\t<integer>1</integer>
      \t\t<real>2.5</real>
      \t\t<false/>
      \t</array>
      \t<key>c</key>
      \t<true/>
      \t<key>d</key>
      \t<data>AP8=</data>
      </dict>
      </plist>
    XML
  end

  # Apple's own plutil reads it back, where there is one.
  def test_plutil_reads_it
    skip "plutil is macOS's" unless system("command -v plutil > /dev/null 2>&1")

    Dir.mktmpdir do |dir|
      path = File.join(dir, "Info.plist")
      File.write(path, Fledge::Plist.write({ "CFBundleName" => "Hello Wörld & Co", "NSHighResolutionCapable" => true }))
      out, status = Open3.capture2("plutil", "-extract", "CFBundleName", "raw", path)
      assert_predicate status, :success?
      assert_equal "Hello Wörld & Co\n", out
    end
  end
end
