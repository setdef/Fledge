# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT-0
#++

# Draws Basket's icon again from its masters, icon.svg (for 64 pixels and
# up) and icon-small.svg (for under 64 pixels: a thicker handle, one fruit,
# and one band of weave, which still read at 16 pixels), into every file
# that fledge.yml's `icon: icons/icon` asks for, on a Mac, with the tools
# macOS ships: qlmanage, which draws the SVG, sips, and iconutil, which
# writes the .icns. Run it from any folder:
#
#   ruby examples/basket/icons/render.rb
#
# Each system frames the art as its guidelines say:
#
# - macOS: a rounded square 824 pixels wide on a 1024-pixel canvas, with
#   the margin around it, as Apple's "App icons" page of the Human
#   Interface Guidelines draws the macOS icon grid ("Layout"). icon.icns.
# - Windows, and the Linux desktops: a rounded square that fills most of
#   the canvas, as Microsoft's "Construct your Windows app's icon" and
#   GNOME's "App Icon Design" in its Human Interface Guidelines draw an
#   app's tile. icon.ico (PNGs of 16, 24, 32, 48, 64, and 256 pixels, which
#   Windows Vista and later read), icon-16.png to icon-512.png for Linux,
#   and, for an MSIX package's logos, icon-44.png, icon-50.png, and
#   icon-150.png.
# - iOS: the full square, with no rounded corners and no alpha channel,
#   which iOS rounds itself and App Store Connect needs flat (Apple's "App
#   icons", "Specifications"). icon-1024.png.
# - Android: the full square again, with the basket inside its central
#   two thirds of the side, where Android's "Adaptive icons" page puts the
#   safe zone a launcher's mask leaves whole ("Design adaptive icon
#   layers": 66 of 108 dp). icon-48.png to icon-192.png.

require "fileutils"
require "tmpdir"

# The folder of this script, which holds the masters and gets the files.
HERE = __dir__

# Where a frame puts the 1024-pixel art: [x, y, side, corner radius] of its
# rounded square, or nil for the full square.
FRAMES = {
  full: nil,
  desktop: [32, 32, 960, 215],
  mac: [100, 100, 824, 185],
}.freeze

# The art in +art+'s <svg> element, as the SVG of +frame+.
def framed(art, frame)
  inner = art[%r{<svg[^>]*>(.*)</svg>}m, 1]
  return %(<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="1024" height="1024">#{inner}</svg>) unless FRAMES[frame]

  x, y, side, radius = FRAMES[frame]
  scale = side / 1024.0
  <<~SVG
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="1024" height="1024">
      <defs><clipPath id="tile"><rect x="#{x}" y="#{y}" width="#{side}" height="#{side}" rx="#{radius}"/></clipPath></defs>
      <g clip-path="url(#tile)"><g transform="translate(#{x} #{y}) scale(#{scale})">#{inner}</g></g>
    </svg>
  SVG
end

# What to render: [file, frame, pixels, opaque], a file being a name in
# +dir+. The ICO's PNGs, and the iconset iconutil reads, are among them.
def wanted(dir)
  list = []
  [16, 32, 64, 128, 256, 512].each { |px| list << ["icon-#{px}.png", :desktop, px] }
  [44, 50, 150].each { |px| list << ["icon-#{px}.png", :desktop, px] }
  [48, 72, 96, 144, 192].each { |px| list << ["icon-#{px}.png", :full, px] }
  list << ["icon-1024.png", :full, 1024, true]
  [16, 24, 32, 48, 64, 256].each { |px| list << ["ico/#{px}.png", :desktop, px] }
  [16, 32, 128, 256, 512].each do |side|
    list << ["icon.iconset/icon_#{side}x#{side}.png", :mac, side]
    list << ["icon.iconset/icon_#{side}x#{side}@2x.png", :mac, side * 2]
  end
  list.map { |file, frame, px, opaque| [File.join(dir, file), frame, px, opaque] }
end

# An ICO holding +pngs+, each as PNG data (Windows Vista and later read
# them), by side in pixels: a header, a directory of 16 bytes an image,
# and the images.
def ico(pngs)
  offset = 6 + (16 * pngs.size)
  directory = pngs.map do |side, data|
    entry = [side % 256, side % 256, 0, 0, 1, 32, data.bytesize, offset].pack("CCCCvvVV")
    offset += data.bytesize
    entry
  end
  ([0, 1, pngs.size].pack("vvv") + directory.join + pngs.values.join).b
end

# +svg+ drawn into +px+ pixels at +png+, by QuickLook's thumbnailer, which
# macOS ships to draw SVG, with the transparency the art has. With
# +opaque+, the PNG has no alpha channel at all: sips writes no PNG
# without one, so the PNG goes through a JPEG at quality 100 and back,
# which changes no pixel by more than 2 percent.
def draw(svg, px, png, opaque)
  Dir.mktmpdir("basket-thumbnail") do |thumbnails|
    system("qlmanage", "-t", "-s", px.to_s, "-o", thumbnails, svg, exception: true, out: File::NULL, err: File::NULL)
    drawn = File.join(thumbnails, "#{File.basename(svg)}.png")
    if opaque
      jpeg = File.join(thumbnails, "flat.jpg")
      system("sips", "-s", "format", "jpeg", "-s", "formatOptions", "100", drawn, "--out", jpeg, exception: true, out: File::NULL)
      system("sips", "-s", "format", "png", jpeg, "--out", png, exception: true, out: File::NULL)
    else
      FileUtils.mv(drawn, png)
    end
  end
end

Dir.mktmpdir("basket-icon") do |work|
  FileUtils.mkdir_p([File.join(work, "ico"), File.join(work, "icon.iconset")])

  wanted(work).each do |png, frame, px, opaque|
    master = (px < 64) ? "icon-small" : "icon"
    svg = File.join(work, "#{master}-#{frame}.svg")
    File.write(svg, framed(File.read(File.join(HERE, "#{master}.svg")), frame)) unless File.exist?(svg)
    draw(svg, px, png, opaque)
  end

  Dir.glob(File.join(work, "icon-*.png")).each { |png| FileUtils.cp(png, HERE) }
  File.binwrite(File.join(HERE, "icon.ico"), ico([16, 24, 32, 48, 64, 256].to_h { |px| [px, File.binread(File.join(work, "ico", "#{px}.png"))] }))
  system("iconutil", "-c", "icns", File.join(work, "icon.iconset"), "-o", File.join(HERE, "icon.icns"), exception: true)
end
