#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# SPIKE: builds the Windows launcher variants and assembles test apps.
# Runs in an MSYS2 UCRT64 shell. Usage: build.sh RUBYINSTALLER_DIR OUT_DIR
set -euo pipefail

ri=$(cd "$1" && pwd)
out=$2
here=$(cd "$(dirname "$0")" && pwd)
mkdir -p "$out"
out=$(cd "$out" && pwd)
obj=$(mktemp -d)

echo "== toolchain"
command -v gcc windres objdump strip
gcc --version | head -1

cflags=(-std=gnu11 -O2 -Wall -Wextra -Werror -municode
        -isystem "$ri/include/ruby-4.0.0" -isystem "$ri/include/ruby-4.0.0/x64-mingw-ucrt")
# -isystem: Ruby's own headers are not -Wextra clean (unused parameter in
# ruby/internal/gc.h), and their warnings are not ours to fix.
ldflags=(-municode -static-libgcc -s)

(cd "$here" && windres launcher.rc -O coff -o "$obj/launcher.res.o")

echo "== compile: run-time loading, console (the reference build)"
gcc "${cflags[@]}" "$here/launcher.c" "$obj/launcher.res.o" "${ldflags[@]}" -mconsole -o "$out/launcher.exe"
echo "== compile: run-time loading, console, no manifest (long-path control)"
gcc "${cflags[@]}" "$here/launcher.c" "${ldflags[@]}" -mconsole -o "$out/launcher-nomanifest.exe"
echo "== compile: run-time loading, windowed"
gcc "${cflags[@]}" -DFLEDGE_WINDOWED "$here/launcher.c" "$obj/launcher.res.o" "${ldflags[@]}" -mwindows -o "$out/launcherw.exe"
echo "== compile: run-time loading, --disable-gems"
gcc "${cflags[@]}" -DFLEDGE_DISABLE_GEMS "$here/launcher.c" "$obj/launcher.res.o" "${ldflags[@]}" -mconsole -o "$out/launcher-nogems.exe"
echo "== compile: linked against RubyInstaller's import library"
ls -l "$ri"/lib/*.dll.a
gcc "${cflags[@]}" -DFLEDGE_IMPORT -DFLEDGE_BASE='L"..\\..\\"' "$here/launcher.c" "$obj/launcher.res.o" "${ldflags[@]}" -mconsole \
  -L"$ri/lib" -lx64-ucrt-ruby400 -o "$out/launcher-import.exe"
echo "== compile: linked against the import library, side-by-side manifest"
(cd "$here" && windres sxs.rc -O coff -o "$obj/sxs.res.o")
gcc "${cflags[@]}" -DFLEDGE_IMPORT "$here/launcher.c" "$obj/sxs.res.o" "${ldflags[@]}" -mconsole \
  -L"$ri/lib" -lx64-ucrt-ruby400 -o "$out/launcher-sxs.exe"

for exe in "$out"/*.exe; do
  echo "== $(basename "$exe"): $(stat -c %s "$exe") bytes"
  objdump -p "$exe" | grep -E 'Subsystem|DLL Name'
done

# --- Runtimes -------------------------------------------------------------
# full: RubyInstaller's tree unchanged. min: with the conservative cuts.
echo "== assemble runtimes"
mkdir -p "$out/runtime-full" "$out/runtime-min"
cp -a "$ri/." "$out/runtime-full/ruby"
cp -a "$ri/." "$out/runtime-min/ruby"
m="$out/runtime-min/ruby"
# Headers and import/static libraries: only for compiling extensions.
rm -rf "$m/include" "$m/lib/pkgconfig"
rm -f "$m"/lib/*.a
# RDoc/ri documentation and the MSYS2/ridk installer bits.
rm -rf "$m/share" "$m/packages" "$m/ridk_use"
# Command-line wrappers (bundle.bat, gem.cmd, ridk.ps1...): the app runs
# through the launcher, never through these. ruby.exe and rubyw.exe stay:
# RbConfig.ruby and Gem.ruby name them for subprocesses.
find "$m/bin" -maxdepth 1 -type f ! -name '*.exe' ! -name '*.dll' -print -delete
# Per-gem docs and test suites inside the bundled gems are left alone.

du -sh "$ri" "$out/runtime-full" "$out/runtime-min"
du -sh "$m"/* "$m"/lib/ruby/* | sort -h

# --- Apps -----------------------------------------------------------------
# One launcher.exe, compiled once, copied and renamed per app (Q7).
make_app() { # name runtime app_source
  local dir="$out/apps/$1"
  mkdir -p "$dir/app"
  cp -a "$out/$2/ruby" "$dir/ruby"
  cp "$here/$3/main.rb" "$dir/app/main.rb"
  cp "$out/launcher.exe" "$dir/$1.exe"
}
make_app hello runtime-min hello
make_app hello-full runtime-full hello
make_app diag runtime-min diag
cp "$out/launcherw.exe" "$out/apps/hello/hello-windowed.exe"
cp "$out/launcher-nogems.exe" "$out/apps/hello/hello-nogems.exe"
cp "$out/launcher-nomanifest.exe" "$out/apps/hello/hello-nomanifest.exe"
cp "$out/launcher-nogems.exe" "$out/apps/diag/diag-nogems.exe"
cp "$out/launcherw.exe" "$out/apps/diag/diag-windowed.exe"
# The import-linked exe works only beside the DLL; a copy at the top
# shows what happens otherwise.
cp "$out/launcher-import.exe" "$out/apps/diag/ruby/bin/diag-import.exe"
cp "$out/launcher-import.exe" "$out/apps/diag/diag-import-toplevel.exe"

# The side-by-side alternative: DLL and its private assembly moved up
# from ruby\bin to ruby\, plus ruby\ruby.manifest naming the DLL.
make_app sxs runtime-min hello
cp "$out/launcher-sxs.exe" "$out/apps/sxs/sxs.exe"
mv "$out/apps/sxs/ruby/bin/x64-ucrt-ruby400.dll" "$out/apps/sxs/ruby/"
mv "$out/apps/sxs/ruby/bin/ruby_builtin_dlls" "$out/apps/sxs/ruby/"
cp "$here/ruby.assembly.manifest" "$out/apps/sxs/ruby/ruby.manifest"
mkdir -p "$out/apps/sxs-diag" && cp -a "$out/apps/sxs/." "$out/apps/sxs-diag/"
cp "$here/diag/main.rb" "$out/apps/sxs-diag/app/main.rb"
mv "$out/apps/sxs-diag/sxs.exe" "$out/apps/sxs-diag/sxs-diag.exe"

# Fledge's own operating_system.rb in place of RubyInstaller's.
for app in hello diag; do
  make_app "$app-os" runtime-min "$app"
  cp "$here/operating_system.rb" "$out/apps/$app-os/ruby/lib/ruby/4.0.0/rubygems/defaults/operating_system.rb"
done

rm -rf "$out/runtime-full" "$out/runtime-min"
du -sh "$out"/apps/*
