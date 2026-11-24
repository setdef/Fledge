# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
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
  # this module; Tauri's bundler writes the archive itself, which
  # Fledge does not (ADR 101). It lays the built app's folder out as
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
  # SPDX-SnippetCopyrightText: 2026 setdef <kerrick@setdef.com>
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
    # +to+, and returns +to+. +glibc+ is the glibc the app needs
    # (NativeBuild::Floors.glibc), which the build read from its files
    # and recorded, so that a <tt>.deb</tt> made where no tool reads
    # them, by <tt>fledge build --from</tt>, says the same; the package
    # depends on it, so apt refuses an older Debian or Ubuntu, saying
    # why, rather than the app failing to load a file there.
    # +system_libraries+ are the libraries the
    # app's gems load from the distribution (Config::Linux), whose
    # packages the <tt>.deb</tt> depends on, and +system_typelibs+ the
    # typelibs they load, whose packages it depends on too (#typelib_packages).
    # +license+ is the app's license
    # text, and +changelog+ the path of its changelog, or +nil+ for none
    # (#documents). Raises Fledge::Error when
    # this computer has no dpkg-deb, or no dpkg-shlibdeps when it needs
    # one, or either fails.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 setdef <kerrick@setdef.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   Fledge::Deb.write(identity:, folder: "dist/My App-x86_64-linux", platform:, to: "dist/My App-x86_64-linux.deb")
    #--
    # SPDX-SnippetEnd
    #++
    def self.write(identity:, folder:, platform:, to:, glibc:, system_libraries: [], system_typelibs: [], license: nil, changelog: nil)
      package = package_name(identity)
      Dir.mktmpdir("fledge-deb") do |work|
        root = File.join(work, "root")
        lay_out(root, folder, identity, package)
        documents(root, package, license:, changelog:)
        control = File.join(root, "DEBIAN")
        FileUtils.mkdir_p(control, mode: 0o755)
        libraries = dependencies(work, root, platform.cpu, system_libraries)
        depends = ["libc6 (>= #{glibc})", *libraries, *typelib_packages(system_typelibs)]
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
    # SPDX-SnippetCopyrightText: 2026 setdef <kerrick@setdef.com>
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
    # SPDX-SnippetCopyrightText: 2026 setdef <kerrick@setdef.com>
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

    # Writes <tt>/usr/share/doc/PACKAGE</tt>: +license+, the app's license
    # text, as +copyright+, uncompressed, as Debian Policy 12.5 asks of
    # that file, and the file at +changelog+ as <tt>changelog.gz</tt>, the
    # name 12.7 gives the changelog of a package with no separate
    # upstream, compressed with <tt>gzip -9</tt> as 12.7 asks and
    # <tt>-n</tt>, which leaves out gzip's name and time, so the same
    # changelog makes the same bytes. Nothing when both are +nil+.
    private_class_method def self.documents(root, package, license:, changelog:)
      return unless license || changelog

      doc = File.join(root, "usr", "share", "doc", package)
      FileUtils.mkdir_p(doc, mode: 0o755)
      if license
        File.binwrite(File.join(doc, "copyright"), license)
        File.chmod(0o644, File.join(doc, "copyright"))
      end
      return unless changelog

      FileUtils.cp(changelog, File.join(doc, "changelog"))
      File.chmod(0o644, File.join(doc, "changelog"))
      Command.run("gzip", "-n", "-9", File.join(doc, "changelog"), install: "Install gzip, which every Linux distribution has.")
    end

    # The +control+ file: Debian Policy 5.3's mandatory fields and
    # priority and section; the app's description, or else its name, for
    # its synopsis, and its long description after it (Policy 5.6.13);
    # its homepage, when it has one (5.6.23); and its publisher, or its
    # name, for its maintainer, since <tt>fledge.yml</tt> has no
    # address. +Depends+ is +depends+:
    # the glibc the app needs, so apt refuses an older Debian or Ubuntu,
    # saying why, and the packages of the libraries the gems load from
    # the distribution.
    private_class_method def self.control_file(identity, package, architecture, size, depends)
      homepage = identity.homepage
      fields = [
        "Package: #{package}",
        "Version: #{version(identity.version)}",
        "Architecture: #{architecture}",
        "Maintainer: #{line(identity.publisher || identity.name)}",
        "Installed-Size: #{size}",
        "Depends: #{depends.join(', ')}",
        "Section: misc",
        "Priority: optional",
      ]
      fields << "Homepage: #{homepage}" if homepage
      fields << "Description: #{line(identity.description || identity.name)}"
      "#{fields.join("\n")}\n#{extended(identity.long_description)}"
    end

    # The extended description's lines, from +text+, as Debian Policy
    # 5.6.13 writes them: each line after one space, and an empty line as
    # a space and a full stop. Nothing for +nil+.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 setdef <kerrick@setdef.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   Fledge::Deb.extended("One.\n\nTwo.\n") # => " One.\n .\n Two.\n"
    #--
    # SPDX-SnippetEnd
    #++
    def self.extended(text)
      return "" unless text

      text.strip.lines(chomp: true).map { |each| each.strip.empty? ? " .\n" : " #{each.rstrip.tr("\t", ' ')}\n" }.join
    end

    # Each compiled file in the tree at +root+ for +cpu+'s processor, by
    # its path. A file for another processor (Binary#for?), which a gem
    # for every platform carries beside its own, never loads in the app,
    # so it asks nothing of the system.
    private_class_method def self.compiled(root, cpu)
      files = Dir.glob("usr/lib/**/*", base: root).map { |path| File.join(root, path) }.select { |path| elf?(path) }
      Binary.read(files, readers: Binary::Readers.local("linux")).select { |_, binary| binary.for?(cpu) }
    end

    # The packages that provide +libraries+, as dpkg-shlibdeps finds
    # them for the compiled files in the tree at +root+ for +cpu+'s
    # processor (#compiled) that need one: each with
    # the oldest version whose symbols the files use, from the package's
    # own symbols or shlibs file (Debian Policy 8.6), and any other
    # package those files need, but not glibc's, which +Depends+ names
    # already. None when +libraries+ is empty, and then no file is read,
    # so a <tt>.deb</tt> whose gems load no library of the
    # distribution's needs no objdump. A file for
    # another processor is not among them: for it dpkg-shlibdeps would
    # look for that processor's packages of the libraries.
    # dpkg-shlibdeps reads <tt>debian/control</tt> in the folder it runs
    # in, so +work+ gets an empty one; the tree's <tt>DEBIAN</tt> folder
    # tells it the files are a package's.
    private_class_method def self.dependencies(work, root, cpu, libraries)
      return [] if libraries.empty?

      binaries = compiled(root, cpu)
      needing = binaries.select { |_, binary| binary.needed.intersect?(libraries) }.keys
      return [] if needing.empty?

      FileUtils.mkdir_p(File.join(work, "debian"))
      File.write(File.join(work, "debian", "control"), "")
      folders = binaries.keys.map { |path| "-l#{File.dirname(path)}" }.uniq
      output = Command.read("dpkg-shlibdeps", "-O", "-xlibc6", *folders, *needing.map { |path| "-e#{path}" }, chdir: work, install: SHLIBDEPS)
      output[/^shlibs:Depends=(.*)$/, 1].to_s.split(",").map(&:strip).reject(&:empty?)
    end

    # The packages of +typelibs+, each a namespace and its version as
    # libgirepository names it (Config::Linux::TYPELIB), as Debian's
    # GObject introspection mini-policy names them: +gir1.2-+, the
    # namespace in lower case with a hyphen for each underscore, and the
    # version. A package that holds several typelibs provides that name
    # for each, as gir1.2-gtk-4.0 provides gir1.2-gdk-4.0 and
    # gir1.2-glib-2.0 provides gir1.2-gobject-2.0, so apt installs the
    # package that holds the typelib
    # (doc/contributors/design/desktop-apps.md, "Depends").
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 setdef <kerrick@setdef.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   Fledge::Deb.typelib_packages(["Gtk-4.0", "GdkPixbuf-2.0"]) # => ["gir1.2-gtk-4.0", "gir1.2-gdkpixbuf-2.0"]
    #--
    # SPDX-SnippetEnd
    #++
    def self.typelib_packages(typelibs)
      typelibs.map { |typelib| "gir1.2-#{typelib.downcase.tr('_', '-')}" }.uniq
    end

    # Whether the file at +path+ is an ELF file, which alone Linux loads:
    # a gem for every platform carries its Mach-O and PE files too, and
    # this computer's objdump may read no Mach-O file.
    private_class_method def self.elf?(path)
      File.file?(path) && !File.symlink?(path) && Binary.format_of(File.binread(path, 8).to_s) == :elf
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
