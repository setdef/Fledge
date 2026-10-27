# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "rubygems"
require_relative "config"
require_relative "entry"
require_relative "error"

module Fledge
  # A Ruby app Fledge can ship: the program you already run, in the
  # project it belongs to.
  #
  # A Ruby developer already has an entry point, <tt>exe/my_cool_app</tt>
  # in a gem or <tt>bin/server</tt> in an app, run from the project's root,
  # where its Gemfile or gemspec is (decision 2 in
  # <tt>doc/contributors/decisions.md</tt>). Asking for a different
  # layout would make the app's code differ under Fledge, which decision
  # 9 forbids.
  #
  # This class starts from the path you build. A file is the entry
  # point. A folder means its project's only executable, as its gemspec
  # names it, or else its <tt>main.rb</tt>. The project's root is the
  # nearest folder, from the entry point's up, with a Gemfile, a
  # <tt>gems.rb</tt>, a gemspec, or a <tt>fledge.yml</tt>, as Bundler
  # looks for a Gemfile, stopping at a git repository's top; a script
  # with none of them is a project of its own folder. The app's name
  # comes from the gemspec's name, or else the root's folder, camelized
  # as Bundler names a gem's module (<tt>my_cool_app</tt> is
  # +MyCoolApp+), unless <tt>fledge.yml</tt> names it (decision 5).
  # Everything in the root ships but NEVER_SHIPPED and the build's own
  # output (ADR 005).
  #
  # Use it to name what <tt>fledge build</tt> copies into a runtime.
  #
  # === Examples
  #
  #--
  # SPDX-SnippetBegin
  # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
  # SPDX-License-Identifier: MIT-0
  #++
  #   app = Fledge::App.at("examples/my_cool_app/exe/my_cool_app")
  #   app.name    # => "MyCoolApp"
  #   app.entry   # => "exe/my_cool_app"
  #   app.gemfile # => "Gemfile"
  #
  #   Fledge::App.at("examples/hello").entry # => "main.rb"
  #   Fledge::App.at("examples/hello").name  # => "Hello"
  #--
  # SPDX-SnippetEnd
  #++
  class App < Data.define(:root, :entry, :name, :gemfile, :config)
    ##
    # :attr_reader: root
    # The project's root folder, as an absolute path. It ships as the
    # built app's +app+ folder.

    ##
    # :attr_reader: entry
    # The program the launcher runs, relative to #root, with <tt>/</tt>
    # between folders.

    ##
    # :attr_reader: name
    # What the person who runs the app sees: the program's name, and the
    # name of the folder and archive it ships in.

    ##
    # :attr_reader: gemfile
    # The project's Gemfile (or <tt>gems.rb</tt>), relative to #root, or
    # +nil+ for a project without one, which runs without Bundler.

    ##
    # :attr_reader: config
    # The project's Fledge::Config.

    # What never ships, relative to the root: version control history,
    # Bundler's own settings for the developer's computer (.bundle), and
    # the gems Bundler installed or cached there for it (vendor/bundle
    # and vendor/cache). The gems an app ships come from its
    # Gemfile.lock instead, for each target.
    NEVER_SHIPPED = %w[.git .bundle vendor/bundle vendor/cache].freeze

    # The files that make a folder a project's root, besides a gemspec.
    MARKERS = ["Gemfile", "gems.rb", Config::FILE].freeze

    # Names Windows keeps for devices, with or without an extension.
    RESERVED = /\A(?:con|prn|aux|nul|com\d|lpt\d)(?:\..*)?\z/i

    # The app whose entry point is the file +path+, or which the folder
    # +path+ holds. Raises Fledge::Error, saying what to do, when there is
    # no such file or folder, the folder names no one program, the
    # project's root would be +home+, its <tt>fledge.yml</tt> is wrong, or
    # it has a gemspec but no Gemfile.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   Fledge::App.at("bin/server").entry # => "bin/server"
    #--
    # SPDX-SnippetEnd
    #++
    def self.at(path, home: Dir.home)
      full = File.expand_path(path)
      raise Error, "#{path} does not exist. Build the program you run, such as exe/my_app or main.rb." unless File.exist?(full)

      start = File.directory?(full) ? full : File.dirname(full)
      root = project_root(start) || start
      if same_folder?(root, home)
        raise Error, "#{path} would belong to a project at your home folder, #{root}, which Fledge won't ship. " \
          "Move the app into a folder of its own."
      end

      gemspec = gemspec_in(root)
      entry = File.directory?(full) ? default_entry(path, full, root, gemspec) : relative(full, root)
      config = Config.load(root)
      new(root:, entry:, name: name_for(config, gemspec, root), gemfile: gemfile_in(root, gemspec), config:)
    end

    # The nearest folder, from +start+ up, that holds one of MARKERS or a
    # gemspec, or +nil+ when a folder holding <tt>.git</tt>, or the
    # filesystem's root, comes first.
    private_class_method def self.project_root(start) # :nodoc:
      folder = start
      loop do
        return folder if marked?(folder)
        return nil if File.exist?(File.join(folder, ".git"))

        parent = File.dirname(folder)
        return nil if parent == folder

        folder = parent
      end
    end

    private_class_method def self.marked?(folder) # :nodoc:
      MARKERS.any? { |marker| File.file?(File.join(folder, marker)) } || !Dir.glob("*.gemspec", base: folder).empty?
    end

    private_class_method def self.same_folder?(one, other) # :nodoc:
      File.identical?(one, other)
    end

    # The root's gemspec, when it has exactly one that loads.
    private_class_method def self.gemspec_in(root) # :nodoc:
      paths = Dir.glob("*.gemspec", base: root)
      return nil unless paths.size == 1

      Gem::Specification.load(File.join(root, paths.first.to_s))
    end

    private_class_method def self.default_entry(path, folder, root, gemspec) # :nodoc:
      executables = [] # : Array[String]
      executables = gemspec.executables.map { |name| "#{gemspec.bindir}/#{name}" } if gemspec
      only = executables.first.to_s
      return only if executables.size == 1 && File.file?(File.join(root, only))
      return relative(File.join(folder, "main.rb"), root) if File.file?(File.join(folder, "main.rb"))

      suggestion = executables.empty? ? "such as fledge build #{File.join(path, 'exe', 'my_app')}" : executables.join(" or ")
      raise Error, "#{path} is a folder with no main.rb, and its project names no one program to ship. " \
        "Build the program you run, #{suggestion}."
    end

    private_class_method def self.relative(full, root) # :nodoc:
      full.delete_prefix("#{root}/")
    end

    private_class_method def self.gemfile_in(root, gemspec) # :nodoc:
      gemfile = %w[Gemfile gems.rb].find { |name| File.file?(File.join(root, name)) }
      if gemfile.nil? && gemspec
        raise Error, "#{root} has a gemspec but no Gemfile. Fledge ships the gems Bundler locks: add a Gemfile " \
          "holding source \"https://rubygems.org\" and gemspec, run bundle lock, and build again."
      end

      gemfile
    end

    private_class_method def self.name_for(config, gemspec, root) # :nodoc:
      chosen = config.name
      return valid_name(chosen, "#{File.join(root, Config::FILE)} names the app #{chosen.inspect}, but that") if chosen

      source = gemspec&.name || File.basename(root)
      name = camelize(source)
      valid_name(name, "The app's name, #{name.inspect}, made from #{source.inspect},")
    end

    # +name+ as Bundler names a gem's module, without the <tt>::</tt> a
    # file name cannot hold: each run of letters and digits begins with a
    # capital, and nothing else stays.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   Fledge::App.camelize("my_cool_app") # => "MyCoolApp"
    #   Fledge::App.camelize("rack-test")   # => "RackTest"
    #   Fledge::App.camelize("hello")       # => "Hello"
    #--
    # SPDX-SnippetEnd
    #++
    def self.camelize(name)
      name.split(/[^[:alnum:]]+/).reject(&:empty?).map { |part| part[0].to_s.upcase + part[1..].to_s }.join
    end

    # +name+, when every operating system can name a program and a folder
    # with it. Raises Fledge::Error, beginning with +what+, otherwise.
    private_class_method def self.valid_name(name, what) # :nodoc:
      fix = "Give the app a name in #{Config::FILE}, such as name: MyCoolApp."
      raise Error, "#{what} is empty. #{fix}" if name.strip.empty?
      raise Error, "#{what} holds a character some systems' file names cannot. #{fix}" if name.match?(%r{[/\\:*?"<>|\x00-\x1f]})
      raise Error, "#{what} is a name Windows keeps for itself. #{fix}" if name.match?(RESERVED) || name.end_with?(".", " ")

      name
    end

    # The files, folders, and symlinks to ship, with paths relative to
    # the root. Leaves out NEVER_SHIPPED and each path in +skip+ (absolute
    # paths, such as the folder builds go to).
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   Fledge::App.at("my_app/main.rb").entries(skip: [File.expand_path("my_app/dist")])
    #--
    # SPDX-SnippetEnd
    #++
    def entries(skip: [])
      Entry.walk(root, skip: skip + NEVER_SHIPPED.map { |name| File.join(root, name) })
    end
  end
end
