# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "../test_helper"
require "open3"
require "yaml"

# .github/scripts/ruby-pin.sh, which tells CI's setup which Ruby to
# install, run as a shell script; the rest of the contributor tools'
# pins are test/contributor_tools_test.rb's.
class RubyPinTest < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)

  def test_ruby_pin_reads_the_pin_and_takes_head_on_windows_for_a_preview
    script = File.join(ROOT, ".github", "scripts", "ruby-pin.sh")
    version = YAML.safe_load_file(File.join(ROOT, "runtime", "sources.yml")).dig("ruby", "version")
    { "Linux" => version, "Windows" => "head" }.each do |os, expected|
      out, status = Open3.capture2({ "RUNNER_OS" => os }, "sh", script, chdir: ROOT)

      assert status.success?, "ruby-pin.sh failed on #{os}"
      assert_equal "#{expected}\n", out
    end
  end
end
