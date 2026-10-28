# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "fileutils"
require_relative "recipe"

class RuntimeBuilder
  # macOS and Linux: rv-ruby's Ruby, whose static libruby the launcher
  # links, so each builds only on its own platform. The runtime is the
  # launcher with bin/, lib/ruby, and libexec/cert.pem beside it.
  class Unix < Recipe
    def build(stage)
      @prefix = @tree = unpack_ruby
      copy_ruby(stage)
      compile(File.join(stage, "launcher"), launcher_sources, "$ORIGIN/lib")
      compile(File.join(stage, "bin", "ruby"), [File.join(LAUNCHER, "ruby_main.c")], "$ORIGIN/../lib")
      finish(stage)
    end

    private def launcher_sources
      %w[unix.c scrub.c config.c bundler.c locale.c].map { |file| File.join(LAUNCHER, file) } << File.join(LAUNCHER, os_file)
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
    # executables), lib/ruby, and the CA bundle.
    private def copy_ruby(stage)
      FileUtils.mkdir_p(File.join(stage, "lib"))
      FileUtils.cp_r(File.join(@prefix, "bin"), File.join(stage, "bin"))
      FileUtils.rm_f(File.join(stage, "bin", "ruby"))
      FileUtils.cp_r(File.join(@prefix, "lib", "ruby"), File.join(stage, "lib", "ruby"))
      FileUtils.chmod_R("u+w", [File.join(stage, "lib"), File.join(stage, "bin")])
      removed = Pruning.prune(File.join(stage, "lib", "ruby"), @builder.bundled_gems)
      Pruning.prune_bin(File.join(stage, "bin"), removed)
      @builder.install_rubygems_defaults(File.join(stage, "lib", "ruby"))
      FileUtils.mkdir_p(File.join(stage, "libexec"))
      FileUtils.cp(File.join(@prefix, "libexec", "cert.pem"), File.join(stage, "libexec", "cert.pem"))
    end
  end
end
