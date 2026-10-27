# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "test_helper"
require_relative "support/binaries"

# What Fledge::CompiledCode finds in a gem's compiled files (ADR 005,
# section 7): binaries written byte for byte as each format specifies
# (test/support/binaries.rb), with the strings that mark a vendored
# library planted in them, judged against a small map and against the
# map Fledge ships.
class CompiledCodeTest < Minitest::Test
  # libiconv's own charset names, which only its code holds.
  ICONV = "UCS-4-INTERNAL MULELAO-1"

  MAP = {
    "copyleft" => [{ "library" => "GNU libiconv", "license" => "LGPL-2.1-or-later", "bytes" => %w[UCS-4-INTERNAL MULELAO-1] }],
    "toolchain" => [{ "name" => "GCC's runtime library", "license" => "GPL-3.0-or-later WITH GCC-exception-3.1", "evidence" => "GCC: (" }],
    "gems" => {
      "vendors" => {
        "holds" => [
          { "name" => "libvendored", "license" => "MIT", "evidence" => "libvendored 1.0" },
          { "name" => "libmaybe", "license" => "Zlib", "evidence" => "libmaybe 2.0" },
        ],
        "advice" => "Its builds for Linux compile in no libiconv.",
      },
    },
  }.freeze

  def audit(name, files, declared: {}, map: Fledge::CompiledCode::Map.from(MAP))
    Fledge::CompiledCode.new(declared:, map:).audit(name, files, label: "#{name} 1.0.0 (x86_64-linux-gnu)")
  end

  def declared(name, *components)
    { name => components.map { |component| Fledge::Config::Compiled.new(shared_library: nil, source: nil, **component) } }
  end

  def test_a_gem_without_compiled_code_holds_nothing_to_judge
    result = audit("plain", { "lib/plain.rb" => "puts 'ELF'\n", "LICENSE" => "MIT\n" })

    assert_equal [[], []], [result.components, result.problems]
  end

  def test_compiled_code_no_one_reviewed_says_how_to_declare_it
    result = audit("mystery", { "lib/mystery.so" => Binaries.elf(needed: ["libc.so.6"]), "lib/other.so" => Binaries.elf })

    assert_equal 1, result.problems.size
    problem = result.problems.first
    assert_includes problem, "mystery 1.0.0 (x86_64-linux-gnu) ships compiled code (lib/mystery.so and lib/other.so) that Fledge has not reviewed"
    assert_includes problem, "compiled: {mystery: [{name: libfoo 1.2, license: MIT}]}"
    assert_includes problem, "compiled: {mystery: []}"
  end

  def test_a_declared_gem_ships_what_fledge_yml_says_it_holds
    result = audit("mystery", { "lib/mystery.so" => Binaries.elf(payload: "libfoo 1.2") },
      declared: declared("mystery", name: "libfoo 1.2", license: "BSD-3-Clause"))

    assert_empty result.problems
    component = result.components.first
    assert_equal ["libfoo 1.2", "BSD-3-Clause", ["lib/mystery.so"], false, true],
      [component.name, component.license, component.files, component.shared, component.declared]
    assert_empty audit("mystery", { "lib/mystery.so" => Binaries.elf }, declared: { "mystery" => [] }).problems,
      "an empty list says the code is the gem's own alone"
  end

  def test_the_map_lists_each_library_where_its_evidence_is
    result = audit("vendors", { "lib/a.so" => Binaries.elf(payload: "libvendored 1.0"), "lib/b.so" => Binaries.elf(payload: "GCC: (GNU) 13") })

    assert_empty result.problems
    assert_equal({ "libvendored" => ["lib/a.so"], "GCC's runtime library" => ["lib/b.so"] },
      result.components.to_h { |component| [component.name, component.files] })
    refute_predicate result.components.first, :declared
  end

  def test_lgpl_code_compiled_into_a_gems_file_cannot_ship_even_when_declared
    files = { "lib/vendors.so" => Binaries.elf(payload: "libvendored 1.0 #{ICONV}"), "lib/old/vendors.so" => Binaries.elf(payload: ICONV) }

    [audit("vendors", files), audit("vendors", files, declared: declared("vendors", name: "GNU libiconv", license: "LGPL-2.1-or-later"))]
      .each do |result|
        problem = result.problems.find { |candidate| candidate.include?("GNU libiconv's code") }
        refute_nil problem, result.problems.inspect
        assert_includes problem, "vendors 1.0.0 (x86_64-linux-gnu) compiles GNU libiconv's code (LGPL-2.1-or-later) into " \
          "lib/old/vendors.so and lib/vendors.so"
        assert_includes problem, "only as a separate shared library that a person can replace"
      end
    assert_includes audit("vendors", files).problems.first, "Its builds for Linux compile in no libiconv."
  end

  def test_a_declared_copyleft_library_compiled_in_cannot_ship
    result = audit("mystery", { "lib/mystery.so" => Binaries.elf },
      declared: declared("mystery", name: "libreadline 8", license: "GPL-3.0-or-later"))

    assert_equal 1, result.problems.size
    assert_includes result.problems.first, "fledge.yml says mystery 1.0.0 (x86_64-linux-gnu) compiles in libreadline 8 (GPL-3.0-or-later)"
  end

  # An LGPL library in its own file, which another of the gem's files
  # loads, is replaceable, so it ships once fledge.yml says where its
  # source is.
  def test_an_lgpl_shared_library_ships_with_its_source
    files = { "lib/ext.so" => Binaries.elf(needed: %w[libiconv.so.2 libc.so.6]), "lib/libiconv.so.2" => Binaries.elf(payload: ICONV) }
    iconv = { name: "GNU libiconv 1.18", license: "LGPL-2.1-or-later", shared_library: "lib/libiconv.so.*" }
    source = "https://ftp.gnu.org/pub/gnu/libiconv/libiconv-1.18.tar.gz"

    result = audit("mystery", files, declared: declared("mystery", { name: "the gem's own code", license: "MIT" }, iconv.merge(source:)))

    assert_empty result.problems
    shared = result.components.find(&:shared)
    assert_equal ["GNU libiconv 1.18", ["lib/libiconv.so.2"], source], [shared.name, shared.files, shared.source]
    assert_equal ["lib/ext.so"], result.components.find { |component| component.name == "the gem's own code" }.files

    without_source = audit("mystery", files, declared: declared("mystery", iconv))
    assert_includes without_source.problems.join("\n"), "give where its source is, under source"
    undeclared = audit("mystery", files, declared: { "mystery" => [] })
    assert_includes undeclared.problems.join("\n"), "If lib/libiconv.so.2 is GNU libiconv's own shared library"
  end

  def test_a_shared_library_no_other_file_loads_is_not_replaceable
    files = { "lib/ext.so" => Binaries.elf(needed: ["libc.so.6"]), "lib/libiconv.so.2" => Binaries.elf(payload: ICONV) }
    iconv = { name: "GNU libiconv", license: "LGPL-2.1-or-later", shared_library: "lib/libiconv.so.2", source: "https://example.com/iconv.tar.gz" }

    result = audit("mystery", files, declared: declared("mystery", iconv))

    assert_includes result.problems.join("\n"), "no other compiled file of mystery 1.0.0 (x86_64-linux-gnu) loads lib/libiconv.so.2"
    missing = audit("mystery", { "lib/ext.so" => Binaries.elf }, declared: declared("mystery", iconv))
    assert_includes missing.problems.join("\n"), "has no compiled file lib/libiconv.so.2"
  end

  # A Mach-O extension names its library by a path relative to itself,
  # and a PE by a file name in any case.
  def test_a_library_is_loaded_by_its_file_name_in_every_format
    iconv = { name: "GNU libiconv", license: "LGPL-2.1-or-later", source: "https://example.com/iconv.tar.gz" }
    {
      "macho" => {
"lib/ext.bundle" => Binaries.macho(needed: ["@loader_path/../ports/libiconv.2.dylib"]),
"ports/libiconv.2.dylib" => Binaries.macho(payload: ICONV),
},
      "pe" => { "lib/ext.so" => Binaries.pe(needed: ["LIBICONV-2.DLL"]), "bin/libiconv-2.dll" => Binaries.pe(payload: ICONV) },
    }.each do |format, files|
      library = files.keys.last
      result = audit("mystery", files, declared: declared("mystery", iconv.merge(shared_library: library)))

      assert_empty result.problems, format
    end
  end

  def test_fledge_ships_a_map_whose_libraries_it_may_ship
    map = Fledge::CompiledCode.map

    map.gems.each do |gem, entry|
      [*entry.holds, *map.toolchain].each do |library|
        assert Fledge::LicensePolicy.notice_only?(library.license), "#{gem}: #{library.name}"
      end
    end
    map.copyleft.each do |signature|
      refute Fledge::LicensePolicy.notice_only?(signature.license), signature.library
      refute_empty signature.bytes
    end
    assert_equal %w[ffi google-protobuf nokogiri pg prism sqlite3], map.gems.keys.sort
    assert_raises(Fledge::Error) { Fledge::CompiledCode::Map.from({ "copyleft" => [{ "library" => "x" }] }) }
  end
end
