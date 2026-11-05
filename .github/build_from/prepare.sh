#!/bin/sh
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later

# Experiment only (experiment/build-from). Usage: prepare.sh WORK PLATFORM
#
# Packs this checkout as the fledge gem, unpacks it into WORK/fledge as
# a framework would vendor it, copies the builder project beside it, has
# Bundler lock it for PLATFORM, and builds it with fledge build into
# dist/, with the runtime in FLEDGE_RUNTIME_DIR.
set -eu
work=$1
platform=$2
root=$(pwd)
rm -rf "$work"
mkdir -p "$work"
gem build fledge.gemspec -o "$work/fledge.gem"
gem unpack "$work/fledge.gem" --target "$work"
gem spec "$work/fledge.gem" --ruby > "$work/fledge/fledge.gemspec"
cp -R .github/build_from/builder "$work/builder"
cd "$work/builder"
bundle lock
bundle lock --add-platform "$platform"
bundle lock --add-checksums
cat Gemfile.lock
cd "$root"
ruby -I lib exe/fledge build -o dist "$work/builder"
