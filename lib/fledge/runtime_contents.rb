# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "error"
require_relative "archive"

module Fledge
  # What a runtime archive holds that an app's gems depend on: where its
  # gems go, which gems it has, and which Ruby it runs.
  #
  # An app's gems join the runtime's default and bundled gems in Ruby's
  # own gem folder, <tt>lib/ruby/gems/4.1.0+5</tt> (in <tt>ruby\</tt> on
  # Windows), where RubyGems and Bundler find them
  # (doc/contributors/design/gems.md, "Installing into the runtime's gem
  # folder"). A gem the
  # runtime already has at the same version is the runtime's, already
  # audited, and must not be added twice; a gem must suit the runtime's
  # Ruby. The runtime knows all three, so they are read from it rather
  # than kept a second time in Fledge. A gem's compiled file may need one
  # of the runtime's own shared libraries, too, where the loader finds it.
  #
  # This class reads a runtime archive once and keeps the gem folder, by
  # the path of its <tt>specifications</tt> folder, the full name of every
  # gem specification in it, the Ruby version RubyGems and Bundler compare
  # gems and Gemfiles with (Gem.ruby_version), from RbConfig's MAJOR,
  # MINOR, TEENY, and PATCHLEVEL and the runtime's DESCRIPTION file, and
  # that patch level, the file name of every shared library it holds
  # where a compiled file finds it, and the architecture its rbconfig.rb
  # records, which is the platform RubyGems and Bundler see when the app
  # runs (Gem::Platform.local), whatever computer it runs on.
  #
  # Use it to plan which of an app's gems a runtime needs.
  #
  # === Example
  #
  #--
  # SPDX-SnippetBegin
  # SPDX-SnippetCopyrightText: 2026 setdef <kerrick@setdef.com>
  # SPDX-License-Identifier: MIT-0
  #++
  #   contents = Fledge::RuntimeContents.read("fledge-runtime-0.0.1-x64-mingw-ucrt.tar.gz")
  #   contents.gem_dir                    # => "ruby/lib/ruby/gems/4.1.0+5"
  #   contents.ruby_version               # => "4.1.0.dev"
  #   contents.patchlevel                 # => "-1"
  #   contents.gems.include?("csv-3.3.5") # => true
  #   contents.arch                       # => "x64-mingw-ucrt"
  #--
  # SPDX-SnippetEnd
  #++
  class RuntimeContents < Data.define(:gem_dir, :gems, :ruby_version, :patchlevel, :libraries, :arch, :path, :plugins, :binaries,
    :extension_api)
    ##
    # :attr_reader: gem_dir
    # Ruby's gem folder, relative to the runtime's top folder.

    ##
    # :attr_reader: gems
    # The full name of every gem the runtime has, default gems included,
    # such as <tt>csv-3.3.5</tt>.

    ##
    # :attr_reader: ruby_version
    # The runtime's Ruby version as its RubyGems reports it
    # (Gem.ruby_version), such as <tt>4.1.0</tt>, <tt>4.1.0.preview1</tt>
    # for a preview, or <tt>4.1.0.dev</tt> for a build of Ruby's master.

    ##
    # :attr_reader: patchlevel
    # The runtime's Ruby's patch level, RbConfig's PATCHLEVEL, which is
    # its RUBY_PATCHLEVEL: <tt>-1</tt> for a preview or a build of Ruby's
    # master, and <tt>0</tt> or more for a release. Bundler before 4.1
    # compares a Gemfile's patch level with it (Bundler::RubyVersion.system).

    ##
    # :attr_reader: arch
    # The runtime's Ruby's architecture, RbConfig's +arch+, such as
    # <tt>arm64-darwin23</tt>: the platform its RubyGems and Bundler call
    # local (Gem::Platform.local).

    ##
    # :attr_reader: libraries
    # The file name of every shared library the runtime holds where a
    # compiled file that needs it by name finds it, sorted, such as
    # <tt>x64-ucrt-ruby410.dll</tt>: on Windows, Ruby's DLL and the DLLs
    # in <tt>ruby_builtin_dlls</tt> and Ruby's architecture folder, and
    # elsewhere every one, since the runtime places its own.

    ##
    # :attr_reader: path
    # The runtime archive's path.

    ##
    # :attr_reader: plugins
    # The path of every RubyGems plugin loader the runtime's gem folder
    # holds, such as <tt>lib/ruby/gems/4.1.0+5/plugins/rdoc_plugin.rb</tt>,
    # which a gem of the same name at another version would write to
    # (Gem::Installer#generate_plugins).

    ##
    # :attr_reader: binaries
    # The path of every file in the runtime's bin folder (#bin_dir), such
    # as <tt>bin/rake</tt>: the programs of the gems it ships, which a gem
    # of the same name at another version would write over.

    ##
    # :attr_reader: extension_api
    # The name of the folder in which the runtime's RubyGems looks for a
    # gem's compiled extensions (Gem.extension_api_version): the gem
    # folder's name, such as <tt>4.1.0+5</tt>, with <tt>-static</tt> for
    # a Ruby without a shared library, as the iOS runtime's is.

    # The runtime's bin folder, where RubyGems writes a gem's executables
    # (Gem.bindir): beside the gem folder's <tt>lib</tt>, at <tt>bin</tt>,
    # or <tt>ruby/bin</tt> on Windows.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 setdef <kerrick@setdef.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   contents.bin_dir # => "ruby/bin"
    #--
    # SPDX-SnippetEnd
    #++
    def bin_dir
      [gem_dir.sub(%r{/?lib/ruby/gems/[^/]+\z}, ""), "bin"].reject(&:empty?).join("/")
    end

    # A gem specification's path in a runtime: the gem folder, and the
    # gem's full name.
    SPECIFICATION = %r{\A(?<gem_dir>(?:[^/]+/)*lib/ruby/gems/[^/]+)/specifications/(?:default/)?(?<full_name>[^/]+)\.gemspec\z}
    # rbconfig.rb's path in a runtime, in Ruby's architecture folder.
    RBCONFIG = %r{\A(?:[^/]+/)*lib/ruby/\d[^/]*/[^/]+/rbconfig\.rb\z}
    # The lines of rbconfig.rb that hold Ruby's version, a part each, and
    # its patch level, -1 for a preview or a development build.
    VERSION_PARTS = /^\s*CONFIG\["(MAJOR|MINOR|TEENY|PATCHLEVEL)"\] = "(-?\d+)"/
    # The file at a runtime's top that holds its Ruby's RUBY_DESCRIPTION,
    # as far as the platform's name, such as <tt>ruby 4.1.0preview1
    # (2026-10-11 master 2d08b5f42f)</tt>, which the runtime's build reads
    # out of Ruby's own program or library. Ruby compiles the name of a
    # preview or a development build into that string alone (+version.h+
    # and +version.c+), and RubyGems reads it from there
    # (Gem.ruby_version).
    DESCRIPTION = "RUBY_DESCRIPTION"
    # The line of rbconfig.rb that holds Ruby's architecture.
    ARCH = /^\s*CONFIG\["arch"\] = "([^"]+)"/
    # The line of rbconfig.rb that says Ruby is a shared library.
    SHARED = /^\s*CONFIG\["ENABLE_SHARED"\] = "yes"/
    # A RubyGems plugin loader in a gem folder.
    PLUGIN = %r{\A(?:[^/]+/)*lib/ruby/gems/[^/]+/plugins/[^/]+_plugin\.[^/]+\z}
    # The file name of a shared library: .so (with a version or not),
    # .dylib, or .dll.
    LIBRARY = /\.(?:so(?:\.\d+)*|dylib|dll)\z/i

    # The contents of the runtime archive at +path+, or of its folder
    # +under+ (relative to the archive's top folder, ending in a
    # <tt>/</tt>), such as an iOS runtime's XCFramework slice, which holds a
    # Ruby of its own (doc/contributors/design/phone-runtimes.md, "What a phone
    # runtime holds"); its paths are then relative to
    # that folder. Raises Fledge::Error when it holds no gem folder or no
    # rbconfig.rb.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 setdef <kerrick@setdef.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   Fledge::RuntimeContents.read(runtime).gem_dir # => "lib/ruby/gems/4.1.0+5"
    #   Fledge::RuntimeContents.read(ios, under: "FledgeRuby.xcframework/ios-arm64/").gem_dir
    #   # => "lib/ruby/gems/4.1.0+5"
    #--
    # SPDX-SnippetEnd
    #++
    def self.read(path, under: "")
      gem_dirs = [] # : Array[String]
      gems = [] # : Array[String]
      version = nil # : String?
      arch = nil # : String?
      patchlevel = ""
      libraries = [] # : Array[String]
      rbconfig_inside = "" # : String
      plugins = [] # : Array[String]
      inside_all = [] # : Array[String]
      rbconfig = nil # : String?
      description = nil # : String?
      shared = false
      Archive.names(path).each do |name|
        inside = name.split("/", 2).last.to_s
        description = name if inside == DESCRIPTION
        next unless inside.start_with?(under)

        inside = inside.delete_prefix(under)
        libraries << inside if inside.match?(LIBRARY)
        plugins << inside if inside.match?(PLUGIN)
        inside_all << inside
        if (found = SPECIFICATION.match(inside))
          gem_dirs << found[:gem_dir].to_s
          gems << found[:full_name].to_s
        elsif RBCONFIG.match?(inside)
          rbconfig_inside = inside unless rbconfig
          rbconfig ||= name
        end
      end
      if rbconfig
        content = Archive.read(path, rbconfig)
        version = ruby_version_in(content, description && Archive.read(path, description).force_encoding(Encoding::UTF_8))
        arch = content[ARCH, 1]
        shared = content.match?(SHARED)
        patchlevel = content.scan(VERSION_PARTS).to_h["PATCHLEVEL"].to_s
      end
      raise Error, "#{path} is not a Fledge runtime: its rbconfig.rb names no arch" if version && arch.nil?

      contents = build(path, gem_dirs.uniq, gems, version)
      prefix = "#{contents.bin_dir}/"
      binaries = inside_all.select { |inside| inside.start_with?(prefix) && !inside.end_with?("/") }
      archdir = File.dirname(rbconfig_inside)
      found = arch.to_s.include?("mingw") ? libraries.select { |library| searched?(library, contents.bin_dir, archdir) } : libraries
      contents.with(patchlevel:, libraries: found.map { |library| File.basename(library) }.uniq.sort.freeze, arch: arch.to_s,
        plugins: plugins.sort.freeze, binaries: binaries.sort.freeze, extension_api: "#{File.basename(contents.gem_dir)}#{'-static' unless shared}")
    end

    # Whether the app's Ruby on Windows finds the DLL at +path+ when an
    # extension imports it by name: Windows looks among the modules
    # loaded, Ruby's DLL in +bin_dir+ first, which the launcher loads by
    # its path, then in the folders the process's DLL search names, never
    # beside the extension. Those are <tt>ruby_builtin_dlls</tt> in
    # +bin_dir+, which the launcher and the runtime's ruby.exe add, and
    # Ruby's architecture folder, +archdir+, which Fledge's RubyGems
    # defaults add, as RubyInstaller's start-up does
    # (doc/contributors/design/runtimes.md, "The DLLs a compiled gem finds
    # on Windows").
    private_class_method def self.searched?(path, bin_dir, archdir)
      folder = File.dirname(path)
      folder == "#{bin_dir}/ruby_builtin_dlls" || folder == archdir || (folder == bin_dir && File.basename(path).match?(Linkage::RUBY_DLL))
    end

    # The tool +name+ the runtime keeps in its <tt>tools</tt> folder
    # (Fledge::Assembly::TOOLS), written into the folder +into+, where it
    # runs; or nil when the runtime has none.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 setdef <kerrick@setdef.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   contents.tool("llvm-readobj.exe", into: Dir.mktmpdir) # => "/tmp/d20261101-1-x/llvm-readobj.exe"
    #--
    # SPDX-SnippetEnd
    #++
    def tool(name, into:)
      entry = Archive.names(path).find { |candidate| candidate.split("/", 2).last == "tools/#{name}" } or return nil
      target = File.join(into, name)
      File.binwrite(target, Archive.read(path, entry))
      File.chmod(0o755, target)
      target
    end

    # The version of the Ruby whose rbconfig.rb is +rbconfig+ and whose
    # RUBY_DESCRIPTION is +description+, as RubyGems reports it: MAJOR,
    # MINOR, and TEENY, and, when PATCHLEVEL is -1, the name the
    # description gives after them. A runtime built before it recorded
    # its description has none, and reads as MAJOR, MINOR, and TEENY.
    private_class_method def self.ruby_version_in(rbconfig, description) # :nodoc:
      parts = rbconfig.scan(VERSION_PARTS).to_h
      version = %w[MAJOR MINOR TEENY].map { |part| parts[part] or return nil }.join(".")
      return version unless parts["PATCHLEVEL"] == "-1" && description

      #--
      # SPDX-SnippetBegin
      # SPDX-License-Identifier: Ruby OR MIT
      # SPDX-SnippetCopyrightText: Chad Fowler, Rich Kilmer, Jim Weirich and others
      # SPDX-SnippetComment: Gem.ruby_version, adapted from RubyGems'
      #   lib/rubygems.rb at Ruby v4.1.0-preview1 (2d08b5f42f), lines 965
      #   to 979, with rbconfig.rb's version and patch level in place of
      #   RUBY_VERSION and RUBY_PATCHLEVEL, for CRuby, whose engine is ruby.
      #++
      name = description[/\Aruby #{Regexp.quote(version)}([^ ]+) /, 1]
      name ? "#{version}.#{name}" : version
      #--
      # SPDX-SnippetEnd
      #++
    end

    private_class_method def self.build(path, gem_dirs, gems, version) # :nodoc:
      raise Error, "#{path} is not a Fledge runtime: it holds no one gem folder (#{gem_dirs.join(', ')})" unless gem_dirs.size == 1
      raise Error, "#{path} is not a Fledge runtime: it holds no rbconfig.rb" unless version

      new(gem_dir: gem_dirs.first.to_s, gems: gems.sort.freeze, ruby_version: version, patchlevel: "", libraries: [], arch: "", path:, plugins: [], binaries: [], extension_api: "")
    end
  end
end
