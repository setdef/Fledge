#!/bin/sh
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT

# apt-get update in a fresh Debian or Ubuntu container, as root, before a
# Delivery script has apt install a .deb and the packages it depends on.
#
#   apt-update.sh
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
# the mirror has not given every list in three minutes, the image's own
# hosts get four more, and if they fail too, the step fails saying so,
# inside the job's ten minutes. apt-get update calls a list it could not
# fetch a warning and exits 0, so its "W:" lines are read for that.
#
# Any other image, Debian or arm64 Ubuntu, keeps its sources and gets one
# attempt under the same four-minute limit. apt-get update runs without
# -qq, so the log says which host gave each file.
#
# This is POSIX sh on purpose: nothing here may need Ruby.

set -eu

sources=/etc/apt/sources.list.d/ubuntu.sources
archive='http://(archive|security)\.ubuntu\.com/ubuntu/?'
log=$(mktemp)

# update SECONDS: apt-get update within SECONDS, every list fetched.
update() {
  status=0
  timeout "$1" apt-get update >"$log" 2>&1 || status=$?
  cat "$log"
  if [ "$status" = 124 ]; then
    echo "apt-update.sh: apt-get update did not finish in $1 seconds"
    return 1
  fi
  if [ "$status" != 0 ] || grep -q '^W: Failed to fetch' "$log"; then
    echo "apt-update.sh: apt-get update did not fetch every list (exit $status)"
    return 1
  fi
}

if [ -f "$sources" ] && grep -Eq "^URIs: $archive\$" "$sources"; then
  cp "$sources" "$log.sources"
  sed -i -E "s#^URIs: $archive\$#URIs: http://azure.archive.ubuntu.com/ubuntu/#" "$sources"
  echo "apt-update.sh: Ubuntu's archive from http://azure.archive.ubuntu.com/ubuntu/"
  if update 180; then exit 0; fi
  cp "$log.sources" "$sources"
  echo "apt-update.sh: again, from the image's own hosts"
fi
update 240
