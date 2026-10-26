# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "test_helper"
require_relative "../tasks/runtime_builder"

# The parts of rake runtime that need no compiler: the pins it reads, the
# pruning it does, and the notices it writes. CI's runtime jobs build real
# runtimes, and test/built_app_test.rb runs them.
class RuntimeBuilderTest < Minitest::Test
  def builder(name)
    RuntimeBuilder.new(platform: Fledge::Platform.find(name))
  end

  def test_every_platform_pins_an_rv_ruby_build_by_sha256
    pins = builder("x86_64-linux").sources.fetch("ruby").fetch("platforms")

    assert_equal Fledge::Platform.names.sort, pins.keys.sort
    pins.each_value do |pin|
      assert_match(%r{\Ahttps://github\.com/spinel-coop/rv-ruby/releases/download/20261023/ruby-4\.0\.9\.}, pin.fetch("url"))
      assert_match(/\A\h{64}\z/, pin.fetch("sha256"))
    end
  end

  def test_libxcrypt_is_pinned_by_sha256
    pin = builder("x86_64-linux").sources.fetch("libxcrypt")

    assert_match(/\A\h{64}\z/, pin.fetch("sha256"))
    assert_match(%r{\Ahttps://}, pin.fetch("url"))
  end

  def test_linux_carries_the_notices_of_what_it_links_statically_and_macos_does_not
    linux = builder("aarch64-linux").notices.map { |notice| notice.fetch("folder") }
    darwin = builder("arm64-darwin").notices.map { |notice| notice.fetch("folder") }

    assert_equal %w[fledge ruby rust openssl libyaml ca-certificates zlib libxcrypt], linux
    assert_equal %w[fledge ruby rust openssl libyaml ca-certificates], darwin
  end

  def test_every_notice_folder_has_its_license_texts
    builder("x86_64-linux").sources.fetch("notices").each do |notice|
      next if notice.fetch("folder") == "fledge"

      refute_empty Dir.glob(File.join(RuntimeBuilder::ROOT, "runtime/notices", notice.fetch("folder"), "*")), notice.fetch("folder")
    end
  end

  def test_write_notices_copies_each_and_indexes_them
    Dir.mktmpdir do |stage|
      builder("x86_64-linux").write_notices(stage)

      assert_equal %w[README.txt ca-certificates fledge libxcrypt libyaml openssl ruby rust zlib], Dir.children(File.join(stage, "notices")).sort
      assert_path_exists File.join(stage, "notices/fledge/AGPL-3.0-or-later.txt")
      assert_path_exists File.join(stage, "notices/libxcrypt/COPYING.LIB")
      index = File.read(File.join(stage, "notices/README.txt"))
      assert_includes index, "libxcrypt/\n  libxcrypt 4.5.2"
      assert_includes index, "License: LGPL-2.1-or-later\n  Source: https://github.com/besser82/libxcrypt/releases/download/v4.5.2/libxcrypt-4.5.2.tar.xz"
    end
  end

  def test_prune_keeps_the_standard_library_and_default_gems_and_drops_the_rest
    Dir.mktmpdir do |ruby|
      files = %w[
        4.0.0/json.rb
        4.0.0/arm64-darwin23/json/ext/parser.bundle
        4.0.0/arm64-darwin23/json/ext/parser.bundle.dSYM/Contents/Info.plist
        4.0.0/arm64-darwin23/portable_ruby_gems.rb
        4.0.0/arm64-darwin23/stray.a
        gems/4.0.0/specifications/default/json-2.18.0.gemspec
        gems/4.0.0/specifications/csv-3.3.5.gemspec
        gems/4.0.0/gems/bundler-4.0.20/exe/bundle
        gems/4.0.0/gems/csv-3.3.5/lib/csv.rb
        gems/4.0.0/cache/csv-3.3.5.gem
        gems/4.0.0/extensions/arm64-darwin-23/4.0.0-static/bigdecimal-4.0.1/bigdecimal.bundle
        gems/4.0.0/doc/x
        gems/4.0.0/build_info/x
        gems/4.0.0/plugins/rdoc_plugin.rb
      ]
      FileUtils.touch(File.join(ruby, "x"))
      files.each do |file|
        FileUtils.mkdir_p(File.dirname(File.join(ruby, file)))
        FileUtils.touch(File.join(ruby, file))
      end
      FileUtils.mkdir_p(File.join(ruby, "gems/4.0.0/specifications/default"))
      File.write(File.join(ruby, "gems/4.0.0/specifications/default/bundler-4.0.20.gemspec"), "")

      RuntimeBuilder.prune(ruby)

      kept = Dir.glob("**/*", base: ruby).select { |path| File.file?(File.join(ruby, path)) }.sort
      assert_equal %w[
        4.0.0/arm64-darwin23/json/ext/parser.bundle
        4.0.0/json.rb
        gems/4.0.0/gems/bundler-4.0.20/exe/bundle
        gems/4.0.0/specifications/default/bundler-4.0.20.gemspec
        gems/4.0.0/specifications/default/json-2.18.0.gemspec
        x
      ], kept
    end
  end

  def test_the_runtime_is_named_for_this_fledge_version_and_platform
    assert_equal "fledge-runtime-#{Fledge::VERSION}-aarch64-linux", builder("aarch64-linux").top
  end

  def test_a_runtime_builds_only_on_its_own_platform
    other = (Fledge::Platform.names - [Fledge::Platform.local.name]).first.to_s

    error = assert_raises(RuntimeError) { builder(other).call }
    assert_match(/runtimes build on #{other} only/, error.message)
  rescue Fledge::Error
    skip "this computer has no runtime platform"
  end
end
