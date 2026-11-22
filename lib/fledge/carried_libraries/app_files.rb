# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "../entry"
require_relative "../error"

module Fledge
  class CarriedLibraries
    # A desktop app's files with the libraries its project lists under
    # <tt>macos: carried_libraries</tt> (Config::Macos): the gems'
    # files as Fledge::AppGems has them, as Fledge::Entry values, and
    # the project's path gems' files, by their paths in the project, as
    # a CarriedLibraries plan over them changes them.
    #
    # The plan finds and judges each library; this puts its copies and
    # the files it changed in place of the gems' own, once the changed
    # files are seen to load the copies (CarriedLibraries#unreached).
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 setdef <kerrick@setdef.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   files = Fledge::CarriedLibraries::AppFiles.new(["libSDL3.0.dylib"], entries:, path_files: {},
    #     platform: Fledge::Platform.find("arm64-darwin"), provided: [], readers: Fledge::Binary::Readers.local("darwin"))
    #   files.problems                  # => []
    #   files.entries("Game").last.path # => "lib/carried/libSDL3.0.dylib"
    #--
    # SPDX-SnippetEnd
    #++
    class AppFiles
      # The prefix of a path gem's file among the app's paths.
      APP = "app/"

      # Where on this computer each carried library came from, by its
      # file name in the app (CarriedLibraries#sources).
      attr_reader :sources

      # A plan to carry the libraries +names+ for +platform+, over the
      # gems' files +entries+ and the project's path gems' files
      # +path_files+ (contents by path in the project), with what the
      # runtime +provided+, reading compiled files with +readers+.
      def initialize(names, entries:, path_files:, platform:, provided:, readers:)
        @entries = entries
        @held = entries.select { |entry| entry.type == :file }.to_h { |entry| [entry.path, entry.content.to_s] }
          .merge(path_files.transform_keys { |path| "#{APP}#{path}" })
        @plan = CarriedLibraries.new(names, files: @held, platform:, provided:, readers:)
        @sources = @plan.sources
      end

      # What keeps the app from carrying the libraries, as lines
      # (CarriedLibraries#problems).
      def problems
        @plan.problems
      end

      # The gems' entries, each file the plan changed in place of the
      # gem's own, and each copy under CarriedLibraries::FOLDER. Raises
      # Fledge::Error, naming the app +name+, when the changed files
      # would not load the copies.
      def entries(name)
        unreached = @plan.unreached(@held.merge(changed))
        raise Error, "#{name} can't carry its libraries:\n#{unreached.map { |problem| "  #{problem}" }.join("\n")}" unless unreached.empty?

        kept = @entries.map { |entry| changed.key?(entry.path) ? entry.with(content: changed.fetch(entry.path)) : entry }
        copies = changed.keys.select { |path| path.start_with?("#{FOLDER}/") }.sort
        [*kept, *copies.map { |path| Entry.file(path, changed.fetch(path)) }]
      end

      # The project's path gems' files the plan changed, by their paths
      # in the project.
      def path_files
        changed.filter_map { |path, content| [path.delete_prefix(APP), content] if path.start_with?(APP) }.to_h
      end

      # Every file the plan changed or copied, by its path in the app
      # (CarriedLibraries#files), worked out once.
      private def changed
        @changed ||= @plan.files
      end
    end
  end
end
