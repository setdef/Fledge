# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "fileutils"

class RuntimeBuilder
  # How a mobile runtime keeps Ruby's bundled gems with C extensions
  # (bigdecimal, debug, nkf, racc, rbs, syslog, and on Android fiddle) as
  # gems while linking their extensions into Ruby (ADR 011, section 4).
  #
  # A mobile Ruby loads no extension from a file: iOS forbids it, and
  # both runtimes link every extension into the one library an app
  # carries. Ruby's build links its own extensions in that way
  # (--with-static-linked-ext), registering each in extinit.c, but never a
  # bundled gem's: template/configure-ext.mk.tmpl builds .bundle/gems with
  # --no-extstatic, and ext/extmk.rb (line 656 at 4.0.9) leaves a gem's
  # extension out of extinit.c. The mobile spike moved those gems into
  # the standard library, so they loaded but were no longer gems
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
  # feature no file provides).
  module BundledExtensions
    # The names of Ruby's bundled gems in the source tree +source+ whose
    # files include a C extension, as configure's --with-out-ext must name
    # them to leave out their builds as gems: extmk matches a gem by the
    # name of its folder in .bundle/gems, NAME-VERSION, unless the folder
    # holds a NAME.gemspec as well as NAME-VERSION.gemspec, when it
    # matches NAME (ext/extmk.rb, lines 519 to 523 at 4.0.9).
    def self.without(source)
      gems(source).keys.sort.flat_map { |name| [name, "#{name}-*"] }
    end

    # Copies the extension of every bundled gem in +source+ with one, but
    # win32ole (Windows' only) and those named in +omit+, into
    # +source+/ext/gems/NAME: its ext/ folder, without tests, and the
    # folders an extconf.rb reads beside it: lib/ (debug's reads its
    # version there), and include/ and src/ (rbs's). extmk installs only
    # an extension's own lib/ folder, so none of them is installed twice.
    # Returns each copied gem's full name, by name.
    def self.copy(source, omit:)
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
      end
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
