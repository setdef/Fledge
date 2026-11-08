# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT-0

# A static C++ library, as a gem's native engine is, which the gem's
# extconf.rb builds with CMake before mkmf builds the extension over it.
# Nothing here knows about phones: the target comes from the toolchain
# file CMake is given, as CMAKE_TOOLCHAIN_FILE in the environment
# (ADR 027).
cmake_minimum_required(VERSION 3.21)
project(tally LANGUAGES CXX)

add_library(tally STATIC tally.cc)
target_compile_features(tally PRIVATE cxx_std_17)
# The library is linked into a Ruby extension, a shared library on a
# desktop, so it is position-independent everywhere.
set_target_properties(tally PROPERTIES POSITION_INDEPENDENT_CODE ON)
target_compile_definitions(tally PRIVATE
  TALLY_CMAKE_VERSION="${CMAKE_VERSION}"
  TALLY_SYSTEM="${CMAKE_SYSTEM_NAME}")
