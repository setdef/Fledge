#!/bin/sh
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT

# Builds into dist/ the builder app that Delivery runs fledge build
# --from inside (deliver-from.sh, deliver-from.ps1): packs this checkout
# as the fledge gem, unpacks it into WORK/fledge as a framework would
# vendor it, copies the builder project beside it, whose fledge.yml sets
# build_tools, has Bundler lock it for PLATFORM, and builds it with the
# runtime in FLEDGE_RUNTIME_DIR (ADR 032;
# doc/contributors/design/desktop-apps.md, "Building from a built app").
#
#   .github/scripts/prepare-from.sh WORK PLATFORM
set -eu
work=$1
platform=$2
root=$(pwd)
rm -rf "$work"
mkdir -p "$work"
gem build fledge.gemspec -o "$work/fledge.gem"
gem unpack "$work/fledge.gem" --target "$work"
gem spec "$work/fledge.gem" --ruby > "$work/fledge/fledge.gemspec"
cp -R test/fixtures/from/builder "$work/builder"
cd "$work/builder"
# The workflow's BUNDLE_FROZEN is for lockfiles a commit holds. This one
# is written here, and the fledge it locks depends on no other gem.
BUNDLE_FROZEN=false bundle lock
BUNDLE_FROZEN=false bundle lock --add-platform "$platform"
BUNDLE_FROZEN=false bundle lock --add-checksums
cd "$root"
ruby -I lib exe/fledge build -o dist "$work/builder"
