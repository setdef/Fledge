# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "../test_helper"
require "fileutils"
require "open3"
require "tmpdir"

# .github/scripts/alpine-packages.sh, run as a subprocess against the real
# runtime/sources.yml with an apk that writes down what it was asked to
# add.
class AlpinePackagesScriptTest < Minitest::Test
  SCRIPT = File.expand_path("../../.github/scripts/alpine-packages.sh", __dir__)

  PINS = YAML.safe_load_file(File.expand_path("../../runtime/sources.yml", __dir__)).fetch("alpine-packages")

  FAKE_APK = <<~SH
    #!/bin/sh
    echo "$@" >"DIR/apk.args"
  SH

  # The arguments the script gives apk for +role+.
  def asked(role)
    Dir.mktmpdir("alpine-packages") do |dir|
      File.write(File.join(dir, "apk"), FAKE_APK.sub("DIR", dir), perm: 0o755)
      _out, err, status = Open3.capture3({ "PATH" => "#{dir}:#{ENV.fetch('PATH')}" }, "sh", SCRIPT, role)
      assert_predicate status, :success?, err
      File.read(File.join(dir, "apk.args")).split
    end
  end

  def test_every_role_installs_each_package_as_name_tilde_its_upstream_version
    %w[build apps deliver parity].each do |role|
      args = asked(role)

      assert_equal %w[add --no-cache], args.first(2)
      packages = args.drop(2)
      refute_empty packages, role
      packages.each do |package|
        name, upstream = package.split("~", 2)

        assert upstream, "#{package} in role #{role} has no ~"
        assert_equal PINS.fetch(name).sub(/-r\d+\z/, ""), upstream, "#{name} in role #{role}"
      end
    end
  end

  def test_a_version_with_a_dash_of_its_own_keeps_it
    Dir.mktmpdir("alpine-packages-sources") do |dir|
      FileUtils.mkdir_p(File.join(dir, ".github/scripts"))
      FileUtils.mkdir_p(File.join(dir, "runtime"))
      FileUtils.cp(SCRIPT, File.join(dir, ".github/scripts/alpine-packages.sh"))
      File.write(File.join(dir, "runtime/sources.yml"), "alpine-packages:\n  glib: 2.88.4-rc1-r10\n")
      File.write(File.join(dir, "apk"), FAKE_APK.sub("DIR", dir), perm: 0o755)
      _out, err, status = Open3.capture3({ "PATH" => "#{dir}:#{ENV.fetch('PATH')}" }, "sh", File.join(dir, ".github/scripts/alpine-packages.sh"), "parity")

      assert_predicate status, :success?, err
      assert_equal "add --no-cache glib~2.88.4-rc1", File.read(File.join(dir, "apk.args")).strip
    end
  end
end
