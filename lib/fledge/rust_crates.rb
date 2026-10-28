# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "json"
require "open3"
require_relative "compiled_code"
require_relative "error"

module Fledge
  # The Rust crates a gem's Rust extension compiled in, and their
  # licenses.
  #
  # A gem with a Rust extension (rb-sys's create_rust_makefile, or a
  # Cargo.toml RubyGems builds itself) compiles every crate its Cargo.lock
  # resolves into one shared library, under licenses its specification
  # does not name. Everything Fledge copies into an app must ask nothing
  # beyond notices (decision 8), so each crate's license has to be known
  # and judged, as cargo-deny's licenses check judges a Rust program's
  # (ADR 006).
  #
  # This class asks cargo, which knows: <tt>cargo metadata</tt>, offline
  # and locked, so it reads the very resolution the build used, filtered
  # to the target's platform. From the extension's own crate it follows
  # every dependency that is not only for development. The extension's
  # own crate is the gem's own code, which the gem's license covers. The
  # crates it reaches by normal dependencies, other than procedural
  # macros, are compiled in; the rest ran only while it compiled (build dependencies,
  # such as bindgen, and procedural macros and what they use), writing
  # code that is compiled in, so Fledge judges them too, as cargo-deny's
  # licenses check judges every crate by default. It gives each crate as
  # a Fledge::CompiledCode::Library with its SPDX license, a Cargo
  # license of the old <tt>MIT/Apache-2.0</tt> form read as cargo reads
  # it, and NOASSERTION for a crate that names only a license file.
  #
  # Use it through Fledge::NativeBuild.
  #
  # === Example
  #
  #--
  # SPDX-SnippetBegin
  # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
  # SPDX-License-Identifier: MIT-0
  #++
  #   crates = Fledge::RustCrates.new("gems/ferro-idna-0.1.0.pre.1/ext/ferro_idna/Cargo.toml", target: "aarch64-apple-darwin")
  #   crates.call(label: "ferro-idna 0.1.0.pre.1").compiled.find { |crate| crate.name.start_with?("Rust crate idna ") }.license
  #   # => "MIT OR Apache-2.0"
  #--
  # SPDX-SnippetEnd
  #++
  class RustCrates
    # What a Rust extension's build used: the crates compiled into it, and
    # those that ran only while it compiled.
    class Found < Data.define(:compiled, :build)
      ##
      # :attr_reader: compiled
      # The Library of each crate compiled in, sorted by name.

      ##
      # :attr_reader: build
      # The Library of each crate that ran only while it compiled, sorted
      # by name.
    end

    # The crates cargo describes in +data+ (<tt>cargo metadata</tt>'s
    # output, read) that the crate of +manifest+ reaches, as a Found.
    # Raises Fledge::Error when no crate of +data+ is +manifest+'s.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   Fledge::RustCrates.from_metadata(JSON.parse(metadata), "/gem/ext/ext/Cargo.toml").build.first.name
    #   # => "Rust crate bindgen 0.72.1"
    #--
    # SPDX-SnippetEnd
    #++
    def self.from_metadata(data, manifest)
      packages = items(data, "packages").to_h { |package| [text(package, "id"), package] }
      root = packages.values.find { |package| same_file?(text(package, "manifest_path"), manifest) } or
        raise Error, "cargo metadata describes no crate of #{manifest}"
      nodes = items(mapping(data, "resolve"), "nodes").to_h { |node| [text(node, "id"), node] }
      root_id = text(root, "id")
      every = reach(nodes, root_id) { |kinds, _| !kinds.empty? && kinds.all?("dev") }
      compiled = reach(nodes, root_id) { |kinds, id| !kinds.include?(nil) || proc_macro?(packages.fetch(id)) }
      found = -> (ids) { ids.map { |id| library(packages.fetch(id)) }.sort_by(&:name) }
      Found.new(compiled: found.call(compiled - [root_id]), build: found.call(every - compiled))
    end

    # The crates reached from +root+ by every dependency the block does not
    # refuse, given its kinds (nil for normal, "build", "dev") and the id
    # of the crate it leads to.
    private_class_method def self.reach(nodes, root) # :nodoc:
      reached = [] # : Array[String]
      queue = [root]
      while (id = queue.shift)
        next if reached.include?(id)

        reached << id
        node = nodes[id] or next
        items(node, "deps").each do |dependency|
          kinds = items(dependency, "dep_kinds").map { |kind| kind["kind"]&.to_s }
          target = text(dependency, "pkg")
          queue << target unless yield(kinds, target)
        end
      end
      reached
    end

    # Whether the crate is a procedural macro, whose code runs in the
    # compiler and is not compiled in.
    private_class_method def self.proc_macro?(package) # :nodoc:
      items(package, "targets").any? do |target|
        kinds = target["kind"]
        kinds.is_a?(Array) && kinds.include?("proc-macro")
      end
    end

    private_class_method def self.same_file?(one, other) # :nodoc:
      File.expand_path(one) == File.expand_path(other) || (File.exist?(one) && File.exist?(other) && File.identical?(one, other))
    end

    # A crate as a Library: its name and version, and its license, with
    # Cargo's old "/" between alternatives read as OR (the Cargo Book,
    # the manifest's license field).
    private_class_method def self.library(package) # :nodoc:
      declared = package["license"]
      license = declared.is_a?(String) ? declared.split("/").map(&:strip).join(" OR ") : "NOASSERTION"
      CompiledCode::Library.new(name: "Rust crate #{text(package, 'name')} #{text(package, 'version')}", license:, evidence: nil, os: nil)
    end

    # The objects in the list +key+ of +object+, none when it has none.
    # Raises Fledge::Error when it is not a list of objects.
    private_class_method def self.items(object, key) # :nodoc:
      value = object.fetch(key, [])
      raise Error, "cargo metadata's #{key} is not a list of objects" unless value.is_a?(Array) && value.all?(Hash)

      value.map { |item| item.to_h { |name, field| [name.to_s, field] } }
    end

    private_class_method def self.mapping(object, key) # :nodoc:
      value = object[key]
      raise Error, "cargo metadata's #{key} is not an object" unless value.is_a?(Hash)

      value.to_h { |name, field| [name.to_s, field] }
    end

    private_class_method def self.text(object, key) # :nodoc:
      value = object[key]
      raise Error, "cargo metadata's #{key} is not text" unless value.is_a?(String)

      value
    end

    # Creates the reader for the extension whose Cargo.toml is +manifest+,
    # compiled for the Rust target +target+, with cargo run in +env+.
    def initialize(manifest, target:, env: {})
      @manifest = manifest
      @target = target
      @env = env
    end

    # The crates the extension's build used, as a Found. Raises
    # Fledge::Error, naming +label+, when cargo cannot say.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   crates.call(label: "ferro-idna 0.1.0.pre.1").compiled.size # => 38
    #--
    # SPDX-SnippetEnd
    #++
    def call(label:)
      out, err, status = Open3.capture3(@env, "cargo", "metadata", "--format-version", "1", "--locked", "--offline",
        "--filter-platform", @target, "--manifest-path", @manifest)
      raise Error, "cargo cannot say which Rust crates #{label} compiled in:\n#{err}" unless status.success?

      RustCrates.from_metadata(JSON.parse(out), @manifest)
    rescue SystemCallError => e
      raise Error, "#{label} has a Rust extension, and reading which crates it compiled in needs cargo on PATH (#{e.message})"
    end
  end
end
