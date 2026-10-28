# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "test_helper"
require_relative "support/binaries"

class WindowsResourcesTest < Minitest::Test
  def identity(icon: nil, **overrides)
    Fledge::Identity.new(name: "Hello Window", kind: "windowed", identifier: "com.example.HelloWindow", version: "1.2.3",
      publisher: "Example, Inc.", copyright: "© 2026 Example", icon:, **overrides)
  end

  # The strings of a VS_VERSIONINFO, read back by walking its blocks.
  def strings(info)
    found = {}
    at = info.index("0\x004\x000\x009\x000\x004\x00B\x000\x00".b) + 18
    finish = info.index("V\x00a\x00r\x00F\x00i\x00l\x00e\x00".b)
    while at < finish - 6
      length, = info.byteslice(at, 2).unpack("v")
      break if length.zero?

      fields = info.byteslice(at + 6, length - 6).force_encoding(Encoding::UTF_16LE).encode(Encoding::UTF_8).split("\0").reject(&:empty?)
      found[fields[0]] = fields[1]
      at = (at + length + 3) / 4 * 4
    end
    found
  end

  def test_writes_version_information_and_keeps_the_manifest
    program = Fledge::WindowsResources.apply(Programs.windows(manifest: "<assembly>keep</assembly>"),
      identity:, file_name: "Hello Window.exe")
    resources = Fledge::WindowsProgram.new(program).resources

    assert_equal [[16, 1, 1033], [24, 1, 1033]], resources.keys
    assert_equal "<assembly>keep</assembly>", resources.fetch([24, 1, 1033])
    assert_equal({
"CompanyName" => "Example, Inc.",
"FileDescription" => "Hello Window",
"FileVersion" => "1.2.3",
"InternalName" => "Hello Window",
"LegalCopyright" => "© 2026 Example",
"OriginalFilename" => "Hello Window.exe",
"ProductName" => "Hello Window",
"ProductVersion" => "1.2.3",
},
      strings(resources.fetch([16, 1, 1033])))
  end

  def test_leaves_out_what_the_identity_does_not_say
    program = Fledge::WindowsResources.apply(Programs.windows, identity: identity(publisher: nil, copyright: nil), file_name: "H.exe")
    found = strings(Fledge::WindowsProgram.new(program).resources.fetch([16, 1, 1033]))
    refute_includes found.keys, "CompanyName"
    refute_includes found.keys, "LegalCopyright"
  end

  # Each image of the icon is an RT_ICON numbered from 1, and the
  # RT_GROUP_ICON numbered 32512, which Windows shows for the program, lists
  # them by size and number (a GRPICONDIR and its GRPICONDIRENTRYs).
  def test_writes_the_icon_as_icon_resources_and_a_group
    image = Fledge::Png.new(width: 1024, height: 1024, pixels: ([10, 20, 30, 255] * (1024 * 1024)).pack("C*"))
    icon = Fledge::Icon.new(image)
    program = Fledge::WindowsResources.apply(Programs.windows, identity: identity(icon:), file_name: "H.exe")
    resources = Fledge::WindowsProgram.new(program).resources

    images = icon.windows_images
    images.each_with_index { |(_, data), index| assert_equal data, resources.fetch([3, index + 1, 1033]) }
    group = resources.fetch([14, 32_512, 1033])
    assert_equal [0, 1, images.size], group.byteslice(0, 6).unpack("v3")
    entries = Array.new(images.size) { |index| group.byteslice(6 + (index * 14), 14).unpack("CCCCvvVv") }
    assert_equal [16, 16, 0, 0, 1, 32, images.first.last.bytesize, 1], entries.first
    assert_equal [0, 0, 0, 0, 1, 32, images.last.last.bytesize, images.size], entries.last

    again = Fledge::WindowsResources.apply(program, identity:, file_name: "H.exe")
    assert_equal [[16, 1, 1033], [24, 1, 1033]], Fledge::WindowsProgram.new(again).resources.keys, "an old icon is replaced"
  end
end
