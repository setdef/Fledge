# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "test_helper"
require "open3"
require "tmpdir"

# .github/scripts/runner-apt-update.sh tolerates a failed apt-get update on
# a GitHub runner only when at least one error names packages.microsoft.com
# and no error or warning names anything else. Each test runs the script
# with a stand-in sudo first on PATH, which prints what the case gives it
# and exits with the case's status.
class RunnerAptUpdateTest < Minitest::Test
  SCRIPT = File.expand_path("../.github/scripts/runner-apt-update.sh", __dir__)

  MICROSOFT = <<~APT
    E: Failed to fetch https://packages.microsoft.com/ubuntu/24.04/prod/dists/noble/InRelease  403  Forbidden [IP: 13.107.246.40 443]
    E: The repository 'https://packages.microsoft.com/ubuntu/24.04/prod noble InRelease' is no longer signed.
  APT

  UBUNTU = <<~APT
    E: Failed to fetch http://archive.ubuntu.com/ubuntu/dists/noble/InRelease  403  Forbidden [IP: 91.189.91.82 80]
  APT

  def test_succeeds_when_apt_succeeds
    status, output = run_script("Reading package lists...\n", 0)

    assert_equal 0, status
    assert_includes output, "Reading package lists..."
  end

  def test_tolerates_a_failure_whose_errors_all_name_packages_microsoft_com
    status, output = run_script(MICROSOFT, 100)

    assert_equal 0, status
    assert_includes output, "no longer signed"
  end

  def test_fails_when_an_ubuntu_archive_error_comes_with_the_microsoft_ones
    status, = run_script(MICROSOFT + UBUNTU, 100)

    assert_equal 100, status
  end

  def test_fails_when_a_warning_names_another_host_beside_the_microsoft_errors
    status, = run_script("#{MICROSOFT}W: Failed to fetch http://security.ubuntu.com/ubuntu/dists/noble-security/InRelease\n", 100)

    assert_equal 100, status
  end

  def test_fails_when_apt_prints_no_error_or_warning_line
    status, = run_script("Segmentation fault\n", 100)

    assert_equal 100, status
  end

  def test_fails_when_sudo_itself_fails_and_prints_nothing
    status, = run_script("", 1)

    assert_equal 1, status
  end

  def test_fails_when_only_a_warning_names_packages_microsoft_com
    status, = run_script("W: Failed to fetch https://packages.microsoft.com/ubuntu/24.04/prod/dists/noble/InRelease\n", 100)

    assert_equal 100, status
  end

  private def run_script(printed, exit_status)
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "printed"), printed)
      sudo = File.join(dir, "sudo")
      File.write(sudo, "#!/bin/sh\ncat \"#{dir}/printed\"\nexit #{exit_status}\n")
      File.chmod(0o755, sudo)

      path = [dir, ENV.fetch("PATH")].join(File::PATH_SEPARATOR)
      output, status = Open3.capture2e({ "PATH" => path }, "sh", SCRIPT)
      [status.exitstatus, output]
    end
  end
end
