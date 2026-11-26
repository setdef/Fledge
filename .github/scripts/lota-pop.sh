#!/bin/sh
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT

# Lays out examples/lota_pop for a build, as its README.md's "Get Lota's
# gems" says: Lota is not on RubyGems.org, so each release of
# github.com/setdef/Lota carries its gems. This takes them from that
# release into the project's vendor/cache, each checked against the
# SHA-256 pinned here (the release's SHA256SUMS, and the project's
# Gemfile.lock holds the same), and, for a phone, unpacks the host
# Lota's source gem carries, the startup files SDL3 needs, into the
# project's host folder, where its fledge.yml names it, and the Rice
# gem, which a phone's build compiles Lota's extension with when its
# phone Ruby is not the one Lota's release built the extension against
# (README.md, "Build it with Fledge").
#
#   lota-pop.sh PROJECT [GEM_PLATFORM]
#
# GEM_PLATFORM is the platform of the gem a desktop build needs, such as
# arm64-darwin or x86_64-linux-gnu. Without one, only the source gem is
# fetched, which a phone's build compiles Lota's extension from.

set -eu

version=0.8.0
# Rice, a C++ library of headers, at the version Lota's extconf.rb pins,
# and the SHA-256 that rubygems.org lists for its gem.
rice_version=4.12.0
rice_sha256=672c369ca706ff5be46695537f51e1a3db262c1b789af5b967ef477f25111dfd
base="https://github.com/setdef/Lota/releases/download/v$version"

project=${1:?usage: lota-pop.sh PROJECT [GEM_PLATFORM]}
platform=${2:-}

sha256_of() {
  case $1 in
    "") echo d09ec4ac7db98bebd12a26b235bad4ed7d13dd6b158b65899dd7e5d579ed23b3 ;;
    aarch64-linux-gnu) echo 72d73704b55040533d645f9fa72004f99a25e19d35af7faf3fdec2570c32d572 ;;
    aarch64-mingw-ucrt) echo 136f1d7f5942e2887d8aeaef17dfdbbb6bd23618000411bd6dcbecc88e649d63 ;;
    arm64-darwin) echo 899beadc4d30160c71e4dcbf695913dc6308a825a6dd8d615f6e1cc2d71c62c5 ;;
    x64-mingw-ucrt) echo dcce5733dd28cb352450c8333261209752d25e65efd04f696e5b8ca7b2cd23e8 ;;
    x86_64-linux-gnu) echo 3125ee93bb956b4c1d3f08b4159b7a39b8e14f53b0bb76d3d57474d19c7d8ea3 ;;
    *) echo "lota-pop.sh: no Lota $version gem for $1" >&2; exit 2 ;;
  esac
}

fetch() {
  gem_platform=$1
  file=lota-$version${gem_platform:+-$gem_platform}.gem
  want=$(sha256_of "$gem_platform")
  mkdir -p "$project/vendor/cache"
  curl -fsSL --retry 3 -o "$project/vendor/cache/$file" "$base/$file"
  if command -v sha256sum > /dev/null; then
    have=$(sha256sum "$project/vendor/cache/$file" | cut -d' ' -f1)
  else
    have=$(shasum -a 256 "$project/vendor/cache/$file" | cut -d' ' -f1)
  fi
  [ "$have" = "$want" ] || { echo "::error::$file is $have, not the pinned $want" >&2; exit 1; }
}

fetch ""
[ -z "$platform" ] || fetch "$platform"

# The host is in the source gem, which a phone's build compiles Lota from.
if [ -z "$platform" ]; then
  unpacked=$(mktemp -d)
  gem unpack "$project/vendor/cache/lota-$version.gem" --target "$unpacked" > /dev/null
  rm -rf "$project/host"
  cp -R "$unpacked/lota-$version/ext/lota/phone/host" "$project/host"
  rm -rf "$unpacked"

  # Rice goes under vendor/cache, which fledge build never puts in the
  # app, for the build option --with-rice-dir to name.
  work=$(mktemp -d)
  curl -fsSL --retry 3 -o "$work/rice-$rice_version.gem" "https://rubygems.org/downloads/rice-$rice_version.gem"
  if command -v sha256sum > /dev/null; then
    have=$(sha256sum "$work/rice-$rice_version.gem" | cut -d' ' -f1)
  else
    have=$(shasum -a 256 "$work/rice-$rice_version.gem" | cut -d' ' -f1)
  fi
  [ "$have" = "$rice_sha256" ] || { echo "::error::rice-$rice_version.gem is $have, not the pinned $rice_sha256" >&2; exit 1; }
  rm -rf "$project/vendor/cache/rice-$rice_version"
  gem unpack "$work/rice-$rice_version.gem" --target "$project/vendor/cache" > /dev/null
  rm -rf "$work"
fi
