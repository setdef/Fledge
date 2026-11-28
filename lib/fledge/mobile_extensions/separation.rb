# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require "fileutils"
require "open3"
require "shellwords"
require_relative "../error"

module Fledge
  class MobileExtensions
    # Keeps to each extension linked into a phone's app the names it
    # defines that another part of the app also defines.
    #
    # On a desktop each extension is a file of its own, and a Mac's Ruby
    # binds each file's calls to its own definitions. An iOS app links
    # every extension into one executable, and an Android app links
    # Rust's and Rakefiles' into one <tt>libfledgeext.so</tt>. There two
    # gems that each define a function of one name meet: the linker keeps
    # one definition and binds both gems to it, or stops with "duplicate
    # symbol", naming source files and no gem.
    #
    # This class links each extension with the static libraries only it
    # links into one relocatable object, reads the names that object
    # defines, and makes local in it those that another linked
    # extension, a static library several share, or (on iOS) the
    # runtime's library also defines. An extension that shares no name
    # is linked as it was. Use it on one target's Reports before they
    # are linked.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 setdef <kerrick@setdef.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   reports = Fledge::MobileExtensions::Separation.new(runner:, work: "/work").call(target, reports, gems: { "clash/clash" => "clash" })
    #--
    # SPDX-SnippetEnd
    #++
    class Separation
      # A part of the app that defines names: the relocatable object of a
      # linked extension, a static library several extensions link, or the
      # runtime's library.
      class Owner < Data.define(:what, :names, :keep)
        ##
        # :attr_reader: what
        # Words that name the part in a refusal, such as <tt>"the gem
        # clash's extension clash/clash"</tt>.

        ##
        # :attr_reader: names
        # The global names it defines, weak ones left out.

        ##
        # :attr_reader: keep
        # The names that must stay global in it: an extension's Init
        # function, which the registration unit calls.
      end

      # The names each of +objects+, the Owner of each linked extension's
      # object, makes local: each it defines that another of +objects+ or
      # of +fixed+ also defines, but those it keeps (Owner#keep). +fixed+
      # are the parts whose names stay global: the static libraries
      # several extensions link and the runtime's library. Raises
      # Fledge::Error, naming the name and the parts, when two parts that
      # keep a name global define it, which no object's local copy can
      # keep apart.
      #
      # === Example
      #
      #--
      # SPDX-SnippetBegin
      # SPDX-SnippetCopyrightText: 2026 setdef <kerrick@setdef.com>
      # SPDX-License-Identifier: MIT-0
      #++
      #   a = Fledge::MobileExtensions::Separation::Owner.new(what: "a", names: %w[Init_fledge_0 clash], keep: %w[Init_fledge_0])
      #   b = Fledge::MobileExtensions::Separation::Owner.new(what: "b", names: %w[Init_fledge_1 clash], keep: %w[Init_fledge_1])
      #   Fledge::MobileExtensions::Separation.local_names([a, b], []) # => [["clash"], ["clash"]]
      #--
      # SPDX-SnippetEnd
      #++
      def self.local_names(objects, fixed)
        definers = Hash.new { |hash, name| hash[name] = [] } # : Hash[String, Array[Owner]]
        (objects + fixed).each { |owner| owner.names.uniq.each { |name| definers[name] << owner } }
        definers.each do |name, owners|
          global = owners.select { |owner| fixed.include?(owner) || owner.keep.include?(name) }
          next if owners.size < 2 || global.size < 2

          raise Error, "#{name} is defined by #{global.map(&:what).join(', and by ')}, and one app cannot link it twice: " \
            "fledge build keeps apart only the names an extension's own code defines. " \
            "Leave one of their gems out of the phone's build with the Gemfile's platforms: option"
        end
        objects.map { |owner| (owner.names.uniq.select { |name| definers.fetch(name).size > 1 } - owner.keep).sort }
      end

      # The separator, with +runner+ (Runner) to run the tools and +work+,
      # a folder for what they make.
      def initialize(runner:, work:)
        @runner = runner
        @work = work
      end

      # +reports+, the linked extensions of +target+, each with the names
      # another part also defines made local in its own archive, which
      # then holds the static libraries only it links; +gems+ names each
      # extension's gem by its feature, for a refusal. A Report with no
      # such name is returned as it was. Raises Fledge::Error when a tool
      # fails, or when two parts must keep one name global
      # (.local_names).
      #
      # === Example
      #
      #--
      # SPDX-SnippetBegin
      # SPDX-SnippetCopyrightText: 2026 setdef <kerrick@setdef.com>
      # SPDX-License-Identifier: MIT-0
      #++
      #   separation.call(target, reports, gems: { "clash/clash" => "clash" }).first.archive # => "/work/ios-arm64/separate/0/libclash.a"
      #--
      # SPDX-SnippetEnd
      #++
      def call(target, reports, gems:)
        return reports if reports.empty?

        tools = Tools.for(target, @runner)
        runtime = tools.runtime
        return reports if reports.size < 2 && runtime.nil?

        shared = shared_libraries(reports)
        folder = File.join(@work, target.name, "separate")
        FileUtils.rm_rf(folder)
        objects = reports.each_with_index.map { |report, index| prelink(tools, report, shared, File.join(folder, index.to_s), gems) }
        fixed = shared.map { |path, users| Owner.new(what: "the static library #{path}, which #{users.map { |report| gem_words(report, gems) }.join(' and ')} link", names: tools.names(path), keep: []) }
        locals = self.class.local_names(objects.map(&:first), fixed + [runtime].compact)
        reports.zip(objects, locals).map do |report, (_, object), names|
          next report if names.to_a.empty?

          archive = tools.localize(object.to_s, names.to_a, File.join(File.dirname(object.to_s), File.basename(report.archive)))
          report.with(archive:, flags: report.flags - private_libraries(report, shared))
        end
      end

      # The static libraries that more than one of +reports+ links, each
      # with the reports that link it.
      private def shared_libraries(reports)
        users = Hash.new { |hash, path| hash[path] = [] } # : Hash[String, Array[Report]]
        reports.each { |report| report.flags.select { |flag| flag.end_with?(".a") }.uniq.each { |path| users[path] << report } }
        users.select { |_, linked| linked.size > 1 }
      end

      # The static libraries +report+ alone links, of those its flags name.
      private def private_libraries(report, shared)
        report.flags.select { |flag| flag.end_with?(".a") && !shared.key?(flag) }
      end

      # The Owner of +report+'s relocatable object, which +tools+ link in
      # +folder+ from its archive and the static libraries it alone links,
      # and the object's path.
      private def prelink(tools, report, shared, folder, gems)
        FileUtils.mkdir_p(folder)
        object = File.join(folder, "extension.o")
        tools.prelink(report.init, [report.archive, *private_libraries(report, shared)], object)
        [Owner.new(what: "the extension #{report.feature} of #{gem_words(report, gems)}", names: tools.names(object), keep: [report.init]), object]
      end

      private def gem_words(report, gems)
        "the gem #{gems.fetch(report.feature, report.feature)}"
      end

      # The tools of one phone that link a relocatable object, read the
      # names an object or archive defines, and make names local.
      class Tools
        # The Tools for +target+: Apple's for an iOS slice, the NDK's for
        # an Android ABI.
        def self.for(target, runner)
          target.abi ? Android.new(target, runner) : Apple.new(target, runner)
        end

        # The tools for +target+, run by +runner+.
        def initialize(target, runner)
          @target = target
          @runner = runner
        end

        # The runtime's static library as an Owner, whose names an
        # extension's must not take; +nil+ where the runtime is a shared
        # library that keeps its libraries' names to itself.
        def runtime
          nil
        end

        # Links +inputs+, an extension's archive and its static libraries,
        # into the relocatable object +out+, with the members that the Init
        # function +init+ reaches.
        def prelink(init, inputs, out)
          @runner.call(@runner.clean_env, *compiler, "-r", "-nostdlib", *prelink_flags(init), "-o", out, *inputs,
            what: "linking #{File.basename(inputs.first.to_s)} into one object for #{@target.name}")
        end

        # Makes +names+ local in the object +object+, and archives the result
        # as +archive+, which it returns.
        def localize(object, names, archive)
          edited = "#{object}.local.o"
          list = "#{object}.local"
          File.write(list, names.map { |name| "#{symbol(name)}\n" }.join)
          @runner.call(@runner.clean_env, *localizer(list, object, edited), what: "keeping #{names.join(', ')} to #{File.basename(archive)} for #{@target.name}")
          FileUtils.rm_f(archive)
          @runner.call(@runner.clean_env, *archiver, archive, edited, what: "archiving #{File.basename(archive)} for #{@target.name}")
          archive
        end

        # The global names +path+, an object or archive, defines, weak ones
        # left out; each phone's tools read them.
        def names(path)
          raise NotImplementedError, "#{self.class} reads no names in #{path}"
        end

        # The linker flags of #prelink that keep the Init function +init+
        # and what it reaches.
        private def prelink_flags(init)
          raise NotImplementedError, "#{self.class} has no flags for #{init}"
        end

        # The command that writes +object+ with the names in the file +list+
        # made local, as +edited+.
        private def localizer(list, object, edited)
          raise NotImplementedError, "#{self.class} cannot edit #{object} by #{list} into #{edited}"
        end

        # The command, but its operands, that archives an object.
        private def archiver
          raise NotImplementedError, "#{self.class} has no archiver"
        end

        # The compiler that links, as a command.
        private def compiler
          @target.environment.fetch("FLEDGE_CC").shellsplit
        end

        # The symbol of +name+ in an object file.
        private def symbol(name)
          name
        end

        # Runs +command+ and returns its output; raises Fledge::Error when it
        # fails.
        private def capture(*command)
          output, status = Open3.capture2e(*command)
          raise Error, "#{File.basename(command.first.to_s)} could not read #{command.last}:\n#{output}" unless status.success?

          output
        rescue SystemCallError => e
          raise Error, "fledge build needs #{File.basename(command.first.to_s)}, which it could not run (#{e.message})"
        end

        # Xcode's tools: <tt>ld -r</tt> keeping private externs, which is
        # what a name hidden by <tt>-fvisibility=hidden</tt> is in an
        # object, <tt>nm -m</tt>, <tt>nmedit -R</tt>, and
        # <tt>libtool -static</tt>.
        class Apple < Tools
          # The names the runtime's Ruby defines for the slice: those its
          # FledgeRuby.framework exports, or, in a runtime whose Ruby is
          # static, as 0.17.0's, those its libfledgeruby.a defines.
          def runtime
            library = [File.join(@target.libdir, "FledgeRuby.framework", "FledgeRuby"), File.join(@target.libdir, "libfledgeruby.a")]
              .find { |path| File.file?(path) }
            Owner.new(what: "the runtime's library #{File.basename(library)}", names: names(library), keep: []) if library
          end

          # The global names +path+ defines, private externs among them,
          # weak ones left out, without the leading underscore, read from
          # its Mach-O symbol table, which the linker binds by. Xcode's nm
          # is LLVM's, which reads an object's names from the LLVM bitcode
          # in its <tt>__LLVM,__bitcode</tt> section, where it has one,
          # and stops at bitcode from a newer LLVM than its own; Rust's
          # standard library carries such bitcode, which some of Xcode's
          # <tt>ld -r</tt> keep. <tt>--no-llvm-bc</tt> reads no bitcode.
          def names(path)
            capture("xcrun", "nm", "-m", "--no-llvm-bc", path).lines.filter_map do |line|
              line[/\A\h+ \([^)]*\) (?:private )?external _(\S+)\s*\z/, 1]
            end
          end

          private def prelink_flags(init)
            ["-Wl,-keep_private_externs", "-Wl,-u,_#{init}"]
          end

          private def symbol(name)
            "_#{name}"
          end

          private def localizer(list, object, edited)
            ["xcrun", "nmedit", "-R", list, object, "-o", edited]
          end

          private def archiver
            %w[xcrun libtool -static -no_warning_for_no_symbols -o]
          end
        end

        # The NDK's tools: <tt>ld.lld -r</tt>, <tt>llvm-nm</tt>,
        # <tt>llvm-objcopy --localize-symbols</tt>, and <tt>llvm-ar</tt>.
        class Android < Tools
          # The global names +path+ defines, weak ones left out, read from
          # its ELF symbol table, as Apple#names reads them. LLVM's nm
          # reads an ELF object's names from bitcode only in the
          # <tt>.llvm.lto</tt> section of a fat LTO object, not from the
          # <tt>.llvmbc</tt> Rust embeds; <tt>--no-llvm-bc</tt> keeps it
          # off the first too.
          def names(path)
            capture(tool("llvm-nm"), "--defined-only", "--extern-only", "--no-llvm-bc", "--format=posix", path).lines.filter_map do |line|
              name, type = line.split
              name if type&.match?(/\A[A-Z]\z/) && !%w[U V W].include?(type)
            end
          end

          private def prelink_flags(init)
            ["-Wl,-d", "-Wl,-u,#{init}"]
          end

          private def localizer(list, object, edited)
            [tool("llvm-objcopy"), "--localize-symbols=#{list}", object, edited]
          end

          private def archiver
            [tool("llvm-ar"), "rcs"]
          end

          private def tool(name)
            File.join(File.dirname(@target.environment.fetch("FLEDGE_AR")), name)
          end
        end
      end
    end
  end
end
