# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "digest"
require "fileutils"
require "json"
require "rubygems/package"
require "tmpdir"
require_relative "../lib/fledge/mobile_platform"
require_relative "../lib/fledge/mobile_project"
require_relative "../lib/fledge/platform"
require_relative "../lib/fledge/runtime_contents"
require_relative "../lib/fledge/runtime_gem"
require_relative "../lib/fledge/runtimes"

# Builds the gems a release would publish on RubyGems.org (ADR 030), from
# the release's own assets, for a person to push by hand: no task here
# pushes anything, and agents never do (AGENTS.md, Releasing).
#
# A release's assets are pinned in the gem by SHA-256 before it is tagged
# (ADR 014). Each runtime gem carries its target's assets byte for byte
# in its runtime folder, so the gem that pins them checks them there as
# it checks a download, and the plain fledge gem, built from the source
# tree whose pins name those assets, depends on the runtime gem of its
# own version, as sorbet depends on sorbet-static. Every pinned asset
# goes into exactly one gem, the LGPL source bundle and NOTICES beside the
# runtime they are for, and an asset that is not the one pinned stops the
# build. RubyGems writes the same bytes for the same files and spec on
# every run (Gem.source_date_epoch), so anyone can build a release's gems
# again from its assets and compare their SHA-256s.
module ReleaseGems
  # The assets are not the ones the source tree pins, or a gem would not
  # go to RubyGems.org.
  class Mismatch < StandardError; end

  # RubyGems.org's front proxy takes a request body of at most 500 MiB
  # (rubygems/rubygems.org config/deploy/nginx-configmap.yaml.erb,
  # client_max_body_size 500M, at 8b646ca4), so a bigger gem cannot be
  # pushed.
  LIMIT = 500 * 1024 * 1024

  # Where a gem may be pushed from 1.0.0, when a person publishes Fledge
  # there (decisions, 2026-11-03).
  RUBYGEMS = "https://rubygems.org"

  # The asset of each kind a target may have, by the suffix after
  # fledge-runtime-VERSION-TARGET (RuntimeBuilder#assets).
  SUFFIXES = %w[.tar.gz -dev.tar.gz -NOTICES.txt .spdx.json -lgpl-sources.tar.gz].freeze

  # Builds every gem into +out+ and returns their paths, the fledge gem
  # last, the order they are pushed in: each runtime gem for a desktop
  # platform, each phone's, and fledge. +assets+ is a folder of the
  # release's assets (or of folders of them, one per artifact); +root+ is
  # the source tree of the release, whose fledge.gemspec the fledge gem is
  # built from; +pins+ is the file the assets are checked against, its
  # lib/fledge/SHA256SUMS, which the fledge gem carries. Raises Mismatch,
  # and builds no gem, when the assets are not exactly the ones pinned.
  def self.build(assets:, out:, root: File.expand_path("..", __dir__), pins: File.join(root, "lib", "fledge", "SHA256SUMS"))
    fledge = Dir.chdir(root) { Gem::Specification.load(File.join(root, "fledge.gemspec")) } or raise Mismatch, "#{root} has no fledge.gemspec"
    version = fledge.version.to_s
    files = check(assets, read_pins(pins), version)
    FileUtils.mkdir_p(out)
    built = files.map { |target, paths| runtime_gem(target, paths, fledge, out) }
    built << fledge_gem(fledge, root, out)
    oversize = built.select { |path| File.size(path) > LIMIT }
    raise Mismatch, "Bigger than RubyGems.org takes (#{LIMIT} bytes): #{oversize.join(', ')}" unless oversize.empty?

    File.write(File.join(out, "SHA256SUMS"), built.map { |path| "#{Digest::SHA256.file(path).hexdigest}  #{File.basename(path)}\n" }.sort.join)
    built
  end

  # Where each gem may be pushed: RubyGems.org for 1.0.0 and later, the
  # versions a person publishes there; nowhere for an earlier one, as the
  # gemspec says, so a gem built before 1.0 cannot be pushed by mistake.
  def self.push_host(version)
    (Gem::Version.new(version) >= Gem::Version.new("1.0.0")) ? RUBYGEMS : "https://fledge.invalid"
  end

  # The SHA-256 of each file named in the sha256sum file +path+.
  def self.read_pins(path)
    File.readlines(path, chomp: true).to_h do |line|
      sha256, name = line.split(" ", 2)
      [name.to_s.strip.delete_prefix("*"), sha256.to_s.downcase]
    end
  end

  # The path of every pinned asset in +folder+, by target, each checked
  # against its pin.
  def self.check(folder, pinned, version)
    found = Dir.glob("**/*", base: folder).select { |path| File.file?(File.join(folder, path)) }
    by_name = found.to_h { |path| [File.basename(path), File.join(folder, path)] }
    by_target = [*Fledge::Platform.names, *Fledge::MobilePlatform.names].to_h do |target|
      [target, SUFFIXES.map { |suffix| "fledge-runtime-#{version}-#{target}#{suffix}" } & pinned.keys]
    end
    problems = problems(pinned, by_name, by_target, version)
    raise Mismatch, "The assets are not the ones #{version} pins: #{problems.join('; ')}" unless problems.empty?

    by_target.transform_values { |names| names.map { |name| by_name.fetch(name) } }
  end

  def self.problems(pinned, by_name, by_target, version)
    [
      *(pinned.keys - by_target.values.flatten).map { |name| "#{name} is pinned but belongs to no runtime gem" },
      *by_target.filter_map { |target, names| "no runtime for #{target} is pinned" unless names.include?(Fledge::Runtimes.file_name(target, version:)) },
      *pinned.filter_map do |name, sha256|
        path = by_name[name]
        next "#{name} is missing" unless path

        actual = Digest::SHA256.file(path).hexdigest
        "#{name} has SHA-256 #{actual}, and #{sha256} is pinned" unless actual == sha256
      end,
    ]
  end

  def self.runtime_gem(target, paths, fledge, out)
    gem = Fledge::RuntimeGem.new(target:)
    Dir.mktmpdir("runtime-gem") do |stage|
      FileUtils.mkdir_p(File.join(stage, Fledge::RuntimeGem::FOLDER))
      files = paths.sort.map do |path|
        inside = File.join(Fledge::RuntimeGem::FOLDER, File.basename(path))
        FileUtils.cp(path, File.join(stage, inside))
        inside
      end
      spec = runtime_spec(gem, fledge, files, paths)
      Dir.chdir(stage) { build_quietly(spec, File.join(out, spec.file_name)) }
    end
  end

  def self.runtime_spec(gem, fledge, files, paths)
    runtime = paths.find { |path| File.basename(path) == Fledge::Runtimes.file_name(gem.target, version: fledge.version.to_s) }
    Gem::Specification.new do |spec|
      spec.name = gem.name
      spec.version = fledge.version
      spec.platform = gem.platform
      spec.authors = fledge.authors
      spec.email = fledge.email
      spec.homepage = fledge.homepage
      spec.summary = "The runtime fledge build copies an app into, for #{gem.target}."
      spec.description = "Fledge #{fledge.version}'s relocatable Ruby and launcher for #{gem.target}, with its SBOM, " \
        "its NOTICES, and the source its licenses ask Fledge to publish. Install fledge; it depends on this gem."
      spec.licenses = licenses(paths.find { |path| path.end_with?(".spdx.json") })
      spec.files = files
      spec.require_paths = [Fledge::RuntimeGem::FOLDER]
      spec.required_ruby_version = ruby_requirement(runtime.to_s, gem)
      spec.metadata = metadata(fledge)
    end
  end

  # The Rubies a runtime gem installs on: its runtime's Ruby minor, the
  # one fledge build accepts (ADR 028, section 3), with no previews of the
  # next, as nokogiri's precompiled gems declare theirs.
  def self.ruby_requirement(runtime, gem)
    under = gem.desktop? ? "" : Fledge::MobileProject.for(Fledge::MobilePlatform.new(name: gem.target)).ruby_under
    major, minor = Fledge::RuntimeContents.read(runtime, under:).ruby_version.split(".").map(&:to_i)
    [">= #{major}.#{minor}", "< #{major}.#{minor.to_i + 1}.dev"]
  end

  # The licenses of the runtime that the SBOM +sbom+ lists, each SPDX
  # identifier once, an exception kept with its license.
  def self.licenses(sbom)
    return [] unless sbom

    expressions = JSON.parse(File.read(sbom)).fetch("packages").map { |package| package["licenseConcluded"].to_s }
    expressions.flat_map { |expression| expression.split(/\s+(?:AND|OR)\s+|[()]/) }.map(&:strip)
      .reject { |license| license.empty? || %w[NOASSERTION NONE].include?(license) }.uniq.sort
  end

  def self.metadata(fledge)
    fledge.metadata.merge("allowed_push_host" => push_host(fledge.version.to_s))
  end

  def self.fledge_gem(fledge, root, out)
    spec = fledge.dup
    spec.add_dependency(Fledge::RuntimeGem::NAME, "= #{fledge.version}")
    spec.metadata = metadata(fledge)
    Dir.chdir(root) { build_quietly(spec, File.join(out, spec.file_name)) }
  end

  def self.build_quietly(spec, path)
    Gem::DefaultUserInteraction.use_ui(Gem::SilentUI.new) { Gem::Package.build(spec, false, false, path) }
    path
  end

  private_class_method :read_pins, :check, :problems, :runtime_gem, :runtime_spec, :ruby_requirement, :licenses, :metadata,
    :fledge_gem, :build_quietly
end

# ruby tasks/release_gems.rb ASSETS OUT, as the Gems workflow runs it,
# with no bundle: what rake gems does.
if $PROGRAM_NAME == __FILE__
  assets, out = ARGV
  abort "usage: ruby tasks/release_gems.rb ASSETS OUT" unless assets && out
  begin
    ReleaseGems.build(assets:, out:).each { |path| puts format("%12d  %s", File.size(path), File.basename(path)) }
  rescue ReleaseGems::Mismatch => e
    abort "❌ #{e.message}"
  end
end
