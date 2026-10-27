# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "test_helper"
require "json"
require "open3"

# What a gem's Rust extension compiled in, read from cargo's own account
# of the build (cargo metadata, from the build's Cargo.lock), so each
# crate's license meets Fledge's policy (ADR 006).
class RustCratesTest < Minitest::Test
  def package(name, version, license, manifest = "/registry/#{name}-#{version}/Cargo.toml", kind: "lib")
    {
"id" => "#{name} #{version}",
"name" => name,
"version" => version,
"license" => license,
"manifest_path" => manifest,
"targets" => [{ "kind" => [kind] }],
}
  end

  def node(id, *deps)
    { "id" => id, "deps" => deps.map { |pkg, kind| { "pkg" => pkg, "dep_kinds" => [{ "kind" => kind, "target" => nil }] } } }
  end

  # The crates the extension's own crate reaches by normal dependencies
  # are compiled into it; those it reaches only through build
  # dependencies, or through a procedural macro, ran while it compiled;
  # those only its tests use are neither.
  def test_reads_what_the_extension_compiled_in_and_what_only_built_it
    data = {
      "packages" => [
        package("ext", "0.1.0", "MIT", "/gem/ext/ext/Cargo.toml"),
        package("idna", "1.1.0", "MIT/Apache-2.0"),
        package("icu", "2.4.0", "Unicode-3.0"),
        package("bindgen", "0.72.1", "BSD-3-Clause"),
        package("criterion", "0.5.0", "MIT"),
        package("mystery", "0.1.0", nil),
        package("derive", "1.0.0", "MIT", kind: "proc-macro"),
        package("syn", "2.0.0", "MIT"),
],
      "resolve" => {
"root" => nil,
"nodes" => [
  node("ext 0.1.0", ["idna 1.1.0", nil], ["bindgen 0.72.1", "build"], ["criterion 0.5.0", "dev"], ["derive 1.0.0", nil]),
  node("idna 1.1.0", ["icu 2.4.0", nil]),
  node("icu 2.4.0"),
  node("bindgen 0.72.1", ["mystery 0.1.0", nil]),
  node("criterion 0.5.0"),
  node("mystery 0.1.0"),
  node("derive 1.0.0", ["syn 2.0.0", nil]),
  node("syn 2.0.0"),
],
},
    }

    crates = Fledge::RustCrates.from_metadata(data, "/gem/ext/ext/Cargo.toml")

    assert_equal [["Rust crate ext 0.1.0", "MIT"], ["Rust crate icu 2.4.0", "Unicode-3.0"], ["Rust crate idna 1.1.0", "MIT OR Apache-2.0"]],
      crates.compiled.map { |crate| [crate.name, crate.license] }
    assert_equal [
      ["Rust crate bindgen 0.72.1", "BSD-3-Clause"],
      ["Rust crate derive 1.0.0", "MIT"],
      ["Rust crate mystery 0.1.0", "NOASSERTION"],
      ["Rust crate syn 2.0.0", "MIT"],
], crates.build.map { |crate| [crate.name, crate.license] }
  end

  def test_a_manifest_cargo_does_not_describe_is_refused
    error = assert_raises(Fledge::Error) { Fledge::RustCrates.from_metadata({ "packages" => [], "resolve" => { "nodes" => [] } }, "/x/Cargo.toml") }

    assert_includes error.message, "/x/Cargo.toml"
  end

  # cargo itself, on a workspace whose crate depends on another by path.
  def test_asks_cargo_about_a_real_workspace
    skip "no cargo on PATH" unless system("cargo", "--version", out: File::NULL, err: File::NULL)

    Dir.mktmpdir do |dir|
      {
"ext/Cargo.toml" => "[package]\nname = \"ext\"\nversion = \"0.1.0\"\nedition = \"2021\"\nlicense = \"MIT\"\n\n" \
  "[dependencies]\nhelper = { path = \"../helper\" }\n",
"ext/src/lib.rs" => "",
"helper/src/lib.rs" => "",
"helper/Cargo.toml" => "[package]\nname = \"helper\"\nversion = \"0.2.0\"\nedition = \"2021\"\nlicense = \"Apache-2.0\"\n",
}
        .each do |path, content|
          FileUtils.mkdir_p(File.dirname(File.join(dir, path)))
          File.write(File.join(dir, path), content)
        end
      manifest = File.join(dir, "ext", "Cargo.toml")
      _, status = Open3.capture2e("cargo", "generate-lockfile", "--offline", "--manifest-path", manifest)
      assert_predicate status, :success?

      crates = Fledge::RustCrates.new(manifest, target: Fledge::Platform.find("x86_64-linux").rust_target).call(label: "ext 0.1.0")

      assert_equal [["Rust crate ext 0.1.0", "MIT"], ["Rust crate helper 0.2.0", "Apache-2.0"]],
        crates.compiled.map { |crate| [crate.name, crate.license] }
      assert_empty crates.build
    end
  end
end
