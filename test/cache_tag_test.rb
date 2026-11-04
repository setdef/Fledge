# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "test_helper"

# The Cache Directory Tagging Specification's tag, which marks each
# folder fledge build makes for its builds (ADR 005, section 1).
class CacheTagTest < Minitest::Test
  def setup
    @dir = Dir.mktmpdir
  end

  def teardown
    FileUtils.rm_rf(@dir)
  end

  def test_a_folder_the_build_makes_is_tagged_as_the_specification_says
    out = File.join(@dir, "builds/linux")

    Fledge::CacheTag.make_folder(out)

    tag = File.binread(File.join(out, "CACHEDIR.TAG"))
    assert tag.start_with?("Signature: 8a477f597d28d172789f06886806bc55"), tag
    assert_includes tag, "fledge build"
    assert Fledge::CacheTag.tagged?(out)
    refute Fledge::CacheTag.tagged?(File.join(@dir, "builds")), "only the folder builds go to is tagged"
  end

  def test_an_empty_folder_is_tagged_and_a_folder_holding_anything_else_is_left_alone
    empty = File.join(@dir, "empty")
    held = File.join(@dir, "held")
    FileUtils.mkdir_p([empty, held])
    File.write(File.join(held, "notes.txt"), "mine")

    Fledge::CacheTag.make_folder(empty)
    Fledge::CacheTag.make_folder(held)

    assert Fledge::CacheTag.tagged?(empty)
    refute Fledge::CacheTag.tagged?(held)
    assert_equal ["notes.txt"], Dir.children(held)
  end

  def test_a_tag_written_once_stays_as_it_is
    out = File.join(@dir, "dist")
    Fledge::CacheTag.make_folder(out)
    File.write(File.join(out, "CACHEDIR.TAG"), "Signature: 8a477f597d28d172789f06886806bc55\n# Mine.\n")

    Fledge::CacheTag.make_folder(out)

    assert_equal "Signature: 8a477f597d28d172789f06886806bc55\n# Mine.\n", File.read(File.join(out, "CACHEDIR.TAG"))
  end

  def test_only_a_file_beginning_with_the_signature_tags_a_folder
    {
"cargo" => "Signature: 8a477f597d28d172789f06886806bc55\n# created by cargo.\n",
"bare" => "Signature: 8a477f597d28d172789f06886806bc55",
"lower" => "signature: 8a477f597d28d172789f06886806bc55\n",
"short" => "Signature: 8a477f597d28d172789f06886806bc5",
"empty" => "",
}.each do |name, content|
      FileUtils.mkdir_p(File.join(@dir, name))
      File.write(File.join(@dir, name, "CACHEDIR.TAG"), content)
    end
    FileUtils.mkdir_p(File.join(@dir, "folder/CACHEDIR.TAG"))

    tagged = %w[cargo bare lower short empty folder none].select { |name| Fledge::CacheTag.tagged?(File.join(@dir, name)) }

    assert_equal %w[cargo bare], tagged
  end
end
