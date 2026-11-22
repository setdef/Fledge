#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
# Builds apps with fledge build in manylinux_2_28, the image the glibc
# Linux runtimes are built in, so that a gem compiled from source there
# needs no newer glibc than 2.28, the runtimes' floor, and the app runs
# on every Linux the floor admits. It is what a developer does who
# follows fledge build's warning about a gem compiled on a newer glibc
# (doc/contributors/design/gems.md, "The toolchain and the oldest
# systems"), with the image as the older Linux: AlmaLinux 8 with GCC
# from its gcc-toolset, binutils, and make, which is all a C extension's
# build needs.
#
#   .github/scripts/glibc-app.sh PLATFORM RUNTIMES OUT PROJECT...
#
# runs the builds in the image with docker, on a computer of PLATFORM's
# architecture (x86_64-linux or aarch64-linux): each PROJECT, a folder
# of this checkout, is built with the runtime in RUNTIMES, a folder as
# FLEDGE_RUNTIME_DIR names one, into OUT. The image has no Ruby, so the
# platform's Ruby pin, which needs only glibc 2.17, runs fledge build
# there, as it runs the runtime's build (glibc-runtime.sh); the
# computer's own Ruby downloads it into the folder Fledge's builds keep
# downloads in, checked by its SHA-256.
#
#   .github/scripts/glibc-app.sh --in-image PLATFORM ARCHIVE PROJECT...
#
# is what runs in the image: it checks ARCHIVE, the Ruby pin as the
# image sees it, by its SHA-256 again, and builds each PROJECT into
# /out with the runtimes in /runtimes. It is for this image only.

set -euo pipefail

usage() {
  echo "usage: glibc-app.sh PLATFORM RUNTIMES OUT PROJECT..." >&2
  echo "       glibc-app.sh --in-image PLATFORM ARCHIVE PROJECT..." >&2
  exit 2
}

pin() {
  ruby -ryaml -e 'puts YAML.safe_load_file("runtime/sources.yml").dig(*ARGV)' "$@"
}

same_machine() {
  local machine here
  case $platform in
    x86_64-linux) machine=x86_64 ;;
    aarch64-linux) machine=aarch64 ;;
    *) usage ;;
  esac
  here=$(uname -m)
  [ "$here" = arm64 ] && here=aarch64
  if [ "$here" != "$machine" ]; then
    echo "glibc-app.sh: $platform is built on $machine, and this computer is $here" >&2
    exit 1
  fi
}

in_image() {
  local archive=$1 sha256 driver=/tmp/driver status=0
  shift
  sha256=$(sed -n "/^    $platform:\$/,/sha256:/{/sha256:/{s/^ *sha256: *//p;q;};}" runtime/sources.yml)
  echo "$sha256  $archive" | sha256sum --strict -c -
  mkdir -p "$driver"
  tar -xzf "$archive" -C "$driver" --no-same-owner
  PATH="$(dirname "$(find "$driver" -maxdepth 3 -path '*/bin/ruby' -print -quit)"):$PATH"
  export PATH CC=gcc FLEDGE_RUNTIME_DIR=/runtimes FLEDGE_RUNTIME_DIR_UNCHECKED=1
  ruby -v
  gcc --version | sed -n 1p
  ldd --version | sed -n 1p
  for project in "$@"; do
    ruby -I lib exe/fledge build -o /out "$project" || status=$?
  done
  # The output and the checkout are the caller's: hand back what the
  # builds wrote there.
  if [ -n "${FLEDGE_OWNER:-}" ]; then
    chown -R "$FLEDGE_OWNER" /out "$@"
  fi
  exit "$status"
}

on_host() {
  local root runtimes out cache archive
  runtimes=$(cd "$1" && pwd)
  mkdir -p "$2"
  out=$(cd "$2" && pwd)
  shift 2
  root=$(cd "$(dirname "$0")/../.." && pwd)
  cd "$root"
  cache=${XDG_CACHE_HOME:-$HOME/.cache}/fledge/downloads
  mkdir -p "$cache"
  archive=$(ruby .github/scripts/fetch_pin.rb ruby platforms "$platform")
  case $archive in
    "$cache"/*) ;;
    *) echo "glibc-app.sh: $archive is not in $cache" >&2; exit 1 ;;
  esac
  docker run --rm -v "$root:/fledge" -v "$cache:/cache/fledge/downloads" -v "$runtimes:/runtimes:ro" -v "$out:/out" \
    -w /fledge -e XDG_CACHE_HOME=/cache -e SOURCE_DATE_EPOCH -e FLEDGE_OWNER="$(id -u):$(id -g)" \
    "$(pin manylinux images "$platform")" \
    .github/scripts/glibc-app.sh --in-image "$platform" "/cache/fledge/downloads/${archive#"$cache"/}" "$@"
}

if [ "${1:-}" = --in-image ]; then
  platform=${2:-}
  [ -n "${4:-}" ] || usage
  same_machine
  shift 2
  in_image "$@"
else
  platform=${1:-}
  [ -n "${4:-}" ] || usage
  same_machine
  shift
  on_host "$@"
fi
