# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

module Fledge
  class Linkage
    # Where macOS's loader, dyld, would find each library a gem's Mach-O
    # files name, among the gem's own files.
    #
    # A Mach-O file names a library by a path that may begin with a
    # prefix dyld expands as it loads (Apple's <tt>dyld(1)</tt> man page,
    # "Dynamic Library Loading"): <tt>@loader_path</tt> is the folder of
    # the file that names it, <tt>@executable_path</tt> the program's, and
    # <tt>@rpath</tt> each run path in turn, from the LC_RPATH commands of
    # the file that names it and then of each file that loaded that one,
    # up to the program. A run path may itself begin with
    # <tt>@loader_path</tt>, which is then the folder of the file whose
    # LC_RPATH names it.
    #
    # This class expands those prefixes against the paths of the gem's
    # files, as the gem's folder is laid out in the app, and follows the
    # libraries each file loads to give each the run paths of the files
    # that load it. A run path that is absolute, such as
    # <tt>/opt/homebrew/lib</tt>, or relative to the folder the program
    # starts in, leads to nothing the app carries. Anything that depends
    # on where the gem sits in the app, which differs by the app's kind,
    # it cannot tell: a path from <tt>@executable_path</tt>, or one that
    # climbs out of the gem's folder.
    #
    # Use it through Fledge::Linkage, for a gem bound for macOS.
    class Dyld
      # The prefixes dyld expands.
      PREFIXES = %w[@rpath/ @loader_path/ @executable_path/].freeze

      # Creates the loader's view of +binaries+, the gem's Mach-O files by
      # their paths in its folder (Fledge::Binary).
      def initialize(binaries)
        @binaries = binaries
        @shipped = binaries.keys.to_h { |path| [path.downcase, path] }
        @chains = binaries.to_h { |path, binary| [path, binary.rpaths.map { |rpath| [path, rpath] }] }
        inherit
      end

      # Whether dyld expands +library+, as a file names it.
      def self.relative?(library)
        PREFIXES.any? { |prefix| library.start_with?(prefix) }
      end

      # The run paths dyld searches for an <tt>@rpath</tt> library of the
      # file at +path+, as their LC_RPATH commands name them: the file's
      # own, then those of the files that load it.
      def run_paths(path)
        @chains.fetch(path, []).map(&:last).uniq
      end

      # Where +library+, as the file at +path+ names it, loads from: the
      # path of one of the gem's files, <tt>:unknown</tt> when that
      # depends on where the gem sits in the app, or +nil+ when it is
      # none of the gem's files.
      def resolve(path, library)
        resolve_through(@chains.fetch(path, []), path, library)
      end

      # Gives each file the run paths of the files that load it, until
      # none gains one.
      private def inherit
        loop do
          grown = @binaries.sum do |path, binary|
            binary.needed.sum do |library|
              target = resolve(path, library)
              next 0 unless target.is_a?(String) && target != path

              added = @chains.fetch(path) - @chains.fetch(target)
              @chains[target] = @chains.fetch(target) + added
              added.size
            end
          end
          break if grown.zero?
        end
      end

      private def resolve_through(chain, path, library)
        if library.start_with?("@rpath/")
          rest = library.delete_prefix("@rpath/")
          found = chain.map { |holder, rpath| locate(holder, rpath, rest) }
          found.find { |target| target.is_a?(String) } || (found.include?(:unknown) ? :unknown : nil)
        elsif library.start_with?("@loader_path/")
          locate(path, "@loader_path", library.delete_prefix("@loader_path/"))
        else
          :unknown
        end
      end

      # The gem's file at +rest+ in the folder +folder+ names, as the
      # file at +holder+ names it, <tt>:unknown</tt>, or +nil+.
      private def locate(holder, folder, rest)
        return :unknown if folder.start_with?("@executable_path")
        return nil unless folder == "@loader_path" || folder.start_with?("@loader_path/")

        segments = normalize([*File.dirname(holder).split("/"), *folder.delete_prefix("@loader_path").split("/"), *rest.split("/")])
        return :unknown unless segments

        @shipped[segments.join("/").downcase]
      end

      # +segments+ of a path from the gem's folder, with "." and ".." and
      # empty ones taken out, or +nil+ when they climb out of the folder.
      private def normalize(segments)
        kept = [] # : Array[String]
        segments.each do |segment|
          case segment
          when "", "." then next
          when ".." then return nil if kept.pop.nil?
          else kept << segment
          end
        end
        kept
      end
    end
  end
end
