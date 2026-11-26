#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT

# Builds Fledge's own Ruby for glibc Linux, tasks/ruby_archive.rb's
# archive, in Ubuntu 22.04, whose glibc 2.35 is the archive's floor
# (doc/contributors/design/runtimes.md, "Fledge's own Ruby builds").
# Every input is pinned here: the image by digest, each package apt
# installs by version, and the Ruby that runs the task by SHA-256.
#
#   .github/scripts/ruby-archive.sh PLATFORM
#
# runs the build in the image with docker, or with the program set in
# FLEDGE_CONTAINER (podman, say), on a computer of PLATFORM's
# architecture (x86_64-linux or aarch64-linux), and leaves the archive
# in tmp/ruby-archive/ruby-VERSION-PLATFORM.tar.gz, with its build logs
# in tmp/ruby-archive/PLATFORM/logs. The downloads the task makes are
# kept in the folder Fledge's builds keep them in
# ($XDG_CACHE_HOME/fledge/downloads), each checked by its SHA-256.
#
#   .github/scripts/ruby-archive.sh --in-image PLATFORM
#
# is what runs in the image: it installs the packages, downloads the
# Ruby that runs the task and checks it, runs the task, and prints the
# archive's SHA-256. It is for this image only.
#
# Ubuntu's -updates and -security pockets keep only each package's
# newest build, so a pin below stops resolving when Ubuntu publishes a
# new one, and apt fails with "Version '...' for '...' was not found".
# Move the pin on purpose: find the version the image now offers
# (apt-cache policy NAME in it), change it here, and run the build on
# both architectures.

set -euo pipefail

# ubuntu:22.04, the index of every architecture's image, from Docker Hub,
# named with its registry so that podman needs no list of them.
IMAGE=docker.io/library/ubuntu:22.04@sha256:f64b2ffc2f10ab8f8505aa56b2664bd846cbb9df87c7e2532e30f7667021c0e6

# What the task builds Ruby with: a C toolchain, Perl for OpenSSL's
# build, patchelf and binutils' readelf for bin/ruby's RPATH, xz and
# file; curl and the CA certificates to download; and the shared
# libraries the driver Ruby below links. Versions are jammy's, the same
# on amd64 and arm64.
PACKAGES=(
  build-essential=12.9ubuntu3
  gcc-11=11.4.0-1ubuntu1~22.04.3
  g++-11=11.4.0-1ubuntu1~22.04.3
  libc6=2.35-0ubuntu3.18
  libc6-dev=2.35-0ubuntu3.18
  binutils=2.38-4ubuntu2.12
  make=4.3-4.1build1
  perl=5.34.0-3ubuntu1.10
  patchelf=0.14.3-1
  xz-utils=5.2.5-2ubuntu1.2
  file=1:5.41-3ubuntu0.1
  curl=7.81.0-1ubuntu1.30
  ca-certificates=20260816ubuntu0.22.04.2
  libssl3=3.0.2-0ubuntu1.30
  libyaml-0-2=0.2.2-1build2
  zlib1g=1:1.2.11.dfsg-2ubuntu9.2
  libffi8=3.4.2-4
  libgmp10=2:6.2.1+dfsg-3ubuntu1
  libreadline8=8.1.2-1
)

# The Ruby that runs the task: rv-ruby's builds do not start on glibc
# 2.35, so ruby/setup-ruby's own build of Ruby for Ubuntu 22.04, from
# ruby/ruby-builder, at the folder it was built for. jdx/ruby's, which
# need glibc 2.17, would serve too.
DRIVER_VERSION=4.1.0-preview1
DRIVER_URL=https://github.com/ruby/ruby-builder/releases/download/ruby-$DRIVER_VERSION/ruby-$DRIVER_VERSION-ubuntu-22.04

usage() {
  echo "usage: ruby-archive.sh [--in-image] x86_64-linux|aarch64-linux" >&2
  exit 2
}

# Sets machine, the architecture uname names, and driver_arch and
# driver_sha256, ruby-builder's name for it and its build's SHA-256.
architecture() {
  case $1 in
    x86_64-linux)
      machine=x86_64 driver_arch=x64
      driver_sha256=4c53513de4cd9fdb52bd97629abe117ea2bfb4ca6653d369debb8ff6063b86c4
      ;;
    aarch64-linux)
      machine=aarch64 driver_arch=arm64
      driver_sha256=e2afab1bb67915f502b3e70918839e27a8622c5508a3df9dcf5f462955129043
      ;;
    *) usage ;;
  esac
}

# Fledge builds each platform on a computer of that platform, so a
# machine of another architecture is refused rather than emulated.
same_machine() {
  local here
  here=$(uname -m)
  [ "$here" = arm64 ] && here=aarch64
  if [ "$here" != "$machine" ]; then
    echo "ruby-archive.sh: $platform is built on $machine, and this computer is $here" >&2
    exit 1
  fi
}

in_image() {
  same_machine
  export DEBIAN_FRONTEND=noninteractive
  apt-get -o Acquire::Retries=3 update -qq
  apt-get -o Acquire::Retries=3 install -y -qq --no-install-recommends "${PACKAGES[@]}"

  local toolcache=/opt/hostedtoolcache/Ruby/$DRIVER_VERSION
  curl -fsSL --retry 3 -o /tmp/driver.tar.gz "$DRIVER_URL-$driver_arch.tar.gz"
  echo "$driver_sha256  /tmp/driver.tar.gz" | sha256sum --strict -c -
  mkdir -p "$toolcache"
  tar -xzf /tmp/driver.tar.gz -C "$toolcache" --no-same-owner
  rm /tmp/driver.tar.gz
  export PATH="$toolcache/$driver_arch/bin:$PATH"
  ruby -v

  local status=0
  ruby tasks/ruby_archive.rb "$platform" || status=$?
  # The checkout is the caller's: hand back what the build wrote there.
  if [ -n "${FLEDGE_OWNER:-}" ] && [ -d tmp/ruby-archive ]; then
    chown -R "$FLEDGE_OWNER" tmp/ruby-archive
  fi
  [ "$status" -eq 0 ] || exit "$status"
  sha256sum tmp/ruby-archive/ruby-*-"$platform".tar.gz
}

on_host() {
  same_machine
  local root cache container owner=()
  root=$(cd "$(dirname "$0")/../.." && pwd)
  cache=${XDG_CACHE_HOME:-$HOME/.cache}/fledge/downloads
  container=${FLEDGE_CONTAINER:-docker}
  mkdir -p "$cache"
  # Docker's root is the computer's root, so the build hands back what it
  # wrote. Rootless podman's root is the account that runs it, so what the
  # build wrote is the account's, and a chown to the account's ID,
  # which is another user's inside its user namespace, would take it away.
  [ "$(basename "$container")" = podman ] || owner=(-e "FLEDGE_OWNER=$(id -u):$(id -g)")
  "$container" run --rm -v "$root:/fledge" -v "$cache:/cache/fledge/downloads" -w /fledge \
    -e XDG_CACHE_HOME=/cache ${owner[@]+"${owner[@]}"} "$IMAGE" \
    .github/scripts/ruby-archive.sh --in-image "$platform"
}

if [ "${1:-}" = --in-image ]; then
  platform=${2:-}
  architecture "$platform"
  in_image
else
  platform=${1:-}
  architecture "$platform"
  on_host
fi
