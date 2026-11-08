# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT-0
#++

# Builds the C++ library in lib/ with CMake, and then, with mkmf, the C
# extension that links it, as a gem over a native engine does. Nothing
# here names a phone: on one, fledge build runs this once for each
# target and puts that target's toolchain file in CMAKE_TOOLCHAIN_FILE,
# which CMake reads when a build folder is new (ADR 027); on a desktop
# CMake builds for the desktop.
require "mkmf"

source = File.expand_path("lib", __dir__)
build = File.expand_path("tally-build")
find_executable("cmake") or abort "tally needs CMake 3.21 or later to build its C++ library"
system("cmake", "-S", source, "-B", build, "-DCMAKE_BUILD_TYPE=Release", exception: true)
system("cmake", "--build", build, exception: true)

$INCFLAGS << " -I#{source}"
$LOCAL_LIBS << " #{File.join(build, 'libtally.a')}"
# The library is C++, and the extension C, so the link names the C++
# runtime, as it must on a desktop too.
$libs << (RbConfig::CONFIG["host_os"].match?(/darwin/) ? " -lc++" : " -lstdc++")

have_func("rb_str_new", "ruby.h")
create_makefile("tally/tally")
