# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

module Fledge
  # The files of a git or path gem's folder that the linkage check reads.
  #
  # An app carries a git or path gem's whole folder, as bundle exec has
  # it, and a repository holds more than its gem: tests, and the compiled
  # fixtures some tests read, which no install of the gem holds and no
  # Ruby loads. Judging every compiled file in the folder refused such a
  # gem, though it runs wherever the app goes (Fledge's own repository,
  # whose test/fixtures/binaries link libraries on purpose, among them).
  #
  # This module takes the files the gemspec lists, which are all a
  # RubyGems install of the gem holds, and every file under its require
  # paths, which Ruby loads whether the gemspec lists it or not. A gemspec
  # that lists no files, or a require path of the folder itself, leaves
  # the whole folder to judge (doc/contributors/design/gems.md, "The
  # linkage check").
  #
  # Use it for Fledge::GitPackage#gem_files and Fledge::PathPackage#gem_files.
  #
  # === Example
  #
  #--
  # SPDX-SnippetBegin
  # SPDX-SnippetCopyrightText: 2026 setdef <kerrick@setdef.com>
  # SPDX-License-Identifier: MIT-0
  #++
  #   Fledge::GemFiles.of(spec, { "lib/a.rb" => "", "test/fixture.so" => "" }).keys # => ["lib/a.rb"]
  #--
  # SPDX-SnippetEnd
  #++
  module GemFiles
    # Of +files+ (paths relative to the gem's folder, and contents), those
    # the gem whose Gem::Specification is +spec+ holds as a gem.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 setdef <kerrick@setdef.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   Fledge::GemFiles.of(package.spec, package.contents)
    #--
    # SPDX-SnippetEnd
    #++
    def self.of(spec, files)
      folders = spec.require_paths.reject { |path| File.absolute_path?(path) }.map { |path| File.join(path, "") }
      return files if spec.files.empty? || folders.include?("./")

      listed = spec.files.to_set
      files.select { |path, _| listed.include?(path) || folders.any? { |folder| path.start_with?(folder) } }
    end
  end
end
