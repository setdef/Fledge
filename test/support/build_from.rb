# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require "stringio"

# What the tests of fledge build --from APP (ADR 032) share:
# test/build_from_test.rb's, with fake runtimes alone, and
# test/integration/build_from_tools_test.rb's, with the tools of the
# platform the app is for. Each test has a folder of its own, with a fake
# runtime for every platform.
module BuildFromHelpers
  LINUX = "x86_64-linux"
  PLATFORMS = %w[arm64-darwin x64-mingw-ucrt aarch64-mingw-ucrt x86_64-linux aarch64-linux x86_64-linux-musl aarch64-linux-musl].freeze

  def setup
    @dir = File.realpath(Dir.mktmpdir)
    @runtimes = File.join(@dir, "runtimes")
    FileUtils.mkdir_p(@runtimes)
    Fledge::Platform.names.each { |name| FakeRuntime.write(@runtimes, Fledge::Platform.find(name)) }
  end

  def teardown
    FileUtils.rm_rf(@dir)
  end

  def build(*argv, host: LINUX, env: { "FLEDGE_RUNTIME_DIR" => @runtimes })
    out = StringIO.new
    err = StringIO.new
    status = Dir.chdir(@dir) { Fledge::CLI::Build.new(out:, err:, env:, host: Gem::Platform.new(host)).call(argv) }
    [out.string, err.string, status]
  end

  # A gem in +folder+ whose lib/NAME.rb defines +body+.
  def path_gem(folder, name)
    FileUtils.mkdir_p(File.join(folder, "lib"))
    File.write(File.join(folder, "#{name}.gemspec"),
      "Gem::Specification.new { |s| s.name = #{name.inspect}; s.version = '1.0'; s.summary = 'x'; s.authors = ['x']; " \
        "s.files = ['lib/#{name}.rb'] }\n")
    File.write(File.join(folder, "lib", "#{name}.rb"), "# #{name}\n")
  end

  # The project of the app others are built from: Player, whose Gemfile
  # takes greeter from a folder inside it and elsewhere from one beside
  # it, and whose fledge.yml adds +config+.
  def player(config = "")
    root = FakeApp.write(@dir, "player")
    path_gem(File.join(root, "vendor", "greeter"), "greeter")
    path_gem(File.join(@dir, "elsewhere"), "elsewhere")
    File.write(File.join(root, "Gemfile"), "source \"https://rubygems.org\"\n\ngem \"greeter\", path: \"vendor/greeter\"\ngem \"elsewhere\", path: \"../elsewhere\"\n")
    File.write(File.join(root, "Gemfile.lock"), <<~LOCK)
      PATH
        remote: ../elsewhere
        specs:
          elsewhere (1.0)

      PATH
        remote: vendor/greeter
        specs:
          greeter (1.0)

      GEM
        remote: https://rubygems.org/
        specs:

      PLATFORMS
      #{PLATFORMS.sort.map { |platform| "  #{platform}" }.join("\n")}

      DEPENDENCIES
        elsewhere!
        greeter!

      CHECKSUMS
        elsewhere (1.0)
        greeter (1.0)

      BUNDLED WITH
        #{Bundler::VERSION}
    LOCK
    File.write(File.join(root, "fledge.yml"), "name: Player\nversion: \"9.9\"\npublisher: Player Inc.\n#{config}")
    root
  end

  # A project with no gems of its own, which fledge.yml names Game.
  def game(config = "")
    root = FakeApp.write(@dir, "game")
    File.write(File.join(root, "main.rb"), "require \"greeter\"\nputs 'game'\n")
    FileUtils.mkdir_p(File.join(root, "assets"))
    File.write(File.join(root, "assets", "level.txt"), "1\n")
    File.write(File.join(root, "fledge.yml"), "name: Game\n#{config}")
    root
  end

  # Builds Player for +host+ and returns its folder.
  def built_player(config = "", host: LINUX)
    player(config)
    _, err, status = build("-o", "players", "player", host:)
    assert_equal [0, ""], [status, err]
    File.join(@dir, "players", "Player-#{Fledge::Platform.local(Gem::Platform.new(host))}")
  end

  def files(folder)
    Dir.glob("**/*", File::FNM_DOTMATCH, base: folder).reject { |path| File.basename(path) == "." }.sort
  end

  # A folder of no runtimes, so that none is at hand.
  def no_runtime
    folder = File.join(@dir, "no runtimes")
    FileUtils.mkdir_p(folder)
    { "FLEDGE_RUNTIME_DIR" => folder }
  end
end
