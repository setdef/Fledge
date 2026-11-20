# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "test_helper"
require_relative "../tasks/licensing_page"

# doc/licensing.md from what runtime/audited.yml records of the runtimes,
# and the repository, with no runtime: so a change that would leave the
# page stale (Fledge's version, a word of runtime/licenses.yml, the
# generator's prose) fails here, before a push, and not an hour later in
# CI's "Licensing page is current" job, which audits the real runtimes.
# test/integration/licensing_page_test.rb audits runtime archives.
class LicensingPageTest < Minitest::Test
  def findings
    @findings ||= LicensingPage.load
  end

  def page(found = findings, version: "9.8.7", map: LicenseAudit::MAP)
    LicensingPage.new(found, version:, map:)
  end

  def section(text, title)
    text[/^## #{Regexp.escape(title)}\n.*?(?=^## )/m].to_s
  end

  def linux(text)
    section(text, LicensingPage::TITLES.fetch("x86_64-linux"))
  end

  # The page from the map as the block changes it, in a file of its own.
  def with_map
    map = YAML.safe_load_file(LicenseAudit::MAP)
    yield map
    Dir.mktmpdir do |directory|
      path = File.join(directory, "licenses.yml")
      File.write(path, YAML.dump(map))
      return page(map: path).text
    end
  end

  def change(platform, **fields)
    findings.merge(platform => findings.fetch(platform).with(**fields))
  end

  def test_the_page_and_runtime_audited_yml_are_what_the_generator_writes
    LicensingPage.files(findings).each do |path, expected|
      committed = File.read(path)
      line = committed.lines.zip(expected.lines).index { |have, want| have != want }
      assert committed == expected, "#{path.delete_prefix("#{LicenseAudit::ROOT}/")} is stale from line #{line.to_i + 1}: " \
        "run mise x -- bundle exec rake licensing and commit what it writes (doc/contributors/design/license-audit.md, \"The licensing page\")"
    end
  end

  def test_the_page_names_fledges_version_wherever_it_names_a_release_asset
    text = page.text

    assert_includes text, "for Fledge 9.8.7, every third-party component"
    assert_includes linux(text), "`fledge-runtime-9.8.7-x86_64-linux-lgpl-sources.tar.gz`"
    refute_includes text, Fledge::VERSION
  end

  def test_the_maps_words_for_a_component_reach_every_platform_that_holds_it
    text = with_map { |map| map.fetch("components").find { |entry| entry.fetch("id") == "libxcrypt" }["ships"] = "a library of its own, renamed" }

    assert_includes linux(text), "| `LGPL-2.1-or-later` | a library of its own, renamed |"
    refute_includes section(text, LicensingPage::TITLES.fetch("arm64-darwin")), "renamed"
  end

  def test_a_component_the_runtime_lacks_has_no_row_and_one_newly_mapped_has_one
    lacking = linux(page(change("x86_64-linux", absent: [*findings.fetch("x86_64-linux").absent, "zlib"])).text)
    mapped = linux(with_map do |map|
      zlib = map.fetch("components").find { |entry| entry.fetch("id") == "zlib" }
      map.fetch("components") << Marshal.load(Marshal.dump(zlib)).merge("id" => "zlib-new", "name" => "zlib, newly mapped")
    end)

    refute_includes lacking, "| zlib, compiled into"
    assert_includes mapped, "| zlib, newly mapped |"
  end

  def test_the_maps_correction_of_a_gems_license_wins_over_what_its_specification_declares
    name = findings.fetch("x86_64-linux").gems.keys.first
    text = with_map { |map| map.fetch("gems")[name] = { "license" => "MIT-0" } }

    assert_includes linux(text), "- `MIT-0`: #{name}\n"
  end

  def test_what_the_map_no_longer_asks_of_the_findings_drops_out_of_runtime_audited_yml
    found = findings.fetch("x86_64-linux")
    changed = change("x86_64-linux", absent: [*found.absent, "no-such-component"], files: found.files.merge("zlib" => ["lib/libz.so"]))

    assert_equal page.audited, page(changed).audited
  end

  def test_findings_that_lack_what_only_a_runtime_can_say_name_what_to_do
    found = findings.fetch("x86_64-linux")
    missing = [findings.except("android"), change("x86_64-linux", files: found.files.except("libxcrypt"))]

    messages = missing.map { |each| assert_raises(RuntimeError) { page(each).text }.message }

    assert_includes messages[0], "runtime/audited.yml records no runtime for android"
    assert_includes messages[1], "runtime/audited.yml names no files of libxcrypt on x86_64-linux"
    messages.each { |message| assert_includes message, "bundle exec rake \"licensing[DIR]\"" }
  end
end
