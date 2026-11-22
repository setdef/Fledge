# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "../binary"
require_relative "../native_build/built_files"
require_relative "rust"

module Fledge
  class MobileExtensions
    # What a phone app carries of the files a gem's builds left in the
    # gem's folder, one build for each of the phone's targets.
    #
    # Under <tt>bundle exec</tt> a gem's Ruby may read, by its path, any
    # file its build left, since RubyGems leaves the gem's folder as the
    # build left it (Fledge::NativeBuild::BuiltFiles), and a desktop's
    # app carries all of it. A phone builds the gem once for each target,
    # into a folder of its own, and the app has one Ruby tree for every
    # target. So the app carries each file every target's build left
    # alike, byte for byte, at its path, as data an <tt>extconf.rb</tt>
    # writes is; and none that the builds left differently, or that only
    # some left, since a file one target's build wrote is not that file
    # for another: a Makefile names its target's compiler, and Cargo's
    # records its target. Nor does it carry compiled code, which a phone
    # runs only from the app's executable, its frameworks, or its native
    # libraries, where Fledge puts what Ruby loads of it, or the files
    # Fledge's own build writes beside an extension
    # (doc/contributors/design/phone-projects.md, "Files a gem's build
    # leaves").
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 setdef <kerrick@setdef.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   builds = %w[ios-arm64 ios-arm64-simulator].map { |name| Fledge::MobileExtensions::LeftFiles.of(package, File.join(work, name, "adder-1.0.0")) }
    #   Fledge::MobileExtensions::LeftFiles.common(builds).map(&:path) # => ["data/table.txt"]
    #--
    # SPDX-SnippetEnd
    #++
    module LeftFiles
      # The files Fledge's own build of an extension writes in its folder:
      # the shim's report (ExtconfBuild) and Rust::SHIM's files.
      FLEDGES = ["fledge-report.json", Rust::NATIVE_LIBS, Rust::LIBRARY, Rust::MAKEFILE].freeze

      # The formats of compiled code (Fledge::Binary.format_of): objects,
      # libraries, and programs, and the static archives that hold them.
      COMPILED = %i[elf macho archive].freeze

      # The entries of what one target's build of +package+ left in
      # +root+, the folder it built in, with paths relative to it
      # (Fledge::NativeBuild::BuiltFiles.of), less compiled code and
      # FLEDGES.
      def self.of(package, root)
        NativeBuild::BuiltFiles.of(package, root).reject do |entry|
          FLEDGES.include?(File.basename(entry.path)) || COMPILED.include?(Binary.format_of(entry.content))
        end
      end

      # The entries in every one of +builds+, each target's #of, alike.
      def self.common(builds)
        first, *rest = builds
        sets = rest.map(&:to_set)
        (first || []).select { |entry| sets.all? { |set| set.include?(entry) } }
      end
    end
  end
end
