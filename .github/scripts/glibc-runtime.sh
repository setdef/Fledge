#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT

# Builds a glibc Linux runtime (ruby tasks/runtime_builder.rb) in
# manylinux_2_28, whose glibc 2.28 is the runtime's floor, so that the
# launcher, bin/ruby, and libxcrypt, which the builder compiles, need no
# newer glibc than that. The Ruby they link, jdx/ruby's, is built in
# manylinux2014 and needs only glibc 2.17.
#
#   .github/scripts/glibc-runtime.sh PLATFORM
#
# runs the build in the image, on a computer of PLATFORM's architecture
# (x86_64-linux or aarch64-linux), and leaves the runtime where rake
# runtime leaves it, in tmp/runtime/. It runs the image with docker, as
# CI's runners have it (podman's docker command serves too). On a
# computer without docker, and with no root to install it, it unpacks
# the image with crane (go-containerregistry's, which mise.toml pins on
# Linux) and enters it with bubblewrap, which needs no root where the
# kernel lets users make user namespaces, as root of a namespace of its
# own, with the checkout and the downloads bound in as docker binds
# them. It first downloads the
# platform's Ruby pin and its AlmaLinux Perl packages into the folder
# Fledge's builds keep downloads in ($XDG_CACHE_HOME/fledge/downloads),
# each checked by its SHA-256, with the computer's own Ruby, since that
# pin is also the Ruby that runs the build in the image, which has no
# Ruby of its own.
#
#   .github/scripts/glibc-runtime.sh --in-image PLATFORM ARCHIVE PACKAGE...
#
# is what runs in the image: it checks ARCHIVE, the Ruby pin as the image
# sees it, and each PACKAGE, runtime/sources.yml's almalinux-perl in its
# order, by their SHA-256 again, installs the packages together, and
# runs the builder with that Ruby. It is for this image only.
#
# The image is PyPA's, pinned by digest in runtime/sources.yml
# (manylinux): manylinux_2_28 is AlmaLinux 8 with a newer GCC from its
# gcc-toolset, binutils, make, Perl, xz, and patchelf, which is
# everything the builder runs but Perl's open module, which AlmaLinux
# ships apart, as perl-open, and libxcrypt's configure loads; that
# package and the two it needs that the image lacks are pinned beside
# the image (almalinux-perl). manylinux2014, whose
# glibc is 2.17, would lower the floor further, but its GCC 10 analyzer
# reports a double free in the launcher that is not there, and the
# launcher's analysis stays a gate (runtimes.md, "The glibc floor").
# Move the pins on purpose, and rebuild both platforms.

set -euo pipefail

usage() {
  echo "usage: glibc-runtime.sh [--in-image] x86_64-linux|aarch64-linux [ARCHIVE PACKAGE...]" >&2
  exit 2
}

# Sets machine, the architecture uname names.
architecture() {
  case $1 in
    x86_64-linux) machine=x86_64 ;;
    aarch64-linux) machine=aarch64 ;;
    *) usage ;;
  esac
}

# Prints the value at the keys given in runtime/sources.yml.
pin() {
  ruby -ryaml -e 'puts YAML.safe_load_file("runtime/sources.yml").dig(*ARGV)' "$@"
}

# Prints the keys of the pin of each of runtime/sources.yml's
# almalinux-perl packages for the platform, a package a line.
perl_packages() {
  ruby -ryaml -e '
    YAML.safe_load_file("runtime/sources.yml").fetch("almalinux-perl").each do |name, pin|
      puts ["almalinux-perl", name, *(pin.key?("platforms") ? ["platforms", ARGV[0]] : [])].join(" ")
    end' "$platform"
}

# Fledge builds each platform on a computer of that platform, so a
# machine of another architecture is refused rather than emulated.
same_machine() {
  local here
  here=$(uname -m)
  [ "$here" = arm64 ] && here=aarch64
  if [ "$here" != "$machine" ]; then
    echo "glibc-runtime.sh: $platform is built on $machine, and this computer is $here" >&2
    exit 1
  fi
}

in_image() {
  same_machine
  local archive=$1 sha256 driver=/tmp/driver keys index=0
  shift
  local packages=("$@")
  sha256=$(sed -n "/^    $platform:\$/,/sha256:/{/sha256:/{s/^ *sha256: *//p;q;};}" runtime/sources.yml)
  echo "$sha256  $archive" | sha256sum --strict -c -
  mkdir -p "$driver"
  tar -xzf "$archive" -C "$driver" --no-same-owner
  PATH="$(dirname "$(find "$driver" -maxdepth 3 -path '*/bin/ruby' -print -quit)"):$PATH"
  export PATH CC=gcc
  ruby -v
  while read -r keys; do
    # shellcheck disable=SC2086 # the keys are words, one for each key
    echo "$(pin $keys sha256)  ${packages[index]:?one PACKAGE for each almalinux-perl package}" | sha256sum --strict -c -
    index=$((index + 1))
  done < <(perl_packages)
  [ "$index" = "${#packages[@]}" ] || usage
  rpm --install --nosignature "${packages[@]}"
  # sed, not head, reads each to its end, so that no program dies of
  # SIGPIPE under pipefail.
  gcc --version | sed -n 1p
  ldd --version | sed -n 1p

  local status=0
  ruby tasks/runtime_builder.rb "$platform" || status=$?
  # The checkout and the downloads are the caller's: hand back what the
  # build wrote there.
  if [ -n "${FLEDGE_OWNER:-}" ]; then
    chown -R "$FLEDGE_OWNER" "$(dirname "$archive")/.."
    [ ! -d tmp/runtime ] || chown -R "$FLEDGE_OWNER" tmp/runtime
  fi
  exit "$status"
}

on_host() {
  same_machine
  local root cache archive keys file packages=()
  root=$(cd "$(dirname "$0")/../.." && pwd)
  cd "$root"
  cache=${XDG_CACHE_HOME:-$HOME/.cache}/fledge/downloads
  mkdir -p "$cache"
  archive=$(ruby .github/scripts/fetch_pin.rb ruby platforms "$platform")
  while read -r keys; do
    # shellcheck disable=SC2086 # the keys are words, one for each key
    packages+=("$(ruby .github/scripts/fetch_pin.rb $keys)")
  done < <(perl_packages)
  for file in "$archive" "${packages[@]}"; do
    case $file in
      "$cache"/*) ;;
      *) echo "glibc-runtime.sh: $file is not in $cache" >&2; exit 1 ;;
    esac
  done
  local image
  image=$(pin manylinux images "$platform")
  set -- .github/scripts/glibc-runtime.sh --in-image "$platform" "/cache/fledge/downloads/${archive#"$cache"/}" \
    "${packages[@]/#"$cache"//cache/fledge/downloads}"
  if command -v docker >/dev/null; then
    exec docker run --rm -v "$root:/fledge" -v "$cache:/cache/fledge/downloads" -w /fledge \
      -e XDG_CACHE_HOME=/cache -e SOURCE_DATE_EPOCH -e FLEDGE_OWNER="$(id -u):$(id -g)" "$image" "$@"
  fi
  unprivileged "$image" "$root" "$cache" "$@"
}
# unprivileged IMAGE ROOT CACHE COMMAND...: runs COMMAND in IMAGE as
# docker run would, with no daemon and no root. crane export writes the
# image's filesystem, its layers applied in order, as one tar; the
# image's environment is its config's Env. Files it writes are already
# the caller's, so no FLEDGE_OWNER.
unprivileged() {
  local image=$1 root=$2 cache=$3 rootfs status=0 variable
  shift 3
  for variable in crane bwrap; do
    command -v "$variable" >/dev/null || {
      echo "glibc-runtime.sh: no docker, and no $variable to run $image without them" >&2
      exit 1
    }
  done
  rootfs=$(mktemp -d "${TMPDIR:-/tmp}/manylinux.XXXXXX")
  crane export "$image" - | tar -x -C "$rootfs" --no-same-owner --delay-directory-restore --exclude='dev/*'
  local environment=()
  # shellcheck disable=SC2016 # Ruby's $stdin, not the shell's
  while IFS= read -r variable; do
    environment+=(--setenv "${variable%%=*}" "${variable#*=}")
  done < <(crane config "$image" | ruby -rjson -e 'puts JSON.parse($stdin.read).dig("config", "Env")')
  [ -z "${SOURCE_DATE_EPOCH:-}" ] || environment+=(--setenv SOURCE_DATE_EPOCH "$SOURCE_DATE_EPOCH")
  bwrap --unshare-user --uid 0 --gid 0 --unshare-pid --unshare-ipc --unshare-uts --die-with-parent \
    --bind "$rootfs" / --proc /proc --dev /dev --tmpfs /tmp --ro-bind /etc/resolv.conf /etc/resolv.conf \
    --bind "$root" /fledge --bind "$cache" /cache/fledge/downloads --chdir /fledge \
    --clearenv "${environment[@]}" --setenv HOME /root --setenv XDG_CACHE_HOME /cache "$@" || status=$?
  # The image keeps some folders read-only, which rm cannot empty.
  chmod -R u+w "$rootfs"
  rm -rf "$rootfs"
  exit "$status"
}

if [ "${1:-}" = --in-image ]; then
  platform=${2:-}
  architecture "$platform"
  [ -n "${4:-}" ] || usage
  shift 2
  in_image "$@"
else
  platform=${1:-}
  architecture "$platform"
  on_host
fi
