#!/bin/sh
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
# Prints the container images runtime/sources.yml pins under images, by
# tag and digest, for a workflow to run them by:
#
#   pinned-images.sh env [SOURCES]    a NAME=IMAGE line for each, for
#                                     GITHUB_ENV, its key in capitals
#                                     with - as _ (alpine-ruby is
#                                     ALPINE_RUBY)
#   pinned-images.sh json [SOURCES]   one images={"KEY":"IMAGE",...} line,
#                                     for GITHUB_OUTPUT, which a later
#                                     job's container names by key
#
# SOURCES is runtime/sources.yml unless given. The pins live there, not
# in the workflows, because a workflow's own token cannot push a commit
# that changes a workflow file, and the pin move pushes with that token. It runs
# the runner's own Ruby, which every GitHub-hosted Ubuntu image has, before
# any Ruby of Fledge's is set up.
set -eu
exec ruby -ryaml -rjson -e '
  mode, sources = ARGV
  images = YAML.safe_load_file(sources).fetch("images").transform_values { |pin| pin.fetch("image") }
  case mode
  when "env" then images.each { |key, image| puts "#{key.upcase.tr("-", "_")}=#{image}" }
  when "json" then puts "images=#{JSON.generate(images)}"
  else abort "usage: pinned-images.sh env|json [SOURCES]"
  end' "${1:?usage: pinned-images.sh env|json [SOURCES]}" "${2:-runtime/sources.yml}"
