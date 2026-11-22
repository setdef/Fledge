# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT-0
#++

# Prints the version of the libpng that png_version's extension loaded,
# which is the computer's own, not the one it was built against, and
# exits with the status its argument names, or 0.
require "png_version"

puts "png_version loaded libpng #{PngVersion.libpng} from the system"
exit Integer(ARGV.fetch(0, "0"))
