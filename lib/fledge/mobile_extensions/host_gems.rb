# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require "fileutils"
require_relative "../native_build"

module Fledge
  class MobileExtensions
    # The code of the gems a Rakefile's build requires, for this
    # computer's Ruby: every gem the gems whose Rakefiles Fledge runs
    # depend on, at any depth, each written out with its files, and each
    # with an extension compiled for this computer by Fledge::NativeBuild
    # first, as <tt>gem install</tt> would have installed it before the
    # Rakefile ran.
    #
    # A Rakefile's build runs under this computer's Ruby reading the
    # phone's <tt>rbconfig.rb</tt>, so RubyGems there looks for gems in
    # the phone runtime's gem folder, where a gem installed for this
    # computer is not, and takes the phone for the local platform. The
    # folders #load_path gives go on the load path of every Ruby the
    # build starts instead, as an <tt>extconf.rb</tt>'s dependencies do.
    # ffi-compiler requires ffi, whose compiled extension must be this
    # computer's to load; the phone's copy, compiled for the app, cannot
    # (doc/contributors/research/2026-11-19-ffi-libraries-on-phones.md,
    # section 4).
    #
    # Use it from Fledge::MobileExtensions, once for each build.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 setdef <kerrick@setdef.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   gems = Fledge::MobileExtensions::HostGems.new(specs: [llhttp.spec], dependencies:, build:, work:)
    #   gems.load_path # => [".../ffi-1.17.4/lib", ".../ffi-compiler-1.4.3/lib", ".../rake-13.4.2/lib"]
    #--
    # SPDX-SnippetEnd
    #++
    class HostGems
      # The build options of the gems compiled here, by name. ffi compiles
      # with the libffi it bundles, as ffi's own gems for each desktop are
      # built (its <tt>ext/ffi_c/extconf.rb</tt>, line 46, at 1.17.4, takes
      # no system libffi under rake-compiler-dock), so that its extension
      # does not depend on which libffi this computer offers: on GitHub's
      # macos-26 runner, whose pkg-config answers for libffi, the system's
      # header and library disagreed, and the ffi compiled against them
      # did not load.
      BUILD_ARGS = { "ffi" => ["--disable-system-libffi"] }.freeze

      # Creates the finder.
      #
      # [specs] The Gem::Specification of each gem whose Rakefile the
      #         build runs.
      # [dependencies] The packages of the gems the app's compiled gems
      #                depend on, by gem, among which are theirs.
      # [build] The Fledge::NativeBuild that compiles a gem for this
      #         computer.
      # [work] A folder of the build's own.
      def initialize(specs:, dependencies:, build:, work:)
        @specs = specs
        @dependencies = dependencies
        @build = build
        @work = work
        @load_path = nil # : Array[String]?
      end

      # The folders of the require paths of the gems the Rakefiles' gems
      # depend on, compiled for this computer where they have an
      # extension, written into the work folder once. Raises Fledge::Error
      # when one does not compile.
      def load_path
        @load_path ||= @build.call(needed, build_args: BUILD_ARGS).values.flat_map { |package| write(package) }
      end

      # The packages among the dependencies that the gems of the
      # Rakefiles depend on, at any depth.
      private def needed
        by_name = @dependencies.keys.to_h { |gem| [gem.name, gem] }
        names = @specs.flat_map { |spec| spec.runtime_dependencies.map(&:name) }
        found = {} # : Hash[locked_gem, package]
        until names.empty?
          gem = by_name[names.shift.to_s]
          next if gem.nil? || found.key?(gem)

          found[gem] = @dependencies.fetch(gem)
          names.concat(found.fetch(gem).spec.runtime_dependencies.map(&:name))
        end
        found
      end

      # Writes +package+'s files, with what its build compiled, into a
      # folder of its own, and returns the folders of its require paths.
      private def write(package)
        root = File.join(@work, package.spec.full_name)
        FileUtils.rm_rf(root)
        package.contents.each do |path, content|
          file = File.join(root, path)
          FileUtils.mkdir_p(File.dirname(file))
          File.binwrite(file, content)
        end
        package.spec.require_paths.reject { |path| File.absolute_path?(path) }.map { |path| File.join(root, path) }
      end
    end
  end
end
