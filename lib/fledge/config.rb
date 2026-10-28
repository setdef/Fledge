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
  # it needs no file.
  #
  # This class reads <tt>fledge.yml</tt> from the project's root, a YAML
  # mapping as RuboCop's and Kamal's configuration are, checks each value,
  # and refuses a key it does not know, so a typo fails the build instead
  # of being ignored. The file also marks its folder as a project's root,
  # for a script with no Gemfile or gemspec of its own.
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
  class Config < Data.define(:name, :kind, :identifier, :version, :icon, :publisher, :copyright, :installers)
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

    # The file's name, in the project's root.
    FILE = "fledge.yml"

    # The keys the file may hold.
    KEYS = %w[name kind identifier version icon publisher copyright installers].freeze

    # KEYS, as a sentence lists them.
    KNOWN = "name, kind, identifier, version, icon, publisher, copyright, and installers"

    # The installers a windowed app may have: a disk image for macOS, an
    # NSIS setup program for Windows, and an AppImage for Linux.
    INSTALLERS = %w[dmg nsis appimage].freeze

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
      new(name: nil, kind: nil, identifier: nil, version: nil, icon: nil, publisher: nil, copyright: nil, installers: nil)
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
        installers: installers(data, path)
      )
    end

    # The icon's path without an extension, as Briefcase's +icon+ is.
    # One that ends in an icon's extension, as 0.0.1.pre.7's one PNG did,
    # is refused with what to write instead.
    private_class_method def self.icon(data, path) # :nodoc:
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
        raise Error, "#{path}: installers must be a list of #{known}, such as installers: [dmg, nsis, appimage], or [] for none"
      end

      unknown = value - INSTALLERS
      raise Error, "#{path}: installers has #{unknown.join(', ')}, which Fledge does not build. It builds #{known}." unless unknown.empty?
      if !value.empty? && data["kind"] != "windowed"
        raise Error, "#{path}: only a windowed app has installers; a console app ships as its archive, so leave out installers"
      end

      value.uniq
    end

    private_class_method def self.text(data, key, path, example) # :nodoc:
      value = data[key]
      return nil if value.nil?
      raise Error, "#{path}: #{key} must be text, such as #{key}: #{example}" unless value.is_a?(String) && !value.strip.empty?

      value
    end

    private_class_method def self.kind(data, path) # :nodoc:
      value = text(data, "kind", path, "windowed")
      return value if value.nil? || KINDS.include?(value)

      raise Error, "#{path}: kind must be console or windowed, not #{value}"
    end

    private_class_method def self.identifier(data, path) # :nodoc:
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
