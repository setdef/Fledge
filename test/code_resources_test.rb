# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "test_helper"
require "digest"

# What codesign --sign - wrote on macOS 15 for a bundle holding these
# files, a link, a localized file, and a .DS_Store is what the seal must
# list: SHA-1s of the files under Resources/ (a .DS_Store among them) in
# files, and in files2 the SHA-256 of each file, the target of each link,
# and no .DS_Store.
class CodeResourcesTest < Minitest::Test
  def seal(*entries)
    resources = Fledge::CodeResources.new
    entries.each { |entry| resources.add(entry) }
    resources.bytes
  end

  def data(bytes)
    "<data>#{[bytes].pack('m0')}</data>"
  end

  def section(plist, key)
    plist[%r{\t<key>#{key}</key>\n\t<dict>\n(.*?)\n\t</dict>}m, 1].to_s
  end

  def test_lists_files_links_and_localized_files_as_codesign_does
    plist = seal(
      Fledge::Entry.directory("Resources"),
      Fledge::Entry.file("Resources/a.txt", "hi\n"),
      Fledge::Entry.symlink("Resources/link", "a.txt"),
      Fledge::Entry.file("Resources/en.lproj/x.strings", "l\n"),
      Fledge::Entry.file("Resources/.DS_Store", "d\n"),
      Fledge::Entry.symlink("MacOS/lib", "../Resources/lib"),
      Fledge::Entry.file("Info.plist", "<plist/>"),
    )

    files = section(plist, "files")
    assert_includes files, "<key>Resources/a.txt</key>\n\t\t#{data(Digest::SHA1.digest("hi\n"))}"
    assert_includes files, "<key>Resources/.DS_Store</key>"
    assert_includes files, "<key>Resources/en.lproj/x.strings</key>\n\t\t<dict>\n\t\t\t<key>hash</key>\n\t\t\t#{data(Digest::SHA1.digest("l\n"))}\n\t\t\t<key>optional</key>\n\t\t\t<true/>"
    refute_includes files, "link"
    refute_includes files, "Info.plist"

    files2 = section(plist, "files2")
    assert_includes files2, "<key>Resources/a.txt</key>\n\t\t<dict>\n\t\t\t<key>hash2</key>\n\t\t\t#{data(Digest::SHA256.digest("hi\n"))}"
    assert_includes files2, "<key>Resources/link</key>\n\t\t<dict>\n\t\t\t<key>symlink</key>\n\t\t\t<string>a.txt</string>"
    assert_includes files2, "<key>MacOS/lib</key>\n\t\t<dict>\n\t\t\t<key>symlink</key>\n\t\t\t<string>../Resources/lib</string>"
    assert_includes files2, "<key>optional</key>"
    refute_includes files2, ".DS_Store"
    refute_includes files2, "Info.plist"
    assert_includes plist, "<key>^(Frameworks|SharedFrameworks|PlugIns|Plug-ins|XPCServices|Helpers|MacOS|Library/(Automator|Spotlight|LoginItems))/</key>"
  end

  def test_picks_the_rule_of_greatest_weight
    rules = Fledge::CodeResources::RULES2
    assert_equal({ "omit" => true, "weight" => 2000.0 }, Fledge::CodeResources.rule(rules, "Resources/x/.DS_Store"))
    assert_equal({ "weight" => 20.0 }, Fledge::CodeResources.rule(rules, "Resources/lib/x.rb"))
    assert_equal({ "nested" => true, "weight" => 10.0 }, Fledge::CodeResources.rule(rules, "MacOS/helper"))
    assert_equal({}, Fledge::CodeResources.rule(rules, "other/file"))
    assert_nil Fledge::CodeResources.rule(Fledge::CodeResources::RULES, "MacOS/helper")
  end

  def test_refuses_a_file_where_code_with_its_own_signature_belongs
    error = assert_raises(Fledge::Error) { seal(Fledge::Entry.file("MacOS/helper", "code")) }
    assert_equal "MacOS/helper is where a bundle keeps code with its own signature, which Fledge does not sign", error.message
  end
end
