# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require "fileutils"
require "rubygems"
require_relative "entry"
require_relative "error"
require_relative "gem_package"

module Fledge
  # A path gem's folder, seen as one gem and as what a built app needs of it.
  #
  # A gem from a folder outside the project (Fledge::PathGem) ships in
  # Bundler's own place for one, <tt>vendor/cache/NAME</tt> beside the
  # app's Gemfile, whole but for git's files and with its gemspecs
  # evaluated, as <tt>bundle cache --all</tt> copies it
  # (Bundler::Source::Path#cache) and as a git gem's are
  # (doc/contributors/design/gems.md, "Path gems"). A gem with an extension is compiled by Fledge::NativeBuild in a
  # copy made of the files its gemspec lists, as <tt>gem build</tt> and
  # <tt>gem install</tt> would build it, and what the build wrote into the
  # gem's require paths ships over the developer's own (usually compiled
  # for their Ruby, in the same place, by rake-compiler), inside the
  # project as a replacement for the file the project holds, and outside
  # in the copy.
  #
  # Use it as the package of a Fledge::PathGem.
  #
  # === Example
  #
  #--
  # SPDX-SnippetBegin
  # SPDX-SnippetCopyrightText: 2026 setdef <kerrick@setdef.com>
  # SPDX-License-Identifier: MIT-0
  #++
  #   package = Fledge::PathPackage.new(path_gem)
  #   package.app_entries([]).first.path # => "app/vendor/cache/greeter"
  #--
  # SPDX-SnippetEnd
  #++
  class PathPackage
    # The gem's Gem::Specification, as Bundler evaluates its gemspec.
    attr_reader :spec

    # The gem's folder, where Fledge::NativeBuild copies it from.
    attr_reader :checkout

    # The gemspec's path in the folder.
    attr_reader :gemspec

    # The gem's own folder in the checkout: this folder, +.+.
    attr_reader :folder

    # Reads +gem+'s (a Fledge::PathGem) gemspec. Raises Fledge::Error when
    # the folder holds no gemspec of that name, or one of another version
    # than the lockfile's.
    def initialize(gem)
      @gem = gem
      @checkout = gem.folder
      @folder = "."
      found = Dir.glob(gem.glob, base: gem.folder).sort.filter_map do |relative|
        spec = Bundler.load_gemspec(File.join(gem.folder, relative))
        [relative, spec] if spec&.name == gem.name
      end.first
      raise Error, "#{gem.folder} holds no gemspec of #{gem.name} (#{gem.glob}). Run bundle lock, then build again." unless found

      @gemspec, @spec = found
      unless @spec.version.to_s == gem.version
        raise Error, "#{gem.folder} holds #{gem.name} #{@spec.version}, but the lockfile locks #{gem}. Run bundle lock, then build again."
      end
      @spec.installed_by_version = Gem::VERSION
    end

    # A name for the gem's copy while it is compiled.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 setdef <kerrick@setdef.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   package.scope # => "path-greeter-1.0"
    #--
    # SPDX-SnippetEnd
    #++
    def scope
      @gem.scope
    end

    # What keeps the gem from running on a runtime whose Ruby is
    # +ruby_version+.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 setdef <kerrick@setdef.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   package.problems(ruby_version: "4.0.9") # => []
    #--
    # SPDX-SnippetEnd
    #++
    def problems(ruby_version:)
      GemPackage.ruby_problems(spec, ruby_version)
    end

    # Whether the gem has an extension to compile.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 setdef <kerrick@setdef.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   package.extensions? # => true
    #--
    # SPDX-SnippetEnd
    #++
    def extensions?
      !spec.extensions.empty?
    end

    # Every file in the gem's require paths, by its path in the gem's
    # folder, and its bytes: what a compiled file is compared with, and
    # what the check that it loads reads.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 setdef <kerrick@setdef.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   package.contents.keys # => ["lib/greeter.rb"]
    #--
    # SPDX-SnippetEnd
    #++
    def contents
      @contents ||= begin
        files = {} # : Hash[String, String]
        spec.require_paths.each do |path|
          next unless File.directory?(File.join(checkout, path))

          Entry.walk(File.join(checkout, path), skip: git_files).each do |entry|
            files["#{path}/#{entry.path}"] = entry.content.to_s if entry.type == :file
          end
        end
        files
      end
    end

    # Where the gem is in a built app whose gem folder is +gem_dir+: nowhere.
    # A path gem is not installed in the gem folder; Bundler loads it from
    # the folder the lockfile names (#app_entries).
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 setdef <kerrick@setdef.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   package.installed_path("lib/ruby/gems/4.0.0") # => "app/vendor/cache/greeter"
    #--
    # SPDX-SnippetEnd
    #++
    def installed_path(_gem_dir)
      "app/#{@gem.app_path}"
    end

    # The entries that install the gem in the runtime's gem folder +gem_dir+:
    # none (see #installed_path).
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 setdef <kerrick@setdef.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   package.entries("lib/ruby/gems/4.0.0") # => []
    #--
    # SPDX-SnippetEnd
    #++
    def entries(_gem_dir)
      [] # : Array[Entry]
    end

    # Makes +destination+ a copy of the files the gemspec lists, and the
    # gemspec evaluated, which is what <tt>gem build</tt> would pack for
    # <tt>gem install</tt> to compile, without the rest of the folder (a
    # project's output, its git history).
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 setdef <kerrick@setdef.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   package.copy_to("tmp/copy") # => "tmp/copy"
    #--
    # SPDX-SnippetEnd
    #++
    def copy_to(destination)
      FileUtils.rm_rf(destination)
      FileUtils.mkdir_p(destination)
      spec.files.each do |relative|
        source = File.join(checkout, relative)
        next unless File.file?(source)

        FileUtils.mkdir_p(File.dirname(File.join(destination, relative)))
        FileUtils.cp(source, File.join(destination, relative), preserve: true)
      end
      File.binwrite(File.join(destination, gemspec), spec.to_ruby)
      destination
    end

    # The entries that put a gem from a folder outside the project in
    # Bundler's place for it, in the built app, with paths relative to the
    # folder that holds +app+: the gem's whole folder less git's files, its
    # gemspecs evaluated, and +built+ (the Entry of each file a compile
    # wrote, with paths relative to the gem's folder) over it.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 setdef <kerrick@setdef.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   package.app_entries([]).map(&:path) # => ["app/vendor/cache/greeter", "app/vendor/cache/greeter/greeter.gemspec", ...]
    #--
    # SPDX-SnippetEnd
    #++
    def app_entries(built)
      top = "app/#{@gem.app_path}"
      replacements = built.to_h { |entry| [entry.path, entry] }
      gemspecs = evaluated_gemspecs
      files = Entry.walk(checkout, skip: git_files).map do |entry|
        next entry if entry.type != :file

        entry = entry.with(content: gemspecs.fetch(entry.path)) if gemspecs.key?(entry.path)
        replacements.delete(entry.path) || entry
      end
      [Entry.directory(top), *[*files, *replacements.values].map { |entry| entry.with(path: "#{top}/#{entry.path}") }]
    end

    # The files that replace the project's own for a gem inside the
    # project, by path relative to the app's folder: +built+, as for
    # #app_entries.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 setdef <kerrick@setdef.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   package.app_files(built).keys # => ["gems/greeter/lib/greeter/greeter.bundle"]
    #--
    # SPDX-SnippetEnd
    #++
    def app_files(built)
      prefix = (@gem.app_path == ".") ? "" : "#{@gem.app_path}/"
      files = {} # : Hash[String, String]
      built.each { |entry| files["#{prefix}#{entry.path}"] = entry.content.to_s if entry.type == :file }
      files
    end

    # Each gemspec the glob finds, by its path in the folder, evaluated as
    # Bundler evaluates it and written as the Ruby it comes to, so that one
    # which runs git keeps working where the app runs
    # (Bundler::Source::Git#serialize_gemspecs_in).
    private def evaluated_gemspecs
      specs = {} # : Hash[String, String]
      Dir.glob(@gem.glob, base: checkout).each do |relative|
        spec = Bundler.load_gemspec(File.join(checkout, relative)) or next
        spec.installed_by_version = Gem::VERSION
        specs[relative] = spec.to_ruby
      end
      specs
    end

    # Git's own files in the folder: its <tt>.git</tt> folder or file.
    private def git_files
      Dir.glob("**/.git", File::FNM_DOTMATCH, base: checkout).map { |relative| File.join(checkout, relative) }
    end
  end
end
