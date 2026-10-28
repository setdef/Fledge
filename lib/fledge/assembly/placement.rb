# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "../entry"
require_relative "../error"

module Fledge
  class Assembly
    # Places each entry of a built app in every form the app takes at
    # once: its folder, its archive, its bundle's seal, and its
    # installers, with any folder above it first, and never one path
    # twice.
    class Placement # :nodoc:
      # A placement into +folder+ and, under +base_name+, the archive
      # +writer+ writes, sealed by +bundle+ when the app is a Mac bundle
      # and added to each of +installers+. +runtime+ names the runtime
      # archive, for the error when the build would replace its file.
      def initialize(folder:, base_name:, writer:, bundle:, installers:, runtime:)
        @folder = folder
        @base_name = base_name
        @writer = writer
        @bundle = bundle
        @installers = installers
        @runtime = runtime
        @placed = {} # : Hash[String, bool]
      end

      # Places an entry of the runtime, the app, or the build, at its place
      # in the built app: where it is, or in a bundle's +Resources+.
      def add(entry)
        bundle = @bundle
        put(bundle ? entry.with(path: bundle.resource(entry.path)) : entry)
      end

      # Places +entry+, whose path is in the built app's folder, after any
      # folder above it that is not there yet. A folder already there stays;
      # any other entry already there is the runtime's, which nothing the
      # build adds may replace.
      def put(entry)
        parents = entry.path.split("/")[0...-1] || []
        parents.each_index do |index|
          parent = parents.first(index + 1).join("/")
          place(Entry.directory(parent)) unless @placed.key?(parent)
        end
        return if entry.type == :directory && @placed.key?(entry.path)
        raise Error, "#{entry.path} is in #{@runtime} already, so the build can't add its own" if @placed.key?(entry.path)

        place(entry)
      end

      private def place(entry)
        entry.write_into(@folder)
        @writer.add(entry.with(path: "#{@base_name}/#{entry.path}"))
        @placed[entry.path] = true
        @bundle&.seal(entry)
        @installers.each { |installer| installer.add(entry) }
      end
    end
  end
end
