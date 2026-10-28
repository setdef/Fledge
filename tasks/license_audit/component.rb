# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

class LicenseAudit
  # Something the tree ships: a component from the map, or a gem.
  class Component < Data.define(:id, :name, :version, :license, :kind, :first_party, :download, :notice, :source, :ships,
    :supplier, :files, :binaries, :embedded, :sha256, :fallback, :gem_dir)
    def self.from_map(entry, expand)
      patterns = -> (key) { Array(entry[key]).map { |pattern| pattern.is_a?(Hash) ? pattern.transform_keys(&:to_s) : pattern } }
      new(id: entry.fetch("id"), name: entry.fetch("name"), version: expand.call(entry.fetch("version").to_s),
        license: entry.fetch("license"), kind: entry.fetch("kind"), first_party: entry.fetch("first_party", false),
        download: entry.fetch("download"), notice: entry["notice"], source: entry["source"], ships: expand.call(entry.fetch("ships")),
        supplier: entry["supplier"], files: patterns.call("files"), binaries: patterns.call("binaries"),
        embedded: Array(entry["embedded"]), sha256: entry.fetch("sha256", {}), fallback: entry.fetch("fallback", false), gem_dir: nil)
    end
  end
end
