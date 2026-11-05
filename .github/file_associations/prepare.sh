#!/bin/sh
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later

# Experiment only (experiment/file-associations). Usage:
#   prepare.sh WORK PLATFORM
#
# Builds examples/windowed_app into dist/, with its file_associations,
# then packs this checkout as the fledge gem, unpacks it into WORK/fledge
# as a framework would vendor it, copies the builder project beside it,
# whose fledge.yml sets build_tools, has Bundler lock it for PLATFORM,
# and builds it into dist/, with the runtime in FLEDGE_RUNTIME_DIR. It
# prints the size of the builder's tools folder, and of the builder
# built again without build_tools, for the size cost.
set -eu
work=$1
platform=$2
root=$(pwd)
ruby -I lib exe/fledge build -o dist examples/windowed_app
rm -rf "$work"
mkdir -p "$work"
gem build fledge.gemspec -o "$work/fledge.gem"
gem unpack "$work/fledge.gem" --target "$work"
gem spec "$work/fledge.gem" --ruby > "$work/fledge/fledge.gemspec"
cp -R .github/file_associations/builder "$work/builder"
cd "$work/builder"
bundle lock
bundle lock --add-platform "$platform"
bundle lock --add-checksums
cd "$root"
ruby -I lib exe/fledge build -o dist "$work/builder"
sed '/^build_tools:/d' "$work/builder/fledge.yml" > "$work/fledge.yml" && mv "$work/fledge.yml" "$work/builder/fledge.yml"
ruby -I lib exe/fledge build -o "$work/without" "$work/builder"
for archive in dist/Builder-"$platform".* "$work/without/Builder-$platform".*; do
  case "$archive" in *.sha256) ;; *) echo "size: $(wc -c < "$archive") bytes, $archive" ;; esac
done
echo "size: $(du -sk "dist/Builder-$platform" | cut -f1) KB unpacked with build_tools, $(du -sk "$work/without/Builder-$platform" | cut -f1) KB without"
