#!/bin/sh
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
# Makes every Gradle build on this runner patient with the Maven
# repositories it downloads from. Each CI job that runs
# Gradle runs it before Gradle starts:
#
#   .github/scripts/gradle-patience.sh
#
# It writes two of Gradle's own settings into gradle.properties in the
# Gradle user home ($GRADLE_USER_HOME, or ~/.gradle), where Gradle reads
# every build's system properties from, whichever project it builds and
# however it is started (by the pinned Gradle, a project's wrapper, or
# a daemon). The pinned Gradle retries a download that failed for a
# reason that is the repository's or the network's (an answer of 408,
# 429, or any 5xx, a refused or reset connection, a timeout), waiting
# before each try twice as long as before the last, and reports
# anything else, a 404 or a build error, at once, as it always does
# (ErrorHandlingModuleComponentRepository and NetworkingIssueVerifier in
# its dependency-management jar). By default it tries 3 times, a second
# and then two apart. Here it tries 7 times, from 10 seconds apart: it
# waits 10, 20, 40, 80, 160, and 320 seconds, ten and a half minutes in
# all, before it gives a download up, which a Gradle job's time limit
# leaves room for. Gradle keeps each file it downloaded, so a retry asks
# only for the one that failed.

set -eu
home=${GRADLE_USER_HOME:-$HOME/.gradle}
mkdir -p "$home"
properties=$home/gradle.properties
for setting in \
  systemProp.org.gradle.internal.repository.max.tentatives=7 \
  systemProp.org.gradle.internal.repository.initial.backoff=10000; do
  grep -qxF "$setting" "$properties" 2>/dev/null || echo "$setting" >>"$properties"
done
echo "Gradle retries downloads patiently: $properties"
