# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "test_helper"
require_relative "../tasks/ruby_header"

# The rules the gate's normalizer (rake reuse:normalize_ruby) rewrites a
# Ruby file's header by, and the check that reports a file it would
# rewrite, which bin/check runs before a push.
class RubyHeaderTest < Minitest::Test
  UNWRAPPED = <<~RUBY
    # frozen_string_literal: true

    # SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
    # SPDX-License-Identifier: MIT

    puts 1
  RUBY

  WRAPPED = <<~RUBY
    # frozen_string_literal: true

    #--
    # SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
    # SPDX-License-Identifier: MIT
    #++

    puts 1
  RUBY

  def test_a_header_without_the_wrapping_lines_is_reported_and_a_wrapped_one_is_not
    in_tree("a.rb" => UNWRAPPED, "b.rb" => WRAPPED) do |root|
      problems = RubyHeader.check(root, %w[a.rb b.rb])

      assert_equal 1, problems.size
      assert_match(/\Aa\.rb: /, problems.first)
      assert_includes problems.first, "#--"
      assert_includes problems.first, "mise x -- bundle exec rake reuse:normalize_ruby"
    end
  end

  def test_a_header_with_no_empty_line_after_the_closing_line_is_reported
    in_tree("a.rb" => WRAPPED.sub("#++\n\n", "#++\n")) do |root|
      assert_match(/\Aa\.rb: /, RubyHeader.check(root, %w[a.rb]).first)
    end
  end

  def test_checking_writes_nothing
    in_tree("a.rb" => UNWRAPPED) do |root|
      RubyHeader.check(root, %w[a.rb])

      assert_equal UNWRAPPED, File.read(File.join(root, "a.rb"))
    end
  end

  def test_fixing_writes_the_wrapped_header_and_then_the_check_passes
    in_tree("a.rb" => UNWRAPPED) do |root|
      assert_equal %w[a.rb], RubyHeader.fix(root, %w[a.rb])
      assert_equal WRAPPED, File.read(File.join(root, "a.rb"))
      assert_empty RubyHeader.check(root, %w[a.rb])
    end
  end

  def test_a_file_without_an_spdx_header_is_left_alone
    in_tree("a.rb" => "puts 1\n") do |root|
      assert_empty RubyHeader.check(root, %w[a.rb])
    end
  end

  def test_only_ruby_files_outside_vendor_tmp_dist_and_dot_folders_are_among_the_files
    paths = %w[a.rb b.rake c.gemspec d.md vendor/e.rb tmp/f.rb dist/g.rb .h/i.rb lib/j.rb]

    assert_equal %w[a.rb b.rake c.gemspec lib/j.rb], RubyHeader.among(paths)
  end

  private def in_tree(files)
    Dir.mktmpdir do |root|
      files.each { |path, content| File.write(File.join(root, path), content) }
      yield root
    end
  end
end
