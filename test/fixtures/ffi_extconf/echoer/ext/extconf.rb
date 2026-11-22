# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

# Builds a shared library of C++ for Ruby's ffi to open, as sassc 2.4.0's
# ext/extconf.rb builds libsass: mkmf's own Makefile, no libruby, and no
# Init function, so what create_makefile names is no extension of Ruby's.
# Each step below is one of sassc's, in its order.
require "mkmf"

$CXXFLAGS << " -std=c++11"

# RubyGems' name for this computer, which sassc's reads to choose its
# link-time optimisation, as RubyGems runs an extconf.rb with RubyGems
# loaded.
$CXXFLAGS << " -flto" if Gem::Platform.local.os == "darwin" && ENV.key?("NIX_CC")

# The library stripped of its local symbols but on Apple's systems, as
# sassc's strips libsass.
MakeMakefile::LINK_SO << "\nstrip -x $@" if enable_config("strip", RbConfig::CONFIG["host_os"].downcase !~ /darwin/)

# Don't link libruby, as sassc's says.
$LIBRUBYARG = nil

# No export file naming an Init_libechoer, which the library does not
# have, as sassc's leaves out its Init_libsass.
MakeMakefile.__send__(:remove_const, :EXPORT_PREFIX)
MakeMakefile::EXPORT_PREFIX = nil

create_makefile "echoer/libechoer"
