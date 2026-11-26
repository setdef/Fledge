# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "test_helper"

# What examples/basket tells each system about itself: its fledge.yml
# keys, and the icon files that fledge.yml's icon key points to, each the
# size in its file name, so that every build of Basket, for a phone or a
# desktop, has an icon and the fields a developer sees.
class BasketIdentityTest < Minitest::Test
  ROOT = File.expand_path("../examples/basket", __dir__)

  PNG_SIGNATURE = "\x89PNG\r\n\x1a\n".b

  def setup
    @config = Fledge::Config.load(ROOT)
    @icon = File.join(ROOT, @config.icon)
  end

  def test_it_says_who_makes_it_and_what_it_is
    assert_equal "Basket", @config.name
    assert_equal "com.setdef.fledge.Basket", @config.identifier
    assert_equal "1.0.0", @config.version
    assert_equal "setdef", @config.publisher
    assert_equal "© 2026 setdef", @config.copyright
    assert_equal "Keeps a shopping list", @config.description
    assert_includes @config.long_description, "Type an item and add it"
    assert_equal "https://github.com/setdef/Fledge/tree/trunk/examples/basket", @config.homepage
  end

  def test_its_license_is_a_file_of_the_project
    assert_equal "LICENSE.txt", @config.license_file
    assert_includes File.read(File.join(ROOT, @config.license_file)), "MIT No Attribution"
  end

  def test_it_asks_for_every_installer_a_desktop_makes
    assert_equal %w[dmg nsis appimage deb msix], @config.installers
  end

  def test_its_msix_package_has_a_test_identity
    assert_equal "setdef.Basket", @config.windows.msix_name
    assert_equal "CN=setdef", @config.windows.msix_publisher
  end

  def test_every_png_an_icon_asks_for_is_the_size_its_name_claims
    sizes = Fledge::Icon::LINUX + [Fledge::Icon::IOS] + Fledge::Icon::ANDROID.values + Fledge::Icon::MSIX.values

    sizes.each do |size|
      width, height, = png_header("#{@icon}-#{size}.png")

      assert_equal [size, size], [width, height], "#{@config.icon}-#{size}.png"
    end
  end

  # App Store Connect refuses an iOS icon with an alpha channel, even an
  # opaque one: a PNG's color type 2 is RGB, and 6 is RGBA.
  def test_the_ios_icon_has_no_alpha_channel
    assert_equal 2, png_header("#{@icon}-1024.png").last
  end

  # Windows Vista and later read PNGs in an ICO, and scale the nearest
  # size to the one a place asks for.
  def test_the_windows_icon_holds_the_sizes_windows_shows
    data = File.binread("#{@icon}.ico")
    count = data.byteslice(4, 2).unpack1("v")
    sides = Array.new(count) { |index| data.getbyte(6 + (16 * index)).then { |side| (side == 0) ? 256 : side } }
    widths = Array.new(count) { |index| png_header_of(ico_image(data, index)).first }

    assert_equal [16, 24, 32, 48, 64, 256], sides
    assert_equal sides, widths
  end

  # iconutil writes each size as ic04 (16 pixels) to ic14 (512 at twice
  # the density); ic10 is 1024 pixels.
  def test_the_mac_icon_is_an_icns_file_of_the_sizes_macos_shows
    data = File.binread("#{@icon}.icns")

    assert_equal "icns", data.byteslice(0, 4)
    assert_equal data.bytesize, data.byteslice(4, 4).unpack1("N")
    assert_empty %w[ic04 ic05 ic07 ic08 ic09 ic10 ic11 ic12 ic13 ic14] - icns_types(data)
  end

  private def png_header(path)
    png_header_of(File.binread(path))
  end

  # The width, height, and color type of the PNG in +data+.
  private def png_header_of(data)
    assert_equal PNG_SIGNATURE, data.byteslice(0, 8)
    [*data.byteslice(16, 8).unpack("NN"), data.getbyte(25)]
  end

  private def ico_image(data, index)
    size, offset = data.byteslice(6 + (16 * index) + 8, 8).unpack("VV")
    data.byteslice(offset, size)
  end

  private def icns_types(data)
    types = []
    offset = 8
    while offset < data.bytesize
      types << data.byteslice(offset, 4)
      offset += data.byteslice(offset + 4, 4).unpack1("N")
    end
    types
  end
end
