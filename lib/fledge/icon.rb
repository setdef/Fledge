# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "error"

module Fledge
  # Your app's icon, in the file each operating system takes it from.
  #
  # macOS shows an app's icon from an <tt>.icns</tt> file in its bundle,
  # Windows from icon resources inside its program, made from an
  # <tt>.ico</tt>, and Linux desktops from PNGs in the hicolor icon
  # theme's folders, each at several sizes, so the icon stays sharp in a
  # Dock, a title bar, and a file list (decision 18). Each system's own
  # tools make its format, and the icon editors you draw with export
  # them.
  #
  # This class names those files as Briefcase does: <tt>icon:</tt> in
  # <tt>fledge.yml</tt> is a path without an extension, and the build for
  # each system takes the file it needs from beside it, as you made it
  # (ADR 010):
  #
  # * <tt>ICON.icns</tt> on macOS, which <tt>iconutil -c icns
  #   ICON.iconset</tt> makes from PNGs;
  # * <tt>ICON.ico</tt> on Windows, holding the sizes Windows shows, 16,
  #   32, 48, 64, and 256 pixels a side, as Briefcase asks;
  # * <tt>ICON-16.png</tt> to <tt>ICON-512.png</tt> on Linux, one for
  #   each of LINUX's sizes;
  # * <tt>ICON-1024.png</tt> for iOS and iPadOS, the one size an asset
  #   catalog's app icon has needed since Xcode 14, which makes the rest
  #   (IOS);
  # * <tt>ICON-48.png</tt> to <tt>ICON-192.png</tt> for Android, one for
  #   each screen density's launcher icon (ANDROID), the sizes Briefcase
  #   asks for.
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
  #   icon = Fledge::Icon.new(base: "/path/to/my_app/icons/app", name: "icons/app")
  #   icon.file("icns") # => "/path/to/my_app/icons/app.icns"
  #   icon.png(48)      # => "/path/to/my_app/icons/app-48.png"
  #--
  # SPDX-SnippetEnd
  #++
  class Icon < Data.define(:base, :name)
    ##
    # :attr_reader: base
    # The icon's path without an extension, absolute.

    ##
    # :attr_reader: name
    # The icon's path as <tt>fledge.yml</tt> gives it, for messages.

    # The sizes of a Linux app's icons, which Briefcase asks of an
    # AppImage, each in the hicolor theme's folder of that size.
    LINUX = [16, 32, 64, 128, 256, 512].freeze

    # The size of an iOS app's icon, from which Xcode makes the others.
    IOS = 1024

    # The size of an Android app's launcher icon for each screen density,
    # by the density's name in its <tt>mipmap-</tt> folder.
    ANDROID = { "mdpi" => 48, "hdpi" => 72, "xhdpi" => 96, "xxhdpi" => 144, "xxxhdpi" => 192 }.freeze

    # How to make each file, for the message when it is missing: by its
    # extension, or for a PNG by the system that takes it.
    MAKE = {
      "icns" => "Make it from PNGs with iconutil -c icns, as a Mac app's icon is made.",
      "ico" => "Make it with the sizes Windows shows, 16, 32, 48, 64, and 256 pixels a side.",
      "png" => "Linux apps take one PNG of each size, #{LINUX.map { |size| "-#{size}" }.join(', ')}.",
      "ios" => "iOS apps take one PNG of #{IOS} pixels a side, -#{IOS}, from which Xcode makes the rest.",
      "android" => "Android apps take one PNG of each size, #{ANDROID.values.map { |size| "-#{size}" }.join(', ')}, " \
        "one for each screen density.",
    }.freeze

    # The icon file with +extension+ beside the icon's base, such as
    # <tt>ICON.icns</tt>. Raises Fledge::Error, saying how to make it,
    # when it does not exist.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   icon.file("ico") # => "/path/to/my_app/icons/app.ico"
    #--
    # SPDX-SnippetEnd
    #++
    def file(extension)
      found("#{base}.#{extension}", "#{name}.#{extension}", extension)
    end

    # The PNG of the icon at +size+ pixels a side, <tt>ICON-SIZE.png</tt>.
    # Raises Fledge::Error, saying which sizes the system +system+ takes
    # (a key of MAKE: Linux's when it is +png+), when it does not exist.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   icon.png(256)          # => "/path/to/my_app/icons/app-256.png"
    #   icon.png(1024, "ios")  # => "/path/to/my_app/icons/app-1024.png"
    #--
    # SPDX-SnippetEnd
    #++
    def png(size, system = "png")
      found("#{base}-#{size}.png", "#{name}-#{size}.png", system)
    end

    private def found(path, shown, system)
      return path if File.file?(path)

      raise Error, "the icon #{shown} does not exist. fledge.yml's icon names the icon's files without an extension, " \
        "as Briefcase's does. #{MAKE.fetch(system)}"
    end
  end
end
