# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "test_helper"
require_relative "../tasks/ruby_archive"

# The pruning of Fledge's own Ruby archive (tasks/ruby_archive.rb): the
# archive is for compiling against and running a newer Ruby, and goes
# through the pruning a runtime does before the license
# audit reads it.
class RubyArchivePruningTest < Minitest::Test
  SOURCES = YAML.safe_load_file(File.join(RuntimeBuilder::ROOT, "runtime", "sources.yml"))
  RUBY = "lib/ruby/4.1.0+5"
  GEMS = "lib/ruby/gems/4.1.0+5"

  # Stands in for the builder, keeping the commands it would run.
  class Commands
    attr_reader :ran

    def initialize
      @ran = []
    end

    def sources
      SOURCES
    end

    def run(*command, **)
      @ran << command
    end
  end

  # An installed prefix, with something of each kind: what a runtime
  # removes, and what mkmf, Lota's CMake, and the static libruby read.
  def write_prefix(prefix, arch)
    files = %W[
      bin/ruby
      bin/bootsnap
      bin/csv
      include/ruby-4.1.0+5/ruby.h
      lib/libruby.4.1-static.a
      lib/pkgconfig/ruby-4.1.pc
      #{RUBY}/#{arch}/zlib.so
      #{RUBY}/#{arch}/stray.a
      #{RUBY}/#{arch}/portable_ruby_gems.rb
      #{RUBY}/#{arch}/zlib.so.dSYM/Contents/Resources/DWARF/zlib.so
      #{GEMS}/gems/csv-3.3.5/lib/csv.rb
      #{GEMS}/gems/newer-1.0.0/lib/newer.rb
      #{GEMS}/gems/bigdecimal-4.0.1/ext/bigdecimal/bigdecimal.h
      #{GEMS}/gems/bootsnap-1.0.0/lib/bootsnap.rb
      #{GEMS}/gems/nkf-0.3.0/ext/nkf/nkf.c
      #{GEMS}/gems/nkf-0.3.0/ext/java/org/jruby/ext/nkf/RubyNKF.java
      #{GEMS}/doc/csv-3.3.5/ri/x
      libexec/cert.pem
    ]
    files.each do |file|
      FileUtils.mkdir_p(File.dirname(File.join(prefix, file)))
      FileUtils.touch(File.join(prefix, file))
    end
    FileUtils.mkdir_p(File.join(prefix, GEMS, "specifications"))
    { "csv" => "3.3.5", "newer" => "1.0.0", "bigdecimal" => "4.0.1", "bootsnap" => "1.0.0", "nkf" => "0.3.0" }.each do |name, version|
      spec = Gem::Specification.new do |gem|
        gem.name = name
        gem.version = version
        gem.summary = name
        gem.authors = ["x"]
        gem.executables = [name] if %w[bootsnap csv].include?(name)
      end
      File.write(File.join(prefix, GEMS, "specifications", "#{name}-#{version}.gemspec"), spec.to_ruby)
    end
  end

  # The bundled gems of the Ruby the archive is built from, as its own
  # source lists them. They need not be those runtime/sources.yml lists
  # for the Ruby a runtime copies: an archive of a newer Ruby may bundle
  # a gem that list lacks (newer, here), and pruning by that list would
  # remove it.
  def write_bundled_gems(work, platform)
    source = File.join(work, platform, "sources", "ruby", "gems")
    FileUtils.mkdir_p(source)
    File.write(File.join(source, "bundled_gems"), <<~LIST)
      # name version repository
      csv 3.3.5 https://github.com/ruby/csv
      bigdecimal 4.0.1 https://github.com/ruby/bigdecimal
      nkf 0.3.0 https://github.com/ruby/nkf
      newer 1.0.0 https://github.com/ruby/newer
    LIST
  end

  # Prunes a prefix of +platform+, and yields its path, the files that
  # remain in it, and the commands the builder ran.
  def prune(platform, arch)
    Dir.mktmpdir do |work|
      prefix = File.join(work, "prefix")
      write_prefix(prefix, arch)
      write_bundled_gems(work, platform)
      commands = Commands.new
      RubyArchive.new(platform: Fledge::Platform.find(platform), work:, builder: commands).prune(prefix)
      yield prefix, Dir.glob("**/*", base: prefix).select { |path| File.file?(File.join(prefix, path)) }.sort, commands.ran
    end
  end

  # What a runtime keeps and an archive too: Ruby's headers, the static
  # libruby, the libraries, the pkg-config file Lota's CMake reads, and
  # the CA bundle. What goes is what no program reads: debug symbols,
  # static libraries, and gems' headers in lib/ruby, documentation, the
  # Java sources of JRuby's nkf, and a gem that is not Ruby's own.
  KEPT = %W[
    bin/csv
    bin/ruby
    include/ruby-4.1.0+5/ruby.h
    lib/libruby.4.1-static.a
    lib/pkgconfig/ruby-4.1.pc
    #{GEMS}/gems/csv-3.3.5/lib/csv.rb
    #{GEMS}/gems/newer-1.0.0/lib/newer.rb
    #{GEMS}/gems/nkf-0.3.0/ext/nkf/nkf.c
    #{GEMS}/specifications/bigdecimal-4.0.1.gemspec
    #{GEMS}/specifications/csv-3.3.5.gemspec
    #{GEMS}/specifications/newer-1.0.0.gemspec
    #{GEMS}/specifications/nkf-0.3.0.gemspec
    libexec/cert.pem
  ].freeze

  def test_a_linux_archive_is_pruned_as_a_runtime_is_and_its_debug_information_stripped
    prune("x86_64-linux", "x86_64-linux") do |prefix, files, ran|
      assert_equal [*KEPT, "#{RUBY}/x86_64-linux/zlib.so"].sort, files
      assert_equal [
        ["strip", "--strip-debug", File.join(prefix, RUBY, "x86_64-linux", "zlib.so")],
        ["strip", "-S", File.join(prefix, "lib", "libruby.4.1-static.a")],
      ], ran
    end
  end

  # The pruning comes first, so that the checks and the license audit,
  # and so the notices and the SBOM, see the archive as it is archived.
  def test_the_archive_is_pruned_before_it_is_checked_and_audited
    seen = []
    test = self
    state = -> (prefix) { File.exist?(File.join(prefix, RUBY, "x86_64-linux", "zlib.so.dSYM")) ? :whole : :pruned }
    recipe = Class.new(RubyArchive) do
      define_method(:build) do |prefix|
        test.write_prefix(prefix, "x86_64-linux")
        test.write_bundled_gems(@work, "x86_64-linux")
        prefix
      end
      define_method(:check) { |prefix| seen << [:check, state.call(prefix)] }
      define_method(:license) { |prefix, **| seen << [:license, state.call(prefix)] }
    end
    Dir.mktmpdir do |work|
      path = recipe.new(platform: Fledge::Platform.find("x86_64-linux"), work:, builder: Commands.new).call

      assert_equal [[:check, :pruned], [:license, :pruned]], seen
      assert File.file?(path), path
    end
  end

  # A Mac's extensions carry their debug information in .dSYM folders,
  # which go, and the static libruby is stripped of its debug map as a
  # runtime's is; a Mac's extensions are not stripped, as a runtime's
  # are not.
  def test_a_macs_archive_loses_its_dsym_folders_and_the_debug_map_of_its_static_libruby
    prune("arm64-darwin", "arm64-darwin") do |prefix, files, ran|
      assert_equal [*KEPT, "#{RUBY}/arm64-darwin/zlib.so"].sort, files
      assert_equal [["strip", "-S", File.join(prefix, "lib", "libruby.4.1-static.a")]], ran
    end
  end
end
