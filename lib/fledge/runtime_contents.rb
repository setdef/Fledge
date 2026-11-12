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
  # own gem folder, <tt>lib/ruby/gems/4.0.0</tt> (in <tt>ruby\</tt> on
  # Windows), where RubyGems and Bundler find them
  # (doc/contributors/design/gems.md, "Installing into the runtime's gem
  # folder"). A gem the
  # runtime already has at the same version is the runtime's, already
  # audited, and must not be added twice; a gem must suit the runtime's
  # Ruby. The runtime knows all three, so they are read from it rather
  # than kept a second time in Fledge. A gem's compiled file may need one
  # of the runtime's own shared libraries, too.
  #
  # This class reads a runtime archive once and keeps the gem folder, by
  # the path of its <tt>specifications</tt> folder, the full name of every
  # gem specification in it, the Ruby version its <tt>rbconfig.rb</tt>
  # records, as RbConfig's MAJOR, MINOR, and TEENY, and the file name of
  # every shared library it holds, and the architecture its rbconfig.rb
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
  #   contents.gem_dir                    # => "ruby/lib/ruby/gems/4.0.0"
  #   contents.ruby_version               # => "4.0.9"
  #   contents.gems.include?("csv-3.3.5") # => true
  #   contents.arch                       # => "x64-mingw-ucrt"
  #--
  # SPDX-SnippetEnd
  #++
  class RuntimeContents < Data.define(:gem_dir, :gems, :ruby_version, :libraries, :arch, :path, :plugins, :binaries)
    ##
    # :attr_reader: gem_dir
    # Ruby's gem folder, relative to the runtime's top folder.

    ##
    # :attr_reader: gems
    # The full name of every gem the runtime has, default gems included,
    # such as <tt>csv-3.3.5</tt>.

    ##
    # :attr_reader: ruby_version
    # The runtime's Ruby version, such as <tt>4.0.9</tt>.

    ##
    # :attr_reader: arch
    # The runtime's Ruby's architecture, RbConfig's +arch+, such as
    # <tt>arm64-darwin23</tt>: the platform its RubyGems and Bundler call
    # local (Gem::Platform.local).

    ##
    # :attr_reader: libraries
    # The file name of every shared library the runtime holds, sorted,
    # such as <tt>x64-ucrt-ruby400.dll</tt>.

    ##
    # :attr_reader: path
    # The runtime archive's path.

    ##
    # :attr_reader: plugins
    # The path of every RubyGems plugin loader the runtime's gem folder
    # holds, such as <tt>lib/ruby/gems/4.0.0/plugins/rdoc_plugin.rb</tt>,
    # which a gem of the same name at another version would write to
    # (Gem::Installer#generate_plugins).

    ##
    # :attr_reader: binaries
    # The path of every file in the runtime's bin folder (#bin_dir), such
    # as <tt>bin/rake</tt>: the programs of the gems it ships, which a gem
    # of the same name at another version would write over.

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
    # The lines of rbconfig.rb that hold Ruby's version, a part each.
    VERSION_PARTS = /^\s*CONFIG\["(MAJOR|MINOR|TEENY)"\] = "(\d+)"/
    # The line of rbconfig.rb that holds Ruby's architecture.
    ARCH = /^\s*CONFIG\["arch"\] = "([^"]+)"/
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
    #   Fledge::RuntimeContents.read(runtime).gem_dir # => "lib/ruby/gems/4.0.0"
    #   Fledge::RuntimeContents.read(ios, under: "FledgeRuby.xcframework/ios-arm64/").gem_dir
    #   # => "lib/ruby/gems/4.0.0"
    #--
    # SPDX-SnippetEnd
    #++
    def self.read(path, under: "")
      gem_dirs = [] # : Array[String]
      gems = [] # : Array[String]
      version = nil # : String?
      arch = nil # : String?
      libraries = [] # : Array[String]
      plugins = [] # : Array[String]
      inside_all = [] # : Array[String]
      rbconfig = nil # : String?
      Archive.names(path).each do |name|
        inside = name.split("/", 2).last.to_s
        next unless inside.start_with?(under)

        inside = inside.delete_prefix(under)
        libraries << File.basename(inside) if inside.match?(LIBRARY)
        plugins << inside if inside.match?(PLUGIN)
        inside_all << inside
        if (found = SPECIFICATION.match(inside))
          gem_dirs << found[:gem_dir].to_s
          gems << found[:full_name].to_s
        elsif RBCONFIG.match?(inside)
          rbconfig ||= name
        end
      end
      if rbconfig
        content = Archive.read(path, rbconfig)
        version = ruby_version_in(content)
        arch = content[ARCH, 1]
      end
      raise Error, "#{path} is not a Fledge runtime: its rbconfig.rb names no arch" if version && arch.nil?

      contents = build(path, gem_dirs.uniq, gems, version)
      prefix = "#{contents.bin_dir}/"
      binaries = inside_all.select { |inside| inside.start_with?(prefix) && !inside.end_with?("/") }
      contents.with(libraries: libraries.uniq.sort.freeze, arch: arch.to_s, plugins: plugins.sort.freeze, binaries: binaries.sort.freeze)
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

    # The version rbconfig.rb's MAJOR, MINOR, and TEENY make.
    private_class_method def self.ruby_version_in(rbconfig) # :nodoc:
      parts = rbconfig.scan(VERSION_PARTS).to_h
      %w[MAJOR MINOR TEENY].map { |part| parts[part] or return nil }.join(".")
    end

    private_class_method def self.build(path, gem_dirs, gems, version) # :nodoc:
      raise Error, "#{path} is not a Fledge runtime: it holds no one gem folder (#{gem_dirs.join(', ')})" unless gem_dirs.size == 1
      raise Error, "#{path} is not a Fledge runtime: it holds no rbconfig.rb" unless version

      new(gem_dir: gem_dirs.first.to_s, gems: gems.sort.freeze, ruby_version: version, libraries: [], arch: "", path:, plugins: [], binaries: [])
    end
  end
end
