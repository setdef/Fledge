# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: MIT-0
#++

require "mkmf"

# libpng's headers and its library from the distribution, as a desktop
# library's wrapper finds its own with pkg-config.
unless have_header("png.h") && have_library("png16", "png_get_libpng_ver")
  abort "png_version needs libpng's headers: install them, such as with sudo apt install libpng-dev"
end

create_makefile("png_version/png_version")
