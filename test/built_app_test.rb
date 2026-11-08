# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "test_helper"
require_relative "../tasks/parity"
require_relative "support/disk_images"
require "json"
require "open3"
require "stringio"

# examples/hello and examples/my_cool_app, built by fledge build from a
# real runtime for this computer, unpacked by the system's own tool (tar,
# or Expand-Archive on Windows), and run in a clean and in a hostile
# environment. Building my_cool_app downloads its gems from RubyGems.org.
# .github/scripts/deliver.sh and deliver.ps1 run the same checks on fresh
# computers with no Ruby; this test runs them wherever a runtime is.
#
# The runtime comes from FLEDGE_RUNTIME_DIR, or from tmp/runtime, where
# rake runtime writes it. Without one the test skips, unless
# FLEDGE_REQUIRE_RUNTIME is set, as CI sets it on every platform with a
# runtime, so a missing runtime there fails instead of passing silently.
class BuiltAppTest < Minitest::Test
  HELLO = File.expand_path("../examples/hello", __dir__)
  MY_COOL_APP = File.expand_path("../examples/my_cool_app", __dir__)
  WINDOWED_APP = File.expand_path("../examples/windowed_app", __dir__)
  PROGRAMS = File.expand_path("../examples/programs", __dir__)
  PROBE = File.expand_path("fixtures/parity", __dir__)
  CONSOLE = File.expand_path("fixtures/console", __dir__)
  DELIVER_CONSOLE = File.expand_path("../.github/scripts/deliver-console.sh", __dir__)
  EXE = File.expand_path("../exe/fledge", __dir__)
  LIB = File.expand_path("../lib", __dir__)

  def setup
    @platform = Fledge::Platform.local
    @runtimes = ENV.fetch("FLEDGE_RUNTIME_DIR", File.expand_path("../tmp/runtime", __dir__))
    return if File.file?(File.join(@runtimes, Fledge::Runtimes.file_name(@platform)))

    message = "no #{Fledge::Runtimes.file_name(@platform)} in #{@runtimes}; run bundle exec rake runtime"
    flunk message if ENV["FLEDGE_REQUIRE_RUNTIME"]
    skip message
  rescue Fledge::Error => e
    flunk e.message if ENV["FLEDGE_REQUIRE_RUNTIME"]
    skip e.message
  end

  def expected
    "Hello from Ruby 4.0.9 on #{expected_platform}\n"
  end

  # RUBY_PLATFORM as rv-ruby reports it: macOS builds carry the Darwin
  # version they were built for, macOS 14's.
  def expected_platform
    (@platform.name == "arm64-darwin") ? "arm64-darwin23" : @platform.name
  end

  # What examples/my_cool_app prints: the versions of i18n and sqlite3 its
  # Gemfile.lock locks, and the SQLite that sqlite3 carries.
  def my_cool_app_line
    lock = File.read(File.join(MY_COOL_APP, "Gemfile.lock"))
    i18n = lock[/^    i18n \(([^)]+)\)$/, 1]
    sqlite3 = lock[/^    sqlite3 \(([\d.]+)-/, 1]
    /\AMyCoolApp 0\.1\.0 says hello through i18n #{Regexp.escape(i18n.to_s)} and sqlite3 #{Regexp.escape(sqlite3.to_s)} \(SQLite 3\.\d+\.\d+\)\n\z/
  end

  # One build of each app serves every test: building takes seconds.
  def app = built(HELLO)

  def my_cool_app
    gem_shaped!
    built(MY_COOL_APP)
  end

  # examples/my_cool_app's Gemfile, which the gem-shaped probe shares,
  # locks sqlite3, which has no build for some platforms and does not
  # compile there (Parity::WITHOUT_GEM_APP; ADR 018).
  def gem_shaped!
    skip "sqlite3, which examples/my_cool_app locks, does not install on #{@platform} (ADR 018)" if
      Parity::WITHOUT_GEM_APP.include?(@platform.name)
  end

  def probe = built(PROBE)

  # The probe as a gem-shaped app's program (Parity.gem_probe), run with
  # Bundler as bundle exec would.
  def bundled_probe
    gem_shaped!
    self.class.built[:bundled_probe] ||= begin
      dir = Dir.mktmpdir
      Minitest.after_run { FileUtils.rm_rf(dir) }
      build_and_unpack(dir, Parity.gem_probe(File.join(dir, "parity-bundle"), name: "ParityBundle"), name: "ParityBundle")
    end
  end

  # The probe as a windowed app, which on macOS is an .app bundle
  # (Fledge::MacBundle). Returns the program a person runs.
  def windowed_probe
    self.class.built[:windowed_probe] ||= begin
      dir = Dir.mktmpdir
      Minitest.after_run { FileUtils.rm_rf(dir) }
      project = File.join(dir, "windowed-parity")
      FileUtils.mkdir_p(project)
      FileUtils.cp(File.join(PROBE, "main.rb"), project)
      File.write(File.join(project, "fledge.yml"), "name: WindowedParity\nkind: windowed\nidentifier: com.setdef.fledge.WindowedParity\n")
      program = build_and_unpack(dir, project, name: "WindowedParity")
      bundle = File.join(File.dirname(program), "WindowedParity.app", "Contents", "MacOS", "WindowedParity")
      (@platform.os == "darwin") ? bundle : program
    end
  end

  def built(source)
    self.class.built[source] ||= begin
      dir = Dir.mktmpdir
      Minitest.after_run { FileUtils.rm_rf(dir) }
      build_and_unpack(dir, source)
    end
  end

  class << self
    def built = (@built ||= {})
  end

  # ADR 015: Ctrl-C typed into a terminal, and a hangup, end the built
  # console probe as they end ruby main.rb, through Ruby's own handlers
  # (.github/scripts/deliver-console.sh, which CI's Delivery runs too).
  # Windows' console is CI's to check, with deliver-console.ps1.
  def test_ctrl_c_and_a_hangup_end_the_built_app_as_they_end_ruby
    skip "deliver-console.ps1 checks Windows' console in CI" if @platform.windows?

    Dir.mktmpdir do |dir|
      out, err, status = Open3.capture3({ "FLEDGE_RUNTIME_DIR" => @runtimes }, RbConfig.ruby, "-I", LIB, EXE, "build",
        "-o", dir, CONSOLE)
      assert_predicate status, :success?, err

      [[out.lines.first.to_s.chomp], ["--reference", RbConfig.ruby, File.join(CONSOLE, "main.rb")]].each do |arguments|
        report, status = Open3.capture2e(DELIVER_CONSOLE, *arguments)
        assert_predicate status, :success?, report
      end
    end
  end

  def test_the_built_app_runs_with_no_ruby_environment
    Dir.mktmpdir do |dir|
      out, err, status = run_app({ "HOME" => dir }, app)

      assert_equal [expected, "", 0], [out, err, status.exitstatus]
    end
  end

  def test_the_built_app_ignores_a_hostile_ruby_environment
    Dir.mktmpdir do |dir|
      evil = File.join(dir, "evil")
      user_gems = File.join(dir, ".gem/ruby/4.0.0")
      FileUtils.mkdir_p([evil, File.join(user_gems, "gems/json-99.0.0/lib"), File.join(user_gems, "specifications")])
      leak = "raise 'the caller\\'s Ruby environment leaked into the app'\n"
      %w[json nonexistent bundler_setup].each { |name| File.write(File.join(evil, "#{name}.rb"), leak) }
      File.write(File.join(user_gems, "gems/json-99.0.0/lib/json.rb"), leak)
      File.write(File.join(user_gems, "specifications/json-99.0.0.gemspec"), <<~SPEC)
        Gem::Specification.new { |s| s.name = "json"; s.version = "99.0.0"; s.summary = "x"; s.authors = ["x"]; s.files = ["lib/json.rb"] }
      SPEC
      env = {
        "HOME" => dir,
        "RUBYLIB" => evil,
        "RUBYOPT" => "-rnonexistent",
        "GEM_HOME" => user_gems,
        "GEM_PATH" => user_gems,
        "BUNDLE_GEMFILE" => File.join(evil, "Gemfile"),
        "BUNDLER_SETUP" => File.join(evil, "bundler_setup.rb"),
        "RUBYGEMS_GEMDEPS" => "-",
        # RubyInstaller's: folders to load DLLs from, and putting them on
        # PATH. Windows' variable names ignore case, so a lowercase
        # bundle_ variable is Bundler's too.
        "RUBY_DLL_PATH" => evil,
        "RI_FORCE_PATH_FOR_DLL" => "1",
        "bundle_gemfile" => File.join(evil, "Gemfile"),
      }

      out, err, status = run_app(env, app)

      assert_equal [expected, "", 0], [out, err, status.exitstatus]
    end
  end

  # The launcher hides the person's Ruby settings from Ruby's boot, then
  # puts them back (ADR 003): the app's own gems stay the runtime's, and a
  # Ruby the app starts sees the person's settings, as under ruby main.rb.
  def test_the_persons_ruby_settings_reach_child_processes_but_not_the_apps_gems
    Dir.mktmpdir do |dir|
      gems = File.join(dir, "person-gems")
      env = { "HOME" => dir, "GEM_HOME" => gems, "bundle_gemfile" => File.join(dir, "Gemfile") }

      out, err, status = run_app(env, probe, "child-env", "GEM_HOME")
      assert_equal ["#{gems}\n", "", 0], [out, err, status.exitstatus]

      out, err, status = run_app(env, probe, "gem-path")
      assert_equal 0, status.exitstatus, err
      refute_includes out, gems
      assert_equal 1, out.lines.size, out
    end
  end

  # An app with a Gemfile gets the ENV bundle exec gives (ADR 005):
  # Bundler's settings over the person's, so a child Ruby runs in the
  # app's bundle with the person's RUBYOPT after Bundler's own, and
  # Bundler.with_original_env and with_unbundled_env, which a Bundler app
  # uses to start a person's own tools, give the person's environment
  # back. The app's own gems stay the runtime's. The environment names no
  # locale, so the child's is C, which bin/ruby makes a UTF-8 one as the
  # launcher does (ADR 026, section 1): in a C locale, Bundler 4.0.20
  # cannot set up a bundle in a folder whose name is not ASCII, and the
  # app is unpacked in one.
  def test_a_bundler_apps_children_see_the_persons_ruby_settings_as_under_bundle_exec
    Dir.mktmpdir do |dir|
      gems = File.join(dir, "person-gems")
      env = { "HOME" => dir, "GEM_HOME" => gems, "RUBYOPT" => "-W0", "BUNDLE_PERSON" => "1" }
      seen = -> (*argv) { run_app(env, bundled_probe, *argv).then { |out, err, status| [out.chomp, err, status.exitstatus] } }

      %w[original-child-env unbundled-child-env].each do |command|
        assert_equal [gems, "", 0], seen.call(command, "GEM_HOME"), command
        assert_equal ["-W0", "", 0], seen.call(command, "RUBYOPT"), command
      end
      assert_equal ["1", "", 0], seen.call("original-child-env", "BUNDLE_PERSON")
      assert_equal ["(unset)", "", 0], seen.call("unbundled-child-env", "BUNDLE_PERSON")
      assert_match %r{\A-r(?:\S*/)?bundler/setup -W0\z}, seen.call("child-env", "RUBYOPT").first
      refute_equal gems, seen.call("child-env", "GEM_HOME").first
      refute_includes seen.call("gem-path").first, gems
    end
  end

  # The runtime's own bin/ruby, the Ruby an app restarts or a gem's
  # executable runs on, chooses its locale as the launcher does (ADR 026,
  # section 1, after PEP 538): with no locale in the environment, which is
  # C, it reads a folder whose name is not ASCII as UTF-8. Windows keeps
  # RubyInstaller's ruby.exe, which reads the console's code page (ADR
  # 003, section 5).
  def test_the_runtimes_own_ruby_turns_a_c_locale_into_utf8_as_the_launcher_does
    skip "Windows keeps RubyInstaller's ruby.exe (ADR 001, section 8)" if @platform.windows?

    Dir.mktmpdir do |dir|
      script = File.join(dir, "Ünïcödé", "encoding.rb")
      FileUtils.mkdir_p(File.dirname(script))
      File.write(script, "print Encoding.default_external, ' ', __dir__.encoding, ' ', __dir__.valid_encoding?\n")
      out, err, status = run_app({ "HOME" => dir }, File.join(File.dirname(app), "bin", "ruby"), script)

      assert_equal ["UTF-8 UTF-8 true", "", 0], [out, err, status.exitstatus]
    end
  end

  # The launcher and bin/ruby keep a character set the person chose, C
  # included, as ruby does, and turn only a C locale that comes from LANG
  # or from no variable at all into a UTF-8 one (ADR 026, section 1;
  # PEP 538 never coerces under LC_ALL). The probe and the script run
  # from a folder whose name is ASCII, where ruby itself runs in a C
  # locale.
  def test_an_explicit_c_locale_is_kept_and_only_a_bare_one_becomes_utf8
    skip "Windows takes its encoding from the console's code page (ADR 003, section 5)" if @platform.windows?

    Dir.mktmpdir do |dir|
      launcher = build_and_unpack(dir, PROBE, place: File.join(dir, "ascii"))
      ruby = File.join(File.dirname(launcher), "bin", "ruby")
      script = File.join(dir, "encoding.rb")
      File.write(script, "print Encoding.default_external\n")
      {
        {} => "UTF-8",
        { "LANG" => "C" } => "UTF-8",
        { "LC_ALL" => "", "LANG" => "POSIX" } => "UTF-8",
        { "LC_ALL" => "C" } => "US-ASCII",
        { "LC_CTYPE" => "C" } => "US-ASCII",
        { "LC_ALL" => "C", "LANG" => "en_US.UTF-8" } => "US-ASCII",
      }.each do |locale, expected|
        env = { "HOME" => dir }.merge(locale)
        out, err, status = run_app(env, ruby, script)
        assert_equal [expected, "", 0], [out, err, status.exitstatus], "bin/ruby with #{locale}"
        out, err, status = run_app(env, launcher)
        assert_equal [expected, 0], [Parity::Reports.report(out).fetch("Encoding.default_external"), status.exitstatus],
          "the launcher with #{locale}: #{err}"
      end
    end
  end

  # ADR 032: an app built with fledge build --from takes the runtime and
  # the gems of an app already built, and runs a project of its own,
  # which requires a gem the old app's Gemfile takes from a folder in its
  # project, written to a folder whose name is not ASCII, and run there
  # with no Ruby around.
  def test_an_app_built_from_a_built_app_runs_its_own_project_with_the_old_apps_gems
    Dir.mktmpdir do |dir|
      player = File.join(dir, "player")
      FileUtils.mkdir_p([File.join(player, ".git"), File.join(player, "vendor", "greeter", "lib")])
      File.write(File.join(player, "vendor", "greeter", "greeter.gemspec"),
        "Gem::Specification.new { |s| s.name = 'greeter'; s.version = '1.0'; s.summary = 'x'; s.authors = ['x']; s.files = ['lib/greeter.rb'] }\n")
      File.write(File.join(player, "vendor", "greeter", "lib", "greeter.rb"), "module Greeter\n  def self.hi(name) = \"hello from greeter in \#{name}\"\nend\n")
      File.write(File.join(player, "Gemfile"), "source \"https://rubygems.org\"\n\ngem \"greeter\", path: \"vendor/greeter\"\n")
      platforms = %w[aarch64-linux aarch64-linux-musl aarch64-mingw-ucrt arm64-darwin x64-mingw-ucrt x86_64-linux x86_64-linux-musl]
      File.write(File.join(player, "Gemfile.lock"), "PATH\n  remote: vendor/greeter\n  specs:\n    greeter (1.0)\n\n" \
        "GEM\n  remote: https://rubygems.org/\n  specs:\n\nPLATFORMS\n#{platforms.map { |name| "  #{name}\n" }.join}\n" \
        "DEPENDENCIES\n  greeter!\n\nCHECKSUMS\n  greeter (1.0)\n\nBUNDLED WITH\n  4.0.20\n")
      File.write(File.join(player, "main.rb"), "require \"greeter\"\nputs Greeter.hi(\"the player\")\n")
      File.write(File.join(player, "fledge.yml"), "name: Player\n")
      game = File.join(dir, "game")
      FileUtils.mkdir_p(File.join(game, ".git"))
      File.write(File.join(game, "main.rb"), "require \"greeter\"\nputs Greeter.hi(File.basename(__dir__))\n")
      File.write(File.join(game, "fledge.yml"), "name: Game\n")

      env = { "FLEDGE_RUNTIME_DIR" => @runtimes }
      out, err, status = Open3.capture3(env, RbConfig.ruby, "-I", LIB, EXE, "build", "-o", File.join(dir, "players"), player)
      assert_predicate status, :success?, err
      from = File.join(dir, "players", "Player-#{@platform}")
      place = File.join(dir, "My Games", "Ünïcödé 日本")
      out, err, status = Open3.capture3(env, RbConfig.ruby, "-I", LIB, EXE, "build", "--from", from, "-o", place, game)
      assert_equal [true, ""], [status.success?, err]
      assert_equal "#{File.join(place, "Game-#{@platform}#{@platform.archive_extension}")}\n", out

      out, err, status = run_app({ "HOME" => dir }, File.join(place, "Game-#{@platform}", @platform.executable("Game")))
      assert_equal ["hello from greeter in app\n", "", 0], [out, err, status.exitstatus]
    end
  end

  # require "mkmf" loads in a built app, as under ruby, since the runtime
  # keeps Ruby's headers (ADR 003, section 2), and some gems require it
  # at run time for MakeMakefile#find_executable.
  def test_mkmf_loads_in_a_built_app_and_finds_an_executable
    Dir.mktmpdir do |dir|
      project = File.join(dir, "mkmf-app")
      FileUtils.mkdir_p(project)
      File.write(File.join(project, "main.rb"), "require \"mkmf\"\nputs \"found \#{find_executable(ARGV.fetch(0))}\"\n")
      File.write(File.join(project, "fledge.yml"), "name: MkmfApp\n")
      launcher = build_and_unpack(dir, project, name: "MkmfApp")
      program, folder = @platform.windows? ? ["cmd", ENV.fetch("SystemRoot", "C:\\Windows")] : ["sh", "/bin"]
      env = { "HOME" => dir, "PATH" => @platform.windows? ? File.join(folder, "System32") : folder }

      out, err, status = run_app(env, launcher, program, chdir: dir)

      assert_equal [0, ""], [status.exitstatus, err]
      assert_match(/^found .*#{Regexp.escape(program)}(?:\.exe)?$/i, out)
    end
  end

  # binding.irb in an app with a Gemfile that does not lock irb opens
  # IRB, as under bundle exec: Ruby activates irb in a temporary bundle,
  # which the app's frozen bundle would refuse without Fledge's RubyGems
  # defaults (runtime/rubygems/operating_system.rb). Ruby warns that irb
  # is no longer a default gem, as it warns under bundle exec; Bundler
  # says nothing of the lockfile.
  #
  # On Windows, bundle exec cannot open IRB this way either: reline 0.6.3,
  # which irb requires, requires fiddle/import there (lib/reline/io/windows.rb,
  # line 1), and fiddle, a bundled gem since Ruby 4.0, is neither in the
  # Gemfile nor a dependency of irb or reline, so the temporary bundle
  # leaves it out and require raises LoadError, in the app and under
  # bundle exec alike (stock Ruby 4.0.9 on both Windows runners, branch
  # experiment/win-irb, run 41842939667; with fiddle in the Gemfile,
  # bundle exec opens IRB).
  def test_binding_irb_opens_irb_in_an_app_with_a_gemfile
    skip "bundle exec cannot open IRB either: reline needs fiddle on Windows, and the bundle lacks it" if @platform.windows?

    Dir.mktmpdir do |dir|
      out, err, status = run_app({ "HOME" => dir }, bundled_probe, "irb", stdin: "answer\nexit\n")

      assert_equal 0, status.exitstatus, err
      assert_includes out.lines.map(&:strip), "42", out
      refute_match(/lockfile|Gemfile\.lock|frozen/, err)
    end
  end

  # A program restarts itself as Ruby programs do, with exec
  # RbConfig.ruby, $0, *ARGV, and the runtime's bin/ruby hands the app's
  # own program back to its launcher (ADR 026, section 3). So the restart
  # is the same process running the same program, in the same locale,
  # with the same gems and environment: with no locale, from a folder
  # whose name is not ASCII, in the person's environment and in a hostile
  # one, with a Gemfile and without, and in a macOS .app, in the same
  # bundle. The probe compares what it sees after the restart with what
  # it saw before.
  def test_a_restart_through_rbconfig_ruby_is_the_same_app_again
    skip "On Windows, RbConfig.ruby is RubyInstaller's ruby.exe (ADR 026, section 4)" if @platform.windows?

    Dir.mktmpdir do |dir|
      evil = File.join(dir, "evil")
      FileUtils.mkdir_p(evil)
      %w[json nonexistent bundler_setup].each { |name| File.write(File.join(evil, "#{name}.rb"), "raise 'the caller\\'s Ruby environment leaked into the restart'\n") }
      person = { "HOME" => dir, "GEM_HOME" => File.join(dir, "person gems"), "RUBYOPT" => "-W0", "RUBYLIB" => evil }
      hostile = person.merge("RUBYOPT" => "-rnonexistent", "BUNDLER_SETUP" => File.join(evil, "bundler_setup.rb"),
        "BUNDLE_GEMFILE" => File.join(evil, "Gemfile"), "RUBYGEMS_GEMDEPS" => "-")
      programs = [probe]
      programs << windowed_probe if @platform.os == "darwin"
      programs << bundled_probe unless Parity::WITHOUT_GEM_APP.include?(@platform.name)

      programs.product([{ "HOME" => dir }, person, hostile]).each do |program, env|
        out, err, status = run_app(env, program, "restart")
        assert_equal ["restarted as itself\n", "", 0], [out, err, status.exitstatus], "#{program} with #{env.keys.join(', ')}"
      end
    end
  end

  # bin/ruby hands only its first argument to the launcher, and only when
  # it is an app's program (ADR 026, section 3): with an option before
  # the program, it is plain Ruby, whose RubyGems reads the person's
  # GEM_HOME, as ruby -W1 main.rb would.
  def test_bin_ruby_runs_an_apps_program_through_its_launcher_unless_an_option_comes_first
    skip "On Windows, RbConfig.ruby is RubyInstaller's ruby.exe (ADR 026, section 4)" if @platform.windows?

    ruby = File.join(File.dirname(probe), "bin", "ruby")
    main = File.join(File.dirname(probe), "app", "main.rb")
    Dir.mktmpdir do |dir|
      gems = File.join(dir, "person gems")
      env = { "HOME" => dir, "GEM_HOME" => gems }
      seen = -> (*argv) { run_app(env, ruby, *argv).then { |out, err, status| [out.include?(gems), err, status.exitstatus] } }

      assert_equal [false, "", 0], seen.call(main, "gem-path")
      assert_equal [true, "", 0], seen.call("-W1", main, "gem-path")
    end
  end

  def test_a_missing_main_rb_exits_with_ex_noinput
    main = File.join(File.realpath(File.dirname(app)), "app", "main.rb")
    File.rename(main, "#{main}.away")
    out, err, status = run_app({}, app)

    assert_equal ["", 66], [out, status.exitstatus]
    assert_equal "#{@platform.executable('Hello')}: this app is incomplete: #{main.tr('/', File::ALT_SEPARATOR || '/')} is missing\n",
      err.gsub("\r\n", "\n")
  ensure
    File.rename("#{main}.away", main) if main && File.exist?("#{main}.away")
  end

  # ADR 030: on Linux, a library the app's gems load from the
  # distribution that this computer lacks stops the app before Ruby
  # starts, with EX_OSFILE and the library's name, never a LoadError
  # that names a gem; one it has changes nothing.
  def test_a_system_library_the_computer_lacks_is_named_before_ruby_starts
    skip "only a Linux app's gems load libraries from its distribution" unless @platform.os == "linux"
    config = File.join(File.realpath(File.dirname(app)), "fledge.cfg")
    original = File.read(config)
    present = @platform.musl? ? "libc.musl-#{@platform.name.split('-').first}.so.1" : "libm.so.6"

    File.write(config, "#{original}system_libraries = #{present}\n")
    assert_equal [expected, "", 0], run_app({}, app).then { |out, err, status| [out, err, status.exitstatus] }

    File.write(config, "#{original}system_libraries = #{present} libfledge-absent.so.1\n")
    out, err, status = run_app({}, app)
    assert_equal ["", 72], [out, status.exitstatus]
    assert_match(/\AHello: this app needs libfledge-absent\.so\.1, which this computer does not have \(.*libfledge-absent\.so\.1.*\)\. /, err)
    assert err.end_with?("Install it from your Linux distribution's packages, then run the app again\n"), err
  ensure
    File.write(config, original) if config && original
  end

  # The gem-shaped app (ADR 005): exe/my_cool_app, with i18n and the
  # runtime's own build of sqlite3 set up by Bundler as bundle exec would.
  def test_the_gem_shaped_app_runs_with_its_gems_and_its_status
    Dir.mktmpdir do |dir|
      out, err, status = run_app({ "HOME" => dir }, my_cool_app, "5")

      assert_match my_cool_app_line, out
      assert_equal ["", 5], [err, status.exitstatus]
    end
  end

  # Nothing of the person's Bundler (their ~/.bundle/config, BUNDLE_*,
  # BUNDLER_VERSION) changes which gems the app loads, and running it
  # changes nothing in its folder: frozen, Bundler neither installs nor
  # rewrites the lockfile.
  def test_the_gem_shaped_app_ignores_the_persons_bundler_and_writes_nothing
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, ".bundle"))
      File.write(File.join(dir, ".bundle", "config"), <<~YAML)
        ---
        BUNDLE_GEMFILE: "#{File.join(dir, 'Gemfile')}"
        BUNDLE_FORCE_RUBY_PLATFORM: "true"
        BUNDLE_WITHOUT: "default"
        BUNDLE_PATH: "#{dir}"
        BUNDLE_AUTO_INSTALL: "true"
      YAML
      env = {
        "HOME" => dir,
        "USERPROFILE" => dir,
        "BUNDLE_GEMFILE" => File.join(dir, "Gemfile"),
        "BUNDLE_FROZEN" => "false",
        "BUNDLE_WITHOUT" => "default",
        "BUNDLE_APP_CONFIG" => dir,
        "BUNDLER_VERSION" => "2.1.0",
        "GEM_HOME" => dir,
        "RUBYOPT" => "-rnonexistent",
      }
      root = File.dirname(my_cool_app)
      before = snapshot(root)

      out, err, status = run_app(env, my_cool_app)

      assert_match my_cool_app_line, out
      assert_equal ["", 0], [err, status.exitstatus]
      assert_equal before, snapshot(root)
    end
  end

  def test_a_gem_shaped_app_without_its_program_exits_with_ex_noinput
    program = File.join(File.realpath(File.dirname(my_cool_app)), "app", "exe", "my_cool_app")
    File.rename(program, "#{program}.away")
    out, err, status = run_app({}, my_cool_app)

    assert_equal ["", 66], [out, status.exitstatus]
    assert_equal "#{@platform.executable('MyCoolApp')}: this app is incomplete: #{program.tr('/', File::ALT_SEPARATOR || '/')} is missing\n",
      err.gsub("\r\n", "\n")
  ensure
    File.rename("#{program}.away", program) if program && File.exist?("#{program}.away")
  end

  # Every file under +root+, with its size and modification time.
  def snapshot(root)
    Dir.glob("**/*", File::FNM_DOTMATCH, base: root).sort.map do |path|
      stat = File.lstat(File.join(root, path))
      [path, stat.size, stat.mtime.to_f]
    end
  end

  def test_the_apps_exit_status_reaches_the_caller
    Dir.mktmpdir do |dir|
      out, _, status = run_app({ "HOME" => dir }, app, "3")

      assert_equal [expected, 3], [out, status.exitstatus]
    end
  end

  # examples/windowed_app, built as a windowed app (ADR 008): on macOS an
  # .app bundle that Apple's codesign verifies, strictly and deeply, and
  # whose Info.plist plutil reads; on Windows a GUI program; on Linux a
  # folder with a desktop entry. Run by its program, it writes its report
  # and exits with the status it is given; on Windows it has no console,
  # and its AppUserModelID is its identifier.
  def test_the_windowed_app_runs_from_its_bundle_or_folder
    Dir.mktmpdir do |dir|
      folder = File.dirname(build_and_unpack(dir, WINDOWED_APP, name: "Hello Window"))
      program = File.join(folder, @platform.executable("Hello Window"))
      case @platform.os
      when "darwin"
        bundle = File.join(folder, "Hello Window.app")
        program = File.join(bundle, "Contents", "MacOS", "Hello Window")
        out, status = Open3.capture2e("codesign", "--verify", "--strict", "--deep", "--verbose=2", bundle)
        assert_predicate status, :success?, out
        out, status = Open3.capture2e("plutil", "-extract", "CFBundleIdentifier", "raw", File.join(bundle, "Contents", "Info.plist"))
        assert_equal ["com.setdef.fledge.HelloWindow\n", true], [out, status.success?]
        out, status = Open3.capture2e("plutil", "-extract", "CFBundleDocumentTypes.1.CFBundleTypeExtensions.0", "raw",
          File.join(bundle, "Contents", "Info.plist"))
        assert_equal ["hellowindow\n", true], [out, status.success?]
      when "windows"
        header = File.binread(program, 4096)
        assert_equal 2, header.byteslice(header.byteslice(0x3C, 4).unpack1("V") + 24 + 68, 2).unpack1("v"), "its PE Subsystem is GUI"
      else
        desktop = File.read(File.join(folder, "com.setdef.fledge.HelloWindow.desktop"))
        assert_includes desktop, "Exec=\"Hello Window\" %F\n"
        assert_includes desktop, "MimeType=inode/directory;application/x-hellowindow;\n"
      end

      report = File.join(dir, "report.json")
      _, err, status = run_app({ "HOME" => dir }, program, report, "4")

      assert_equal ["", 4], [err, status.exitstatus]
      facts = { "ruby" => "4.0.9", "platform" => expected_platform, "program" => "main.rb", "folder" => "app", "arguments" => 2 }
      facts.merge!("console" => false, "app_user_model_id" => "com.setdef.fledge.HelloWindow") if @platform.windows?
      facts["yjit"] = true unless @platform.windows?
      assert_equal facts, JSON.parse(File.read(report))
    end
  end

  # In a macOS .app the launcher runs from Contents/MacOS, beside links
  # to the runtime and the app in Contents/Resources (Fledge::MacBundle).
  # $0, __FILE__, __dir__, and Ruby's prefix all name the app's real
  # folder there, so File.dirname(__FILE__) is __dir__, as under ruby
  # (ADR 026, section 2).
  def test_a_mac_apps_program_runs_from_the_folder_it_really_is_in
    skip "only a macOS .app runs its program through links" unless @platform.os == "darwin"

    out, err, status = run_app({ "HOME" => Dir.tmpdir }, windowed_probe)
    assert_equal ["", 0], [err, status.exitstatus]
    report = JSON.parse(out[/^FLEDGE-PARITY (.*)$/, 1].to_s)
    resources = File.realpath(File.join(File.dirname(windowed_probe, 2), "Resources"))

    assert_equal [File.join(resources, "app", "main.rb")] * 3, report.values_at("$0", "__FILE__", "$PROGRAM_NAME")
    assert_equal [File.join(resources, "app"), resources], [report["__dir__"], report.dig("paths", "prefix")]
  end

  # examples/programs (ADR 024): a console program and a windowed one,
  # built into one folder, each run by its own name, open one save, and
  # say they run one project on one Ruby. A copy renamed by hand finds no
  # program of its name in fledge.cfg, and exits with EX_NOINPUT.
  def test_several_programs_share_one_folder_and_one_save
    Dir.mktmpdir do |dir|
      folder = File.dirname(build_and_unpack(dir, PROGRAMS, name: "Shared Save"))
      console = File.join(folder, @platform.executable("shared-save"))
      windowed = File.join(folder, @platform.executable("Shared Save"))
      windowed = File.join(folder, "Shared Save.app", "Contents", "MacOS", "Shared Save") if @platform.os == "darwin"
      save = File.join(dir, "save.jsonl")
      report = File.join(dir, "report.json")

      assert_equal ["", "", 0], run_app({ "HOME" => dir }, console, save).then { |out, err, status| [out, err, status.exitstatus] }
      _, err, status = run_app({ "HOME" => dir }, windowed, save, report)
      assert_equal ["", 0], [err, status.exitstatus]
      out, err, status = run_app({ "HOME" => dir }, console, save)
      assert_equal ["", 0], [err, status.exitstatus]

      read = JSON.parse(File.read(report)).fetch("read")
      entries = out.lines.map { |line| JSON.parse(line) }
      assert_equal [["shared-save"], ["shared-save", "Shared Save"]], [read.map { |entry| entry["by"] }, entries.map { |entry| entry["by"] }]
      assert_equal read.first, entries.first, "the windowed program read what the console one saved"
      assert_equal [1, 1], %w[project ruby].map { |key| entries.map { |entry| entry.fetch(key) }.uniq.size }
      assert entries.first.fetch("project").start_with?(File.realpath(folder)), "the project is the one in the built folder"

      renamed = File.join(File.dirname(File.realpath(console)), @platform.executable("renamed"))
      FileUtils.cp(File.realpath(console), renamed)
      _, err, status = run_app({ "HOME" => dir }, renamed, save)
      assert_equal 66, status.exitstatus
      assert_includes err, "has no program named renamed"
    end
  end

  # ADR 016: --sign signs every compiled file of an app with the identity
  # FLEDGE_TEST_SIGN_IDENTITY names: "-", ad hoc, on any Mac, and in CI a
  # self-signed certificate it makes. On macOS every Mach-O program and library of a console
  # app's folder and of a bundle carries the hardened runtime, a
  # timestamp, and Fledge's entitlements, then the bundle and its disk
  # image are signed, and YJIT still writes machine code. On Windows
  # signtool verifies every PE file and the setup program, signed by
  # makensis as it wrote it. Delivery verifies the same on fresh runners
  # (deliver-signed.sh and deliver-signed.ps1).
  def test_a_signed_build_signs_all_its_code
    identity = ENV["FLEDGE_TEST_SIGN_IDENTITY"].to_s
    skip "Linux apps are not signed" if @platform.os == "linux"
    skip "FLEDGE_TEST_SIGN_IDENTITY names no identity to sign with (\"-\" signs ad hoc on a Mac)" if identity.empty?

    Dir.mktmpdir do |dir|
      hello = signed_build(dir, HELLO, identity)
      windowed = signed_build(dir, WINDOWED_APP, identity)
      @platform.windows? ? check_signed_windows(hello, windowed) : check_signed_mac(dir, hello, windowed, timestamped: identity != "-")
    end
  end

  # Builds +source+ signed with +identity+ into DIR/dist, and returns the
  # paths fledge build printed: the archive, and any installer.
  def signed_build(dir, source, identity)
    out, err, status = Open3.capture3({ "FLEDGE_RUNTIME_DIR" => @runtimes }, RbConfig.ruby, "-I", LIB, EXE, "build",
      "--sign", identity, "-o", File.join(dir, "dist"), source)
    assert_predicate status, :success?, err
    out.lines.map { |line| File.expand_path(line.chomp, Dir.pwd) }
  end

  def check_signed_mac(dir, hello, windowed, timestamped:)
    hardened = timestamped ? /flags=0x10000\(runtime\).*^Timestamp=/m : /flags=0x10002\(adhoc,runtime\)/
    folder = hello.first.delete_suffix(".tar.gz")
    code = Fledge::Signing.code_files(folder, :macho).reject { |file| Fledge::MacSigning.object_file?(file) }
    assert_includes code, File.join(folder, "Hello")
    code.each { |file| assert_match(hardened, signature(file), file) }
    assert_includes signature(File.join(folder, "Hello")), "com.apple.security.cs.allow-unsigned-executable-memory"
    out, err, status = run_app({ "HOME" => dir }, File.join(folder, "Hello"))
    assert_equal [expected, "", 0], [out, err, status.exitstatus]

    bundle = File.join(windowed.first.delete_suffix(".tar.gz"), "Hello Window.app")
    verified, status = Open3.capture2e("codesign", "--verify", "--strict", "--deep", "--verbose=2", bundle)
    assert_predicate status, :success?, verified
    assert_includes signature(bundle), "Identifier=com.setdef.fledge.HelloWindow"
    assert_match(hardened, signature(bundle))
    Fledge::Signing.code_files(File.join(bundle, "Contents", "Resources"), :macho).each do |file|
      assert_match(hardened, signature(file), file) unless Fledge::MacSigning.object_file?(file)
    end
    report = File.join(dir, "report.json")
    _, err, status = run_app({ "HOME" => dir }, File.join(bundle, "Contents", "MacOS", "Hello Window"), report, "0")
    assert_equal ["", 0], [err, status.exitstatus]
    assert JSON.parse(File.read(report)).fetch("yjit"), "YJIT wrote machine code under the hardened runtime"

    verified, status = Open3.capture2e("codesign", "--verify", "--strict", "--verbose=2", windowed.fetch(1))
    assert_predicate status, :success?, verified
  end

  def check_signed_windows(hello, windowed)
    signtool = Fledge::WindowsSigning.signtool(ENV)
    [hello.first.delete_suffix(".zip"), windowed.first.delete_suffix(".zip")].each do |folder|
      code = Fledge::Signing.code_files(folder, :pe).select { |file| Fledge::WindowsSigning::EXTENSIONS.include?(File.extname(file)) }
      assert_includes code, File.join(folder, "#{File.basename(folder).delete_suffix("-#{@platform}")}.exe")
      verified, status = Open3.capture2e(signtool, "verify", "/pa", *code)
      assert_predicate status, :success?, verified
    end
    verified, status = Open3.capture2e(signtool, "verify", "/pa", windowed.fetch(1))
    assert_predicate status, :success?, verified
  end

  # What codesign says of the signature of +path+, and its entitlements.
  def signature(path)
    out, status = Open3.capture2e("codesign", "--display", "--verbose=2", "--entitlements", "-", path)
    assert_predicate status, :success?, out
    out
  end

  # examples/windowed_app's installer (ADR 009), built beside its archive
  # from this computer's runtime: on macOS a disk image that hdiutil
  # verifies and attaches, whose bundle codesign verifies, strictly and
  # deeply, inside it, and runs from it; on Linux an AppImage that runs,
  # extracting itself where there is no FUSE, and that --appimage-extract
  # unpacks into an AppDir; on Windows a setup program, which Delivery
  # installs (.github/scripts/deliver-installer.ps1), compiled by the
  # Windows runtime's own NSIS. On Linux a .deb follows the AppImage
  # (ADR 021), and dpkg-deb reads it back. On Linux the build needs
  # mksquashfs and dpkg-deb.
  def test_the_windowed_apps_installer_holds_the_app_and_runs_it
    Dir.mktmpdir do |dir|
      out, err, status = Open3.capture3({ "FLEDGE_RUNTIME_DIR" => @runtimes, "XDG_CACHE_HOME" => File.join(dir, "cache") }, RbConfig.ruby,
        "-I", LIB, EXE, "build", "-o", File.join(dir, "dist"), WINDOWED_APP)
      assert_predicate status, :success?, err
      installer = File.expand_path(out.lines.fetch(1).chomp, Dir.pwd)
      report = File.join(dir, "report.json")
      facts = { "ruby" => "4.0.9", "platform" => expected_platform, "program" => "main.rb", "folder" => "app", "arguments" => 2 }
      case @platform.os
      when "darwin"
        assert_equal "Hello Window-arm64-darwin.dmg", File.basename(installer)
        verified, status = Open3.capture2e("hdiutil", "verify", installer)
        assert_predicate status, :success?, verified
        DiskImages.mounted(installer) do |mount|
          bundle = File.join(mount, "Hello Window.app")
          signed, status = Open3.capture2e("codesign", "--verify", "--strict", "--deep", "--verbose=2", bundle)
          assert_predicate status, :success?, signed
          assert_equal "/Applications", File.readlink(File.join(mount, "Applications"))
          _, err, status = run_app({ "HOME" => dir }, File.join(bundle, "Contents", "MacOS", "Hello Window"), report, "3")
          assert_equal ["", 3], [err, status.exitstatus]
        end
      when "linux"
        assert_equal "Hello Window-#{@platform}.AppImage", File.basename(installer)
        _, err, status = run_app({ "HOME" => dir, "APPIMAGE_EXTRACT_AND_RUN" => "1", "TMPDIR" => dir }, installer, report, "3")
        assert_equal ["", 3], [err, status.exitstatus]
        extracted, status = Open3.capture2e(installer, "--appimage-extract", chdir: dir)
        assert_predicate status, :success?, extracted
        root = File.join(dir, "squashfs-root")
        assert_equal "Hello Window", File.readlink(File.join(root, "AppRun"))
        assert_path_exists File.join(root, "com.setdef.fledge.HelloWindow.desktop")
        assert_equal "com.setdef.fledge.HelloWindow.png", File.readlink(File.join(root, ".DirIcon"))
        assert_deb(out.lines.fetch(2).chomp) if Fledge::Deb::ARCHITECTURES.key?(@platform.name)
      else
        assert_equal "Hello Window-#{@platform}-setup.exe", File.basename(installer)
        assert_equal "MZ", File.binread(installer, 2)
      end
      assert_equal facts, JSON.parse(File.read(report)).slice(*facts.keys) unless @platform.windows?
    end
  end

  # The .deb at +path+, which dpkg-deb reads back as examples/windowed_app's
  # package for this platform.
  def assert_deb(path)
    deb = File.expand_path(path, Dir.pwd)
    assert_equal "Hello Window-#{@platform}.deb", File.basename(deb)
    fields, status = Open3.capture2e("dpkg-deb", "--showformat", "${Package} ${Version} ${Architecture}", "--show", deb)
    assert_predicate status, :success?, fields
    assert_equal "com.setdef.fledge.hellowindow 1.2.3 #{Fledge::Deb::ARCHITECTURES.fetch(@platform.name)}", fields
  end

  # Builds the app in +source+ through the fledge executable, as a person
  # would, and unpacks its archive into +place+, by default under a path
  # with spaces and characters outside ASCII. Returns the launcher's path.
  # +name+ is the app's name, when the caller knows it; reading it from
  # the project would load a copy of my_cool_app's gemspec, and so its
  # version constant, again.
  def build_and_unpack(dir, source, name: Fledge::App.at(source).name, place: File.join(dir, "My Apps", "Ünïcödé 日本"))
    out, err, status = Open3.capture3({ "FLEDGE_RUNTIME_DIR" => @runtimes }, RbConfig.ruby, "-I", LIB, EXE, "build",
      "-o", File.join(dir, "dist"), source)
    assert_predicate status, :success?, err
    archive = File.expand_path(out.lines.first.to_s.chomp, Dir.pwd)

    FileUtils.mkdir_p(place)
    unpack(archive, place)
    File.join(place, "#{name}-#{@platform}", @platform.executable(name))
  end

  # Windows' own Expand-Archive for a .zip, as a person on Windows has
  # it, and the system's tar for a .tar.gz.
  def unpack(archive, place)
    command = if @platform.windows?
      [
        "powershell",
        "-NoProfile",
        "-NonInteractive",
        "-Command",
        "$ErrorActionPreference = 'Stop'; Expand-Archive -LiteralPath $env:ARCHIVE -DestinationPath $env:PLACE",
]
    else
      ["tar", "-xzf", archive, "-C", place]
    end
    out, status = Open3.capture2e({ "ARCHIVE" => archive, "PLACE" => place }, *command)
    assert_predicate status, :success?, out
  end

  # Runs the app, never through a shell, with nothing in its environment
  # but +env+. Windows' network and cryptography libraries need
  # SystemRoot, so on Windows that stays, with a PATH of System32.
  def run_app(env, app, *argv, chdir: Dir.tmpdir, stdin: "")
    if @platform.windows?
      system_root = ENV.fetch("SystemRoot", "C:\\Windows")
      env = { "SystemRoot" => system_root, "PATH" => File.join(system_root, "System32") }.merge(env)
    end
    Open3.capture3(env, [app, app], *argv, unsetenv_others: true, chdir:, stdin_data: stdin)
  end
end
