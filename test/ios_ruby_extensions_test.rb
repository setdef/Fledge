# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "test_helper"

# Fledge::MobileProject::IOSRubyExtensions: which of the iOS runtime's
# own extensions become frameworks of the app, read from each slice's
# list, and the links that take their places in each slice's Ruby, from
# a runtime written here. The frameworks themselves, made with Xcode's
# tools, are the iOS integration tests'.
class IOSRubyExtensionsTest < Minitest::Test
  SLICES = %w[ios-arm64 ios-arm64-simulator].freeze

  def setup
    @dir = Dir.mktmpdir
    @runtime = File.join(@dir, "FledgeRuby.xcframework")
  end

  def teardown
    FileUtils.rm_rf(@dir)
  end

  def test_each_extension_a_slice_lists_is_a_framework_of_that_slices_file
    runtime("fledgerubyext.json.ext.parser.bundle" => "4.1.0/arm64-darwin/json/ext/parser.bundle",
      "fledgerubyext.enc.encdb.bundle" => "4.1.0/arm64-darwin/enc/encdb.bundle")

    frameworks = extensions.frameworks

    assert_equal %w[fledgerubyext.enc.encdb.bundle fledgerubyext.json.ext.parser.bundle], frameworks.keys.sort
    assert_equal SLICES.to_h { |slice| [slice, File.join(@runtime, slice, "lib/ruby/4.1.0/arm64-darwin/json/ext/parser.bundle")] },
      frameworks.fetch("fledgerubyext.json.ext.parser.bundle")
  end

  # 0.17.0's runtime links its extensions into a static library, lists
  # none, and holds no framework of Ruby's own.
  def test_a_runtime_that_lists_no_extensions_has_no_frameworks_and_a_static_ruby
    SLICES.each { |slice| FileUtils.mkdir_p(File.join(@runtime, slice, "lib/ruby")) }

    assert_empty extensions.frameworks
    refute_predicate extensions, :dynamic?
  end

  def test_a_runtime_whose_slices_hold_ruby_as_a_framework_is_dynamic
    runtime({})
    SLICES.each { |slice| FileUtils.mkdir_p(File.join(@runtime, slice, "FledgeRuby.framework")) }

    assert_predicate extensions, :dynamic?
  end

  def test_slices_that_list_different_extensions_are_refused
    runtime("fledgerubyext.etc.bundle" => "4.1.0/arm64-darwin/etc.bundle")
    File.write(File.join(@runtime, "ios-arm64-simulator", "fledge.links"), "fledgerubyext.io.console.bundle\tlib/ruby/4.1.0/arm64-darwin/io/console.bundle\n")

    error = assert_raises(Fledge::Error) { extensions.frameworks }
    assert_equal "the iOS runtime's slices list different extensions: ios-arm64 fledgerubyext.etc.bundle, " \
      "ios-arm64-simulator fledgerubyext.io.console.bundle", error.message
  end

  # OpenSSL's extension carries OpenSSL's own privacy manifest, which
  # the runtime keeps beside its list, out of Ruby's tree.
  def test_an_extension_whose_slices_keep_a_privacy_manifest_has_it_in_its_framework
    runtime("fledgerubyext.openssl.bundle" => "4.1.0/arm64-darwin/openssl.bundle",
      "fledgerubyext.etc.bundle" => "4.1.0/arm64-darwin/etc.bundle")
    SLICES.each do |slice|
      FileUtils.mkdir_p(File.join(@runtime, slice, "privacy"))
      File.write(File.join(@runtime, slice, "privacy", "fledgerubyext.openssl.bundle.xcprivacy"), "<plist/>")
    end

    assert_equal SLICES.to_h { |slice| [slice, File.join(@runtime, slice, "privacy", "fledgerubyext.openssl.bundle.xcprivacy")] },
      extensions.manifests("fledgerubyext.openssl.bundle")
    assert_empty extensions.manifests("fledgerubyext.etc.bundle")
  end

  # A bundled gem's extension is installed twice, in the gem's require
  # path and its extension folder, and both paths lead to one framework.
  def test_each_listed_path_in_each_slice_becomes_a_link_to_its_framework_in_the_app
    runtime("fledgerubyext.etc.bundle" => "4.1.0/arm64-darwin/etc.bundle")
    SLICES.each do |slice|
      path = "lib/ruby/gems/4.1.0/extensions/arm64-darwin/4.1.0/etc/etc.bundle"
      FileUtils.mkdir_p(File.dirname(File.join(@runtime, slice, path)))
      File.write(File.join(@runtime, slice, path), "same bytes")
      File.write(File.join(@runtime, slice, "fledge.links"), "fledgerubyext.etc.bundle\t#{path}\n", mode: "a")
    end

    extensions.link

    SLICES.each do |slice|
      assert_equal "#{'../' * 5}Frameworks/fledgerubyext.etc.bundle.framework/fledgerubyext.etc.bundle",
        File.readlink(File.join(@runtime, slice, "lib/ruby/4.1.0/arm64-darwin/etc.bundle"))
      assert_equal "#{'../' * 9}Frameworks/fledgerubyext.etc.bundle.framework/fledgerubyext.etc.bundle",
        File.readlink(File.join(@runtime, slice, "lib/ruby/gems/4.1.0/extensions/arm64-darwin/4.1.0/etc/etc.bundle"))
    end
  end

  # Ruby's own library is FledgeRuby.framework, which the runtime holds
  # already: its line makes no framework, only the link at libdir/
  # LIBRUBY_SO, where Ruby's install put it and RbConfig names it, as
  # under ruby main.rb.
  def test_rubys_own_library_is_linked_where_rbconfig_names_it_and_is_no_extension
    runtime("fledgerubyext.etc.bundle" => "4.1.0/arm64-darwin/etc.bundle")
    SLICES.each do |slice|
      FileUtils.mkdir_p(File.join(@runtime, slice, "FledgeRuby.framework"))
      File.write(File.join(@runtime, slice, "fledge.links"), "FledgeRuby\tlib/libfledgeruby.dylib\n", mode: "a")
    end

    assert_equal %w[fledgerubyext.etc.bundle], extensions.frameworks.keys
    extensions.link

    SLICES.each do |slice|
      assert_equal "../../Frameworks/FledgeRuby.framework/FledgeRuby", File.readlink(File.join(@runtime, slice, "lib/libfledgeruby.dylib"))
    end
  end

  # Each slice of a runtime written here: its lib/ruby holds a file at
  # each listed path, and its fledge.links names each by its framework.
  private def runtime(listed)
    SLICES.each do |slice|
      FileUtils.mkdir_p(File.join(@runtime, slice))
      lines = listed.map do |name, path|
        at = File.join(@runtime, slice, "lib/ruby", path)
        FileUtils.mkdir_p(File.dirname(at))
        File.write(at, "#{slice} #{name}")
        "#{name}\tlib/ruby/#{path}\n"
      end
      File.write(File.join(@runtime, slice, "fledge.links"), lines.join)
    end
  end

  private def extensions
    Fledge::MobileProject::IOSRubyExtensions.new(@runtime)
  end
end
