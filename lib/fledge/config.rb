# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "rubygems"
require "yaml"
require_relative "error"

module Fledge
  # What a project tells Fledge in its <tt>fledge.yml</tt>, when it needs
  # to tell it anything.
  #
  # Fledge takes almost everything from the project as it already is: the
  # program from the path you build, the gems from the Gemfile.lock, and
  # the app's name, version, and publisher from the gemspec or the folder
  # (ADR 005 and ADR 008). What it cannot know is how the app presents
  # itself to the person who runs it: whether it opens windows or runs in
  # a terminal, the identifier the operating system knows it by, its
  # icon, and its copyright (decision 18). A project that needs none of
  # it needs no file. Nor can it know which of a project's programs ship
  # together: list them under +programs+ (Config::Program), each with its
  # own path, name, kind, identifier, and icon, and they ship as one
  # folder that shares one runtime, one copy of the project, and one set
  # of gems (ADR 024). Nor can it know the files a phone's project needs
  # that no gem supplies, such as SDL3's host for a game whose SDL owns
  # the main loop: name a folder of them under +ios+ or +android+
  # (Config::Phone), and <tt>fledge build ios</tt> or <tt>fledge build
  # android</tt> copies them over the project it writes (ADR 025). Nor
  # can it know which libraries a project's gems may load from a Linux
  # distribution, such as a webview's WebKitGTK: list them under +linux+
  # (Config::Linux), and the build accepts them, and a <tt>.deb</tt>
  # depends on them (ADR 030).
  #
  # This class reads <tt>fledge.yml</tt> from the project's root, a YAML
  # mapping as RuboCop's and Kamal's configuration are, checks each value,
  # and refuses a key it does not know, so a typo fails the build instead
  # of being ignored. The file also marks its folder as a project's root,
  # for a script with no Gemfile or gemspec of its own.
  #
  # An editor can check the file as you type, before a build does.
  # <tt>config.schema.json</tt>, beside this file, is a JSON Schema of
  # these keys and rules (ADR 023). Name it on the file's first line, at
  # the tag your Gemfile installs Fledge from, and an editor that runs
  # Red Hat's YAML language server, such as VS Code with Red Hat's YAML
  # extension, completes each key and value, shows what each means, and
  # marks a typo, as the Fledge you build with reads them:
  #
  #--
  # SPDX-SnippetBegin
  # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
  # SPDX-License-Identifier: MIT-0
  #++
  #   # yaml-language-server: $schema=https://raw.githubusercontent.com/setdef/Fledge/v0.5.1/lib/fledge/config.schema.json
  #--
  # SPDX-SnippetEnd
  #++
  #
  # Use it through Fledge::App.
  #
  # === Example
  #
  #--
  # SPDX-SnippetBegin
  # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
  # SPDX-License-Identifier: MIT-0
  #++
  #   # fledge.yml:
  #   #   name: Cool App
  #   #   kind: windowed
  #   #   identifier: com.example.CoolApp
  #   #   icon: icons/app
  #   config = Fledge::Config.load("path/to/project")
  #   config.name       # => "Cool App"
  #   config.kind       # => "windowed"
  #   config.identifier # => "com.example.CoolApp"
  #--
  # SPDX-SnippetEnd
  #++
  class Config < Data.define(:name, :kind, :identifier, :version, :icon, :publisher, :copyright, :installers, :programs, :ios, :android, :linux)
    ##
    # :attr_reader: name
    # The app's name, or +nil+ for the one Fledge makes.

    ##
    # :attr_reader: kind
    # One of KINDS, or +nil+ for +console+.

    ##
    # :attr_reader: identifier
    # The app's reverse-DNS identifier, such as
    # <tt>"com.example.MyCoolApp"</tt>, or +nil+ for none.

    ##
    # :attr_reader: version
    # The app's version, or +nil+ for the gemspec's.

    ##
    # :attr_reader: icon
    # The path of the app's icon files without their extension, relative
    # to the project's root, such as <tt>icons/app</tt> for
    # <tt>icons/app.icns</tt> and the rest (Fledge::Icon), or +nil+ for
    # none.

    ##
    # :attr_reader: publisher
    # Who publishes the app, or +nil+ for the gemspec's authors.

    ##
    # :attr_reader: copyright
    # The app's copyright notice, or +nil+ for none.

    ##
    # :attr_reader: installers
    # The installers to build, from INSTALLERS, or +nil+ for every one a
    # windowed app's targets have (ADR 009).

    ##
    # :attr_reader: programs
    # The project's programs (Config::Program), when it ships several
    # from one folder, or +nil+ for the one program you build (ADR 024).

    ##
    # :attr_reader: ios
    # What <tt>fledge build ios</tt> lays over the project it writes
    # (Config::Phone), or +nil+ for nothing (ADR 025).

    ##
    # :attr_reader: android
    # What <tt>fledge build android</tt> lays over the project it writes
    # (Config::Phone), or +nil+ for nothing (ADR 025).

    ##
    # :attr_reader: linux
    # The libraries the project's gems load from the Linux distribution
    # (Config::Linux), or +nil+ for none (ADR 030).

    # The file's name, in the project's root.
    FILE = "fledge.yml"

    # The keys the file may hold.
    KEYS = %w[name kind identifier version icon publisher copyright installers programs ios android linux].freeze

    # KEYS, as a sentence lists them.
    KNOWN = "name, kind, identifier, version, icon, publisher, copyright, installers, programs, ios, android, and linux"

    # The keys that, beside +programs+, belong to each program instead.
    PER_PROGRAM = %w[kind identifier icon].freeze

    # The phones whose projects a project's own files may change, each a
    # key of its own (Config::Phone).
    PHONES = %w[ios android].freeze

    # The installers a windowed app may have: a disk image for macOS, an
    # NSIS setup program for Windows, an AppImage for Linux, and a
    # <tt>.deb</tt> for Debian and Ubuntu.
    INSTALLERS = %w[dmg nsis appimage deb].freeze

    # The installers a windowed app gets when <tt>fledge.yml</tt> lists
    # none of its own: every one but +deb+, which needs dpkg-deb, a tool
    # not every Linux computer has, so a developer asks for it (ADR 021).
    DEFAULT_INSTALLERS = %w[dmg nsis appimage].freeze

    # The kinds of app (ADR 001, section 5): one that runs in a terminal,
    # and one that opens its own windows and shows none.
    KINDS = %w[console windowed].freeze

    # A reverse-DNS identifier: two or more labels of letters, digits, and
    # hyphens, between dots, as Apple's CFBundleIdentifier allows, in at
    # most IDENTIFIER_MAX characters, the most an AppUserModelID holds.
    IDENTIFIER = /\A[A-Za-z0-9][A-Za-z0-9-]*(?:\.[A-Za-z0-9][A-Za-z0-9-]*)+\z/

    # The longest identifier: an AppUserModelID's limit.
    IDENTIFIER_MAX = 128

    # The configuration of a project with no <tt>fledge.yml</tt>.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   Fledge::Config.none.name # => nil
    #--
    # SPDX-SnippetEnd
    #++
    def self.none
      new(name: nil, kind: nil, identifier: nil, version: nil, icon: nil, publisher: nil, copyright: nil, installers: nil, programs: nil, ios: nil,
        android: nil, linux: nil)
    end

    # The configuration in +root+/fledge.yml, or Config.none when there is
    # no such file. Raises Fledge::Error, naming the file, when it is not
    # a YAML mapping of the keys in KEYS with the values they need.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   Fledge::Config.load("examples/hello").name # => nil
    #--
    # SPDX-SnippetEnd
    #++
    def self.load(root)
      path = File.join(root, FILE)
      return none unless File.file?(path)

      from(read(path), path)
    end

    private_class_method def self.read(path) # :nodoc:
      YAML.safe_load_file(path) || {}
    rescue Psych::Exception => e
      raise Error, "#{path} is not valid YAML: #{e.message}"
    end

    private_class_method def self.from(data, path) # :nodoc:
      raise Error, "#{path} must be a mapping of #{KNOWN}" unless data.is_a?(Hash)

      unknown = data.keys - KEYS
      raise Error, "#{path} has #{unknown.map { |key| "'#{key}'" }.join(', ')}, which Fledge does not know. It knows #{KNOWN}." unless unknown.empty?

      new(
        name: text(data, "name", path, "MyCoolApp"),
        kind: kind(data, path),
        identifier: identifier(data, path),
        version: version(data, path),
        icon: icon(data, path),
        publisher: text(data, "publisher", path, "Example, Inc."),
        copyright: text(data, "copyright", path, "\"Copyright 2026 Example, Inc.\""),
        installers: installers(data, path),
        programs: programs(data, path),
        ios: Phone.from(data, "ios", path),
        android: Phone.from(data, "android", path),
        linux: Linux.from(data, path)
      )
    end

    # The configuration of +program+, one of #programs: its name, kind,
    # identifier, and icon, with the project's version, publisher,
    # copyright, and installers, and no programs of its own.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   config = Fledge::Config.load("examples/programs")
    #   config.for_program(config.programs.first).kind # => "windowed"
    #--
    # SPDX-SnippetEnd
    #++
    def for_program(program)
      with(name: program.name, kind: program.kind, identifier: program.identifier, icon: program.icon, programs: nil)
    end

    # The libraries the project's gems load from the system on +os+
    # (Fledge::Platform#os): on +linux+, glibc's or musl's, those its
    # +linux+ mapping lists (Config::Linux), and none elsewhere.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   config = Fledge::Config.load("examples/system_library")
    #   config.system_libraries("linux")  # => ["libpng16.so.16"]
    #   config.system_libraries("darwin") # => []
    #--
    # SPDX-SnippetEnd
    #++
    def system_libraries(os)
      return [] unless os == "linux"

      linux&.system_libraries || []
    end

    # The programs under +programs+ (ADR 024): a list of at least one,
    # with names and identifiers no two share, at most one windowed, and
    # no kind, identifier, or icon beside them, which belong to each
    # program.
    private_class_method def self.programs(data, path) # :nodoc:
      value = data["programs"]
      return nil if value.nil?
      unless value.is_a?(Array) && !value.empty?
        raise Error, "#{path}: programs must be a list of at least one program, each a mapping such as - path: bin/cli"
      end

      misplaced = PER_PROGRAM.find { |key| !data[key].nil? }
      raise Error, "#{path}: with programs, #{misplaced} belongs to each program; move it into the program it describes" if misplaced

      programs = value.each_with_index.map { |item, index| Program.from(item, index + 1, path) }
      unique(programs.select(&:name), path, "named") { |program| program.name.to_s }
      unique(programs.select(&:identifier), path, "identified as") { |program| program.identifier.to_s }
      windowed = programs.select(&:windowed?)
      return programs if windowed.size < 2

      raise Error, "#{path}: #{windowed.map(&:path).join(' and ')} are both windowed, and a project has one windowed program; " \
        "build another on its own, with fledge build #{windowed.last&.path}"
    end

    # Refuses two of +programs+ for which the block gives the same text,
    # ignoring case, as Windows' and macOS's file systems do.
    private_class_method def self.unique(programs, path, what, &value) # :nodoc:
      programs.group_by { |program| value.call(program).downcase }.each_value do |same|
        next if same.size < 2

        raise Error, "#{path}: #{same.map(&:path).join(' and ')} are both #{what} #{value.call(same.first)}; give each its own"
      end
    end

    # The icon's path without an extension, as Briefcase's +icon+ is.
    # One that ends in an icon's extension, as 0.0.1.pre.7's one PNG did,
    # is refused with what to write instead.
    def self.icon(data, path) # :nodoc:
      value = text(data, "icon", path, "icons/app")
      return value unless value&.match?(/\.(?:png|icns|ico)\z/i)

      raise Error, "#{path}: icon names the icon's files without an extension, such as icon: #{value.sub(/\.[^.]+\z/, '')} " \
        "for #{value.sub(/\.[^.]+\z/, '')}.icns, .ico, and -16.png to -512.png"
    end

    # The installers to build: a list of INSTALLERS, which may be empty,
    # and only for a windowed app, since a console app gets none (ADR
    # 009).
    private_class_method def self.installers(data, path) # :nodoc:
      value = data["installers"]
      return nil if value.nil?

      known = INSTALLERS.join(", ")
      unless value.is_a?(Array) && value.all? { |item| item.is_a?(String) }
        raise Error, "#{path}: installers must be a list of #{known}, such as installers: [dmg, nsis, appimage, deb], or [] for none"
      end

      unknown = value - INSTALLERS
      raise Error, "#{path}: installers has #{unknown.join(', ')}, which Fledge does not build. It builds #{known}." unless unknown.empty?
      if !value.empty? && !windowed?(data)
        raise Error, "#{path}: only a windowed app has installers; a console app ships as its archive, so leave out installers"
      end

      value.uniq
    end

    # Whether the app, or one of its programs, is windowed.
    private_class_method def self.windowed?(data) # :nodoc:
      programs = data["programs"]
      return data["kind"] == "windowed" unless programs.is_a?(Array)

      programs.any? { |item| item.is_a?(Hash) && item["kind"] == "windowed" }
    end

    # The text at +key+ in +data+, or +nil+ when there is none. Raises
    # Fledge::Error, beginning with +path+ and suggesting +example+, for
    # anything else. Config::Program reads its keys with it too.
    def self.text(data, key, path, example) # :nodoc:
      value = data[key]
      return nil if value.nil?
      raise Error, "#{path}: #{key} must be text, such as #{key}: #{example}" unless value.is_a?(String) && !value.strip.empty?

      value
    end

    # Whether +path+ names a file or folder in the project: relative to
    # its root, with <tt>/</tt> between folders, none of them empty,
    # <tt>.</tt>, or <tt>..</tt>, no backslash or line break, and no space
    # at either end. Config::Program and Config::Phone check their paths
    # with it.
    def self.inside?(path) # :nodoc:
      path == path.strip && !path.match?(/[\r\n\\]/) && path.split("/", -1).none? { |segment| ["", ".", ".."].include?(segment) }
    end

    # The kind at +data+'s +kind+, one of KINDS, or +nil+.
    def self.kind(data, path) # :nodoc:
      value = text(data, "kind", path, "windowed")
      return value if value.nil? || KINDS.include?(value)

      raise Error, "#{path}: kind must be console or windowed, not #{value}"
    end

    # The reverse-DNS identifier at +data+'s +identifier+, or +nil+.
    def self.identifier(data, path) # :nodoc:
      value = text(data, "identifier", path, "com.example.MyCoolApp")
      return value if value.nil? || (value.match?(IDENTIFIER) && value.length <= IDENTIFIER_MAX)

      raise Error, "#{path}: identifier must be reverse-DNS, such as com.example.MyCoolApp: letters, digits, and hyphens, " \
        "in two or more parts between dots, in at most #{IDENTIFIER_MAX} characters, not #{value}"
    end

    # A version: text that begins with a number and that RubyGems reads as
    # a version, such as 1.2.3 or 0.1.0.pre.1. YAML reads 1.2 as a number,
    # which would make 1.10 into 1.1, so it must be quoted.
    private_class_method def self.version(data, path) # :nodoc:
      value = data["version"]
      return nil if value.nil?
      raise Error, "#{path}: version must be text; quote it, as in version: \"#{value}\"" if value.is_a?(Numeric)

      value = text(data, "version", path, "1.2.3").to_s
      return value if value.match?(/\A\d/) && Gem::Version.correct?(value)

      raise Error, "#{path}: version must be a version that begins with a number, such as 1.2.3, not #{value}"
    end
  end
end

require_relative "config/linux"
require_relative "config/phone"
require_relative "config/program"
