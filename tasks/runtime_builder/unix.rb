# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require "fileutils"
require_relative "recipe"

class RuntimeBuilder
  # macOS and Linux: rv-ruby's Ruby, whose static libruby the launcher
  # links, so each builds only on its own platform. The runtime is the
  # launcher with bin/, lib/ruby, the static libruby, and
  # libexec/cert.pem beside it.
  class Unix < Recipe
    def build(stage)
      @prefix = unpack_ruby
      copy_ruby(stage)
      compile(File.join(stage, "launcher"), launcher_sources, "$ORIGIN/lib")
      compile(File.join(stage, "bin", "ruby"), ruby_sources, "$ORIGIN/../lib")
      finish(stage)
    end

    # Ruby's own main.c, which chooses its locale as the launcher does,
    # and hands an app's own program back to its launcher (ADR 087 and ADR 096).
    private def ruby_sources
      %w[ruby_main.c relaunch.c config.c locale.c].map { |file| File.join(LAUNCHER, file) } << File.join(LAUNCHER, os_file)
    end

    private def launcher_sources
      %w[unix.c scrub.c config.c bundler.c locale.c].map { |file| File.join(LAUNCHER, file) } << File.join(LAUNCHER, os_file)
    end

    # Runs gcc's static analyzer over each of +sources+, warnings as
    # errors, as clang's checks every other platform's launcher.
    private def analyze_with_gcc(cc, sources)
      sources.each do |source|
        @builder.run(cc, "-fanalyzer", "-Werror", "-std=gnu11", *includes, "-c", source, "-o", File::NULL)
      end
    end

    private def includes
      headers = Dir.glob(File.join(@prefix, "include", "ruby-*")).first or raise "#{@prefix} has no Ruby headers"
      arch = Dir.glob(File.join(headers, "*")).find { |dir| File.directory?(dir) && File.basename(dir) != "ruby" }
      ["-isystem", arch.to_s, "-isystem", headers, "-I", LAUNCHER]
    end

    private def unpack_ruby
      pin = @builder.sources.fetch("ruby").fetch("platforms").fetch(@builder.platform.name)
      tarball = @builder.fetch(pin.fetch("url"), pin.fetch("sha256"))
      unpacked = File.join(@build_dir, "rv-ruby")
      FileUtils.mkdir_p(unpacked)
      @builder.run("tar", "-xzf", tarball, "-C", unpacked)
      prefixes = Dir.glob(File.join(unpacked, "*", @builder.sources.fetch("ruby").fetch("version")))
      raise "#{tarball} does not hold one Ruby prefix: #{prefixes}" unless prefixes.size == 1

      prefixes.first.to_s
    end

    # Copies rv-ruby's bin/ (whose ruby compile then replaces with one
    # built from the same libruby as the launcher; the rest are the gems'
    # executables), lib/ruby, Ruby's headers (include/, which require
    # "mkmf" looks for; Pruning.prune), the static libruby, and the CA
    # bundle. mkmf links the test program of every have_func,
    # have_library, and try_link against $(LIBRUBYARG), which for a static
    # Ruby is LIBRUBYARG_STATIC, -lruby.4.1-static from $(libdir)
    # (mkmf.rb, link_config, lines 541 to 553, at Ruby 4.1.0-preview1), so
    # without it an app's own running mkmf raises "The compiler failed to
    # generate an executable file". No other static library comes along:
    # rv-ruby's lib/libcrypt.a is libxcrypt, which is LGPL, and the linker
    # finds the system's -lcrypt instead.
    private def copy_ruby(stage)
      FileUtils.mkdir_p(File.join(stage, "lib"))
      FileUtils.cp_r(File.join(@prefix, "bin"), File.join(stage, "bin"))
      FileUtils.rm_f(File.join(stage, "bin", "ruby"))
      FileUtils.cp_r(File.join(@prefix, "lib", "ruby"), File.join(stage, "lib", "ruby"))
      FileUtils.cp(Dir.glob(File.join(@prefix, "lib", "libruby*-static.a")), File.join(stage, "lib"))
      FileUtils.cp_r(File.join(@prefix, "include"), File.join(stage, "include"))
      FileUtils.chmod_R("u+w", [File.join(stage, "lib"), File.join(stage, "bin"), File.join(stage, "include")])
      removed = Pruning.prune(File.join(stage, "lib", "ruby"), @builder.bundled_gems)
      Pruning.prune_bin(File.join(stage, "bin"), removed)
      @builder.install_rubygems_defaults(File.join(stage, "lib", "ruby"))
      FileUtils.mkdir_p(File.join(stage, "libexec"))
      FileUtils.cp(File.join(@prefix, "libexec", "cert.pem"), File.join(stage, "libexec", "cert.pem"))
    end
  end
end
