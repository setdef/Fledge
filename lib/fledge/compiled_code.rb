# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "yaml"
require_relative "binary"
require_relative "config"
require_relative "error"
require_relative "license_policy"

module Fledge
  # What a native gem's compiled files hold, and whether it may ship.
  #
  # A gem's specification declares one license, the gem's own. A
  # precompiled build often carries more: nokogiri's compiles in libxml2,
  # libxslt, and zlib, and for macOS and Windows GNU libiconv, which is
  # LGPL. Everything Fledge copies into an app, the app's developer gives
  # away with it, and the maintainer's rule is that an LGPL library ships
  # only as a separate shared library a person can replace, with its
  # source published, and GPL code not at all (decision 8 and the replies
  # of 2026-10-26 in <tt>doc/contributors/decisions.md</tt>). A gem's
  # declared license cannot say whether its binaries keep that rule.
  #
  # This class reads every compiled file of a gem (Fledge::Binary), as the
  # license audit reads a runtime's (ADR 004). It fails on a copyleft
  # library's code compiled into a file, found by bytes only that library
  # has, whatever anyone declares. It attributes everything else to the
  # gem's own code and to the libraries that Fledge's map
  # (<tt>compiled_code.yml</tt>, beside this file) or the app's
  # <tt>fledge.yml</tt> (Fledge::Config#compiled) says the gem holds, as
  # cargo-deny's <tt>clarify</tt> lets a project say what a crate is, and
  # fails on compiled code that neither describes. An LGPL library in its
  # own file ships when another of the gem's files loads it, so a person
  # can replace it, and <tt>fledge.yml</tt> says where its source is.
  #
  # Use it for each gem an app ships, through Fledge::AppGems.
  #
  # === Examples
  #
  #--
  # SPDX-SnippetBegin
  # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
  # SPDX-License-Identifier: MIT-0
  #++
  #   package = Fledge::GemPackage.new("sqlite3-2.10.2-x86_64-linux-gnu.gem")
  #   result = Fledge::CompiledCode.new.audit("sqlite3", package.contents)
  #   result.problems                  # => []
  #   result.components.map(&:license) # => ["blessing", "GPL-3.0-or-later WITH GCC-exception-3.1"]
  #
  #   package = Fledge::GemPackage.new("nokogiri-1.19.4-arm64-darwin.gem")
  #   Fledge::CompiledCode.new.audit("nokogiri", package.contents).problems.first
  #   # => "nokogiri compiles GNU libiconv's code (LGPL-2.1-or-later) into lib/nokogiri/3.2/nokogiri.bundle, ..."
  #--
  # SPDX-SnippetEnd
  #++
  class CompiledCode
    # Fledge's map of what native gems compile in.
    MAP = File.expand_path("compiled_code.yml", __dir__.to_s)

    # Why a copyleft library compiled into a file keeps a gem from
    # shipping.
    RULE = "Fledge ships LGPL code only as a separate shared library that a person can replace, with its source " \
      "published, and GPL code not at all (doc/licensing.md)"

    # A copyleft library, known by bytes only its code holds.
    class Signature < Data.define(:library, :license, :bytes)
      ##
      # :attr_reader: library
      # The library's name.

      ##
      # :attr_reader: license
      # The library's SPDX license expression.

      ##
      # :attr_reader: bytes
      # The strings that, all found in one file, show the library's code
      # is in it.

      # Whether +content+ holds every one of the bytes.
      #
      # === Example
      #
      #--
      # SPDX-SnippetBegin
      # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
      # SPDX-License-Identifier: MIT-0
      #++
      #   signature.in?(File.binread("nokogiri.bundle")) # => true
      #--
      # SPDX-SnippetEnd
      #++
      def in?(content)
        bytes.all? { |needle| content.include?(needle.b) }
      end
    end

    # A library a gem's compiled files may hold, and the string that shows
    # it is there.
    class Library < Data.define(:name, :license, :evidence)
      ##
      # :attr_reader: name
      # The library's name.

      ##
      # :attr_reader: license
      # The library's SPDX license expression.

      ##
      # :attr_reader: evidence
      # A string found only where the library is compiled in, or +nil+
      # when every compiled file of the gem holds it.
    end

    # What Fledge knows one gem's precompiled builds hold.
    class Entry < Data.define(:holds, :advice)
      ##
      # :attr_reader: holds
      # The Library entries its builds compile in, besides its own code.

      ##
      # :attr_reader: advice
      # What to tell a developer whose build of the gem holds a copyleft
      # library, or +nil+.
    end

    # Fledge's map, read: the copyleft libraries it looks for, what
    # compilers link into every binary, what each reviewed gem holds, and
    # the libraries each operating system provides.
    class Map < Data.define(:copyleft, :toolchain, :gems, :system_libraries)
      ##
      # :attr_reader: copyleft
      # The Signature of each copyleft library.

      ##
      # :attr_reader: toolchain
      # The Library entries a compiler links into the binaries it builds.

      ##
      # :attr_reader: gems
      # Each reviewed gem's Entry, by the gem's name.

      ##
      # :attr_reader: system_libraries
      # By operating system (+darwin+, +linux+, +windows+), the patterns
      # of the libraries it provides, which an app need not ship.

      # The Map that +data+, as <tt>compiled_code.yml</tt> holds it,
      # describes. Raises Fledge::Error when it is not one.
      #
      # === Example
      #
      #--
      # SPDX-SnippetBegin
      # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
      # SPDX-License-Identifier: MIT-0
      #++
      #   map = Fledge::CompiledCode::Map.from({ "copyleft" => [], "toolchain" => [], "gems" => { "prism" => { "holds" => [] } } })
      #   map.gems.keys # => ["prism"]
      #--
      # SPDX-SnippetEnd
      #++
      def self.from(data)
        copyleft = list(data, "copyleft").map do |item|
          Signature.new(library: text(item, "library"), license: text(item, "license"), bytes: list(item, "bytes").map(&:to_s))
        end
        none = {} # : Hash[String, Object]
        gems = data.fetch("gems", none)
        raise Error, "#{MAP}: gems must be a mapping" unless gems.is_a?(Hash)

        new(copyleft:, toolchain: list(data, "toolchain").map { |item| library(item) },
          gems: gems.to_h { |name, entry| [name.to_s, Entry.new(holds: list(entry, "holds").map { |item| library(item) }, advice: entry["advice"]&.to_s)] },
          system_libraries: system_libraries(data))
      end

      # Each OS's patterns, written as /REGEXP/ or /REGEXP/i, as
      # runtime/licenses.yml writes them.
      private_class_method def self.system_libraries(data) # :nodoc:
        none = {} # : Hash[String, Object]
        libraries = data.fetch("system_libraries", none)
        raise Error, "#{MAP}: system_libraries must be a mapping" unless libraries.is_a?(Hash)

        libraries.to_h do |os, patterns|
          [
            os.to_s,
            list({ "patterns" => patterns }, "patterns").map do |pattern|
              found = %r{\A/(.*)/(i?)\z}m.match(pattern.to_s) or raise Error, "#{MAP}: #{pattern} is not a /pattern/"
              Regexp.new(found[1].to_s, found[2].to_s.empty? ? nil : Regexp::IGNORECASE)
            end,
]
        end
      end

      private_class_method def self.library(item) # :nodoc:
        Library.new(name: text(item, "name"), license: text(item, "license"), evidence: item["evidence"]&.to_s)
      end

      private_class_method def self.list(item, key) # :nodoc:
        value = item.fetch(key) { [] }
        raise Error, "#{MAP}: #{key} must be a list" unless value.is_a?(Array)

        value
      end

      private_class_method def self.text(item, key) # :nodoc:
        value = item[key]
        raise Error, "#{MAP}: every entry needs a #{key}" unless value.is_a?(String)

        value
      end
    end

    # A library found in a gem's compiled files, or the gem's own code as
    # <tt>fledge.yml</tt> declares it.
    class Component < Data.define(:name, :license, :files, :shared, :source, :declared)
      ##
      # :attr_reader: name
      # The library's name.

      ##
      # :attr_reader: license
      # Its SPDX license expression.

      ##
      # :attr_reader: files
      # The gem's files that hold it, relative to the gem's folder.

      ##
      # :attr_reader: shared
      # Whether it ships as its own shared library, which another of the
      # gem's files loads, rather than compiled in.

      ##
      # :attr_reader: source
      # Where its source is, as <tt>fledge.yml</tt> says, or +nil+.

      ##
      # :attr_reader: declared
      # Whether <tt>fledge.yml</tt>, rather than Fledge's map, says so.
    end

    # What an audit found: the components in the gem's compiled files,
    # and every reason the gem cannot ship, as sentences.
    class Result < Data.define(:components, :problems)
      ##
      # :attr_reader: components
      # The Component entries found.

      ##
      # :attr_reader: problems
      # Why the gem cannot ship, one sentence each, or none.
    end

    # Fledge's own Map, read once.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   Fledge::CompiledCode.map.gems.fetch("sqlite3").holds.first.license # => "blessing"
    #--
    # SPDX-SnippetEnd
    #++
    def self.map
      @map ||= Map.from(YAML.safe_load_file(MAP))
    end

    # Creates the auditor.
    #
    # [declared] What <tt>fledge.yml</tt> says each gem compiles in
    #            (Fledge::Config#compiled), which wins over the map.
    # [map] The Map of what reviewed gems hold.
    # [os] The operating system the app is for (Fledge::Platform#os),
    #      whose libraries a compiled file may need, or +nil+ to leave
    #      what files need unjudged.
    # [provided] The file names of the shared libraries the runtime
    #            ships, which a compiled file may need too.
    def initialize(declared: {}, map: CompiledCode.map, os: nil, provided: [])
      @declared = declared
      @map = map
      @os = os
      @provided = provided
    end

    # Audits the gem +name+, whose files are +files+ (paths relative to its
    # folder, and their bytes), naming it +label+ in what it says.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   code = Fledge::CompiledCode.new(declared: { "mystery" => [] })
    #   code.audit("mystery", { "lib/mystery.so" => File.binread("mystery.so") }, label: "mystery 1.0.0").problems # => []
    #--
    # SPDX-SnippetEnd
    #++
    #
    # +crates+, for a gem whose Rust extension Fledge compiled, are the
    # Rust crates its build compiled in (Fledge::NativeBuild), as Library
    # entries; they describe its compiled code as the map would, and each
    # must ask nothing beyond notices.
    def audit(name, files, label: name, crates: nil)
      binaries = files.filter_map { |path, content| binary(path, content)&.then { |found| [path, found] } }.sort.to_h
      return Result.new(components: [], problems: []) if binaries.empty?

      loaded = loaded_files(binaries)
      shared = shared_libraries(name, binaries)
      copyleft = copyleft_problems(name, label, files, binaries.keys - shared.keys, loaded)
      components, problems = crates ? crate_components(label, binaries, crates) : attribute(name, label, files, binaries, shared, loaded)
      problems.clear if !copyleft.empty? && !@declared.key?(name) && !@map.gems.key?(name) && crates.nil?
      problems += linkage_problems(label, binaries)
      Result.new(components: components + toolchain(files, binaries), problems: copyleft + problems)
    rescue ArgumentError => e
      Result.new(components: [], problems: ["#{label} ships a compiled file Fledge cannot read: #{e.message}"])
    end

    # The Binary +content+ holds, or nil; ArgumentError, naming +path+,
    # when it looks like one but cannot be read.
    private def binary(path, content)
      Binary.parse(content)
    rescue RangeError, TypeError, NoMethodError => e
      raise ArgumentError, "#{path}: unreadable binary (#{e.message})"
    end

    # The paths of +binaries+ that another of them loads, by file name.
    private def loaded_files(binaries)
      binaries.select do |path, _|
        binaries.any? { |other, binary| other != path && binary.needed.any? { |library| File.basename(library).casecmp?(File.basename(path)) } }
      end.keys
    end

    # The files fledge.yml says are a library's own shared library, and
    # that library.
    private def shared_libraries(name, binaries)
      found = {} # : Hash[String, Config::Compiled]
      @declared.fetch(name, []).each do |library|
        glob = library.shared_library or next
        binaries.each_key { |path| found[path] = library if File.fnmatch?(glob, path, File::FNM_PATHNAME | File::FNM_EXTGLOB) }
      end
      found
    end

    # Every copyleft library compiled into one of +paths+, whatever anyone
    # declares.
    private def copyleft_problems(name, label, files, paths, loaded)
      @map.copyleft.filter_map do |signature|
        found = paths.select { |path| signature.in?(files.fetch(path)) }
        next if found.empty?

        hint = found.select { |path| loaded.include?(path) }.map do |path|
          " If #{path} is #{signature.library}'s own shared library, which the gem's other files load, say so in fledge.yml, " \
            "with where its source is, such as compiled: {#{name}: [{name: #{signature.library}, license: #{signature.license}, " \
            "shared_library: #{path}, source: https://example.com/source.tar.gz}]}."
        end
        advice = @map.gems[name]&.advice
        "#{label} compiles #{signature.library}'s code (#{signature.license}) into #{sentence(found)}. #{RULE}, so this " \
          "build of #{name} cannot ship.#{hint.join}#{" #{advice}" if advice}"
      end
    end

    # The components fledge.yml or the map says the gem holds, or why its
    # compiled code cannot be attributed.
    private def attribute(name, label, files, binaries, shared, loaded)
      declared = @declared[name]
      return declared_components(label, files, binaries, declared, shared, loaded) if declared

      entry = @map.gems[name]
      return [[], [unreviewed(name, label, binaries.keys)]] unless entry

      components = entry.holds.filter_map do |library|
        holding = binaries.keys.select { |path| library.evidence.nil? || files.fetch(path).include?(library.evidence.to_s.b) }
        component(library.name, library.license, holding, declared: false) unless holding.empty?
      end
      [components, []]
    end

    private def declared_components(label, files, binaries, declared, shared, loaded)
      compiled_into = binaries.keys - shared.keys
      problems = [] # : Array[String]
      components = declared.filter_map do |library|
        if library.shared_library
          paths = shared.select { |_, owner| owner.equal?(library) }.keys
          problems.concat(shared_problems(label, files, library, paths, loaded))
          component(library.name, library.license, paths, declared: true, shared: true, source: library.source) unless paths.empty?
        else
          problems << compiled_in_problem(label, library) unless LicensePolicy.notice_only?(library.license)
          component(library.name, library.license, compiled_into, declared: true) unless compiled_into.empty?
        end
      end
      [components, problems]
    end

    private def shared_problems(label, files, library, paths, loaded)
      said = "fledge.yml says #{library.shared_library} is #{library.name}'s own shared library"
      return ["#{said}, but #{label} has no compiled file #{library.shared_library}."] if paths.empty?

      category = LicensePolicy.category(library.license)
      copyleft = paths.any? { |path| @map.copyleft.any? { |signature| signature.in?(files.fetch(path)) } }
      problems = paths.reject { |path| loaded.include?(path) }.map do |path|
        "#{said}, but no other compiled file of #{label} loads #{path}, so it is not a library a person can replace, and " \
          "#{RULE}."
      end
      if %i[notice_only shared_library].none?(category)
        problems << "#{said}, under #{library.license}, which Fledge does not ship (doc/licensing.md)."
      elsif (category == :shared_library || copyleft) && library.source.nil?
        problems << "#{said}, and its license asks that its source be published with the app: give where its source is, " \
          "under source, such as source: https://example.com/source.tar.gz."
      end
      problems
    end

    private def compiled_in_problem(label, library)
      "fledge.yml says #{label} compiles in #{library.name} (#{library.license}). #{RULE}, so it cannot ship compiled in. " \
        "If it ships as its own shared library, which the gem's other files load, say which, under shared_library, and " \
        "where its source is, under source."
    end

    private def unreviewed(name, label, paths)
      "#{label} ships compiled code (#{sentence(paths)}) that Fledge has not reviewed, so it cannot say what libraries " \
        "are compiled into it or what their licenses ask of you. Read the gem's notices (its LICENSE files and README), " \
        "then say what its compiled code holds in fledge.yml, under compiled, such as " \
        "compiled: {#{name}: [{name: libfoo 1.2, license: MIT}]}, or compiled: {#{name}: []} when it is the gem's own " \
        "code alone."
    end

    # The crates a Rust build compiled into every compiled file of the
    # gem, and why any of them cannot ship.
    private def crate_components(label, binaries, crates)
      problems = crates.reject { |crate| LicensePolicy.notice_only?(crate.license) }.map do |crate|
        said = (crate.license == "NOASSERTION") ? "declares no license" : "is #{crate.license}"
        "#{label} compiles in the #{crate.name}, which #{said}, and Fledge ships only code whose license asks nothing " \
          "beyond keeping its notices (doc/licensing.md)."
      end
      [crates.map { |crate| component(crate.name, crate.license, binaries.keys, declared: false) }, problems]
    end

    # A Windows Ruby's DLL, such as x64-ucrt-ruby400.dll.
    RUBY_DLL = /\A[\w-]*-ruby\d+\.dll\z/i

    # Why a compiled file would not load where the app goes: a library it
    # needs that neither the operating system, nor the runtime, nor the
    # gem itself provides. A file that needs another Ruby's DLL is built
    # for that Ruby, as a gem precompiled for several Ruby versions ships
    # one file for each (lib/nokogiri/3.4/nokogiri.so), and the runtime's
    # Ruby never loads it.
    private def linkage_problems(label, binaries)
      return [] unless @os

      system = @map.system_libraries.fetch(@os, [])
      shipped = (binaries.keys.map { |path| File.basename(path) } + @provided).map(&:downcase)
      binaries.flat_map do |path, binary|
        next [] if binary.needed.any? { |library| library.match?(RUBY_DLL) && !shipped.include?(library.downcase) }

        binary.needed.reject { |library| system.any? { |pattern| pattern.match?(library) } || shipped.include?(File.basename(library).downcase) }
          .map do |library|
            "#{label}'s #{path} needs #{library}, which neither #{@os}, nor Fledge's runtime, nor the gem itself provides, so " \
              "the app could not load it on another computer. Build the gem so that it carries the library, or links it statically."
          end
      end
    end

    # What the compiler linked into each file, where its evidence is.
    private def toolchain(files, binaries)
      @map.toolchain.filter_map do |library|
        holding = binaries.keys.select { |path| files.fetch(path).include?(library.evidence.to_s.b) }
        component(library.name, library.license, holding, declared: false) unless holding.empty?
      end
    end

    private def component(name, license, files, declared:, shared: false, source: nil)
      Component.new(name:, license:, files:, shared:, source:, declared:)
    end

    # +items+ as a sentence lists them.
    private def sentence(items)
      return items.join(" and ") if items.size < 3

      "#{items[0...-1].to_a.join(', ')}, and #{items.last}"
    end
  end
end
