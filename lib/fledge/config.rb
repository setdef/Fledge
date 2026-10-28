# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "yaml"
require_relative "error"

module Fledge
  # What a project tells Fledge in its <tt>fledge.yml</tt>, when it needs
  # to tell it anything.
  #
  # Fledge takes almost everything from the project as it already is: the
  # program from the path you build, the gems from the Gemfile.lock, and
  # the app's name from the gemspec or the folder (ADR 005). The one
  # thing it cannot always know is a name better than the one it would
  # make. A project that needs none needs no file.
  #
  # This class reads <tt>fledge.yml</tt> from the project's root, a YAML
  # mapping as RuboCop's and Kamal's configuration are, and refuses a key
  # it does not know, so a typo fails the build instead of being ignored.
  # The file also marks its folder as a project's root, for a script with
  # no Gemfile or gemspec of its own.
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
  #   #   name: CoolApp
  #   Fledge::Config.load("path/to/project").name # => "CoolApp"
  #--
  # SPDX-SnippetEnd
  #++
  class Config < Data.define(:name)
    ##
    # :attr_reader: name
    # The app's name, or +nil+ for the one Fledge makes.

    # The file's name, in the project's root.
    FILE = "fledge.yml"

    # The keys the file may hold.
    KEYS = %w[name].freeze

    # KEYS, as a sentence lists them.
    KNOWN = "name"

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
      new(name: nil)
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
      raise Error, "#{path} has #{unknown.map { |key| "'#{key}'" }.join(', ')}, which Fledge does not know. It knows only #{KNOWN}." unless unknown.empty?

      new(name: name_from(data["name"], path))
    end

    private_class_method def self.name_from(value, path) # :nodoc:
      return nil if value.nil?
      raise Error, "#{path}: name must be text, such as name: MyCoolApp" unless value.is_a?(String)

      value
    end
  end
end
