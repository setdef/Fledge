# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "test_helper"
require_relative "support/gems"

# What a phone app carries of the files a gem's builds left, one for each
# of the phone's targets (Fledge::MobileExtensions::LeftFiles). A gem's
# real package, and its folder as each target's build left it, written
# here; nothing is compiled.
class MobileExtensionsLeftFilesTest < Minitest::Test
  FILES = {
    "lib/tabled.rb" => "require 'tabled/tabled'\n",
    "ext/tabled/extconf.rb" => "create_makefile('tabled/tabled')\n",
  }.freeze

  TARGETS = %w[aarch64-linux-android x86_64-linux-android].freeze

  def setup
    @dir = Dir.mktmpdir
    @package = Fledge::GemPackage.new(FakeGem.build(@dir, "tabled", "1.0.0", files: FILES, extensions: ["ext/tabled/extconf.rb"]).path)
  end

  def teardown
    FileUtils.rm_rf(@dir)
  end

  # Each target's folder, with the gem's own files and what the build
  # wrote for that target: +built+ gives each path's bytes for a target.
  def builds(built)
    TARGETS.map do |target|
      root = File.join(@dir, target, "tabled-1.0.0")
      FILES.merge(built.transform_values { |bytes| bytes.call(target) }).each do |path, content|
        FileUtils.mkdir_p(File.dirname(File.join(root, path)))
        File.binwrite(File.join(root, path), content)
      end
      Fledge::MobileExtensions::LeftFiles.of(@package, root)
    end
  end

  def carried(built)
    Fledge::MobileExtensions::LeftFiles.common(builds(built)).to_h { |entry| [entry.path, entry.content] }
  end

  # Data an extconf.rb writes alike for every target is carried at its
  # path, where the gem's Ruby reads it under bundle exec; a file the
  # build rewrote among the gem's own too.
  def test_what_every_targets_build_left_alike_is_carried
    assert_equal({ "data/table.txt" => "from the build\n", "lib/tabled.rb" => "require 'tabled/tabled'\nTABLE = 1\n" },
      carried("data/table.txt" => -> (_) { "from the build\n" }, "lib/tabled.rb" => -> (_) { "require 'tabled/tabled'\nTABLE = 1\n" }))
  end

  # A file one target's build wrote is not that file for another: a
  # Makefile names its target's compiler, so no target's is carried.
  def test_what_the_targets_builds_left_differently_is_not_carried
    assert_empty carried("ext/tabled/Makefile" => -> (target) { "CC = #{target}26-clang\n" })
  end

  # A phone runs compiled code only from the app's executable, its
  # frameworks, or its native libraries: an object, an archive, or a
  # library is not carried among the gem's files, even when every target
  # left it alike, as a build script compiled for this computer is.
  def test_compiled_code_is_not_carried
    compiled = {
      "ext/tabled/tabled.o" => -> (_) { "\x7FELF\x02\x01\x01".b },
      "ext/tabled/tabled.a" => -> (_) { "!<arch>\ntabled.o/".b },
      "target/release/build-script-build" => -> (_) { [0xCF, 0xFA, 0xED, 0xFE, 7, 0, 0, 1].pack("C*") },
    }

    assert_empty carried(compiled)
  end

  # Fledge's own report of an extension's build is not the gem's build's.
  def test_the_files_fledges_build_writes_are_not_carried
    assert_empty carried("ext/tabled/fledge-report.json" => -> (_) { "[]" }, "ext/tabled/fledge-rust.mk" => -> (_) { "include Makefile\n" })
  end
end
