# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require "json"
require "rubygems/specification"
require_relative "../error"

module Fledge
  class Bundle
    # What a Gemfile says once Ruby has evaluated it, as data, so that
    # the Ruby that evaluates it need not be the one that reads the
    # result. A Gemfile is a Ruby program, and under <tt>bundle exec</tt>
    # the app's own process runs it; <tt>fledge build</tt> must not run it
    # in its own, where a branch on RUBY_VERSION, a change to ENV, or a
    # +require+ would be the build's. So a Ruby of its own evaluates the
    # Gemfile (Fledge::Bundle::Evaluation, or a test's collaborator that
    # calls .definition in its own process), which describes what
    # Bundler::Dsl holds when the Gemfile is done, in JSON: each source,
    # each dependency with the options Bundler gave it (its groups,
    # platforms, +install_if+ already answered, and the rest), the Gemfile's
    # +ruby+, and its optional groups. Fledge::Bundle then makes a
    # Bundler::Dsl from that data, with no Gemfile code to run (.dsl), and
    # reads it as it read the one the Gemfile built.
    #
    # The description reaches into the Bundler::Dsl of the Bundler that
    # runs <tt>fledge build</tt>, as the Ruby that evaluated it runs the
    # same Bundler (Fledge::Bundle::Evaluation starts the Ruby that runs
    # Fledge), and so its classes and their options are those of the
    # Bundler pinned in Fledge's own lockfile (doc/contributors/design/gems.md,
    # "Reading the Gemfile and lockfile").
    module GemfileData
      # Evaluates the Gemfile at +gemfile+ in this process, as Bundler's
      # own Bundler::Dsl does, with Bundler's root where +gemfile+ is, and
      # answers what it says as data, which .dsl turns back into a
      # Bundler::Dsl. Raises Bundler::BundlerError, as Bundler does, when
      # the Gemfile is not one it accepts, and Fledge::Error for a source
      # that only a Bundler plugin provides.
      def self.definition(gemfile)
        dsl = Bundler::Dsl.new
        dsl.eval_gemfile(gemfile)
        describe(dsl)
      end

      # The gemspec at +path+ as Bundler evaluates it under <tt>bundle
      # exec</tt>, which is after the Gemfile at +gemfile+ (whose code may
      # define what the gemspec names), as its YAML, which .specification
      # reads back as data. Raises Bundler::BundlerError when Bundler
      # cannot evaluate either.
      def self.gemspec(gemfile, path)
        Bundler::Dsl.new.eval_gemfile(gemfile)
        spec = Bundler.load_gemspec(path) or return nil
        spec.to_yaml
      end

      # The Gem::Specification that +yaml+, which .gemspec answered, holds,
      # loaded from +path+.
      def self.specification(yaml, path)
        spec = Gem::Specification.from_yaml(yaml)
        spec.loaded_from = path
        spec
      end

      # The Bundler::Dsl that +data+, from .definition, describes, ready
      # for Bundler::Dsl#to_definition.
      def self.dsl(data)
        dsl = Bundler::Dsl.new
        list = dsl.instance_variable_get(:@sources) # : Bundler::SourceList
        items(data["gemfiles"]).each { |gemfile| dsl.eval_gemfile(string(gemfile), "") }
        lockfile = data["lockfile"]
        dsl.lockfile(string(lockfile)) if lockfile
        ruby = table(data["ruby"])
        unless ruby.empty?
          dsl.instance_variable_set(:@ruby_version,
            Bundler::RubyVersion.new(items(ruby["versions"]).map { |version| string(version) }, ruby["patchlevel"]&.to_s, string(ruby["engine"]),
              items(ruby["engine_versions"]).map { |version| string(version) }))
        end
        items(data["optional_groups"]).each { |group| dsl.group(string(group).to_sym, optional: true) { nil } }
        rebuilt = rebuild_sources(list, table(data["sources"]))
        dsl.dependencies = items(data["dependencies"]).map { |dependency| dependency(table(dependency), rebuilt) }
        dsl
      end

      # What +dsl+ holds, as JSON-ready data.
      def self.describe(dsl)
        list = dsl.instance_variable_get(:@sources) # : Bundler::SourceList
        raise Error, "Fledge can't read a Gemfile source that a Bundler plugin provides." unless list.plugin_sources.empty?

        known = sources_of(list)
        ruby = dsl.instance_variable_get(:@ruby_version) # : Bundler::RubyVersion?
        gemfiles = dsl.instance_variable_get(:@gemfiles) # : Array[Pathname]
        optional = dsl.instance_variable_get(:@optional_groups) # : Array[Symbol]
        {
"gemfiles" => gemfiles.map(&:to_s),
"lockfile" => dsl.lockfile_path&.to_s,
"ruby" => (ruby_data(ruby) if ruby),
"optional_groups" => optional.map(&:to_s),
"sources" => known.to_h { |kind, sources| [kind, sources.map { |source| source_data(source) }] },
"dependencies" => dsl.dependencies.map { |dependency| dependency_data(dependency, known) },
}
      end

      # Each kind of source in +list+ (a Bundler::SourceList), with the
      # sources of that kind in the order Bundler holds them.
      def self.sources_of(list)
        {
"global" => [list.global_rubygems_source],
"rubygems" => list.non_global_rubygems_sources,
"path" => list.path_sources,
"git" => list.git_sources,
}
      end

      def self.ruby_data(ruby)
        { "versions" => ruby.versions, "patchlevel" => ruby.patchlevel&.to_s, "engine" => ruby.engine, "engine_versions" => ruby.engine_versions }
      end

      def self.source_data(source)
        if source.is_a?(Bundler::Source::Rubygems)
          cooldowns = source.remote_cooldowns.to_h { |uri, days| [uri.to_s, days] }
          { "remotes" => source.remotes.map(&:to_s), "cooldowns" => cooldowns }
        elsif source.is_a?(Bundler::Source::Path)
          { "options" => encode(source.options) }
        else
          raise Error, "Fledge can't read a Gemfile source that is a #{source.class}."
        end
      end

      def self.dependency_data(dependency, known)
        options = dependency.instance_variable_get(:@options).dup # : Hash[String, Object?]
        found = known.flat_map { |kind, list| list.each_index.select { |index| list.fetch(index).equal?(options["source"]) }.map { |index| [kind, index] } }
        raise Error, "Fledge can't read the source of #{dependency.name} in the Gemfile." if options["source"] && found.empty?

        options["source"] = found.first
        { "name" => dependency.name, "requirements" => dependency.requirement.as_list, "options" => encode(options) }
      end

      def self.rebuild_sources(list, data)
        rebuilt = { "global" => [list.global_rubygems_source], "rubygems" => [], "path" => [], "git" => [] } # : Hash[String, Array[Bundler::Source]]
        items(data["global"]).each { |source| remotes(list.global_rubygems_source, table(source), global: true) }
        items(data["rubygems"]).each do |source|
          source = table(source)
          rebuilt.fetch("rubygems") << remotes(list.add_rubygems_source("remotes" => items(source["remotes"]).map { |uri| string(uri) }), source)
        end
        items(data["path"]).each { |source| rebuilt.fetch("path") << list.add_path_source(option_table(source)) }
        items(data["git"]).each { |source| rebuilt.fetch("git") << list.add_git_source(option_table(source)) }
        rebuilt
      end

      # The options that +source+, from .source_data, holds.
      def self.option_table(source)
        decoded = decode(table(source)["options"])
        decoded.is_a?(Hash) ? decoded.transform_keys(&:to_s) : {}
      end

      # Gives +source+, a Bundler::Source::Rubygems, the remotes and the
      # cooldowns of +data+. The global source is given its remotes one at
      # a time, last first, as a Gemfile's +source+ lines give them
      # (Bundler::SourceList#add_global_rubygems_remote), each in front.
      def self.remotes(source, data, global: false)
        items(data["remotes"]).reverse_each { |uri| source.add_remote(string(uri)) } if global
        table(data["cooldowns"]).each do |uri, days|
          remote = source.remotes.find { |candidate| candidate.to_s == uri } or next
          source.remote_cooldowns[remote] = Integer(days.to_s)
        end
        source
      end

      def self.dependency(data, rebuilt)
        opts = option_table(data)
        found = opts["source"]
        opts["source"] = rebuilt.fetch(string(found[0])).fetch(Integer(found[1].to_s)) if found.is_a?(Array)
        Bundler::Dependency.new(string(data["name"]), items(data["requirements"]).map { |requirement| string(requirement) }, opts)
      end

      # +value+ as JSON-ready data: what a Gemfile gives an option of a
      # gem or a source, and a tag for what JSON has no kind for.
      def self.encode(value)
        case value
        when String, Integer, Float, true, false, nil then value
        when Symbol then { "$symbol" => value.to_s }
        when Pathname then { "$pathname" => value.to_s }
        when Regexp then { "$regexp" => value.source, "$options" => value.options }
        when Array then value.map { |item| encode(item) }
        when Hash then { "$hash" => value.map { |key, item| [encode(key), encode(item)] } }
        when Gem::Specification then { "$specification" => value.to_yaml, "$loaded_from" => value.loaded_from }
        else raise Error, "Fledge can't read a Gemfile option that is a #{value.class}."
        end
      end

      def self.decode(value)
        case value
        when Array then value.map { |item| decode(item) }
        when Hash then decode_tagged(value)
        else value
        end
      end

      def self.decode_tagged(value)
        return items(value["$hash"]).to_h { |pair| [decode(items(pair)[0]), decode(items(pair)[1])] } if value.key?("$hash")
        return string(value["$symbol"]).to_sym if value.key?("$symbol")
        return Pathname.new(string(value["$pathname"])) if value.key?("$pathname")
        return Regexp.new(string(value["$regexp"]), Integer(value["$options"].to_s)) if value.key?("$regexp")

        specification(string(value["$specification"]), string(value["$loaded_from"]))
      end

      def self.items(value)
        value.is_a?(Array) ? value : []
      end

      def self.table(value)
        value.is_a?(Hash) ? value : {}
      end

      def self.string(value)
        value.to_s
      end
      private_class_method :describe, :sources_of, :ruby_data, :source_data, :dependency_data, :rebuild_sources, :option_table, :remotes, :dependency,
        :encode, :decode, :decode_tagged, :items, :table, :string
    end
  end
end
