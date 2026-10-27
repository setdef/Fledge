# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "digest"
require "fileutils"
require "rubygems/package"

# Real .gem files, built by RubyGems itself, small enough for a unit
# test, so Fledge::GemPackage and the build read what gem build writes.
module FakeGem
  # A built gem: where its .gem file is, its name for a lockfile, and its
  # SHA-256.
  Built = Data.define(:path, :name, :version, :platform, :sha256) do
    def lock_name = (platform == "ruby") ? "#{name} (#{version})" : "#{name} (#{version}-#{platform})"

    def file_name = File.basename(path)
  end

  # Builds NAME-VERSION[-PLATFORM].gem into +directory+ and returns it.
  # +files+ maps each file's path in the gem to its contents; executable
  # paths under exe/ get mode 0755.
  def self.build(directory, name, version = "1.0.0", platform: "ruby", licenses: ["MIT"],
    files: { "lib/#{name}.rb" => "# #{name}\n", "LICENSE.txt" => "#{name} is MIT\n" },
    extensions: [], required_ruby_version: nil, dependencies: {}, executables: [], plugin: false
  )
    source = File.join(directory, "source-#{name}-#{version}-#{platform}")
    FileUtils.mkdir_p(source)
    all = files.merge(plugin ? { "lib/rubygems_plugin.rb" => "# plugin\n" } : {})
    all.each do |path, content|
      FileUtils.mkdir_p(File.join(source, File.dirname(path)))
      File.write(File.join(source, path), content)
      File.chmod(0o755, File.join(source, path)) if path.start_with?("exe/")
    end
    spec = Gem::Specification.new do |s|
      s.name = name
      s.version = version
      s.platform = platform
      s.summary = "A gem for Fledge's tests"
      s.authors = ["Fledge"]
      s.homepage = "https://example.com/#{name}"
      s.licenses = licenses
      s.files = all.keys
      s.extensions = extensions
      s.bindir = "exe"
      s.executables = executables
      s.required_ruby_version = required_ruby_version if required_ruby_version
      dependencies.each { |dependency, requirement| s.add_dependency(dependency, requirement) }
    end
    built = Dir.chdir(source) do
      Gem::DefaultUserInteraction.use_ui(Gem::SilentUI.new) { File.expand_path(Gem::Package.build(spec, true)) }
    end
    path = File.join(directory, File.basename(built))
    FileUtils.mv(built, path)
    Built.new(path:, name:, version:, platform:, sha256: Digest::SHA256.file(path).hexdigest)
  end
end

# A gem-shaped project, as bundle gem lays one out, with a Gemfile.lock
# written as Bundler 4 writes one.
module FakeProject
  # Writes the project NAME into +directory+ and returns its root. Its
  # gemspec depends on +dependencies+ (name => requirement); +locked+ are
  # FakeGem::Built gems the lockfile locks from +remote+, with their
  # own +locked_dependencies+ (lock name => [dependency names]);
  # +gemfile+ adds lines to the Gemfile and +lock_dependencies+ to its
  # DEPENDENCIES; +checksums+ false leaves the CHECKSUMS section out.
  def self.write(directory, name: "my_app", dependencies: {}, locked: [], remote: "https://rubygems.org/",
    platforms: %w[arm64-darwin x64-mingw-ucrt x86_64-linux aarch64-linux], gemfile: "", lock_dependencies: [],
    locked_dependencies: {}, checksums: true
  )
    root = File.join(directory, name)
    FileUtils.mkdir_p([File.join(root, "exe"), File.join(root, "lib")])
    File.write(File.join(root, "#{name}.gemspec"), gemspec(name, dependencies))
    File.write(File.join(root, "Gemfile"), "source \"#{remote}\"\n\ngemspec\n#{gemfile}")
    File.write(File.join(root, "exe", name), "require \"#{name}\"\nputs \"hi\"\n")
    File.chmod(0o755, File.join(root, "exe", name))
    File.write(File.join(root, "lib", "#{name}.rb"), "")
    File.write(File.join(root, "Gemfile.lock"), lockfile(name, dependencies, locked, remote, platforms, lock_dependencies,
      locked_dependencies, checksums))
    root
  end

  def self.gemspec(name, dependencies)
    <<~GEMSPEC
      Gem::Specification.new do |spec|
        spec.name = #{name.inspect}
        spec.version = "0.1.0"
        spec.authors = ["Fledge"]
        spec.summary = "An app for Fledge's tests"
        spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) { |ls| ls.readlines("\\x0", chomp: true) }
        spec.bindir = "exe"
        spec.executables = [#{name.inspect}]
      #{dependencies.map { |dependency, requirement| "  spec.add_dependency #{dependency.inspect}, #{requirement.inspect}" }.join("\n")}
      end
    GEMSPEC
  end

  def self.lockfile(name, dependencies, locked, remote, platforms, lock_dependencies, locked_dependencies, checksums)
    path_spec = ["    #{name} (0.1.0)", *dependencies.map { |dependency, requirement| "      #{dependency} (#{requirement})" }]
    specs = locked.sort_by(&:lock_name).flat_map do |gem|
      ["    #{gem.lock_name}", *locked_dependencies.fetch(gem.lock_name, []).map { |dependency| "      #{dependency}" }]
    end
    sums = (locked.map { |gem| "  #{gem.lock_name} sha256=#{gem.sha256}" } + ["  #{name} (0.1.0)"]).sort
    <<~LOCK
      PATH
        remote: .
        specs:
      #{path_spec.join("\n")}

      GEM
        remote: #{remote}
        specs:
      #{specs.join("\n")}

      PLATFORMS
      #{platforms.sort.map { |platform| "  #{platform}" }.join("\n")}

      DEPENDENCIES
      #{["  #{name}!", *lock_dependencies.map { |dependency| "  #{dependency}" }].sort.join("\n")}
      #{checksums ? "\nCHECKSUMS\n#{sums.join("\n")}\n" : ''}
      BUNDLED WITH
        4.0.20
    LOCK
  end
end
