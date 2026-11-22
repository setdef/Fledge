# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require "fileutils"
require_relative "../error"
require_relative "ios_libraries"

module Fledge
  class MobileProject
    # Puts the iOS runtime's own extensions into the Xcode project, each
    # in a framework of its own, and a link at each path where Ruby looks
    # for it, so that Ruby loads and records each at the path a desktop
    # has (doc/contributors/design/phone-runtimes.md, "Ruby's extensions
    # on iOS").
    #
    # A runtime whose Ruby is a dynamic framework holds, in each slice of
    # its XCFramework, its extensions as dynamic libraries at their paths
    # under <tt>lib/ruby</tt>, and LINKS, a line for each path: the name
    # of the extension's framework, a tab, and the path under the slice.
    # Each framework is made as a library for Ruby's ffi is
    # (IOSLibraries.xcframework), and each listed file becomes a relative
    # link to its framework's binary in the app (IOSLibraries.target).
    # A runtime whose Ruby is static, as 0.17.0's, lists none.
    #
    # Use it from MobileProject::IOS, once the runtime is in the project.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 setdef <kerrick@setdef.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   extensions = Fledge::MobileProject::IOSRubyExtensions.new(File.join(project, "FledgeRuby.xcframework"))
    #   extensions.call(project, identifier: "com.example.Hello", version: "1.0.0") # => ["fledgerubyext.etc.bundle", ...]
    #   extensions.link
    #--
    # SPDX-SnippetEnd
    #++
    class IOSRubyExtensions
      # The list in each slice of the runtime's extensions.
      LINKS = "fledge.links"

      # The framework of Ruby's own in each slice of a runtime whose Ruby
      # is dynamic.
      RUBY = "FledgeRuby.framework"

      # [runtime] The runtime's XCFramework, in the project.
      def initialize(runtime)
        @runtime = runtime
      end

      # Whether the runtime's Ruby is a dynamic framework, which the app
      # embeds, rather than a static library.
      def dynamic?
        slices.any? { |slice| File.directory?(File.join(@runtime, slice, RUBY)) }
      end

      # Each extension's framework by its name, with its file in each
      # slice. Raises Fledge::Error when the slices list different ones.
      def frameworks
        lines = listed
        names = lines.transform_values { |paths| paths.keys.sort }
        raise Error, "the iOS runtime's slices list different extensions: #{names.map { |slice, list| "#{slice} #{list.join(', ')}" }.join(', ')}" if
          names.values.uniq.size > 1

        (names.values.first || []).to_h do |name|
          [name, lines.to_h { |slice, paths| [slice, File.join(@runtime, slice, paths.fetch(name).first.to_s)] }]
        end
      end

      # Writes each framework's XCFramework into +project+, for an app
      # whose bundle identifier is +identifier+ and bundle version
      # +version+, and returns their names.
      def call(project, identifier:, version:)
        frameworks.map do |name, files|
          IOSLibraries.xcframework(project, name, files, identifier:, version:)
          name
        end
      end

      # Writes, in each slice, a link at each listed path to its
      # framework's binary in the app, in place of the file there.
      def link
        listed.each do |slice, paths|
          paths.each do |name, list|
            list.each do |path|
              at = File.join(@runtime, slice, path)
              FileUtils.rm_f(at)
              File.symlink(IOSLibraries.target(path, name), at)
            end
          end
        end
      end

      # The runtime's slices that hold Ruby.
      private def slices
        IOSLibraries::PLATFORMS.keys.select { |slice| File.directory?(File.join(@runtime, slice)) }
      end

      # Each slice's LINKS, as the paths listed for each name, for the
      # slices that have one.
      private def listed
        @listed ||= slices.filter_map do |slice|
          file = File.join(@runtime, slice, LINKS)
          next unless File.file?(file)

          paths = Hash.new { |hash, name| hash[name] = [] } # : Hash[String, Array[String]]
          File.foreach(file, chomp: true) do |line|
            name, path = line.split("\t", 2)
            paths[name.to_s] << path.to_s if path
          end
          [slice, paths]
        end.to_h
      end
    end
  end
end
