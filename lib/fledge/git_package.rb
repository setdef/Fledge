# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "rubygems"
require_relative "entry"
require_relative "error"
require_relative "gem_package"

module Fledge
  # A gem from git, installed as Bundler installs one, so a built app's
  # Bundler finds it.
  #
  # Bundler does not install a git gem into RubyGems' own folders. It
  # keeps its checkout of the locked revision in
  # <tt>GEM_DIR/bundler/gems/SCOPE</tt>, with every gemspec evaluated, and
  # at run time reads the gemspecs there (Bundler::Source::Git, its
  # #install_path and #load_spec_files, at Bundler 4.0.20): the lockfile
  # names the revision, so no git is needed. A git gem's extensions are
  # compiled there too, into <tt>GEM_DIR/bundler/gems/extensions</tt>
  # (Fledge::NativeBuild).
  #
  # This class is the checkout Fledge::GitCheckout made, seen as one gem:
  # its specification, the files in its own folder (where its gemspec
  # is), and the entries that put that folder where Bundler keeps it in
  # the checkout. Only the gem's folder ships, not the rest of the
  # repository: a repository holds more than its gems (Ferro's holds its
  # own tooling, under another license than its gems', and symbolic links
  # a Windows .zip cannot hold), and Bundler finds a gem by its gemspec,
  # in its folder, alone. The files that ship are the files the license
  # audit reads. It answers the questions Fledge::GemPackage answers for
  # a gem from a gem server.
  #
  # Use it for each git gem an app ships.
  #
  # === Example
  #
  #--
  # SPDX-SnippetBegin
  # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
  # SPDX-License-Identifier: MIT-0
  #++
  #   package = Fledge::GitPackage.new(git_gem, checkouts.checkout(git_gem))
  #   package.installed_path("lib/ruby/gems/4.0.0")
  #   # => "lib/ruby/gems/4.0.0/bundler/gems/Ferro-21a106d0c0d6/gems/idna"
  #--
  # SPDX-SnippetEnd
  #++
  class GitPackage
    # The gem's Gem::Specification, as its evaluated gemspec says.
    attr_reader :spec

    # The checkout, a folder of the locked revision.
    attr_reader :checkout

    # The gem's folder in the checkout, relative to it, such as
    # <tt>gems/idna</tt>, or <tt>.</tt> for a gem at the repository's top.
    attr_reader :folder

    # The gem's gemspec in the checkout, relative to it.
    attr_reader :gemspec

    # Reads +gem+ (a Fledge::GitGem) from +checkout+. Raises Fledge::Error
    # when the checkout holds no gemspec of that name, or one of another
    # version than the lockfile's.
    def initialize(gem, checkout)
      @gem = gem
      @checkout = checkout
      specs = Dir.glob(gem.glob, base: checkout).filter_map do |relative|
        spec = Gem::Specification.load(File.join(checkout, relative))
        [relative, spec] if spec&.name == gem.name
      end
      relative, @spec = specs.first || raise(Error, "#{gem.uri} at #{gem.revision} holds no gemspec of #{gem.name} " \
        "(#{gem.glob}). Run bundle lock, then build again.")
      unless @spec.version.to_s == gem.version
        raise Error, "#{gem.uri} at #{gem.revision} holds #{gem.name} #{@spec.version}, but the lockfile locks #{gem}. " \
          "Run bundle lock, then build again."
      end
      @gemspec = relative.to_s
      @folder = File.dirname(@gemspec)
    end

    # The folder Bundler keeps the checkout in (Fledge::GitGem#scope).
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   package.scope # => "Ferro-21a106d0c0d6"
    #--
    # SPDX-SnippetEnd
    #++
    def scope
      @gem.scope
    end

    # What keeps the gem from running on a runtime whose Ruby is
    # +ruby_version+, as sentences, or none.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
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
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   package.extensions? # => true
    #--
    # SPDX-SnippetEnd
    #++
    def extensions?
      !spec.extensions.empty?
    end

    # Where the checkout goes in a built app whose gem folder is
    # +gem_dir+: Bundler's <tt>bundler/gems/SCOPE</tt>.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   package.checkout_path("lib/ruby/gems/4.0.0") # => "lib/ruby/gems/4.0.0/bundler/gems/Ferro-21a106d0c0d6"
    #--
    # SPDX-SnippetEnd
    #++
    def checkout_path(gem_dir)
      "#{gem_dir}/bundler/gems/#{scope}"
    end

    # Where the gem's own folder is in a built app whose gem folder is
    # +gem_dir+.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   package.installed_path("lib/ruby/gems/4.0.0") # => "lib/ruby/gems/4.0.0/bundler/gems/Ferro-21a106d0c0d6/gems/idna"
    #--
    # SPDX-SnippetEnd
    #++
    def installed_path(gem_dir)
      (folder == ".") ? checkout_path(gem_dir) : "#{checkout_path(gem_dir)}/#{folder}"
    end

    # The entries that put the gem's folder of the checkout where Bundler
    # keeps it, in the gem folder +gem_dir+, without git's own files.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   package.entries("lib/ruby/gems/4.0.0").first.path # => "lib/ruby/gems/4.0.0/bundler/gems/Ferro-21a106d0c0d6/gems/idna"
    #--
    # SPDX-SnippetEnd
    #++
    def entries(gem_dir)
      top = installed_path(gem_dir)
      files = Entry.walk(File.join(checkout, folder), skip: [File.join(checkout, ".git")])
      [Entry.directory(top), *files.map { |entry| entry.with(path: "#{top}/#{entry.path}") }]
    end

    # Every file in the gem's own folder, by its path in that folder, and
    # its bytes.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   package.contents.keys.first # => "CHANGELOG.md"
    #--
    # SPDX-SnippetEnd
    #++
    def contents
      @contents ||= begin
        base = File.join(checkout, folder)
        Entry.walk(base, skip: [File.join(checkout, ".git")]).select { |entry| entry.type == :file }
          .to_h { |entry| [entry.path, entry.content.to_s] }
      end
    end

    # The gem's license files, by their paths in its folder, and their
    # text (Fledge::GemPackage.license_files_in).
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   package.license_files.keys # => ["LICENSES/Apache-2.0.txt", "LICENSES/MIT.txt"]
    #--
    # SPDX-SnippetEnd
    #++
    def license_files
      GemPackage.license_files_in(contents)
    end
  end
end
