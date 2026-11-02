# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: MIT-0
#++

# Links SDL3 into the extension. On a phone, fledge build runs this once
# for each target, with that target's compiler in RbConfig (ADR 022), and
# passes it the options of bundle config build.sdl_demo, which name the
# folder sdl3/build.sh wrote: --with-sdl3-builds=DIR, holding a build of
# SDL3 for each target, in DIR/TARGET. The flags SDL's own sdl3.pc names
# are what the app links. On a desktop, pkg-config finds an SDL3 the
# computer has.
require "mkmf"

# The phone's target this extconf.rb compiles for, from the compiler
# fledge build gives it, or nil on a desktop.
def phone_target
  compiler = RbConfig::CONFIG.fetch("CC")
  case compiler
  when /-target arm64-apple-ios[\d.]*-simulator\b/ then "ios-arm64-simulator"
  when /-target arm64-apple-ios/ then "ios-arm64"
  when /aarch64-linux-android/ then "arm64-v8a"
  when /x86_64-linux-android/ then "x86_64"
  end
end

# The link flags sdl3.pc in +lib+ names, in the form mkmf passes on: a
# static library by its path, and each framework as -framework NAME.
def sdl3_libs(lib, static:)
  libs = File.read(File.join(lib, "pkgconfig", "sdl3.pc"))[/^Libs: (.*)$/, 1].to_s.split
  libs.map do |flag|
    case flag
    when /\A-Wl,-(weak_framework|framework),(\S+)\z/ then "-#{Regexp.last_match(1)} #{Regexp.last_match(2)}"
    when "-lSDL3" then static ? File.join(lib, "libSDL3.a") : flag
    when /\A-L/ then static ? nil : flag
    else flag
    end
  end.compact
end

target = phone_target
if target
  builds = with_config("sdl3-builds") or abort "sdl_demo needs --with-sdl3-builds=DIR, from bundle config build.sdl_demo"
  prefix = File.join(File.expand_path(builds), target)
  abort "#{prefix} holds no SDL3 build for #{target}; run sdl3/build.sh" unless File.directory?(prefix)

  $INCFLAGS << " -I#{File.join(prefix, 'include')}"
  libs = sdl3_libs(File.join(prefix, "lib"), static: target.start_with?("ios"))
  archives, flags = libs.partition { |flag| flag.end_with?(".a") }
  $LOCAL_LIBS << " #{archives.join(' ')}" unless archives.empty?
  $libs << " #{flags.join(' ')}"
else
  pkg_config("sdl3") or abort "sdl_demo needs SDL3, which pkg-config does not find"
end

have_header("SDL3/SDL.h") or abort "sdl_demo finds no SDL3/SDL.h"
have_func("SDL_Init", "SDL3/SDL.h") or abort "sdl_demo can't link SDL_Init"
create_makefile("sdl_demo/sdl_demo")
