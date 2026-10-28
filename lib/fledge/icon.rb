# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "error"
require_relative "png"
require_relative "icon/ico"
require_relative "icon/resampler"

module Fledge
  # Your app's icon, in every size and shape each operating system asks
  # for.
  #
  # macOS shows an app's icon from an <tt>.icns</tt> file in its bundle,
  # Windows from icon resources inside its program, and Linux desktops
  # from PNGs in the hicolor icon theme's folders, and each wants several
  # sizes, so the icon stays sharp in a Dock, a title bar, and a file
  # list (decision 18). Drawing each by hand, and converting each with
  # another tool for each format, is what you would do without Fledge.
  #
  # This class starts from one square PNG of at least MINIMUM pixels a
  # side, as Tauri's and Electron's icon generators do, shrinks it to each
  # size with an area-averaging filter that weighs each pixel's color by
  # its alpha (so a transparent edge does not darken), and writes:
  #
  # * #icns, Apple's icon family, with a PNG for each size from 16 to
  #   1024 pixels and each Retina double;
  # * #windows_images, the images of a Windows icon, as a <tt>.ico</tt>
  #   holds them: a 32-bit bitmap for each size below 256 pixels and a PNG
  #   at 256, which Windows has read since Vista;
  # * #png, a PNG of any size, for Linux.
  #
  # Each size is made once, from the next larger one, and kept.
  #
  # Use it through Fledge::Identity, which knows where your icon is.
  #
  # === Example
  #
  #--
  # SPDX-SnippetBegin
  # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
  # SPDX-License-Identifier: MIT-0
  #++
  #   icon = Fledge::Icon.read("icon.png")
  #   File.binwrite("MyCoolApp.icns", icon.icns)
  #   File.binwrite("48.png", icon.png(48))
  #--
  # SPDX-SnippetEnd
  #++
  class Icon
    # The smallest side a source icon may have: the largest image macOS
    # asks for, 512 points at Retina scale.
    MINIMUM = 1024

    # The types in an <tt>.icns</tt> and the size of each one's PNG
    # (Apple's IconFamily.h names them; Retina doubles are +ic11+ to
    # +ic14+ and +ic10+).
    ICNS = [
      ["icp4", 16],
      ["icp5", 32],
      ["ic11", 32],
      ["ic12", 64],
      ["ic07", 128],
      ["ic13", 256],
      ["ic08", 256],
      ["ic14", 512],
      ["ic09", 512],
      ["ic10", 1024],
    ].freeze

    # The sizes of a Windows icon: those Microsoft's icon guidelines ask
    # for at every display scale.
    WINDOWS = [16, 20, 24, 32, 40, 48, 64, 96, 256].freeze

    # The sizes of a Linux icon, in the hicolor theme's folders.
    LINUX = [16, 24, 32, 48, 64, 128, 256, 512].freeze

    # Reads the icon at +path+. Raises Fledge::Error, naming the file, when
    # it is not a square PNG of at least MINIMUM pixels a side.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   Fledge::Icon.read("icon.png")
    #--
    # SPDX-SnippetEnd
    #++
    def self.read(path)
      raise Error, "the icon #{path} does not exist" unless File.file?(path)

      image = begin
        Png.read(File.binread(path))
      rescue Error => e
        raise Error, "the icon #{path} #{e.message}"
      end
      new(image, path:)
    end

    # Creates an icon from +image+, a Fledge::Png. Raises Fledge::Error,
    # naming +path+, when it is not square or is smaller than MINIMUM.
    #
    # [image] The source Fledge::Png.
    # [path] Where it came from, for messages.
    def initialize(image, path: "icon")
      unless image.width == image.height && image.width >= MINIMUM
        raise Error, "the icon #{path} is #{image.width}x#{image.height} pixels; " \
          "use a square PNG of at least #{MINIMUM}x#{MINIMUM}"
      end

      @source = image.width
      @sizes = { image.width => image }
      @encoded = {} # : Hash[Integer, String]
    end

    # The icon at +size+ pixels a side, as a Fledge::Png.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   icon.image(16).width # => 16
    #--
    # SPDX-SnippetEnd
    #++
    def image(size)
      @sizes[size] ||= Resampler.shrink(image(source_side(size)), size)
    end

    # The side of the image +size+ is shrunk from: the source itself for
    # the largest sizes, and otherwise the smallest of the halvings of
    # MINIMUM at least twice as large, so each pixel averages whole pixels
    # and no image is shrunk from one far larger than it needs.
    private def source_side(size)
      return @source if size * 2 > MINIMUM

      side = MINIMUM
      side /= 2 while side / 2 >= size * 2
      side
    end

    # The icon at +size+ pixels a side, as PNG bytes.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   File.binwrite("256.png", icon.png(256))
    #--
    # SPDX-SnippetEnd
    #++
    def png(size)
      @encoded[size] ||= image(size).encode
    end

    # The icon as an <tt>.icns</tt> file: the +icns+ magic and the file's
    # length, then each of ICNS's types with its own length and PNG, all
    # big-endian.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   File.binwrite("MyCoolApp.icns", icon.icns)
    #--
    # SPDX-SnippetEnd
    #++
    def icns
      elements = ICNS.map { |type, size| type.b + [png(size).bytesize + 8].pack("N") + png(size) }
      "icns".b + [8 + elements.sum(&:bytesize)].pack("N") + elements.join
    end

    # The images of a Windows icon, smallest first: each WINDOWS size and
    # its image as an icon resource holds it (a 32-bit
    # BITMAPINFOHEADER bitmap with its AND mask, or a PNG at 256 pixels).
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   icon.windows_images.first.first # => 16
    #--
    # SPDX-SnippetEnd
    #++
    def windows_images
      WINDOWS.map { |size| [size, (size >= 256) ? png(size) : Ico.bitmap(image(size))] }
    end

    # The icon as an <tt>.ico</tt> file, which an NSIS installer takes for
    # its own icon: an ICONDIR, an ICONDIRENTRY for each of
    # #windows_images, and the images after them (Microsoft's "Icons").
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   File.binwrite("MyCoolApp.ico", icon.ico)
    #--
    # SPDX-SnippetEnd
    #++
    def ico
      Ico.file(windows_images)
    end
  end
end
