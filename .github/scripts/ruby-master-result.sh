#!/bin/sh
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT

# Records one job's result in ruby-master.yml, for its report job:
#
#   ruby-master-result.sh "Runtime (android)" success
#
# writes OUTCOME into tmp/ruby-master-result/, in a file named for the
# job, which the job uploads as an artifact of its own.
set -eu

job=${1:?usage: ruby-master-result.sh JOB OUTCOME}
outcome=${2:-missing}
mkdir -p tmp/ruby-master-result
printf '%s\n' "$outcome" >"tmp/ruby-master-result/$(printf '%s' "$job" | tr -c 'A-Za-z0-9' '_').txt"
