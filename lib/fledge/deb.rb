# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "fileutils"
require "rubygems"
require "tmpdir"
require_relative "binary"
require_relative "command"
require_relative "desktop_entry"
require_relative "error"
require_relative "platform"

module Fledge
  # A Linux app as a package Debian and Ubuntu install with +apt+ and
  # remove with +apt remove+: a <tt>.deb</tt>.
  #
  # Briefcase makes one by writing the package's <tt>DEBIAN/control</tt>
  # and running <tt>dpkg-deb --build --root-owner-group</tt>, and so does
  # this module (ADR 021); Tauri's bundler writes the archive itself, which
  # Fledge does not (ADR 010). It lays the built app's folder out as
  # +dpkg-deb+ packs it: the folder in <tt>/usr/lib/PACKAGE</tt> (Debian
  # Policy 9.1.1 lets a package keep a mixture of files in a
  # subdirectory of +/usr/lib+), its desktop entry, with the program's
  # installed path as its +Exec+, in <tt>/usr/share/applications</tt>,
  # and its icons in <tt>/usr/share/icons</tt>, where desktops look; and
  # a +control+ file from what <tt>fledge.yml</tt> says. Removing the
  # package removes exactly those files.
  #
  # Use it through Fledge::Installers.
  #
  # === Example
  #
  #--
  # SPDX-SnippetBegin
  # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
  # SPDX-License-Identifier: MIT-0
  #++
  #   Fledge::Deb.write(identity:, folder: "dist/My App-x86_64-linux", platform:, to: "dist/My App-x86_64-linux.deb")
  #   # => "dist/My App-x86_64-linux.deb"
  #--
  # SPDX-SnippetEnd
  #++
  module Deb
    # Debian's name for each platform's processor.
    ARCHITECTURES = { "x86_64-linux" => "amd64", "aarch64-linux" => "arm64" }.freeze

    # What to do when this computer has no dpkg-deb.
    INSTALL = "Install dpkg, which has it, such as with sudo apt install dpkg (Debian and Ubuntu have it already) or sudo dnf install dpkg."

    # What to do when this computer has no dpkg-shlibdeps.
    SHLIBDEPS = "Install dpkg-dev, which has it, such as with sudo apt install dpkg-dev (build-essential brings it)."

    # Writes the <tt>.deb</tt> of the app whose Fledge::Identity is
    # +identity+ and whose built folder is +folder+, for +platform+, to
    # +to+, and returns +to+. +system_libraries+ are the libraries the
    # app's gems load from the distribution (Config::Linux), whose
    # packages the <tt>.deb</tt> depends on. Raises Fledge::Error when
    # this computer has no dpkg-deb, or no dpkg-shlibdeps when it needs
    # one, or either fails.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   Fledge::Deb.write(identity:, folder: "dist/My App-x86_64-linux", platform:, to: "dist/My App-x86_64-linux.deb")
    #--
    # SPDX-SnippetEnd
    #++
    def self.write(identity:, folder:, platform:, to:, system_libraries: [])
      package = package_name(identity)
      Dir.mktmpdir("fledge-deb") do |work|
        root = File.join(work, "root")
        lay_out(root, folder, identity, package)
        control = File.join(root, "DEBIAN")
        FileUtils.mkdir_p(control, mode: 0o755)
        depends = ["libc6 (>= #{Platform::GLIBC_MINIMUM})", *dependencies(work, root, system_libraries)]
        File.write(File.join(control, "control"), control_file(identity, package, ARCHITECTURES.fetch(platform.name), installed_size(root), depends))
        Command.run("dpkg-deb", "--build", "--root-owner-group", root, to, install: INSTALL)
      end
      to
    end

    # The package's name: the app's identifier in lower case, which Debian
    # Policy 5.6.7 allows (letters, digits, plus, minus, and full stops)
    # and which no distribution's package shares with an app's by chance.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   Fledge::Deb.package_name(identity) # => "com.example.myapp"
    #--
    # SPDX-SnippetEnd
    #++
    def self.package_name(identity)
      identity.identifier.to_s.downcase
    end

    # +version+ as Debian Policy 5.6.12 spells an upstream version: a
    # RubyGems pre-release's first letter-led part follows a tilde, which
    # sorts before the release, as <tt>1.2.3.pre.4</tt> sorts before
    # <tt>1.2.3</tt>.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   Fledge::Deb.version("1.2.3.pre.4") # => "1.2.3~pre.4"
    #--
    # SPDX-SnippetEnd
    #++
    def self.version(version)
      Gem::Version.new(version).to_s.sub(/\.(?=[A-Za-z])/, "~")
    end

    # The tree +dpkg-deb+ packs, without its +control+ file.
    private_class_method def self.lay_out(root, folder, identity, package)
      app = File.join(root, "usr", "lib", package)
      FileUtils.mkdir_p(File.dirname(app), mode: 0o755)
      FileUtils.cp_r(folder, app, preserve: true)
      FileUtils.rm_f(File.join(app, "#{identity.identifier}.desktop"))

      applications = File.join(root, "usr", "share", "applications")
      FileUtils.mkdir_p(applications, mode: 0o755)
      entry = DesktopEntry.new(identity).text(program: File.join("/usr/lib", package, identity.name))
      File.write(File.join(applications, "#{identity.identifier}.desktop"), entry)

      share = File.join(app, "share")
      Dir.children(share).each { |child| FileUtils.mv(File.join(share, child), File.join(root, "usr", "share", child)) } if File.directory?(share)
      FileUtils.rmdir(share) if File.directory?(share)
    end

    # The +control+ file: Debian Policy 5.3's mandatory fields and
    # priority and section, with the app's name for its synopsis and its
    # publisher, or its name, for its maintainer, since <tt>fledge.yml</tt>
    # has neither a description nor an address. +Depends+ is +depends+:
    # the glibc the runtime needs (Platform::GLIBC_MINIMUM), so apt
    # refuses an older Debian or Ubuntu, saying why, and the packages of
    # the libraries the gems load from the distribution.
    private_class_method def self.control_file(identity, package, architecture, size, depends)
      <<~CONTROL
        Package: #{package}
        Version: #{version(identity.version)}
        Architecture: #{architecture}
        Maintainer: #{line(identity.publisher || identity.name)}
        Installed-Size: #{size}
        Depends: #{depends.join(', ')}
        Section: misc
        Priority: optional
        Description: #{line(identity.name)}
      CONTROL
    end

    # The packages that provide +libraries+, as dpkg-shlibdeps finds
    # them for the compiled files in the tree at +root+ that need one:
    # each with the oldest version whose symbols the files use, from the
    # package's own symbols or shlibs file (Debian Policy 8.6), and any
    # other package those files need, but not glibc's, which +Depends+
    # names at the runtime's floor already. None when +libraries+ is
    # empty. dpkg-shlibdeps reads <tt>debian/control</tt> in the folder
    # it runs in, so +work+ gets an empty one; the tree's
    # <tt>DEBIAN</tt> folder tells it the files are a package's.
    private_class_method def self.dependencies(work, root, libraries)
      return [] if libraries.empty?

      files = Dir.glob("usr/lib/**/*", base: root).map { |path| File.join(root, path) }
      binaries = Binary.read(files, readers: Binary::Readers.local("linux")).select { |_, binary| binary.format == :elf }
      needing = binaries.select { |_, binary| binary.needed.intersect?(libraries) }.keys
      return [] if needing.empty?

      FileUtils.mkdir_p(File.join(work, "debian"))
      File.write(File.join(work, "debian", "control"), "")
      folders = binaries.keys.map { |path| "-l#{File.dirname(path)}" }.uniq
      output = Command.read("dpkg-shlibdeps", "-O", "-xlibc6", *folders, *needing.map { |path| "-e#{path}" }, chdir: work, install: SHLIBDEPS)
      output[/^shlibs:Depends=(.*)$/, 1].to_s.split(",").map(&:strip).reject(&:empty?)
    end

    # +text+ on one line, as a control field holds it.
    private_class_method def self.line(text)
      text.gsub(/\s+/, " ").strip
    end

    # The size of the installed files in KiB, rounded up, as Policy 5.6.20
    # asks, so apt can check the disk has room.
    private_class_method def self.installed_size(root)
      bytes = Dir.glob("usr/**/*", File::FNM_DOTMATCH, base: root).sum do |path|
        stat = File.lstat(File.join(root, path))
        stat.file? ? stat.size : 0
      end
      (bytes / 1024.0).ceil
    end
  end
end
