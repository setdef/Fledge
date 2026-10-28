# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "rubygems"
require "rubygems/package"
require "stringio"
require "zlib"
require_relative "entry"
require_relative "error"

module Fledge
  # A <tt>.gem</tt> file, installed into a runtime's gem folder for
  # another platform than the one Fledge runs on.
  #
  # <tt>gem install</tt> installs a gem for the Ruby that runs it: it
  # checks the gem against that Ruby's platform, compiles its extensions
  # with that Ruby's compiler, and writes executables that start that
  # Ruby. None of that holds for a Windows app built on a Mac. A gem
  # precompiled for the target needs none of it, though: installing it is
  # unpacking it.
  #
  # This class does what Gem::Installer#install does for such a gem, as
  # entries rather than files: the gem's files in
  # <tt>gems/FULL_NAME/</tt> (Gem::Package#extract_files), its
  # specification in <tt>specifications/</tt> (Gem::Installer#write_spec),
  # the <tt>.gem</tt> itself in <tt>cache/</tt>
  # (Gem::Installer#write_cache_file), and a loader in <tt>plugins/</tt> for
  # each RubyGems plugin it carries (Gem::Installer#generate_plugins). It
  # writes no executables in <tt>bin/</tt>, which only a shell uses and
  # which would name the Ruby that built the app. It verifies the file
  # first, as Gem::Package#verify does, says whether it has an extension
  # still to compile (Fledge::NativeBuild compiles it), and says what
  # keeps it from running on the target: a Ruby version it does not
  # support.
  #
  # Use it for each gem an app ships.
  #
  # === Example
  #
  #--
  # SPDX-SnippetBegin
  # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
  # SPDX-License-Identifier: MIT-0
  #++
  #   package = Fledge::GemPackage.new("sqlite3-2.10.2-x64-mingw-ucrt.gem")
  #   package.spec.full_name                       # => "sqlite3-2.10.2-x64-mingw-ucrt"
  #   package.problems(ruby_version: "4.0.9")      # => []
  #   package.entries("ruby/lib/ruby/gems/4.0.0").first.path
  #   # => "ruby/lib/ruby/gems/4.0.0/gems/sqlite3-2.10.2-x64-mingw-ucrt"
  #--
  # SPDX-SnippetEnd
  #++
  class GemPackage
    # Why +spec+'s gem cannot run on a runtime whose Ruby is
    # +ruby_version+, as RubyGems would refuse it, or none.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   Fledge::GemPackage.ruby_problems(spec, "4.0.9") # => ["old 1.0 needs Ruby < 3.0, and Fledge's runtime is Ruby 4.0.9."]
    #--
    # SPDX-SnippetEnd
    #++
    def self.ruby_problems(spec, ruby_version)
      return [] if spec.required_ruby_version.satisfied_by?(Gem::Version.new(ruby_version))

      [
"#{spec.name} #{spec.version}#{" (#{spec.platform})" unless spec.platform.to_s == 'ruby'} needs Ruby " \
  "#{spec.required_ruby_version}, and Fledge's runtime is Ruby #{ruby_version}.",
]
    end

    # The gem's Gem::Specification.
    attr_reader :spec

    # Reads the <tt>.gem</tt> file at +path+. Raises Fledge::Error when it
    # is not a gem whose checksums match its contents.
    def initialize(path)
      @path = path
      package = Gem::Package.new(path)
      package.verify
      @spec = package.spec
      @files = data_files
    rescue Gem::Package::FormatError, Gem::Security::Exception, Zlib::Error => e
      raise Error, "#{path} is not a gem RubyGems can install: #{e.message}"
    end

    # What keeps the gem from running on +platform+'s runtime, whose Ruby
    # is +ruby_version+, as sentences, or none. An extension still to
    # compile is not one of them: whether Fledge can compile it for
    # +platform+ is Fledge::AppGems's to say (#extensions?).
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   Fledge::GemPackage.new("sqlite3-2.10.2-x64-mingw-ucrt.gem").problems(ruby_version: "4.0.9")
    #   # => []
    #--
    # SPDX-SnippetEnd
    #++
    def problems(ruby_version:)
      GemPackage.ruby_problems(spec, ruby_version)
    end

    # Whether the gem has an extension still to compile: a gem built for
    # every platform, with extensions its specification names.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   Fledge::GemPackage.new("redcarpet-3.6.1.gem").extensions? # => true
    #--
    # SPDX-SnippetEnd
    #++
    def extensions?
      !spec.extensions.empty?
    end

    # Where the gem's folder is in a built app whose gem folder is
    # +gem_dir+: <tt>GEM_DIR/gems/FULL_NAME</tt>.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   package.installed_path("lib/ruby/gems/4.0.0") # => "lib/ruby/gems/4.0.0/gems/i18n-1.15.2"
    #--
    # SPDX-SnippetEnd
    #++
    def installed_path(gem_dir)
      "#{gem_dir}/gems/#{spec.full_name}"
    end

    # The path of the <tt>.gem</tt> file.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   package.path # => "/home/you/.cache/fledge/gems/i18n-1.15.2.gem"
    #--
    # SPDX-SnippetEnd
    #++
    attr_reader :path

    # The entries that install the gem into the gem folder +gem_dir+, a
    # path relative to the built app.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   package.entries("lib/ruby/gems/4.0.0").map(&:path).last
    #   # => "lib/ruby/gems/4.0.0/cache/i18n-1.15.2.gem"
    #--
    # SPDX-SnippetEnd
    #++
    def entries(gem_dir)
      full_name = spec.full_name
      installed = installed_path(gem_dir)
      [
        Entry.directory(installed),
        *@files.map { |entry| entry.with(path: "#{installed}/#{entry.path}") },
        Entry.file("#{gem_dir}/specifications/#{full_name}.gemspec", specification),
        Entry.file("#{gem_dir}/cache/#{spec.file_name}", File.binread(@path)),
        *plugins(gem_dir, installed),
      ]
    end

    # Every file in the gem, by its path in the gem, and its bytes.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   package.contents.keys.grep(/\.so\z/) # => ["lib/sqlite3/4.0/sqlite3_native.so", ...]
    #--
    # SPDX-SnippetEnd
    #++
    def contents
      @files.select { |entry| entry.type == :file }.to_h { |entry| [entry.path, entry.content.to_s] }
    end

    # The specification as Gem::Installer#write_spec writes it, marked as
    # installed by this RubyGems.
    private def specification
      copy = spec.dup
      copy.installed_by_version = Gem.rubygems_version
      copy.to_ruby_for_cache
    end

    # Gem::Installer#generate_plugins: a loader for each plugin (a
    # <tt>rubygems_plugin</tt> file in one of the gem's require paths, as
    # Gem::BasicSpecification#plugins finds them), named for the gem, that
    # requires it from the gem's folder.
    private def plugins(gem_dir, installed)
      found = @files.filter_map do |entry|
        entry.path if spec.require_paths.any? { |folder| File.fnmatch?("#{folder}/rubygems_plugin#{Gem.suffix_pattern}", entry.path, File::FNM_EXTGLOB) }
      end
      found.map do |plugin|
        relative = "../gems/#{File.basename(installed)}/#{plugin}"
        Entry.file("#{gem_dir}/plugins/#{spec.name}_plugin#{File.extname(plugin)}", "require_relative '#{relative}'\n")
      end
    end

    # The files, folders, and symlinks in the gem's data.tar.gz, with
    # their paths in the gem, as Gem::Package#extract_files would write
    # them: folders and executable files 0755, other files 0644.
    private def data_files
      data = nil # : String?
      File.open(@path, "rb") do |io|
        Gem::Package::TarReader.new(io).each do |entry|
          next unless entry.full_name == "data.tar.gz"

          data = entry.read.to_s
          break
        end
      end
      raise Error, "#{@path} holds no data.tar.gz" unless data

      Gem::Package::TarReader.new(StringIO.new(Zlib.gunzip(data))).filter_map { |entry| entry_of(entry) }
    end

    private def entry_of(entry)
      path = entry.full_name.delete_prefix("./").delete_suffix("/")
      return nil if path.empty?

      if entry.directory?
        Entry.directory(path)
      elsif entry.symlink?
        Entry.symlink(path, entry.header.linkname)
      else
        Entry.file(path, entry.read.to_s.b, mode: entry.header.mode.anybits?(0o111) ? 0o755 : 0o644)
      end
    end
  end
end
