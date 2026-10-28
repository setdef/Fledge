# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "entry"

module Fledge
  # A gem whose extension Fledge compiled, as it ships.
  #
  # RubyGems installs a compiled extension twice: into the gem's own
  # require path, where <tt>require</tt> finds it, and into the gem's
  # extensions folder (<tt>extensions/PLATFORM/ABI/FULL_NAME</tt>), whose
  # <tt>gem.build_complete</tt> tells RubyGems and Bundler the extension
  # is built (Gem::Ext::Builder#build_extensions, at Ruby 4.0.9); without
  # it, they treat the gem as not yet installed. A gem compiled with
  # build options also gets <tt>build_info/FULL_NAME.info</tt>, which
  # <tt>gem pristine</tt> reads (Gem::Installer#write_build_info_file).
  #
  # This class is a gem's package (Fledge::GemPackage, or a git gem's
  # Fledge::GitPackage) and what Fledge::NativeBuild compiled for it: the
  # files the build wrote into the gem's require paths, its extensions
  # folder (without the build's logs, which hold the build machine's
  # paths), its build information, and the options it was built with. It
  # ships all of them where RubyGems, or for a git gem Bundler, put them,
  # and answers what the package answers, with the compiled files among
  # the gem's contents, so Fledge::Linkage reads them.
  #
  # Use it as the package of a gem Fledge compiled.
  #
  # === Example
  #
  #--
  # SPDX-SnippetBegin
  # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
  # SPDX-License-Identifier: MIT-0
  #++
  #   compiled.contents.keys.grep(/\.bundle\z/) # => ["lib/redcarpet.bundle"]
  #   compiled.entries("lib/ruby/gems/4.0.0").map(&:path).grep(/build_complete/)
  #   # => ["lib/ruby/gems/4.0.0/extensions/arm64-darwin-23/4.0.0-static/redcarpet-3.6.1/gem.build_complete"]
  #--
  # SPDX-SnippetEnd
  #++
  class CompiledGem
    # The package it was compiled from.
    attr_reader :package

    # The options its extension was built with, as extconf.rb got them.
    attr_reader :build_args

    # Creates the compiled gem.
    #
    # [package] The Fledge::GemPackage or Fledge::GitPackage compiled.
    # [built] The Entry of each file the build wrote into the gem's
    #         require paths, with paths relative to the gem's folder.
    # [extensions] The Entry of each file in its extensions folder, with
    #              paths relative to that folder.
    # [extension_dir] Its extensions folder, relative to the gem folder.
    # [build_args] Its build options.
    # [build_info] What RubyGems wrote in its build information, or +nil+.
    # [problems] What keeps the compiled files from running where the app
    #            goes, as sentences.
    def initialize(package:, built:, extensions:, extension_dir:, build_args:, build_info:, problems:)
      @package = package
      @built = built
      @extensions = extensions
      @extension_dir = extension_dir
      @build_args = build_args
      @build_info = build_info
      @problems = problems
    end

    # The gem's Gem::Specification.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   compiled.spec.full_name # => "redcarpet-3.6.1"
    #--
    # SPDX-SnippetEnd
    #++
    def spec
      package.spec
    end

    # Whether it still has an extension to compile: no.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   compiled.extensions? # => false
    #--
    # SPDX-SnippetEnd
    #++
    def extensions?
      false
    end

    # Where the gem's folder is in a built app whose gem folder is
    # +gem_dir+, as its package says.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   compiled.installed_path("lib/ruby/gems/4.0.0") # => "lib/ruby/gems/4.0.0/gems/redcarpet-3.6.1"
    #--
    # SPDX-SnippetEnd
    #++
    def installed_path(gem_dir)
      package.installed_path(gem_dir)
    end

    # What keeps the gem from running on a runtime whose Ruby is
    # +ruby_version+: its package's problems, and its compiled files'.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   compiled.problems(ruby_version: "4.0.9") # => []
    #--
    # SPDX-SnippetEnd
    #++
    def problems(ruby_version:)
      package.problems(ruby_version:) + @problems
    end

    # Every file of the gem, by its path in the gem's folder, with what
    # the build wrote; and each file of its extensions folder whose bytes
    # are not already among them, by its path in the gem folder.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   compiled.contents.keys.grep(/\.bundle\z/) # => ["lib/redcarpet.bundle"]
    #--
    # SPDX-SnippetEnd
    #++
    def contents
      files = package.contents.merge(@built.to_h { |entry| [entry.path, entry.content.to_s] })
      copies = files.values
      @extensions.each_with_object(files) do |entry, all|
        all["#{@extension_dir}/#{entry.path}"] = entry.content.to_s if entry.type == :file && !copies.include?(entry.content)
      end
    end

    # The entries that install the gem, compiled, into the gem folder
    # +gem_dir+: its package's, what the build wrote into its folder, its
    # extensions folder, and its build information.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   compiled.entries("lib/ruby/gems/4.0.0").map(&:path).grep(/\.bundle\z/)
    #   # => ["lib/ruby/gems/4.0.0/gems/redcarpet-3.6.1/lib/redcarpet.bundle",
    #   #     "lib/ruby/gems/4.0.0/extensions/arm64-darwin-23/4.0.0-static/redcarpet-3.6.1/redcarpet.bundle"]
    #--
    # SPDX-SnippetEnd
    #++
    def entries(gem_dir)
      installed = installed_path(gem_dir)
      info = @build_info
      [
        *package.entries(gem_dir),
        *@built.map { |entry| entry.with(path: "#{installed}/#{entry.path}") },
        Entry.directory("#{gem_dir}/#{@extension_dir}"),
        *@extensions.map { |entry| entry.with(path: "#{gem_dir}/#{@extension_dir}/#{entry.path}") },
        *(info ? [Entry.file("#{gem_dir}/build_info/#{spec.full_name}.info", info)] : []),
      ]
    end
  end
end
