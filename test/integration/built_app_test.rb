# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "../test_helper"
require_relative "../../tasks/parity"
require_relative "../support/disk_images"
require_relative "../support/gems"
require_relative "../support/stand_in_notary"
require "digest"
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
  HELLO = File.expand_path("../../examples/hello", __dir__)
  MY_COOL_APP = File.expand_path("../../examples/my_cool_app", __dir__)
  WINDOWED_APP = File.expand_path("../../examples/windowed_app", __dir__)
  PROGRAMS = File.expand_path("../../examples/programs", __dir__)
  PROBE = File.expand_path("../fixtures/parity", __dir__)
  CONSOLE = File.expand_path("../fixtures/console", __dir__)
  RAYLIB = File.expand_path("../fixtures/raylib", __dir__)
  DELIVER_CONSOLE = File.expand_path("../../.github/scripts/deliver-console.sh", __dir__)
  EXE = File.expand_path("../../exe/fledge", __dir__)
  LIB = File.expand_path("../../lib", __dir__)

  def setup
    @platform = Fledge::Platform.local
    @runtimes = ENV.fetch("FLEDGE_RUNTIME_DIR", File.expand_path("../../tmp/runtime", __dir__))
    return if File.file?(File.join(@runtimes, Fledge::Runtimes.file_name(@platform)))

    message = "no #{Fledge::Runtimes.file_name(@platform)} in #{@runtimes}; run bundle exec rake runtime"
    flunk message if ENV["FLEDGE_REQUIRE_RUNTIME"]
    skip message
  rescue Fledge::Error => e
    flunk e.message if ENV["FLEDGE_REQUIRE_RUNTIME"]
    skip e.message
  end

  def expected
    "Hello from Ruby 4.1.0 on #{expected_platform}\n"
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
  # compile there (Parity::WITHOUT_SQLITE3;
  # doc/contributors/design/parity.md, "The gem-shaped run").
  def gem_shaped!
    skip "sqlite3, which examples/my_cool_app locks, does not install on #{@platform} (doc/contributors/design/parity.md, \"The gem-shaped run\")" if
      Parity::WITHOUT_SQLITE3.include?(@platform.name)
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

  # ADR 081: Ctrl-C typed into a terminal, and a hangup, end the built
  # console probe as they end ruby main.rb, through Ruby's own handlers
  # (.github/scripts/deliver-console.sh, which CI's Delivery runs too;
  # doc/contributors/design/parity.md, "Console checks"). Windows'
  # console is CI's to check, with deliver-console.ps1.
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
  # puts them back: the app's own gems stay the runtime's, and
  # a Ruby the app starts sees the person's settings, as under ruby
  # main.rb.
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

  # An app with a Gemfile gets the ENV bundle exec gives:
  # Bundler's settings over the person's, so a child Ruby runs in the
  # app's bundle with the person's RUBYOPT after Bundler's own, and
  # Bundler.with_original_env and with_unbundled_env, which a Bundler
  # app uses to start a person's own tools, give the person's
  # environment back. The app's own gems stay the runtime's. The
  # environment names no locale, so the child's is C, which bin/ruby
  # makes a UTF-8 one as the launcher does: in a C locale,
  # Bundler 4.0.20 cannot set up a bundle in a folder whose name is not
  # ASCII, and the app is unpacked in one.
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
  # executable runs on, chooses its locale as the launcher does (after
  # PEP 538): with no locale in the environment, which is C,
  # it reads a folder whose name is not ASCII as UTF-8. Windows has no C
  # locale to turn: its ruby.exe reads paths as UTF-8 whatever the code
  # page (doc/contributors/design/launcher.md, "The locale").
  def test_the_runtimes_own_ruby_turns_a_c_locale_into_utf8_as_the_launcher_does
    skip "Windows has no C locale (doc/contributors/design/launcher.md, \"The locale\")" if @platform.windows?

    Dir.mktmpdir do |dir|
      script = File.join(dir, "Ünïcödé", "encoding.rb")
      FileUtils.mkdir_p(File.dirname(script))
      File.write(script, "print Encoding.default_external, ' ', __dir__.encoding, ' ', __dir__.valid_encoding?\n")
      out, err, status = run_app({ "HOME" => dir }, File.join(File.dirname(app), "bin", "ruby"), script)

      assert_equal ["UTF-8 UTF-8 true", "", 0], [out, err, status.exitstatus]
    end
  end

  # The launcher and bin/ruby keep a character set the person chose, C
  # included, as ruby does, and turn only a C locale that comes from
  # LANG or from no variable at all into a UTF-8 one (PEP 538
  # never coerces under LC_ALL). The probe and the script run from a
  # folder whose name is ASCII, where ruby itself runs in a C locale.
  def test_an_explicit_c_locale_is_kept_and_only_a_bare_one_becomes_utf8
    skip "Windows takes its encoding from the console's code page (ADR 081)" if @platform.windows?

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

  # An app built with fledge build --from takes the runtime and
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
        "DEPENDENCIES\n  greeter!\n\nCHECKSUMS\n  greeter (1.0)\n\nBUNDLED WITH\n  #{FakeProject.runtime_bundler}\n")
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
      assert_equal [true, ""], [status.success?, but_unchecked(err)]
      assert_equal "#{File.join(place, "Game-#{@platform}#{@platform.archive_extension}")}\n", out

      out, err, status = run_app({ "HOME" => dir }, File.join(place, "Game-#{@platform}", @platform.executable("Game")))
      assert_equal ["hello from greeter in app\n", "", 0], [out, err, status.exitstatus]
    end
  end

  # Ruby 4.1's new digests and zlib load in a built app, each finding the
  # DLLs it imports in the runtime: on Windows, RubyInstaller's head build
  # ships neither the libz-1.dll its zlib.so imports nor the GCC runtime
  # library its x64 digest/blake3.so does, and the runtime adds both
  # (runtime/sources.yml, windows-dlls). A Ruby the app starts through
  # RbConfig.ruby loads them too: on Windows the runtime's ruby.exe looks
  # for DLLs where the launcher does (windows_relaunch.c,
  # fledge_limit_dll_search). BLAKE3 of nothing, and CRC-32 of "abc", are
  # those algorithms' published test vectors.
  def test_zlib_and_rubys_new_digests_load_in_a_built_app
    Dir.mktmpdir do |dir|
      project = File.join(dir, "digests")
      FileUtils.mkdir_p(project)
      File.write(File.join(project, "digests.rb"), <<~RUBY)
        require "zlib"
        require "digest"
        puts Digest::BLAKE3.hexdigest(""), Digest::CRC32.hexdigest("abc"), Zlib.crc32("abc").to_s(16)
      RUBY
      File.write(File.join(project, "main.rb"), <<~RUBY)
        load File.join(__dir__, "digests.rb")
        $stdout.flush
        system(RbConfig.ruby, File.join(__dir__, "digests.rb"), exception: true)
      RUBY
      File.write(File.join(project, "fledge.yml"), "name: Digests\n")
      launcher = build_and_unpack(dir, project, name: "Digests")

      out, err, status = run_app({ "HOME" => dir }, launcher, chdir: dir)

      assert_equal ["af1349b9f5f9a1a6a0404dea36dcc9499bcb25c9adc112b7cc9a93cae41f3262\n352441c2\n352441c2\n" * 2, "", 0],
        [out, err, status.exitstatus]
    end
  end

  # On Windows both launchers declare UTF-8 as the process's ANSI code
  # page, so a Windows function that takes a narrow string reads Ruby's
  # UTF-8 path as UTF-8. ffi opens a gem's DLL with LoadLibraryExA
  # (ext/ffi_c/DynamicLibrary.c, lines 215 to 225, at ffi 1.17.4), which
  # under code page 1252 finds no DLL under a folder named outside ASCII,
  # as every app here is unpacked under "Ünïcödé 日本". The runtime's
  # ruby.exe, which RbConfig.ruby names, declares it too, so a Ruby the
  # app starts reads it the same way.
  def test_a_windows_app_reads_a_narrow_strings_path_as_utf8
    skip "the ANSI code page is Windows'" unless @platform.windows?

    Dir.mktmpdir do |dir|
      project = File.join(dir, "acp")
      FileUtils.mkdir_p(project)
      File.write(File.join(project, "acp.rb"), <<~RUBY)
        require "fiddle"
        kernel32 = Fiddle.dlopen("kernel32.dll")
        acp = Fiddle::Function.new(kernel32["GetACP"], [], Fiddle::TYPE_INT).call
        load = Fiddle::Function.new(kernel32["LoadLibraryExA"], [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT], Fiddle::TYPE_VOIDP)
        dll = Dir.glob(File.join(RbConfig::TOPDIR, "lib", "ruby", "*", "*-mingw-ucrt", "libz-1.dll")).fetch(0)
        handle = load.call(dll, nil, 8) # LOAD_WITH_ALTERED_SEARCH_PATH, as ffi passes for a full path
        File.write(ARGV.fetch(0), "code page \#{acp}, \#{handle.null? ? "no DLL" : "loaded"} from \#{dll.encoding}\\n", mode: "a")
      RUBY
      File.write(File.join(project, "main.rb"), <<~RUBY)
        load File.join(__dir__, "acp.rb")
        system(RbConfig.ruby, File.join(__dir__, "acp.rb"), ARGV.fetch(0), exception: true)
      RUBY
      %w[console windowed].each do |kind|
        File.write(File.join(project, "fledge.yml"), "name: Acp#{kind}\nkind: #{kind}\nidentifier: com.setdef.fledge.Acp#{kind}\n")
        launcher = build_and_unpack(dir, project, name: "Acp#{kind}")
        report = File.join(dir, "#{kind}.txt")

        _, err, status = run_app({ "HOME" => dir }, launcher, report, chdir: dir)

        assert_equal ["", 0], [err, status.exitstatus], kind
        assert_equal "code page 65001, loaded from UTF-8\n" * 2, File.read(report), "#{kind}, then a child through RbConfig.ruby"
      end
    end
  end

  # An app whose name, and a file of whose project, Windows' ANSI code
  # page cannot write is archived under its own names, which
  # Expand-Archive unpacks as a person on Windows would, and runs. The
  # project and the build's output, where the runtime is unpacked, are
  # in a folder so named too, as a person's are whose account is. The
  # premise is the system's code page, as the registry keeps it, which
  # Windows' own tools run in: this test's own Ruby may declare UTF-8 as
  # its process's, as the runtime's does.
  def test_a_windows_app_named_outside_the_ansi_code_page_is_archived_under_its_names
    skip "the ANSI code page is Windows'" unless @platform.windows?
    name = "日本語ツール"
    skip "code page #{system_code_page} can write #{name}" if writable?(name, system_code_page)

    Dir.mktmpdir do |tmp|
      dir = File.join(tmp, "Jürgen 日本")
      project = File.join(dir, "nihongo")
      FileUtils.mkdir_p(File.join(project, "挨拶 ü"))
      FileUtils.cp(File.join(HELLO, "main.rb"), project)
      File.write(File.join(project, "挨拶 ü", "こんにちは.txt"), "hi\n")
      File.write(File.join(project, "fledge.yml"), "name: #{name}\n")
      launcher = build_and_unpack(dir, project, name:)

      out, err, status = run_app({ "HOME" => dir }, launcher)

      assert_equal [expected, "", 0], [out, err, status.exitstatus]
      assert_equal "hi\n", File.read(File.join(File.dirname(launcher), "app", "挨拶 ü", "こんにちは.txt"))
    end
  end

  # The ANSI code page as reg.exe reads it from the registry. Ruby's
  # win32/registry and fiddle are bundled gems, which the Gemfile does
  # not lock, so neither loads under bundle exec.
  def system_code_page
    reg = File.join(ENV.fetch("SystemRoot", "C:\\Windows"), "System32", "reg.exe")
    out, status = Open3.capture2(reg, "query", "HKLM\\SYSTEM\\CurrentControlSet\\Control\\Nls\\CodePage", "/v", "ACP")
    assert_predicate status, :success?, out
    Integer(out[/ACP\s+REG_SZ\s+(\d+)/, 1])
  end

  def writable?(text, code_page)
    text.encode("CP#{code_page}")
    true
  rescue EncodingError
    false
  end

  # require "mkmf" loads in a built app, as under ruby, since the
  # runtime keeps Ruby's headers, and some gems require it at
  # run time for MakeMakefile#find_executable.
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

  # mkmf's checks link a test program against Ruby's library, a static
  # libruby on macOS and Linux and the import library of Ruby's DLL on
  # Windows, which the runtime keeps, so they work in a built app where a
  # compiler is, as under the Ruby the runtime was made from; without the
  # library they raise "The compiler failed to generate an executable
  # file". In a folder whose path has a space they fail, as that Ruby's
  # own do when it runs the same program by the same path: mkmf builds
  # its link command with paths it does not quote (mkmf.rb, link_config,
  # lines 541 to 553, at Ruby 4.1.0-preview1), among them the program's
  # own folder, -I$(srcdir), from $0 (line 2876), which the launcher
  # gives as ruby /path/to/app/main.rb would, and on Linux rv-ruby's
  # LIBRUBYARG_STATIC, -Wl,-rpath,$(libdir), so the linker takes the part
  # after the space for a file ("ld.bfd: cannot find
  # space/rv/rv-ruby@4.1.0-preview1/4.1.0-preview1/lib" for rv-ruby's own
  # ruby on Linux; "ld.exe: cannot find Apps/MkmfLinkApp-x64-mingw-ucrt/app"
  # for the app on Windows, 2026-11-12). The stock Ruby is rv-ruby's
  # release, as the parity check unpacks it, or on Windows
  # RubyInstaller's own ruby.exe in the app's tree.
  def test_mkmf_checks_link_in_a_built_app_as_under_stock_ruby_where_a_compiler_is
    compiler = @platform.windows? ? "gcc" : "cc"
    skip "no #{compiler} on PATH to link with" unless ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).any? do |folder|
      File.executable?(File.join(folder, compiler)) || File.executable?(File.join(folder, "#{compiler}.exe"))
    end

    Dir.mktmpdir do |dir|
      code = "require \"mkmf\"\nputs \"linked \#{have_func('rb_str_new', 'ruby.h')}\"\n"
      project = File.join(dir, "mkmf-link-app")
      FileUtils.mkdir_p(project)
      File.write(File.join(project, "main.rb"), code)
      File.write(File.join(project, "fledge.yml"), "name: MkmfLinkApp\n")
      # A person's TMP and TEMP, where MinGW's gcc writes its temporary
      # files; without them it tries C:\Windows.
      env = { "HOME" => dir, "PATH" => ENV.fetch("PATH"), "TMP" => dir, "TEMP" => dir }
      log = File.join(dir, "mkmf.log")
      outcome = lambda do |command|
        FileUtils.rm_f(log)
        out, err, status = run_app(env, *command, chdir: dir)
        [status.success? && out.include?("linked true"), "#{out}\n#{err}\n#{File.read(log) if File.file?(log)}"]
      end

      results = { "apps" => true, "My Apps" => nil }.to_h do |folder, expected|
        place = File.join(dir, folder)
        launcher = build_and_unpack(dir, project, name: "MkmfLinkApp", place:)
        stock = if @platform.windows?
          File.join(File.dirname(launcher), "ruby", "bin", "ruby.exe")
        else
          FileUtils.mkdir_p(File.join(place, "stock"))
          Parity.new(platform: @platform, work: File.join(place, "stock"), runtimes: @runtimes).unpack_reference
        end
        # As the launcher runs it (ruby /path/to/app/main.rb): mkmf takes
        # $(srcdir) from the program's folder (mkmf.rb, line 2876).
        stock_linked, stock_output = outcome.call([stock, File.join(File.dirname(launcher), "app", "main.rb")])
        app_linked, app_output = outcome.call([launcher])
        assert_equal stock_linked, app_linked, "in #{folder.inspect}: stock Ruby\n#{stock_output}\nthe app\n#{app_output}"
        assert stock_linked, stock_output if expected
        [folder, app_linked]
      end

      assert results.fetch("apps")
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

  # fiddle, a bundled gem since Ruby 4.0 (gems/bundled_gems at
  # v4_1_0_preview1), loads in an app as it loads under ruby main.rb and
  # bundle exec: with no Gemfile, from the runtime's gems; with a Gemfile
  # that leaves it out, not at all, with Ruby's own warning that it is no
  # longer a default gem and a LoadError the program may rescue, as
  # bundle exec gives; and with fiddle in the Gemfile, from the runtime's
  # gems again, at the version it carries, which the build does not
  # fetch. The lockfile takes that version and its checksum from the
  # .gem the runtime keeps in its cache.
  def test_a_bundled_gem_loads_as_under_bundle_exec_with_and_without_a_gemfile
    Dir.mktmpdir do |dir|
      program = "begin\n  require \"fiddle\"\n  puts \"fiddle \#{Fiddle::VERSION}\"\nrescue LoadError => e\n  puts \"\#{e.class}: \#{e.message}\"\nend\n"
      plain = bundled_gem_project(dir, "plain", program)
      app = build_and_unpack(dir, plain)
      gem = Dir.glob(File.join(File.dirname(app), "**", "cache", "fiddle-*.gem")).first
      refute_nil gem, "the runtime keeps no fiddle .gem in its cache"
      version = File.basename(gem, ".gem").delete_prefix("fiddle-")
      out, err, status = run_app({ "HOME" => dir }, app)
      assert_equal ["fiddle #{version}\n", "", 0], [out, err, status.exitstatus], "no Gemfile"

      without = bundled_gem_project(dir, "without", program, gems: {})
      out, err, status = run_app({ "HOME" => dir }, build_and_unpack(dir, without))
      assert_equal ["LoadError: cannot load such file -- fiddle\n", 0], [out, status.exitstatus], "a Gemfile without fiddle: #{err}"
      assert_includes err, "fiddle used to be loaded from the standard library, but is not part of the default gems since Ruby 4.0.0."

      with = bundled_gem_project(dir, "with", program, gems: { "fiddle" => [version, Digest::SHA256.file(gem).hexdigest] })
      out, err, status = run_app({ "HOME" => dir }, build_and_unpack(dir, with))
      assert_equal ["fiddle #{version}\n", "", 0], [out, err, status.exitstatus], "a Gemfile with fiddle"
    end
  end

  # A project whose Gemfile takes Fledge from git in its development
  # group, as the README's line does, here from this checkout's commit,
  # builds, and its app runs with Fledge's whole checkout in it, as
  # bundle exec has it: the program requires fledge, which Bundler sets
  # up in the development group. On macOS the build signs every Mach-O
  # file the app carries.
  def test_an_app_whose_gemfile_carries_fledge_as_the_readme_says_builds_and_runs
    root = File.expand_path("../..", __dir__)
    revision = IO.popen(["git", "-C", root, "rev-parse", "HEAD"], &:read).strip
    Dir.mktmpdir do |dir|
      project = bundled_gem_project(dir, "greeter", "require \"fledge\"\nputs \"fledge \#{Fledge::VERSION}\"\n")
      File.write(File.join(project, "Gemfile"),
        "source \"https://rubygems.org\"\n\ngem \"fledge\", git: #{root.inspect}, ref: #{revision.inspect}, group: :development\n")
      platforms = %w[aarch64-linux aarch64-linux-musl aarch64-mingw-ucrt arm64-darwin ruby x64-mingw-ucrt x86_64-linux x86_64-linux-musl]
      File.write(File.join(project, "Gemfile.lock"), "GIT\n  remote: #{root}\n  revision: #{revision}\n  ref: #{revision}\n  specs:\n" \
        "    fledge (#{Fledge::VERSION})\n\nGEM\n  remote: https://rubygems.org/\n  specs:\n\n" \
        "PLATFORMS\n#{platforms.map { |platform| "  #{platform}\n" }.join}\nDEPENDENCIES\n  fledge!\n\n" \
        "CHECKSUMS\n  fledge (#{Fledge::VERSION})\n\nBUNDLED WITH\n  #{FakeProject.runtime_bundler}\n")

      out, err, status = run_app({ "HOME" => dir }, build_and_unpack(dir, project))

      assert_equal ["fledge #{Fledge::VERSION}\n", "", 0], [out, err, status.exitstatus]
    end
  end

  # A project in +dir+ named +name+ whose main.rb is +program+, with a
  # Gemfile and lockfile of +gems+ (name to version and SHA-256) from
  # RubyGems.org when +gems+ is given, and none otherwise.
  def bundled_gem_project(dir, name, program, gems: nil)
    project = File.join(dir, name)
    FileUtils.mkdir_p(File.join(project, ".git"))
    File.write(File.join(project, "main.rb"), program)
    return project unless gems

    platforms = %w[aarch64-linux aarch64-linux-musl aarch64-mingw-ucrt arm64-darwin ruby x64-mingw-ucrt x86_64-linux x86_64-linux-musl]
    File.write(File.join(project, "Gemfile"), "source \"https://rubygems.org\"\n\n#{gems.keys.map { |gem| "gem \"#{gem}\"\n" }.join}")
    File.write(File.join(project, "Gemfile.lock"), "GEM\n  remote: https://rubygems.org/\n  specs:\n" \
      "#{gems.map { |gem, (version, _)| "    #{gem} (#{version})\n" }.join}\n" \
      "PLATFORMS\n#{platforms.map { |platform| "  #{platform}\n" }.join}\n" \
      "DEPENDENCIES\n#{gems.keys.map { |gem| "  #{gem}\n" }.join}\n" \
      "CHECKSUMS\n#{gems.map { |gem, (version, sha256)| "  #{gem} (#{version}) sha256=#{sha256}\n" }.join}\n" \
      "BUNDLED WITH\n  #{FakeProject.runtime_bundler}\n")
    project
  end

  # A program restarts itself as Ruby programs do, with exec
  # RbConfig.ruby, $0, *ARGV, and the runtime's bin/ruby hands the app's
  # own program back to its launcher. So the restart is the
  # same process running the same program, in the same locale, with the
  # same gems and environment: with no locale, from a folder whose name
  # is not ASCII, in the person's environment and in a hostile one, with
  # a Gemfile and without, and in a macOS .app, in the same bundle. On
  # Windows, where the runtime's ruby.exe runs the app's launcher in a
  # process of its own and waits for it, as Ruby's own exec does there,
  # the restart is a new process, and the same program, with the same
  # code page and AppUserModelID, console and windowed alike. The probe
  # compares what it sees after the restart with what it saw before.
  def test_a_restart_through_rbconfig_ruby_is_the_same_app_again
    Dir.mktmpdir do |dir|
      evil = File.join(dir, "evil")
      FileUtils.mkdir_p(evil)
      %w[json nonexistent bundler_setup].each { |name| File.write(File.join(evil, "#{name}.rb"), "raise 'the caller\\'s Ruby environment leaked into the restart'\n") }
      person = { "HOME" => dir, "GEM_HOME" => File.join(dir, "person gems"), "RUBYOPT" => "-W0", "RUBYLIB" => evil }
      hostile = person.merge("RUBYOPT" => "-rnonexistent", "BUNDLER_SETUP" => File.join(evil, "bundler_setup.rb"),
        "BUNDLE_GEMFILE" => File.join(evil, "Gemfile"), "RUBYGEMS_GEMDEPS" => "-")
      programs = [probe]
      programs << windowed_probe if @platform.os == "darwin" || @platform.windows?
      programs << bundled_probe unless Parity::WITHOUT_SQLITE3.include?(@platform.name)

      programs.product([{ "HOME" => dir }, person, hostile]).each do |program, env|
        out, err, status = run_app(env, program, "restart")
        assert_equal ["restarted as itself\n", "", 0], [out, err, status.exitstatus], "#{program} with #{env.keys.join(', ')}"
      end
    end
  end

  # A child Ruby the app starts with the bundler/setup Bundler put in
  # RUBYOPT sets up the app's own Gemfile, as under bundle exec, though
  # the person's own Bundler settings, in HOME's .bundle/config, name
  # another, and so does their BUNDLE_GEMFILE, which on Windows, whose
  # variable names ignore case, they may spell bundle_gemfile (AGENTS.md,
  # Design precedence 1; doc/contributors/design/launcher.md, "Bundler's
  # variables spelled otherwise").
  def test_a_child_ruby_of_a_bundler_app_sets_up_the_apps_gemfile
    Dir.mktmpdir do |dir|
      evil = person_gemfile(dir)
      gemfile = File.join(File.dirname(bundled_probe), "app", "Gemfile")
      spellings = @platform.windows? ? %w[BUNDLE_GEMFILE bundle_gemfile] : %w[BUNDLE_GEMFILE]

      spellings.each do |name|
        out, err, status = run_app({ "HOME" => dir, name => evil }, bundled_probe, "child-gemfile")
        assert_equal ["", 0], [err, status.exitstatus], name
        assert File.identical?(out.chomp, gemfile), "#{name}: the child set up #{out.inspect}, not #{gemfile}"
      end
    end
  end

  # On Windows a person's bundle_gemfile is Bundler's BUNDLE_GEMFILE, but
  # Bundler's settings read ENV by Bundler's spelling alone (settings.rb,
  # Settings#initialize, at Bundler 4.0.20), so the app's ENV names its
  # Gemfile as BUNDLE_GEMFILE, where bundle exec keeps the person's
  # spelling, and a restart finds nothing changed. The probe's report
  # requires racc/cparse with no racc in its Gemfile, for which Ruby
  # warns under Bundler, as under bundle exec (lib/bundled_gems.rb,
  # build_message), and the report says nothing else on standard error.
  def test_a_bundler_app_spells_its_gemfile_as_bundler_does_through_a_restart
    skip "only Windows' variable names ignore case" unless @platform.windows?
    Dir.mktmpdir do |dir|
      gemfile = File.join(File.dirname(bundled_probe), "app", "Gemfile")
      env = { "HOME" => dir, "bundle_gemfile" => person_gemfile(dir) }

      out, err, status = run_app(env, bundled_probe)
      report = JSON.parse(out[/^FLEDGE-PARITY (.*)$/, 1])
      racc = %r{\A.+:\d+: warning: racc/cparse is found in racc, which .*\r?\nYou can add racc to your Gemfile or gemspec to \w+ this \w+\.\r?\n}

      assert_equal ["", 0], [err.sub(racc, ""), status.exitstatus]
      assert_equal ["BUNDLE_GEMFILE"], report.fetch("ENV").keys.grep(/\Abundle_gemfile\z/i)
      assert File.identical?(report.fetch("ENV").fetch("BUNDLE_GEMFILE"), gemfile), report.fetch("ENV").fetch("BUNDLE_GEMFILE")
      assert_equal ["restarted as itself\n", "", 0], run_app(env, bundled_probe, "restart").then { |o, e, s| [o, e, s.exitstatus] }
    end
  end

  # bin/ruby hands only its first argument to the launcher, and only
  # when it is an app's program
  # (doc/contributors/design/launcher.md, "bin/ruby and restarts"): with
  # an option before the program, it is plain Ruby, whose RubyGems reads
  # the person's GEM_HOME, as ruby -W1 main.rb would.
  def test_bin_ruby_runs_an_apps_program_through_its_launcher_unless_an_option_comes_first
    ruby = runtimes_ruby(File.dirname(probe))
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

  # A missing fledge.cfg is EX_NOINPUT, as a missing entry is
  # (doc/contributors/design/public-interface.md, "Frozen for 1.x").
  def test_a_missing_fledge_cfg_exits_with_ex_noinput
    config = File.join(File.realpath(File.dirname(app)), "fledge.cfg")
    File.rename(config, "#{config}.away")
    out, err, status = run_app({}, app)

    assert_equal ["", 66], [out, status.exitstatus]
    assert_equal "#{@platform.executable('Hello')}: this app is incomplete: #{config.tr('/', File::ALT_SEPARATOR || '/')} is missing\n",
      err.gsub("\r\n", "\n")
  ensure
    File.rename("#{config}.away", config) if config && File.exist?("#{config}.away")
  end

  # bin/ruby hands an app's own script to the app's launcher,
  # and exits with EX_SOFTWARE when it finds the launcher and the system
  # will not run it. The launcher here is executable, so bin/ruby finds
  # it, and is no program, so execv fails. On Windows a launcher is a
  # program that holds the launcher's mark (windows_relaunch.c), which
  # this file holds, and CreateProcessW fails.
  def test_bin_ruby_exits_with_ex_software_when_it_cannot_run_the_launcher
    folder = File.realpath(File.dirname(app))
    launcher = File.join(folder, @platform.executable("Hello"))
    # Kept out of the folder, where any executable file is a launcher.
    kept = "#{folder}.launcher"
    File.rename(launcher, kept)
    File.write(launcher, "not a program\n#{launcher_mark if @platform.windows?}\n")
    File.chmod(0o755, launcher)
    out, err, status = run_app({}, runtimes_ruby(folder), File.join(folder, "app", "main.rb"))

    assert_equal ["", 70], [out, status.exitstatus], err
    assert_includes err.tr("\\", "/"), "ruby: could not run #{launcher}: "
  ensure
    File.rename(kept, launcher) if kept && File.exist?(kept)
  end

  # In an app of one program, whose fledge.cfg has no sections, a
  # Windows runtime's ruby.exe takes only a program that holds the
  # launcher's mark for the app's launcher, so an installer's
  # uninstall.exe beside it is never run in its place
  # (windows_relaunch.c). With no launcher there, the app's program runs
  # as plain Ruby, and prints what it prints in the app, where whoami.exe,
  # standing in for uninstall.exe, would print a user's name.
  def test_ruby_exe_runs_no_other_program_beside_the_launcher_in_its_place
    skip "only Windows finds a launcher by its mark" unless @platform.windows?
    folder = File.realpath(File.dirname(app))
    launcher = File.join(folder, @platform.executable("Hello"))
    impostor = File.join(folder, "uninstall.exe")
    kept = "#{folder}.launcher"
    File.rename(launcher, kept)
    FileUtils.cp(File.join(ENV.fetch("SystemRoot", "C:/Windows"), "System32", "whoami.exe"), impostor)
    out, err, status = run_app({}, runtimes_ruby(folder), File.join(folder, "app", "main.rb"))

    assert_equal [expected, "", 0], [out, err, status.exitstatus]
  ensure
    FileUtils.rm_f(impostor) if impostor
    File.rename(kept, launcher) if kept && File.exist?(kept)
  end

  # The runtime's own Ruby in the built app's +folder+: bin/ruby, or on
  # Windows ruby\bin\ruby.exe.
  def runtimes_ruby(folder)
    @platform.windows? ? File.join(folder, "ruby", "bin", "ruby.exe") : File.join(folder, "bin", "ruby")
  end

  # The bytes every Windows launcher holds (runtime/launcher/launcher.h).
  def launcher_mark
    File.read(File.expand_path("../../runtime/launcher/launcher.h", __dir__))[/#define FLEDGE_LAUNCHER_MARK "([^"]+)"/, 1]
  end

  # On Linux, a library the app's gems load from the
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

  # On Linux, a typelib the app's gems load from the distribution that
  # this computer's libgirepository cannot load stops the app before Ruby
  # starts, with EX_OSFILE and the typelib's name, never Ruby's
  # GObjectIntrospection error from inside a gem; on a computer without
  # libgirepository at all, the app names that library.
  # test/integration/typelib_test.rb shows a gem's real typelib.
  def test_a_typelib_the_computer_lacks_is_named_before_ruby_starts
    skip "only a Linux app's gems load typelibs from its distribution" unless @platform.os == "linux"
    config = File.join(File.realpath(File.dirname(app)), "fledge.cfg")
    original = File.read(config)

    File.write(config, "#{original}system_typelibs = FledgeAbsent-1.0\n")
    out, err, status = run_app({}, app)

    assert_equal ["", 72], [out, status.exitstatus]
    if IO.popen(["/sbin/ldconfig", "-p"], &:read).include?("libgirepository-1.0.so.1 (")
      assert_equal "Hello: this app needs FledgeAbsent-1.0.typelib, which this computer does not have (Typelib file for namespace " \
        "'FledgeAbsent', version '1.0' not found). Install it from your Linux distribution's packages, then run the app again\n", err
    else
      assert_match(/\AHello: this app needs libgirepository-1\.0\.so\.1, which this computer does not have \(.*libgirepository-1\.0\.so\.1.*\)\. /, err)
    end
  ensure
    File.write(config, original) if config && original
  end

  # The libraries test/fixtures/raylib's libraylib needs of a Linux
  # computer, by architecture, as the gem's
  # lib/libraylib.ARCH.so names them: those manylinux lets a gem assume,
  # and those the fixture lists as the distribution's (system_libraries).
  RAYLIB_NEEDS = {
    "x86_64" => [%w[libX11.so.6 libXext.so.6], %w[libGLX.so.0 libOpenGL.so.0]],
    "aarch64" => [%w[libX11.so.6 libXext.so.6 libICE.so.6 libSM.so.6], %w[libGLX.so.0 libOpenGL.so.0]],
  }.freeze

  # raylib-bindings' raygui and physac libraries need libraylib by its
  # SONAME or install name, which no file of the gem is named, and load
  # because the gem loads libraylib first (test/fixtures/raylib/main.rb).
  # fledge build ships it, and the app loads all three as bundle exec
  # does. On Linux a computer without a library the fixture lists stops
  # the app before Ruby starts, naming it; one without a library
  # manylinux assumes cannot run this test.
  def test_a_gem_whose_libraries_need_each_other_by_their_own_names_ships_and_loads
    skip "test/fixtures/raylib locks raylib-bindings for macOS and glibc's Linux only" if @platform.windows? || @platform.musl?
    absent = []
    if @platform.os == "linux"
      have = IO.popen(["/sbin/ldconfig", "-p"], &:read)
      assumed, listed = RAYLIB_NEEDS.fetch(@platform.name.split("-").first).map { |names| names.reject { |name| have.include?("#{name} (") } }
      skip "this computer lacks #{assumed.join(', ')}, which manylinux lets a gem assume" unless assumed.empty?
      absent = listed
    end

    out, err, status = run_app({}, built(RAYLIB))

    if absent.empty?
      assert_equal ["raylib: GetRandomValue(7, 7) = 7\nraygui: GuiGetState() = 0\nphysac: GetPhysicsBodiesCount() = 0\n", "", 0],
        [out, err, status.exitstatus]
    else
      assert_equal ["", 72], [out, status.exitstatus]
      assert_match(/\ARaylib Probe: this app needs (#{absent.map { |name| Regexp.escape(name) }.join('|')}), which this computer does not have/, err)
    end
  end

  # On Windows, a DLL of Microsoft's Visual C++ runtime that the app's
  # gems need and the app does not carry (visual_c_runtime: central),
  # and that System32 lacks, stops the app before Ruby starts, with
  # EX_OSFILE and the Redistributable's name, never a LoadError or a
  # Fiddle::DLError that names a gem; a DLL System32 holds changes
  # nothing. The launcher looks for files by name, so kernel32.dll, in
  # every System32, stands in for a runtime's DLL the computer has.
  def test_a_visual_c_runtime_the_computer_lacks_is_named_before_ruby_starts
    skip "only a Windows app's gems need Microsoft's Visual C++ runtime" unless @platform.windows?
    config = File.join(File.realpath(File.dirname(app)), "fledge.cfg")
    original = File.binread(config)

    File.binwrite(config, "#{original}visual_c_runtime = kernel32.dll\n")
    assert_equal [expected, "", 0], run_app({}, app).then { |out, err, status| [out, err, status.exitstatus] }

    File.binwrite(config, "#{original}visual_c_runtime = kernel32.dll fledge-absent140.dll\n")
    out, err, status = run_app({}, app)
    assert_equal ["", 72], [out, status.exitstatus]
    redistributable = @platform.name.start_with?("aarch64") ? "vc_redist.arm64.exe" : "vc_redist.x64.exe"
    folder = err[/ \((.+) has no fledge-absent140\.dll\)/, 1].to_s
    assert folder.casecmp?(File.join(ENV.fetch("SystemRoot"), "System32").tr("/", "\\")), err
    assert_equal "#{@platform.executable('Hello')}: this app needs Microsoft's Visual C++ Redistributable, which this computer does not have " \
      "(#{folder} has no fledge-absent140.dll). Install it from https://aka.ms/vc14/#{redistributable}, then run the app again\n", err
  ensure
    File.binwrite(config, original) if config && original
  end

  # The gem-shaped app: exe/my_cool_app, with i18n and the
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

  # An app whose Gemfile.lock names a Bundler the runtime's Ruby
  # does not ship runs with that Bundler, as bundle exec does, and tells a
  # Ruby it starts so, whatever BUNDLER_VERSION the person has.
  def test_an_app_runs_the_bundler_its_lockfile_names
    Dir.mktmpdir do |dir|
      program = built(File.join(Parity::BUNDLED_WITH_APP, "exe", "bundled_with"))

      out, err, status = run_app({ "HOME" => dir, "BUNDLER_VERSION" => "2.1.0" }, program, "4")

      assert_equal ["Bundler 4.0.19 set up concurrent-ruby 1.3.8, and BUNDLER_VERSION is 4.0.19\n", "", 4], [out, err, status.exitstatus]
    end
  end

  # A Gemfile may ask for the Ruby the app runs on by its .ruby-version,
  # which names a preview as 4.1.0-preview1. Bundler compares it with
  # Gem.ruby_version, 4.1.0.preview1 on a preview and 4.1.0.dev on a
  # build of Ruby's master, so fledge build must read the runtime's Ruby
  # as that version, and the app's own Bundler then starts the app
  # (doc/contributors/design/gems.md, "The runtime's Ruby version"). A
  # runtime read as plain 4.1.0 would build an app its Bundler refuses.
  def test_an_app_whose_gemfile_names_the_runtimes_ruby_by_its_ruby_version_file_starts
    version = Fledge::RuntimeContents.read(File.join(@runtimes, Fledge::Runtimes.file_name(@platform))).ruby_version
    Dir.mktmpdir do |dir|
      project = File.join(dir, "named_ruby")
      FileUtils.mkdir_p(project)
      File.write(File.join(project, ".ruby-version"), "#{version.sub(/\A(\d+\.\d+\.\d+)\./, '\1-')}\n")
      File.write(File.join(project, "Gemfile"), "ruby file: \".ruby-version\"\n")
      File.write(File.join(project, "Gemfile.lock"), "GEM\n  specs:\n\nPLATFORMS\n  ruby\n\nDEPENDENCIES\n\nRUBY VERSION\n  ruby #{version}\n")
      File.write(File.join(project, "main.rb"), "puts Gem.ruby_version\n")

      out, err, status = run_app({ "HOME" => dir }, build_and_unpack(dir, project))

      assert_equal ["#{version}\n", "", 0], [out, err, status.exitstatus]
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

  # examples/windowed_app, built as a windowed app: on macOS
  # an .app bundle that Apple's codesign verifies, strictly and deeply,
  # and whose Info.plist plutil reads; on Windows a GUI program; on
  # Linux a folder with a desktop entry. Run by its program, it writes
  # its report and exits with the status it is given; on Windows it has
  # no console, and its AppUserModelID is its identifier.
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
        types = File.read(File.join(folder, "share/mime/packages/com.setdef.fledge.HelloWindow.xml"))
        assert_includes types, %(<mime-type type="application/x-hellowindow">\n    <comment>Hello Window report</comment>\n    <glob pattern="*.hellowindow"/>\n)
      end

      report = File.join(dir, "report.json")
      _, err, status = run_app({ "HOME" => dir }, program, report, "4")

      assert_equal ["", 4], [err, status.exitstatus]
      facts = { "ruby" => "4.1.0", "platform" => expected_platform, "program" => "main.rb", "folder" => "app", "arguments" => 2 }
      facts.merge!("console" => false, "app_user_model_id" => "com.setdef.fledge.HelloWindow") if @platform.windows?
      facts["yjit"] = true unless @platform.windows?
      assert_equal facts, JSON.parse(File.read(report))
    end
  end

  # In a macOS .app the launcher runs from Contents/MacOS, beside links
  # to the runtime and the app in Contents/Resources
  # (Fledge::MacBundle). $0, __FILE__, __dir__, and Ruby's prefix all
  # name the app's real folder there, so File.dirname(__FILE__) is
  # __dir__, as under ruby (doc/contributors/design/launcher.md, "The
  # app folder in a macOS bundle").
  def test_a_mac_apps_program_runs_from_the_folder_it_really_is_in
    skip "only a macOS .app runs its program through links" unless @platform.os == "darwin"

    out, err, status = run_app({ "HOME" => Dir.tmpdir }, windowed_probe)
    assert_equal ["", 0], [err, status.exitstatus]
    report = JSON.parse(out[/^FLEDGE-PARITY (.*)$/, 1].to_s)
    resources = File.realpath(File.join(File.dirname(windowed_probe, 2), "Resources"))

    assert_equal [File.join(resources, "app", "main.rb")] * 3, report.values_at("$0", "__FILE__", "$PROGRAM_NAME")
    assert_equal [File.join(resources, "app"), resources], [report["__dir__"], report.dig("paths", "prefix")]
  end

  # examples/programs: a console program and a windowed one,
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

  # --sign signs every compiled file of an app with the identity
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

  # --notarize, against the stand-in notary service of
  # test/support/stand_in_notary.rb, through fledge build as a developer
  # runs it, with the identity FLEDGE_TEST_SIGN_IDENTITY names (CI's
  # self-signed one; Apple notarizes no ad hoc signature, so "-" skips).
  # The windowed app's disk image goes to Apple signed, holding the
  # signed bundle; Apple's ticket is stapled to the image and then to the
  # bundle, before the archive is packed, so the archive holds the
  # stapled bundle, and the checksum is of the stapled image. The console
  # app's folder goes in a zip archive, and nothing is stapled to it.
  def test_a_notarized_build_staples_before_it_archives
    skip "notarization is Apple's" unless @platform.os == "darwin"
    identity = ENV["FLEDGE_TEST_SIGN_IDENTITY"].to_s
    skip "FLEDGE_TEST_SIGN_IDENTITY names no certificate's identity, which --notarize needs (CI makes one)" if ["", "-"].include?(identity)

    StandInNotary.with do |calls, submitted|
      Dir.mktmpdir do |dir|
        archive, image = notarized_build(dir, WINDOWED_APP, identity)
        stage = File.join(dir, "stage")
        image_name = File.basename(image)
        assert_equal [
          ["notarytool", "submit", image, "--keychain-profile", "fledge-test", "--wait", "--output-format", "json"],
          *%w[staple validate].map { |action| ["stapler", action, image_name, "(in #{File.realpath(File.dirname(image))})"] },
          *%w[staple validate].map { |action| ["stapler", action, "Hello Window.app", "(in #{File.realpath(archive.delete_suffix('.tar.gz'))})"] },
        ], calls.call
        sent = File.join(submitted, image_name)
        verified, status = Open3.capture2e("codesign", "--verify", "--strict", "--verbose=2", sent)
        assert_predicate status, :success?, "the image went to Apple signed: #{verified}"
        DiskImages.mounted(sent) do |mount|
          verified, status = Open3.capture2e("codesign", "--verify", "--strict", "--deep", "--verbose=2", File.join(mount, "Hello Window.app"))
          assert_predicate status, :success?, "the image held the signed bundle: #{verified}"
        end
        assert_equal Digest::SHA256.file(image).hexdigest, File.read("#{image}.sha256").split.first, "the checksum is of the stapled image"
        Fledge::Archive.unpack(archive, into: stage)
        bundle = File.join(stage, File.basename(archive, ".tar.gz"), "Hello Window.app")
        assert_equal StandInNotary::TICKET, File.read(File.join(bundle, "Contents", "CodeResources")).chomp, "the archive holds the stapled bundle"
        verified, status = Open3.capture2e("codesign", "--verify", "--strict", "--deep", "--verbose=2", bundle)
        assert_predicate status, :success?, verified

        before = calls.call.size
        archive, = notarized_build(dir, HELLO, identity)
        assert_equal [%w[notarytool submit]], calls.call.drop(before).map { |call| call.first(2) }
        assert_path_exists File.join(submitted, "Hello-#{@platform}.zip")
        assert_path_exists archive
      end
    end
  end

  # The contract test of --notarize, which only the maintainer runs:
  # Apple's real notary service, with a Developer ID Application
  # identity in FLEDGE_TEST_SIGN_IDENTITY and the keychain profile
  # FLEDGE_TEST_NOTARY_PROFILE names (doc/contributors/signing-test.md).
  # Gatekeeper must accept the disk image and the bundle as notarized,
  # and stapler must validate the ticket on each.
  def test_a_notarized_build_opens_with_gatekeepers_blessing
    profile = ENV["FLEDGE_TEST_NOTARY_PROFILE"].to_s
    skip "FLEDGE_TEST_NOTARY_PROFILE names no notarytool profile; the maintainer runs this with his own" if profile.empty?
    skip "notarization is Apple's" unless @platform.os == "darwin"

    Dir.mktmpdir do |dir|
      archive, image = notarized_build(dir, WINDOWED_APP, ENV.fetch("FLEDGE_TEST_SIGN_IDENTITY"), profile:)
      bundle = File.join(archive.delete_suffix(".tar.gz"), "Hello Window.app")
      [image, bundle].each do |path|
        validated, status = Open3.capture2e("xcrun", "stapler", "validate", path)
        assert_predicate status, :success?, validated
      end
      assessed, status = Open3.capture2e("spctl", "--assess", "--type", "open", "--context", "context:primary-signature", "-vv", image)
      assert_predicate status, :success?, assessed
      assert_includes assessed, "source=Notarized Developer ID"
      assessed, status = Open3.capture2e("spctl", "--assess", "--type", "execute", "-vv", bundle)
      assert_predicate status, :success?, assessed
      assert_includes assessed, "source=Notarized Developer ID"
    end
  end

  # Builds +source+ signed with +identity+ and notarized with the keychain
  # profile +profile+ into DIR/dist, and returns the paths fledge build
  # printed.
  def notarized_build(dir, source, identity, profile: "fledge-test")
    out, err, status = Open3.capture3({ "FLEDGE_RUNTIME_DIR" => @runtimes }, RbConfig.ruby, "-I", LIB, EXE, "build",
      "--sign", identity, "--notarize", profile, "-o", File.join(dir, "dist"), source)
    assert_predicate status, :success?, err
    out.lines.map { |line| File.expand_path(line.chomp, Dir.pwd) }
  end

  # What codesign says of the signature of +path+, and its entitlements.
  def signature(path)
    out, status = Open3.capture2e("codesign", "--display", "--verbose=2", "--entitlements", "-", path)
    assert_predicate status, :success?, out
    out
  end

  # examples/windowed_app's installer, built beside its archive
  # from this computer's runtime: on macOS a disk image that hdiutil
  # verifies and attaches, whose bundle codesign verifies, strictly and
  # deeply, inside it, and runs from it; on Linux an AppImage that runs,
  # extracting itself where there is no FUSE, and that --appimage-extract
  # unpacks into an AppDir; on Windows a setup program, which Delivery
  # installs (.github/scripts/deliver-installer.ps1), compiled by the
  # Windows runtime's own NSIS. On Linux a .deb follows the AppImage,
  # and dpkg-deb reads it back. On Linux the build needs
  # mksquashfs and dpkg-deb.
  def test_the_windowed_apps_installer_holds_the_app_and_runs_it
    Dir.mktmpdir do |dir|
      out, err, status = Open3.capture3({ "FLEDGE_RUNTIME_DIR" => @runtimes, "XDG_CACHE_HOME" => File.join(dir, "cache") }, RbConfig.ruby,
        "-I", LIB, EXE, "build", "-o", File.join(dir, "dist"), WINDOWED_APP)
      assert_predicate status, :success?, err
      installer = File.expand_path(out.lines.fetch(1).chomp, Dir.pwd)
      report = File.join(dir, "report.json")
      facts = { "ruby" => "4.1.0", "platform" => expected_platform, "program" => "main.rb", "folder" => "app", "arguments" => 2 }
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
        assert_msix(out.lines.fetch(2).chomp, dir)
      end
      assert_equal facts, JSON.parse(File.read(report)).slice(*facts.keys) unless @platform.windows?
    end
  end

  # The MSIX package at +path+, which the Windows SDK's MakeAppx packed
  # (Fledge::Msix), read back with Windows' own tar, which reads a zip:
  # examples/windowed_app's identity, its logos, its program, and a
  # fledge.cfg with no identifier. Delivery installs and runs it
  # (.github/scripts/deliver-msix.ps1).
  def assert_msix(path, dir)
    msix = File.expand_path(path, Dir.pwd)
    assert_equal "Hello Window-#{@platform}.msix", File.basename(msix)
    into = File.join(dir, "msix")
    FileUtils.mkdir_p(into)
    listed, status = Open3.capture2e(Fledge::Archive.tar, "-tf", msix)
    assert_predicate status, :success?, listed
    entries = listed.lines.map(&:chomp)
    %w[AppxManifest.xml AppxBlockMap.xml Assets/StoreLogo.png Assets/Square44x44Logo.png Assets/Square150x150Logo.png].each do |entry|
      assert_includes entries, entry
    end
    assert entries.any? { |entry| entry.match?(/\AHello(?:%20| )Window\.exe\z/) }, "the package holds the program"
    extracted, status = Open3.capture2e(Fledge::Archive.tar, "-xf", msix, "-C", into, "AppxManifest.xml", "fledge.cfg")
    assert_predicate status, :success?, extracted
    manifest = File.read(File.join(into, "AppxManifest.xml"))
    architecture = Fledge::Msix::ARCHITECTURES.fetch(@platform.name)
    assert_includes manifest, %(<Identity Name="com.setdef.fledge.HelloWindow" Publisher="CN=Fledge Test Signing" Version="1.2.3.0" ProcessorArchitecture="#{architecture}" />)
    refute_includes File.read(File.join(into, "fledge.cfg")), "identifier"
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
  # it, so a reader other than the bsdtar that wrote the .zip proves it
  # opens; and the system's tar for a .tar.gz. Expand-Archive in
  # Windows PowerShell 5.1 (Microsoft.PowerShell.Archive 1.0.1.0)
  # draws a progress bar for each of a runtime's 3,077 files, which
  # takes most of its time though no one sees it: 51 seconds an app
  # with the bar and 15 without it on a Windows computer (2026-11-20),
  # and on CI's x64 runner, where fledge build takes about 9 seconds,
  # about 52 to build and unpack one app.
  # Silencing the bar changes only what is drawn, not how the files are
  # read or written.
  def unpack(archive, place)
    command = if @platform.windows?
      [
        "powershell",
        "-NoProfile",
        "-NonInteractive",
        "-Command",
        "$ErrorActionPreference = 'Stop'; $ProgressPreference = 'SilentlyContinue'; " \
          "Expand-Archive -LiteralPath $env:ARCHIVE -DestinationPath $env:PLACE",
]
    else
      ["tar", "-xzf", archive, "-C", place]
    end
    out, status = Open3.capture2e({ "ARCHIVE" => archive, "PLACE" => place }, *command)
    assert_predicate status, :success?, out
  end

  # A Gemfile of the person's own that fails when Bundler reads it, in
  # +home+, which a .bundle/config there names too, as the person's own
  # Bundler settings. Returns its path.
  def person_gemfile(home)
    gemfile = File.join(home, "person", "Gemfile")
    FileUtils.mkdir_p([File.dirname(gemfile), File.join(home, ".bundle")])
    File.write(gemfile, "raise \"the person's own Gemfile reached the app\"\n")
    File.write(File.join(home, ".bundle", "config"), "---\nBUNDLE_GEMFILE: \"#{gemfile}\"\n")
    gemfile
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

  # What fledge build wrote on standard error but the line saying that
  # the runtime it took, this checkout's own, is unchecked.
  def but_unchecked(err)
    err.lines.grep_v(/ is used unchecked$/).join
  end
end
