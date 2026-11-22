# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

# The raylib probe: an app over raylib-bindings, whose raygui and physac
# libraries need libraylib by a name no file of the gem has
# (libraylib.so.600 on Linux, @rpath/libraylib.600.dylib on macOS), the
# SONAME or install name of the libraylib the gem carries under another
# file name. They load because the gem loads libraylib first, by path,
# and the system's loader then finds it by that name among what is
# already loaded.
#
# It loads the three libraries as the gem's examples/template.rb does,
# with ffi_lib_flags :now, so that a library whose needs went unmet
# fails to load, and calls one function of each, none of which needs a
# window. Raylib.load_lib only warns when a library fails to load, so a
# failed load shows here as a missing method.

require "raylib"

folder = "#{Gem::Specification.find_by_name('raylib-bindings').full_gem_path}/lib/"
arch = RUBY_PLATFORM.split("-").first
suffix = RUBY_PLATFORM.include?("darwin") ? "dylib" : "so"
Raylib.load_lib("#{folder}libraylib.#{arch}.#{suffix}", raygui_libpath: "#{folder}raygui.#{arch}.#{suffix}",
  physac_libpath: "#{folder}physac.#{arch}.#{suffix}")

puts "raylib: GetRandomValue(7, 7) = #{Raylib.GetRandomValue(7, 7)}"
puts "raygui: GuiGetState() = #{Raylib.GuiGetState}"
puts "physac: GetPhysicsBodiesCount() = #{Raylib.GetPhysicsBodiesCount}"
