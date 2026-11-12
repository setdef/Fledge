# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "../test_helper"
require_relative "../support/gems"
require_relative "../support/loopback_server"
require_relative "../../tasks/mobile_parity"

# The mobile check's projects (doc/contributors/design/phone-projects.md,
# "Parity on a phone"), each made by fledge build in a process of its
# own, from fake phone runtimes. test/mobile_parity_test.rb covers the
# rest of the check that needs no simulator or emulator.
class MobileParityProjectsTest < Minitest::Test
  # fledge build prints the project's folder on standard output and what
  # it downloads on standard error, as GNU's conventions keep a command's
  # result apart from its diagnostics, so the check takes the folder from
  # the output alone, even when the app's gems are downloaded first.
  def test_each_project_is_the_folder_fledge_build_prints_while_it_reports_downloads
    begin
      Fledge::MobilePlatform.find("android").check_host(Fledge::Platform.local)
    rescue Fledge::Error => e
      skip e.message
    end
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p([File.join(dir, ".git"), File.join(dir, "runtimes"), File.join(dir, "gems")])
      FakeRuntime.write_mobile(File.join(dir, "runtimes"), Fledge::MobilePlatform.find("android"))
      gem = FakeGem.build(File.join(dir, "gems"), "pure", "1.0.0")
      server = LoopbackServer.new({ "/gems/#{gem.file_name}" => [200, {}, File.binread(gem.path)] })
      begin
        root = FakeProject.write(dir, dependencies: { "pure" => ">= 0" }, locked: [gem], remote: server.url("/"), platforms: %w[ruby])
        File.write(File.join(root, "fledge.yml"), "identifier: com.example.MyApp\n")
        app = MobileParity::App.new(path: root, name: "MyApp", identifier: "com.example.MyApp", prints: nil)

        projects = MobileParity.projects("android", runtimes: File.join(dir, "runtimes"), out: File.join(dir, "dist"), apps: [app],
          env: { "XDG_CACHE_HOME" => File.join(dir, "cache") })

        assert_equal({ app => File.join(dir, "dist", "MyApp-android") }, projects)
        assert_path_exists File.join(dir, "cache"), "the gem was downloaded"
      ensure
        server.stop
      end
    end
  end
end
