# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require "fileutils"
require_relative "unix"

class RuntimeBuilder
  # macOS: link libruby whole into the launcher, which exports its
  # symbols to extensions by default; ad hoc sign it, since Apple Silicon
  # runs only signed code.
  class Darwin < Unix
    # Compiles +sources+ with libruby into the program +output+, which
    # needs no RPATH: it links only libraries macOS ships.
    def compile(output, sources, _rpath)
      cc = ENV.fetch("CC", "clang")
      sources.each do |source|
        report = File.join(@build_dir, "#{File.basename(source, '.c')}.plist")
        @builder.run(cc, "--analyze", "-Xclang", "-analyzer-werror", "-std=gnu11", *includes, source, "-o", report)
      end
      static = Dir.glob(File.join(@prefix, "lib", "libruby.*-static.a")).first or raise "#{@prefix} has no static libruby"
      FileUtils.mkdir_p(File.dirname(output))
      minimum = "-mmacosx-version-min=#{Fledge::Platform::MACOS_MINIMUM}"
      objects = sources.map do |source|
        object = File.join(@build_dir, "objects", File.basename(output), "#{File.basename(source, '.c')}.o")
        FileUtils.mkdir_p(File.dirname(object))
        @builder.run(cc, "-std=gnu11", "-O2", *WARNINGS, minimum, *Hardening::COMPILE.fetch(:darwin), *includes, "-c", source, "-o", object)
        object
      end
      (@objects ||= []) << objects
      @builder.run(cc, minimum, *objects, *Hardening::LINK.fetch(:darwin),
        "-Wl,-force_load,#{static}", *frameworks(sources), "-ldl", "-lobjc", "-lpthread", "-o", output)
      @builder.run("strip", "-x", output)
      @builder.run("codesign", "--sign", "-", "--force", output)
      check_libraries(output)
    end

    def finish(_stage); end

    def hardening_kind
      :darwin
    end

    # The object files of the launcher and of bin/ruby: libruby, which
    # each program holds whole, brings its own canary and checked calls,
    # so Fledge's own code is read before it is linked.
    def objects
      @objects || []
    end

    private def os_file
      "darwin.c"
    end

    # documents.c, which takes the launch's Open Documents Apple event
    # (doc/contributors/design/launcher.md, "Documents opened on macOS"),
    # is the launcher's alone: bin/ruby is never started by Launch
    # Services.
    private def launcher_os_files
      ["documents.c"]
    end

    # CoreFoundation for every program; the Apple Event Manager
    # (CoreServices) and Carbon's event queue (HIToolbox) for the one
    # that compiles documents.c.
    private def frameworks(sources)
      names = ["CoreFoundation"]
      names += %w[CoreServices Carbon] if sources.any? { |source| File.basename(source) == "documents.c" }
      names.flat_map { |name| ["-framework", name] }
    end

    private def check_libraries(output)
      libraries = @builder.capture("otool", "-L", output).lines.drop(1).map { |line| line.strip.split.first.to_s }
      foreign = libraries.reject { |library| library.start_with?("/usr/lib/", "/System/Library/") }
      raise "the launcher links libraries macOS does not ship: #{foreign.join(', ')}" unless foreign.empty?
    end
  end
end
