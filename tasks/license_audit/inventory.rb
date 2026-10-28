# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "rubygems"
require_relative "../../lib/fledge/license_policy"

class LicenseAudit
  # The components an audited tree may hold: those runtime/licenses.yml
  # maps for its platform, and a component for each gem specification in
  # the tree, with the files and binaries each may own.
  class Inventory
    # The inventory of what +audit+ audits: its tree, platform, and map.
    def initialize(audit)
      @audit = audit
    end

    # The components runtime/licenses.yml maps for the audit's platform.
    def map_components
      @audit.map.fetch("components").filter_map do |entry|
        next unless entry.fetch("platforms").include?(@audit.platform)

        Component.from_map(entry, @audit.method(:expand))
      end
    end

    # A component for each gem specification in the tree, owning the
    # gem's files where RubyGems keeps them, in each of the runtime's Ruby
    # trees that holds it (LicenseAudit#prefixes).
    def gem_components
      root = "#{@audit.prefix}lib/ruby/gems/4.0.0"
      Dir.glob(File.join(@audit.tree, root, "specifications", "{,default/}*.gemspec")).map do |path|
        spec = Gem::Specification.load(path) or raise "#{path}: not a gem specification"
        component(spec, root, path)
      end.uniq(&:id)
    end

    # The component of the gem +spec+, whose files are under the pattern
    # +root+, and whose specification is the file +path+, in the gem
    # folder its gem_dir is in.
    private def component(spec, root, path)
      full = spec.full_name
      override = @audit.map.fetch("gems", {}).fetch(spec.name, {})
      default = path.include?("/specifications/default/")
      gems = File.dirname(path, default ? 3 : 2).delete_prefix("#{@audit.tree}/")
      Component.new(id: "gem-#{full}", name: "#{spec.name} (#{default ? 'default' : 'bundled'} gem)", version: spec.version.to_s,
        license: override.fetch("license") { Fledge::LicensePolicy.gem_license(spec.licenses) }, kind: "program",
        first_party: false, download: "https://rubygems.org/gems/#{spec.name}/versions/#{spec.version}", notice: nil, source: nil,
        ships: default ? "Ruby's default gem; its code is in lib/ruby/4.0.0" : "files under lib/ruby/gems/4.0.0/gems/#{full}",
        supplier: nil, files: gem_files(root, spec), binaries: gem_binaries(root, full), embedded: [], sha256: {},
        fallback: false, gem_dir: "#{gems}/gems/#{full}")
    end

    private def gem_files(root, spec)
      full = spec.full_name
      [
        "#{root}/gems/#{full}/**/*",
        "#{root}/specifications/#{full}.gemspec",
        "#{root}/specifications/default/#{full}.gemspec",
        "#{root}/extensions/*/*/#{full}/**/*",
        "#{root}/cache/#{full}.gem",
        "#{root}/build_info/#{full}.info",
        "#{root}/doc/#{full}/**/*",
        "#{root}/plugins/#{spec.name}_plugin.rb",
        *spec.executables.map { |executable| "{#{root}/,#{@audit.prefix}}bin/#{executable}{,.bat,.cmd}" },
      ]
    end

    private def gem_binaries(root, full)
      [
        "#{root}/gems/#{full}/**/*.{so,bundle,dll}",
        "#{root}/gems/#{full}/ext/**/*.{o,a}",
        "#{root}/extensions/*/*/#{full}/**/*.{so,bundle,dll}",
        "#{root}/extensions/*/*/#{full}/**/*.dSYM/Contents/Resources/DWARF/*",
      ]
    end
  end
end
