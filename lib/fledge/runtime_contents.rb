# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "error"
require_relative "tar_gz"

module Fledge
  # What a runtime archive holds that an app's gems depend on: where its
  # gems go, which gems it has, and which Ruby it runs.
  #
  # An app's gems join the runtime's default and bundled gems in Ruby's
  # own gem folder, <tt>lib/ruby/gems/4.0.0</tt> (in <tt>ruby\</tt> on
  # Windows), where RubyGems and Bundler find them (ADR 005). A gem the
  # runtime already has at the same version is the runtime's, already
  # audited, and must not be added twice; a gem must suit the runtime's
  # Ruby. The runtime knows all three, so they are read from it rather
  # than kept a second time in Fledge.
  #
  # This class reads a runtime archive once and keeps the gem folder, by
  # the path of its <tt>specifications</tt> folder, the full name of every
  # gem specification in it, and the Ruby version its
  # <tt>rbconfig.rb</tt> records, as RbConfig's MAJOR, MINOR, and TEENY.
  #
  # Use it to plan which of an app's gems a runtime needs.
  #
  # === Example
  #
  #--
  # SPDX-SnippetBegin
  # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
  # SPDX-License-Identifier: MIT-0
  #++
  #   contents = Fledge::RuntimeContents.read("fledge-runtime-0.0.1-x64-mingw-ucrt.tar.gz")
  #   contents.gem_dir                    # => "ruby/lib/ruby/gems/4.0.0"
  #   contents.ruby_version               # => "4.0.9"
  #   contents.gems.include?("csv-3.3.5") # => true
  #--
  # SPDX-SnippetEnd
  #++
  class RuntimeContents < Data.define(:gem_dir, :gems, :ruby_version)
    ##
    # :attr_reader: gem_dir
    # Ruby's gem folder, relative to the runtime's top folder.

    ##
    # :attr_reader: gems
    # The full name of every gem the runtime has, default gems included,
    # such as <tt>csv-3.3.5</tt>.

    ##
    # :attr_reader: ruby_version
    # The runtime's Ruby version, such as <tt>4.0.9</tt>.

    # A gem specification's path in a runtime: the gem folder, and the
    # gem's full name.
    SPECIFICATION = %r{\A(?<gem_dir>(?:[^/]+/)*lib/ruby/gems/[^/]+)/specifications/(?:default/)?(?<full_name>[^/]+)\.gemspec\z}
    # rbconfig.rb's path in a runtime, in Ruby's architecture folder.
    RBCONFIG = %r{\A(?:[^/]+/)*lib/ruby/\d[^/]*/[^/]+/rbconfig\.rb\z}
    # The lines of rbconfig.rb that hold Ruby's version, a part each.
    VERSION_PARTS = /^\s*CONFIG\["(MAJOR|MINOR|TEENY)"\] = "(\d+)"/

    # The contents of the runtime archive at +path+. Raises Fledge::Error
    # when it holds no gem folder or no rbconfig.rb.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   Fledge::RuntimeContents.read(runtime).gem_dir # => "lib/ruby/gems/4.0.0"
    #--
    # SPDX-SnippetEnd
    #++
    def self.read(path)
      gem_dirs = [] # : Array[String]
      gems = [] # : Array[String]
      version = nil # : String?
      TarGz.each_entry(path) do |entry|
        inside = entry.path.split("/", 2).last.to_s
        if (found = SPECIFICATION.match(inside))
          gem_dirs << found[:gem_dir].to_s
          gems << found[:full_name].to_s
        elsif RBCONFIG.match?(inside)
          version ||= ruby_version_in(entry.content)
        end
      end
      build(path, gem_dirs.uniq, gems, version)
    end

    # The version rbconfig.rb's MAJOR, MINOR, and TEENY make.
    private_class_method def self.ruby_version_in(rbconfig) # :nodoc:
      parts = rbconfig.scan(VERSION_PARTS).to_h
      %w[MAJOR MINOR TEENY].map { |part| parts[part] or return nil }.join(".")
    end

    private_class_method def self.build(path, gem_dirs, gems, version) # :nodoc:
      raise Error, "#{path} is not a Fledge runtime: it holds no one gem folder (#{gem_dirs.join(', ')})" unless gem_dirs.size == 1
      raise Error, "#{path} is not a Fledge runtime: it holds no rbconfig.rb" unless version

      new(gem_dir: gem_dirs.first.to_s, gems: gems.sort.freeze, ruby_version: version)
    end
  end
end
