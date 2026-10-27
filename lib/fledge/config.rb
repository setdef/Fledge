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
  # the app's name from the gemspec or the folder (ADR 005). Three things
  # it cannot always know: a name better than the one it would make, the
  # license of a gem whose specification declares none, or declares one
  # wrongly, and what a native gem compiles into its binaries, when Fledge
  # has not reviewed that gem (Fledge::CompiledCode). A project that needs
  # none of them needs no file.
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
  #   #   licenses:
  #   #     unlabeled_gem: MIT
  #   #   compiled:
  #   #     native_gem:
  #   #       - {name: libfoo 1.2, license: BSD-3-Clause}
  #   config = Fledge::Config.load("path/to/project")
  #   config.name                                 # => "CoolApp"
  #   config.licenses                             # => {"unlabeled_gem" => "MIT"}
  #   config.compiled.fetch("native_gem").first.license # => "BSD-3-Clause"
  #--
  # SPDX-SnippetEnd
  #++
  class Config < Data.define(:name, :licenses, :compiled)
    ##
    # :attr_reader: name
    # The app's name, or +nil+ for the one Fledge makes.

    ##
    # :attr_reader: licenses
    # The SPDX license expression of each gem named, by the gem's name,
    # used in place of what the gem's specification declares.

    ##
    # :attr_reader: compiled
    # What each named native gem's compiled files hold besides the gem's
    # own code, by the gem's name, as Fledge::Config::Compiled entries,
    # used in place of what Fledge's own map says (Fledge::CompiledCode).
    # An empty list says the compiled code is the gem's own alone.

    # One library a native gem compiles in, or ships as its own shared
    # library, as <tt>fledge.yml</tt> declares it.
    class Compiled < Data.define(:name, :license, :shared_library, :source)
      ##
      # :attr_reader: name
      # The library's name, and its version if you know it.

      ##
      # :attr_reader: license
      # The library's SPDX license expression.

      ##
      # :attr_reader: shared_library
      # The glob, relative to the gem's folder, of the library's own
      # shared library, when it ships as one, or +nil+ when it is compiled
      # into the gem's other files.

      ##
      # :attr_reader: source
      # Where the library's exact source is, for one whose license asks
      # for it (the LGPL), or +nil+.

      # The keys an entry may hold.
      KEYS = %w[name license shared_library source].freeze
    end

    # The file's name, in the project's root.
    FILE = "fledge.yml"

    # The keys the file may hold.
    KEYS = %w[name licenses compiled].freeze

    # KEYS, as a sentence lists them.
    KNOWN = "name, licenses, and compiled"

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
      new(name: nil, licenses: {}, compiled: {})
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

      new(name: name_from(data["name"], path), licenses: licenses_from(data["licenses"], path),
        compiled: compiled_from(data["compiled"], path))
    end

    private_class_method def self.name_from(value, path) # :nodoc:
      return nil if value.nil?
      raise Error, "#{path}: name must be text, such as name: MyCoolApp" unless value.is_a?(String)

      value
    end

    private_class_method def self.licenses_from(value, path) # :nodoc:
      return {} if value.nil?

      wrong = "#{path}: licenses must map gem names to SPDX license expressions, such as licenses: {some_gem: MIT}"
      raise Error, wrong unless value.is_a?(Hash)
      raise Error, wrong unless value.all? { |gem, license| gem.is_a?(String) && license.is_a?(String) && !license.strip.empty? }

      value.to_h { |gem, license| [gem.to_s, license.to_s] }
    end

    private_class_method def self.compiled_from(value, path) # :nodoc:
      return {} if value.nil?

      wrong = "#{path}: compiled must map gem names to lists of what their compiled code holds, such as " \
        "compiled: {some_gem: [{name: libfoo 1.2, license: MIT}]}, each with a name and a license, and for a library " \
        "that ships as its own shared library, its shared_library and its source"
      raise Error, wrong unless value.is_a?(Hash) && value.all? { |gem, list| gem.is_a?(String) && list.is_a?(Array) }

      value.to_h { |gem, list| [gem.to_s, list.map { |entry| compiled_entry(entry) || raise(Error, wrong) }] }
    end

    private_class_method def self.compiled_entry(entry) # :nodoc:
      return nil unless entry.is_a?(Hash) && (entry.keys - Compiled::KEYS).empty?

      values = Compiled::KEYS.to_h { |key| [key, entry[key]] }
      return nil unless values.values_at("name", "license").all? { |text| text.is_a?(String) && !text.strip.empty? }
      return nil unless values.values_at("shared_library", "source").all? { |text| text.nil? || text.is_a?(String) }

      Compiled.new(name: values.fetch("name").to_s, license: values.fetch("license").to_s,
        shared_library: values["shared_library"]&.to_s, source: values["source"]&.to_s)
    end
  end
end
