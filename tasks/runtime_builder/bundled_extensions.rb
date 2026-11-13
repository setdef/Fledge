# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require "fileutils"
require_relative "../../lib/fledge/mobile_extensions/stub"

class RuntimeBuilder
  # How a mobile runtime keeps Ruby's bundled gems with C extensions
  # (bigdecimal, debug, fiddle, nkf, prism, racc, rbs, and syslog) as
  # gems while linking their extensions into Ruby (ADR 058),
  # each keeping every symbol but its Init function to itself (ADR 067).
  #
  # A mobile Ruby loads no extension from a file: both runtimes link
  # every extension into the one library an app carries (ADR 011), and
  # iOS loads no loose library. Ruby's build links its own extensions in that way
  # (--with-static-linked-ext), registering each in extinit.c, but never a
  # bundled gem's: template/configure-ext.mk.tmpl builds .bundle/gems with
  # --no-extstatic, and ext/extmk.rb (line 661 at 4.1.0-preview1) leaves a
  # gem's extension out of extinit.c. The mobile spike moved those gems
  # into the standard library, so they loaded but were no longer gems
  # (Gem.loaded_specs["bigdecimal"] was nil), which an app that names them
  # in its Gemfile would notice.
  #
  # Instead, each gem's extension sources are copied among Ruby's own, to
  # ext/gems/NAME, where extmk links them in and registers each under the
  # feature its gem requires (bigdecimal.so, racc/cparse.so); configure
  # leaves the gem's own build out (--with-out-ext); and once Ruby is
  # built, each gem's extension is marked built, as its own build would
  # have marked it, so tool/rbinstall.rb installs the gem, specification
  # and all. RubyGems then activates the gem as it would on a desktop, and
  # its require of the extension finds the one Ruby links in (load.c,
  # search_required, which looks among statically linked extensions for a
  # feature no file provides). A desktop finds a gem's extension only in
  # the gem's own folders, once RubyGems has put them on $LOAD_PATH, so
  # load.c is edited to find a gem's linked extension only then too
  # (RubySource.load_c, given features): else a plain require "bigdecimal"
  # finds the linked bigdecimal.so before RubyGems activates the gem, and
  # the gem's lib/bigdecimal.rb never loads.
  #
  # Ruby finds a gem's extension by its Init function alone. Linked
  # statically, every other symbol the extension defines is global too,
  # and two copies of one library collide: prism's extension compiles
  # its own libprism, and libruby holds another, from other sources
  # (pm_parse, and every pm_ symbol). So each gem's extension is linked
  # into one relocatable object in which only its Init function stays
  # global, as only it is looked up in its shared object on a desktop
  # (ADR 067; relocate).
  module BundledExtensions
    # The Makefile rules each copied gem's extension gets in its depend
    # file, which mkmf appends to the Makefile it writes (lib/mkmf.rb,
    # lines 2732 to 2746 at 4.1.0-preview1): the static library mkmf's
    # rule archives (lines 2693 to 2699) holds one object, made by the
    # platform's %<recipe>s from the extension's objects, rather than the
    # objects themselves. The library's prerequisites keep the objects,
    # since make expands a rule's prerequisites as it reads it, and its
    # recipe only when it runs. FLEDGE_INIT is the extension's Init
    # function, as extmk names it for its feature with -DInit_BASE=
    # (ext/extmk.rb, line 565): Init_racc_cparse for racc/cparse. The
    # extension is compiled with -fno-common, as its shared object is on
    # a Mac (CCDLFLAGS, which mkmf leaves out of a static build,
    # lib/mkmf.rb line 2171) and as GCC and Clang compile by default
    # elsewhere: Xcode's clang makes a global without an initializer
    # (VALUE rb_cPrism;) a common symbol, which no tool can make local and
    # the linker merges with libruby's of the same name.
    RELOCATABLE = <<~MAKE
      CFLAGS += -fno-common
      CXXFLAGS += -fno-common
      FLEDGE_OBJS := $(OBJS)
      FLEDGE_INIT := Init_$(subst /,_,$(patsubst /%%,%%,$(target_prefix)/$(TARGET)))
      $(STATIC_LIB): OBJS = $(TARGET)-relocatable.o
      $(STATIC_LIB): $(TARGET)-relocatable.o
      $(TARGET)-relocatable.o: $(FLEDGE_OBJS)
      \t$(ECHO) linking relocatable object $(@)
      %<recipe>s
    MAKE

    # What mkmf writes when an extension has no depend file, and leaves
    # out when it has one: its objects depend on its headers and Ruby's.
    HEADERS = "$(OBJS): $(HDRS) $(ruby_headers)\n"

    # The names of Ruby's bundled gems in the source tree +source+ whose
    # files include a C extension, as configure's --with-out-ext must name
    # them to leave out their builds as gems: extmk matches a gem by the
    # name of its folder in .bundle/gems, NAME-VERSION, unless the folder
    # holds a NAME.gemspec as well as NAME-VERSION.gemspec, when it
    # matches NAME (ext/extmk.rb, lines 523 to 527 at 4.1.0-preview1).
    def self.without(source)
      gems(source).keys.sort.flat_map { |name| [name, "#{name}-*"] }
    end

    # Copies the extension of every bundled gem in +source+ with one, but
    # win32ole (Windows' only) and those named in +omit+, into
    # +source+/ext/gems/NAME: its ext/ folder, without tests, and the
    # folders an extconf.rb reads beside it: lib/ (debug's reads its
    # version there), and include/ and src/ (rbs's). extmk installs only
    # an extension's own lib/ folder, so none of them is installed twice.
    # Each extension is linked into one relocatable object by the
    # commands +recipe+ names (relocate). Returns each copied gem's full
    # name, by name.
    def self.copy(source, omit:, recipe:)
      gems(source).reject { |name, _| name == "win32ole" || omit.include?(name) }.sort.to_h.each do |name, full|
        %w[ext include src lib].each do |folder|
          from = File.join(source, ".bundle", "gems", full, folder)
          next unless File.directory?(from)

          Dir.glob("**/*", base: from).reject { |path| path.split("/").include?("test") }.each do |path|
            next unless File.file?(File.join(from, path))

            target = File.join(source, "ext", "gems", name, folder, path)
            FileUtils.mkdir_p(File.dirname(target))
            FileUtils.cp(File.join(from, path), target)
          end
        end
        relocate(File.join(source, "ext", "gems", name), recipe:)
      end
    end

    # Gives each extension in the copied gem +folder+ (each folder with
    # an extconf.rb, but its tests) the rules RELOCATABLE holds, after the
    # gem's own depend file or, without one, the line mkmf would have
    # written. +recipe+ is the platform's shell commands that link
    # $(FLEDGE_OBJS) with -r into $@ and leave no symbol but
    # $(FLEDGE_INIT) global (IOS#relocatable, Android#relocatable).
    def self.relocate(folder, recipe:)
      rules = format(RELOCATABLE, recipe: recipe.map { |command| "\t$(Q) #{command}" }.join("\n"))
      Dir.glob("**/extconf.rb", base: folder).reject { |path| path.split("/").include?("test") }.each do |path|
        depend = File.join(folder, File.dirname(path), "depend")
        own = File.file?(depend) ? File.read(depend) : HEADERS
        File.write(depend, "#{own.chomp}\n\n#{rules}")
      end
    end

    # The feature each extension of the copied +gems+ (full names, by
    # name) in +source+ is registered as, with .so as extmk's extinit.c
    # gives it (template/extinit.c.tmpl), mapped to its gem's full name:
    # what its extconf.rb names its Makefile's target for
    # (create_makefile("racc/cparse"), which extmk registers as
    # racc/cparse.so). Raises for an extconf.rb that names none, as a new
    # gem's might.
    def self.features(source, gems)
      gems.sort.to_h.flat_map do |name, full|
        folder = File.join(source, "ext", "gems", name)
        Dir.glob("**/extconf.rb", base: folder).reject { |path| path.split("/").include?("test") }.sort.map do |path|
          target = File.read(File.join(folder, path))[/^\s*create_makefile\s*\(?\s*(["'])([^"']+)\1/, 2]
          raise "#{full}'s #{path} names no create_makefile target" unless target

          ["#{target}.so", full]
        end
      end.to_h
    end

    # Marks the extension of each of +gems+ (full names, by name) built,
    # in the build folder +build+, where tool/rbinstall.rb looks before it
    # installs a bundled gem with an extension: .bundle/extensions/
    # +platform+/+api+/FULL_NAME/gem.build_complete, the file each gem's
    # own build writes.
    def self.mark_built(build, gems, platform:, api:)
      gems.each_value do |full|
        folder = File.join(build, ".bundle", "extensions", platform, api, full)
        FileUtils.mkdir_p(folder)
        FileUtils.touch(File.join(folder, "gem.build_complete"))
      end
    end

    # Writes, in each of +gems+' (full names, by name) extension folders
    # in the build folder +build+, which tool/rbinstall.rb copies whole
    # into the gem's extension folder (install_recursive, line 1309 at
    # 4.1.0-preview1), a Ruby file for each extension that requires the
    # one Ruby links in (Fledge::MobileExtensions::Stub), at the path a
    # desktop has its file: racc/cparse.rb where a desktop has
    # racc/cparse.so. RubyGems' require finds a gem by a file of its
    # extension folder (Gem::BasicSpecification#have_file?,
    # lib/rubygems/basic_specification.rb lines 376 to 388), so a
    # require "racc/cparse" before racc is active activates racc, as on a
    # desktop, and then finds this file, whose require of racc/cparse.so
    # the gate (RubySource.load_c) lets through once the gem is active. A
    # gem whose lib/ has a Ruby file of the extension's name, as
    # bigdecimal's lib/bigdecimal.rb, gets none: the extension folder
    # comes first on $LOAD_PATH, and Ruby tries .rb in every folder before
    # an extension's (rb_find_file_ext, file.c lines 8107 to 8119), so the
    # file would hide the gem's own. Each such gem's require path at
    # 4.1.0-preview1 is lib alone.
    def self.write_stubs(build, gems, platform:, api:)
      features(build, gems).each do |name, full|
        feature = name.delete_suffix(".so")
        next if File.exist?(File.join(build, ".bundle", "gems", full, "lib", "#{feature}.rb"))

        path = File.join(build, ".bundle", "extensions", platform, api, full, "#{feature}.rb")
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, Fledge::MobileExtensions::Stub.source(feature))
      end
    end

    # Raises unless each of +gems+ was installed into the gem folder
    # +gems_dir+ as a gem: with its specification, and its extension
    # marked built, without which RubyGems ignores the gem ("its
    # extensions are not built").
    def self.check_installed(gems_dir, gems, platform:, api:)
      gems.each_value do |full|
        installed = [
          File.join(gems_dir, "specifications", "#{full}.gemspec"),
          File.join(gems_dir, "extensions", platform, api, full, "gem.build_complete"),
        ].all? { |path| File.file?(path) }
        raise "#{full} was not installed as a gem with its extension marked built" unless installed
      end
    end

    # Each bundled gem in +source+ with a C extension, its full name by
    # name.
    private_class_method def self.gems(source)
      Dir.glob(".bundle/gems/*/ext/**/extconf.rb", base: source).reject { |path| path.split("/").include?("test") }.to_h do |path|
        full = path.split("/").fetch(2)
        [full[/\A(.+)-[^-]+\z/, 1].to_s, full]
      end
    end
  end
end
