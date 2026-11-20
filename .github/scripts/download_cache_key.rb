# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

# Readies the download cache (DownloadCache.folder) for CI to save, after
# a job's downloads: removes the files of every SHA-256 that no pin in
# runtime/sources.yml or tasks/ruby_spec.rb names any more, then writes
# files=DIGEST, the SHA-256 of the list of files left (DownloadCache#digest),
# to GITHUB_OUTPUT. DIGEST is empty when the folder holds nothing. It
# runs only in a GitHub Actions job (GITHUB_ACTIONS), so it never prunes
# a developer's own cache, which the builds of other commits share.
#
#   ruby .github/scripts/download_cache_key.rb
require_relative "../../tasks/download_cache"

abort "download_cache_key: only for a GitHub Actions job, which sets GITHUB_ACTIONS and GITHUB_OUTPUT" unless ENV["GITHUB_ACTIONS"] == "true" && ENV["GITHUB_OUTPUT"]

root = File.expand_path("../..", __dir__)
pinned = %w[runtime/sources.yml tasks/ruby_spec.rb].flat_map { |path| File.read(File.join(root, path)).scan(/\b\h{64}\b/) }
cache = DownloadCache.new
cache.prune(pinned)
File.write(ENV.fetch("GITHUB_OUTPUT"), "files=#{cache.digest}\n", mode: "a")
