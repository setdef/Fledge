#!/bin/sh
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT

# Gathers Mesa's OpenGL for a Windows runner that has no GPU, into a
# folder: opengl32.dll, its driver libgallium_wgl.dll, and
# every DLL of BIN that either imports, directly or through another.
# deliver-pop.ps1 then puts the folder's DLLs beside the app's program,
# where Windows looks for the opengl32.dll that SDL3 loads by name
# before it looks in System32, whose OpenGL 1.1 Lota's renderer cannot use.
#
#   gather-mesa.sh BIN FOLDER
#
# BIN is the bin folder of an MSYS2 environment that has Mesa installed
# (mesa:p), in Windows' spelling or MSYS2's, and FOLDER is the
# empty folder to fill. It runs in that environment's shell, which has
# objdump (binutils:p) or, on ARM64, llvm-objdump (llvm-tools:p).

set -eu

bin=${1:?usage: gather-mesa.sh BIN FOLDER}
folder=${2:?usage: gather-mesa.sh BIN FOLDER}

objdump=$(command -v objdump || command -v llvm-objdump) || {
  echo "gather-mesa.sh: neither objdump nor llvm-objdump is on the PATH" >&2
  exit 1
}

mkdir -p "$folder"
queue="opengl32.dll libgallium_wgl.dll"
seen=" "
while [ -n "$queue" ]; do
  # shellcheck disable=SC2086 # the names hold no spaces
  set -- $queue
  dll=$1
  shift
  queue="$*"
  lower=$(printf '%s' "$dll" | tr '[:upper:]' '[:lower:]')
  case $seen in *" $lower "*) continue ;; esac
  seen="$seen$lower "
  [ -f "$bin/$dll" ] || { echo "gather-mesa.sh: $bin/$dll is missing" >&2; exit 1; }
  cp "$bin/$dll" "$folder/"
  echo "$dll: copied from $bin"
  for needed in $("$objdump" -p "$bin/$dll" | sed -n 's/^.*DLL Name: *//p' | tr -d '\r'); do
    [ ! -f "$bin/$needed" ] || queue="$queue $needed"
  done
done
