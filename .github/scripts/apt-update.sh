#!/bin/sh
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT

# apt-get update in a fresh Debian or Ubuntu container, as root, and the
# download of every package a Delivery job's later steps have apt
# install, before they install a .deb and the packages it depends on.
#
#   apt-update.sh [PACKAGE | ./DIR/FILE.deb]...
#
# A .deb brings the packages it depends on, as apt-get install resolves
# them for it. apt reads an argument as a file only when it begins with
# /, ./, or ../ (AddIfVolatile in apt's apt-private/private-install.cc
# at 2.8.3); delivered/FILE.deb it reads as a package named delivered.
#
# An amd64 ubuntu:24.04 image names two hosts in
# /etc/apt/sources.list.d/ubuntu.sources, http://archive.ubuntu.com/ubuntu/
# and http://security.ubuntu.com/ubuntu/, and from GitHub's x86_64 runners
# they sometimes answer slowly or not at all: five of fifteen such jobs
# from 2026-11-15 to 11-19 spent 80 to 586 seconds in apt where the rest
# spent 20 to 28, and two ran into the job's limit, while Debian's
# deb.debian.org, Ubuntu's ports.ubuntu.com for arm64, and the runners'
# own apt steps never did. Those runners fetch from Canonical's mirror in
# Azure, http://azure.archive.ubuntu.com/ubuntu/ (actions/runner-images,
# images/ubuntu/scripts/build/configure-apt-sources.sh), so in amd64
# Ubuntu this fetches from it too. It carries the same archive, signed by
# the same key, which apt checks against the image's own keyring, so apt
# resolves and installs the same packages as from archive.ubuntu.com.
#
# apt's own bounds cannot hold a stalled host to a time: its http Timeout
# and Retries apply to each file, one file after another (apt.conf(5),
# Retries; apt-transport-http(1), Acquire::http::Timeout), and a mirror
# list (apt-transport-mirror(1)) tries the stalled mirror first again for
# every file. Measured on Ubuntu 24.04's apt 2.8.4 with a first mirror that
# accepts and never answers, Retries 1 and Timeout 15 fetched 13 files in
# 900 seconds, apt's defaults 2. So the time limit is this script's: if
# the mirror has not given every list and package in three minutes, the
# image's own hosts get four more, and if they fail too, the step fails
# saying so, inside the job's ten minutes. apt-get update calls a list it
# could not fetch a warning and exits 0, so its "W:" lines are read for
# that.
#
# The packages are fetched here, under the same limit, because a later
# apt-get install fetches from the host the lists came from, with no
# bound but the job's: after a fallback, the very hosts that stalled. A
# package apt finds in its archives folder, at the size the lists give,
# it takes from there and downloads nothing (pkgAcqArchive in apt's
# apt-pkg/acquire-item.cc). That folder is one of this script's own,
# because Debian's images delete every .deb in /var/cache/apt/archives
# after each dpkg run (the docker-clean file debuerreotype writes,
# scripts/debuerreotype-minimizing-config at e63dab16), which would
# leave the second install to download again.
#
# Any other image, Debian or arm64 Ubuntu, keeps its sources and gets one
# attempt under the same four-minute limit. apt-get runs without -qq, so
# the log says which host gave each file.
#
# This is POSIX sh on purpose: nothing here may need Ruby.

set -eu

sources=/etc/apt/sources.list.d/ubuntu.sources
archive='http://(archive|security)\.ubuntu\.com/ubuntu/?'
log=$(mktemp)

mkdir -p /var/cache/apt/delivery/partial
cat >/etc/apt/apt.conf.d/50delivery-archives <<'CONF'
Dir::Cache::Archives "/var/cache/apt/delivery/";
CONF

# fetch SECONDS [PACKAGE]...: within SECONDS, apt-get update, every list
# fetched, and every PACKAGE downloaded with what it depends on.
fetch() {
  limit=$1
  shift
  status=0
  timeout "$limit" sh -c 'apt-get update && { [ "$#" = 0 ] || DEBIAN_FRONTEND=noninteractive apt-get install --download-only -y "$@"; }' \
    sh "$@" >"$log" 2>&1 || status=$?
  cat "$log"
  if [ "$status" = 124 ]; then
    echo "apt-update.sh: apt-get did not fetch the lists and packages in $limit seconds"
    return 1
  fi
  if [ "$status" != 0 ] || grep -q '^W: Failed to fetch' "$log"; then
    echo "apt-update.sh: apt-get did not fetch every list and package (exit $status)"
    return 1
  fi
}

if [ -f "$sources" ] && grep -Eq "^URIs: $archive\$" "$sources"; then
  cp "$sources" "$log.sources"
  sed -i -E "s#^URIs: $archive\$#URIs: http://azure.archive.ubuntu.com/ubuntu/#" "$sources"
  echo "apt-update.sh: Ubuntu's archive from http://azure.archive.ubuntu.com/ubuntu/"
  if fetch 180 "$@"; then exit 0; fi
  cp "$log.sources" "$sources"
  echo "apt-update.sh: again, from the image's own hosts"
fi
fetch 240 "$@"
