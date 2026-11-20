# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "test_helper"
require_relative "support/gems"

# What the linkage check reads of a git or path gem (#gem_files): the
# files its gemspec lists, which are what a RubyGems install of it
# holds, and every file under its require paths, which Ruby can load
# whether listed or not; a test's compiled fixture elsewhere in the
# folder is neither (doc/contributors/design/gems.md, "The linkage
# check").
class GemFilesTest < Minitest::Test
  FILES = {
    "lib/alpha.rb" => "# alpha\n",
    "lib/alpha/alpha.so" => "unlisted, but under a require path\n",
    "vendor/libalpha.so" => "listed, outside the require paths\n",
    "test/fixtures/broken.so" => "a fixture no install holds\n",
    "README.md" => "# Alpha\n",
  }.freeze

  def setup
    @dir = Dir.mktmpdir
  end

  def teardown
    FileUtils.rm_rf(@dir)
  end

  # Writes the gem alpha into +folder+, its gemspec listing +files+. Each
  # file is written byte for byte, as a package reads it: written as
  # text, a line's end would become two bytes on Windows.
  def write(folder, files:, require_paths: ["lib"])
    FILES.each do |path, content|
      FileUtils.mkdir_p(File.dirname(File.join(folder, path)))
      File.binwrite(File.join(folder, path), content)
    end
    File.write(File.join(folder, "alpha.gemspec"), "Gem::Specification.new do |spec|\n  spec.name = \"alpha\"\n  spec.version = \"1.0\"\n" \
      "  spec.summary = \"alpha\"\n  spec.authors = [\"Fledge\"]\n  spec.files = #{files.inspect}\n" \
      "  spec.require_paths = #{require_paths.inspect}\nend\n")
    folder
  end

  def git_package(files:, require_paths: ["lib"])
    checkout = write(File.join(@dir, "checkout"), files:, require_paths:)
    gem = Fledge::GitGem.new(name: "alpha", version: "1.0", uri: "https://example.com/alpha.git", revision: "a" * 40,
      glob: "{,*,*/*}.gemspec", ref: nil, submodules: false)
    Fledge::GitPackage.new(gem, checkout)
  end

  def path_package(files:, require_paths: ["lib"])
    folder = write(File.join(@dir, "alpha"), files:, require_paths:)
    Fledge::PathPackage.new(Fledge::PathGem.new(name: "alpha", version: "1.0", folder:, app_path: "vendor/cache/alpha",
      glob: "{,*,*/*}.gemspec", inside: false))
  end

  def test_a_git_gem_is_judged_by_its_listed_files_and_its_require_paths
    package = git_package(files: ["lib/alpha.rb", "vendor/libalpha.so", "README.md"])

    assert_equal ["README.md", "lib/alpha.rb", "lib/alpha/alpha.so", "vendor/libalpha.so"], package.gem_files.keys.sort
    assert_equal FILES.fetch("vendor/libalpha.so"), package.gem_files.fetch("vendor/libalpha.so")
    assert_includes package.contents.keys, "test/fixtures/broken.so"
  end

  # A gemspec that lists no files says nothing of what the gem holds, so
  # the whole folder is judged; so is a gem whose require path is its
  # folder, since Ruby can load any file in it.
  def test_a_git_gem_that_lists_nothing_or_requires_from_its_top_is_judged_whole
    assert_equal git_package(files: []).contents.keys.sort, git_package(files: []).gem_files.keys.sort
    FileUtils.rm_rf(File.join(@dir, "checkout"))
    top = git_package(files: ["lib/alpha.rb"], require_paths: ["."])
    assert_includes top.gem_files.keys, "test/fixtures/broken.so"
  end

  def test_a_path_gem_is_judged_by_its_listed_files_and_its_require_paths
    package = path_package(files: ["lib/alpha.rb", "vendor/libalpha.so"])

    assert_equal ["lib/alpha.rb", "lib/alpha/alpha.so", "vendor/libalpha.so"], package.gem_files.keys.sort
  end

  def test_a_server_gem_is_judged_by_its_whole_package
    gem = FakeGem.build(@dir, "alpha", "1.0", files: { "lib/alpha.rb" => "# alpha\n" })
    package = Fledge::GemPackage.new(gem.path)

    assert_equal package.contents, package.gem_files
  end
end
