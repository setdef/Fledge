# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require "fileutils"
require "tmpdir"
require_relative "binary"
require_relative "command"
require_relative "error"
require_relative "linkage"

module Fledge
  # The libraries from the developer's computer that a macOS app carries,
  # when its project lists them under <tt>macos: carried_libraries</tt>
  # (Config::Macos).
  #
  # A gem's compiled file may link a library the developer installed with
  # a package manager, such as Homebrew's SDL for gosu, which no Mac has
  # from Apple and which Fledge::Linkage refuses unless the project lists
  # it. A Mac has no package manager of its own to name it to, as a
  # <tt>.deb</tt> names a Linux distribution's, so the app carries a copy,
  # as delocate and dylibbundler do. The developer
  # names every library the app is to carry, its own needs among them, and
  # distributes them under their licenses, which are the developer's to
  # honor, as their gems' are (the maintainer's words of 2026-11-22 and
  # 2026-10-28): Fledge carries nothing unlisted and says nothing of a
  # license.
  #
  # This class finds each listed library where dyld finds it for the
  # developer's own <tt>bundle exec</tt>: at a file's absolute install
  # name, through its absolute run paths and those of the files that load
  # it, or beside the library that names it with <tt>@loader_path</tt>.
  # It refuses one for another processor than the app's, or for a newer
  # macOS than the app's oldest, one that names an unlisted library, and
  # a listed one nothing needs. It copies each into FOLDER, one copy for
  # the whole app, so a library two gems need is loaded once; and changes
  # each need of a carried library, in the gems' files and in the copies,
  # to its <tt>@loader_path</tt> path to the copy, with
  # <tt>install_name_tool -change</tt>, which leaves every other load
  # command as it was, then signs each changed file ad hoc, as Apple
  # Silicon runs only signed code. The copies in the app change; the
  # gems the developer's <tt>bundle exec</tt> loads do not.
  # (doc/contributors/design/gems.md, "Libraries a Mac app carries".)
  #
  # Use it through Fledge::AppGems.
  #
  # === Example
  #
  #--
  # SPDX-SnippetBegin
  # SPDX-SnippetCopyrightText: 2026 setdef <kerrick@setdef.com>
  # SPDX-License-Identifier: MIT-0
  #++
  #   carried = Fledge::CarriedLibraries.new(["libSDL3.0.dylib"], files:, platform: Fledge::Platform.local, readers:)
  #   carried.sources # => { "libSDL3.0.dylib" => "/opt/homebrew/Cellar/sdl3/3.2.26/lib/libSDL3.0.dylib" }
  #   carried.changes # => { "lib/ruby/gems/4.1.0+5/gems/gosu-1.5.0/lib/gosu-ffi.bundle" => [["@rpath/libSDL3.0.dylib", "@loader_path/..."]] }
  #--
  # SPDX-SnippetEnd
  #++
  class CarriedLibraries
    # Where in the app the copies go, beside the runtime's own libraries:
    # in the runtime's folder, which a console app's folder and a
    # windowed app's <tt>Contents/Resources</tt> both hold, and which a
    # bundle's <tt>Contents/MacOS/lib</tt> links to.
    FOLDER = "lib/carried"

    # What to install when a tool this class runs is missing.
    INSTALL = "Install Xcode's command line tools (xcode-select --install), which have install_name_tool and codesign."

    # Plans what the app carries.
    #
    # [names] The file names the project lists (Config::Macos#carried_libraries).
    # [files] The gems' files as the app holds them, by path in the app's
    #         folder (a console app's, or a bundle's
    #         <tt>Contents/Resources</tt>), and their bytes.
    # [platform] The Fledge::Platform the app is for: its processor and
    #            its oldest macOS.
    # [readers] The tools that read compiled files (Fledge::Binary::Readers).
    # [provided] The file names of the libraries the runtime ships.
    # [root] The folder that stands for this computer's root, where
    #        absolute paths are looked up: <tt>/</tt> but in a test.
    def initialize(names, files:, platform:, readers:, provided: [], root: "/")
      @names = names
      @platform = platform
      @readers = readers
      @provided = provided.map(&:downcase)
      @root = root
      @files = files
      @problems = [] # : Array[String]
      @sources = {} # : Hash[String, String]
      @binaries = {} # : Hash[String, Binary]
      @unlisted = [] # : Array[[String, String, String, String?]]
      @seen = [] # : Array[String]
      @gem_binaries = names.empty? ? {} : gem_binaries
      gather unless names.empty?
    end

    # Why the app cannot carry what the project lists, one sentence each,
    # or none.
    def problems
      unlisted = @unlisted.map do |carrier, source, need, found|
        where = found ? ", which is #{found} on this computer and" : ", which this computer does not have where dyld would look, and"
        "#{carrier}, which the app carries from #{source}, needs #{need}#{where} which neither macOS nor Fledge's runtime provides. " \
          "If you may distribute it too, list it in fledge.yml as macos: { carried_libraries: [#{all_names.join(', ')}] }."
      end
      [*@problems, *unlisted, *unused]
    end

    # Where on this computer each library the app carries comes from, by
    # its file name in FOLDER.
    attr_reader :sources

    # The needs to change in each file of the app, by its path there: in
    # the gems' files and in the copies in FOLDER, each need that names a
    # carried library and does not already lead to its copy, with the
    # <tt>@loader_path</tt> path that does.
    def changes
      copies = @sources.to_h { |name, source| ["#{FOLDER}/#{name}", @binaries.fetch(source)] }
      @gem_binaries.merge(copies).to_h { |path, binary| [path, changes_of(path, binary)] }.reject { |_, list| list.empty? }
    end

    # The files the app carries or changes, by path in its folder: a copy
    # of each library in FOLDER, and each of the gems' files that
    # #changes names, changed with install_name_tool and signed ad hoc
    # with codesign, in a temporary folder. Raises Fledge::Error when a
    # tool fails, as when a file has no room for a longer name.
    def files
      copies = @sources.to_h { |name, source| ["#{FOLDER}/#{name}", File.binread(host(source))] }
      planned = changes
      Dir.mktmpdir("fledge-carried") do |work|
        planned.each_with_index.to_h do |(path, list), index|
          [path, rewritten(copies[path] || @files.fetch(path), list, File.join(work, index.to_s, File.basename(path)))]
        end
      end.then { |changed| copies.merge(changed) }
    end

    # Why dyld would not load a carried library's copy for a file of
    # +files+ (#files and the rest of the gems' files, by path in the
    # app), one sentence each, or none: the reachability check of
    # Fledge::Linkage::Dyld, judging the files as the app holds them.
    def unreached(files)
      binaries = Binary.parse(files.select { |_, content| Binary.format_of(content.byteslice(0, 8).to_s) == :macho }, readers: @readers)
      dyld = Linkage::Dyld.new(binaries)
      binaries.flat_map do |path, binary|
        carried_needs(binary).filter_map do |need|
          copy = "#{FOLDER}/#{File.basename(need)}"
          next unless @sources.key?(File.basename(need)) && dyld.resolve(path, need) != copy

          "#{path} needs #{need}, which does not lead to the copy the app carries at #{copy}."
        end
      end
    end

    # The gems' Mach-O files for the app's processor, by path.
    private def gem_binaries
      machos = @files.select { |_, content| Binary.format_of(content.byteslice(0, 8).to_s) == :macho }
      Binary.parse(machos, readers: @readers).select { |_, binary| binary.for?(@platform.cpu) }
    end

    # Finds each listed library the gems' files need, and each library
    # those need in turn, as dyld would.
    private def gather
      queue = [] # : Array[[String, String?, Array[[String?, String]], String]]
      @gem_binaries.each do |path, binary|
        chain = binary.rpaths.map { |rpath| [nil, rpath] } # : Array[[String?, String]]
        carried_needs(binary).select { |need| @names.include?(File.basename(need)) }.each { |need| queue << [need, nil, chain, path] }
      end

      until queue.empty?
        need, owner, chain, needer = queue.shift
        name = File.basename(need)
        next if @seen.include?(name)

        @seen << name
        found = locate(need, owner, chain)
        next unlisted(owner, need, found) unless @names.include?(name)
        next missing(needer, need, chain) unless found

        binary = carry(name, found) or next
        inherited = binary.rpaths.map { |rpath| [File.dirname(found), rpath] } + chain # : Array[[String?, String]]
        carried_needs(binary).each { |inner| queue << [inner, found, inherited, name] }
      end
    end

    # Reads the library at +source+, carries it as +name+ when it suits
    # the app, and returns it.
    private def carry(name, source)
      binary = Binary.parse({ source => File.binread(host(source)) }, readers: @readers).fetch(source)
      floor = @platform.macos_minimum.to_s
      if !binary.for?(@platform.cpu)
        arch = (@platform.cpu == "aarch64") ? "arm64" : @platform.cpu
        @problems << "#{name}, which the app is to carry from #{source}, has no code for #{arch}, the processor of the app's Ruby, so " \
          "the app could not load it. Carry a build of it for #{arch}."
      elsif binary.macos_minimum && Gem::Version.new(binary.macos_minimum.to_s) > Gem::Version.new(floor)
        @problems << "#{name}, which the app is to carry from #{source}, needs macOS #{binary.macos_minimum}, and apps for " \
          "#{@platform} run on macOS #{floor} and later. Carry a build of it made for macOS #{floor}, such as one compiled with " \
          "MACOSX_DEPLOYMENT_TARGET=#{floor}."
      else
        @sources[name] = source
        @binaries[source] = binary
        return binary
      end
      nil
    end

    # Notes that the library at +owner+ needs +need+, found at +found+ or
    # nowhere, which the project did not list.
    private def unlisted(owner, need, found)
      carrier = @sources.key(owner.to_s).to_s
      @unlisted << [carrier, owner.to_s, need, found]
    end

    # Notes that the gem's file at +needer+ names +need+, which the
    # project lists but this computer lacks where +chain+'s run paths
    # lead.
    private def missing(needer, need, chain)
      where = if need.start_with?("@rpath/")
        searched = chain.map(&:last).select { |rpath| rpath.start_with?("/") }.uniq
        "none of the run paths dyld would search for it on this computer (#{searched.empty? ? 'it has none' : searched.join(', ')}) " \
          "leads to a file"
      else
        "this computer has no file there"
      end
      @problems << "#{needer} needs #{need}, which fledge.yml's macos: carried_libraries has the app carry, but #{where}, so there is " \
        "nothing to copy. Install it, or build the gem so that it names the library where it is."
    end

    # One sentence for each listed library nothing needs.
    private def unused
      (@names - @seen).map do |name|
        "fledge.yml's macos: carried_libraries lists #{name}, which none of the gems' compiled files, nor the libraries the app " \
          "carries, needs. Remove it."
      end
    end

    # The project's list, with every library left out of it after.
    private def all_names
      (@names + @unlisted.map { |_, _, need, _| File.basename(need) }).uniq
    end

    # The needs of +binary+ that neither macOS nor the runtime provides.
    private def carried_needs(binary)
      binary.needed.reject do |need|
        Linkage::SYSTEM_LIBRARIES.fetch("darwin").any? { |pattern| pattern.match?(need) } || @provided.include?(File.basename(need).downcase)
      end
    end

    # Where on this computer +need+ is, as the file at +owner+ (+nil+ for
    # a gem's file, whose place here is not the app's) names it, with the
    # run paths +chain+, each with the folder of the file that gives it:
    # its real path, or +nil+.
    private def locate(need, owner, chain)
      found = candidates(need, owner, chain).find { |path| File.file?(host(path)) }
      found && real(found)
    end

    # The paths dyld would try for +need+, in its order.
    private def candidates(need, owner, chain)
      if need.start_with?("@rpath/")
        rest = need.delete_prefix("@rpath/")
        chain.filter_map { |folder, rpath| expand(rpath, folder)&.then { |dir| File.join(dir, rest) } }
      elsif need.start_with?("@loader_path/")
        owner ? [File.join(File.dirname(owner), need.delete_prefix("@loader_path/"))] : []
      else
        need.start_with?("/") ? [need] : []
      end
    end

    # The folder the run path +rpath+ names, given by the file in
    # +folder+, or +nil+ when it is not on this computer.
    private def expand(rpath, folder)
      return rpath if rpath.start_with?("/")
      return nil if folder.nil?
      return nil unless rpath == "@loader_path" || rpath.start_with?("@loader_path/")

      File.join(folder, rpath.delete_prefix("@loader_path"))
    end

    # The changes to the needs of +binary+, at +path+ in the app.
    private def changes_of(path, binary)
      carried_needs(binary).filter_map do |need|
        name = File.basename(need)
        next unless @sources.key?(name)

        relative = Pathname(FOLDER).relative_path_from(Pathname(File.dirname(path))).to_s
        wanted = (relative == ".") ? "@loader_path/#{name}" : "@loader_path/#{relative}/#{name}"
        [need, wanted] unless need == wanted # : [String, String]?
      end.uniq
    end

    # +content+ with the needs +list+ changes changed, written at +file+
    # to change and sign.
    private def rewritten(content, list, file)
      FileUtils.mkdir_p(File.dirname(file))
      File.binwrite(file, content)
      Command.run("install_name_tool", *list.flat_map { |from, to| ["-change", from, to] }, file, install: INSTALL)
      Command.run("codesign", "--force", "--sign", "-", file, install: INSTALL)
      File.binread(file)
    end

    # +path+, a path on this computer, where it is in #root.
    private def host(path)
      (@root == "/") ? path : File.join(@root, path)
    end

    # The real path of +path+, a path on this computer, as this computer
    # names it.
    private def real(path)
      found = File.realpath(host(path))
      return found if @root == "/"

      found.delete_prefix(File.realpath(@root))
    end
  end
end
