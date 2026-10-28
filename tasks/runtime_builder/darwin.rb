# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
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
      static = File.join(@prefix, "lib", "libruby.4.0-static.a")
      FileUtils.mkdir_p(File.dirname(output))
      @builder.run(cc, "-std=gnu11", "-O2", *WARNINGS, "-mmacosx-version-min=14.0", *includes, *sources,
        "-Wl,-force_load,#{static}", "-framework", "CoreFoundation", "-ldl", "-lobjc", "-lpthread", "-o", output)
      @builder.run("strip", "-x", output)
      @builder.run("codesign", "--sign", "-", "--force", output)
      check_libraries(output)
    end

    def finish(_stage); end

    private def os_file
      "darwin.c"
    end

    private def check_libraries(output)
      libraries = @builder.capture("otool", "-L", output).lines.drop(1).map { |line| line.strip.split.first.to_s }
      foreign = libraries.reject { |library| library.start_with?("/usr/lib/", "/System/Library/") }
      raise "the launcher links libraries macOS does not ship: #{foreign.join(', ')}" unless foreign.empty?
    end
  end
end
