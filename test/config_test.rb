# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "test_helper"

class ConfigTest < Minitest::Test
  def load(yaml)
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "fledge.yml"), yaml) if yaml
      Fledge::Config.load(dir)
    end
  end

  def test_no_file_is_no_configuration
    assert_equal Fledge::Config.none, load(nil)
    assert_equal Fledge::Config.none, load("")
    assert_equal Fledge::Config.none, load("# only a comment\n")
  end

  def test_reads_a_name_and_license_corrections
    config = load("name: CoolApp\nlicenses:\n  unlabeled: MIT\n  other: Apache-2.0 OR MIT\n")

    assert_equal "CoolApp", config.name
    assert_equal({ "unlabeled" => "MIT", "other" => "Apache-2.0 OR MIT" }, config.licenses)
  end

  # What a native gem's compiled files hold, as cargo-deny's clarify says
  # what a crate is: each library, its license, and, for one that ships
  # as its own shared library, which file it is and where its source is.
  def test_reads_what_native_gems_compile_in
    config = load(<<~YAML)
      compiled:
        own_only: []
        vendors:
          - name: libfoo 1.2
            license: MIT
          - name: GNU libiconv 1.18
            license: LGPL-2.1-or-later
            shared_library: lib/libiconv.so.2
            source: https://ftp.gnu.org/pub/gnu/libiconv/libiconv-1.18.tar.gz
    YAML

    assert_equal [], config.compiled.fetch("own_only")
    assert_equal [
      Fledge::Config::Compiled.new(name: "libfoo 1.2", license: "MIT", shared_library: nil, source: nil),
      Fledge::Config::Compiled.new(name: "GNU libiconv 1.18", license: "LGPL-2.1-or-later", shared_library: "lib/libiconv.so.2",
        source: "https://ftp.gnu.org/pub/gnu/libiconv/libiconv-1.18.tar.gz"),
    ], config.compiled.fetch("vendors")
    assert_empty load("name: X\n").compiled
  end

  def test_refuses_what_it_cannot_use
    compiled = /: compiled must map gem names to lists of what their compiled code holds, such as compiled: \{some_gem: \[\{name: libfoo 1\.2, license: MIT\}\]\}/
    {
      "name: [" => /is not valid YAML/,
      "- name" => /must be a mapping of name, licenses, and compiled\z/,
      "nmae: x\n" => /has 'nmae', which Fledge does not know\. It knows name, licenses, and compiled\.\z/,
      "compiled: MIT\n" => compiled,
      "compiled:\n  gem: MIT\n" => compiled,
      "compiled:\n  gem:\n    - name: libfoo\n" => compiled,
      "compiled:\n  gem:\n    - {name: libfoo, license: MIT, version: 1}\n" => compiled,
      "name: 3\n" => /: name must be text, such as name: MyCoolApp\z/,
      "licenses: MIT\n" => /: licenses must map gem names to SPDX license expressions/,
      "licenses:\n  gem: ''\n" => /: licenses must map gem names to SPDX license expressions/,
    }.each do |yaml, message|
      error = assert_raises(Fledge::Error, yaml) { load(yaml) }
      assert_match message, error.message, yaml
      assert_includes error.message, "fledge.yml", yaml
    end
  end
end
