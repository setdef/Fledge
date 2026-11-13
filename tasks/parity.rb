# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require "fileutils"
require "json"
require "open3"
require "rbconfig"
require "stringio"
require "yaml"
require_relative "runtime_builder"
require_relative "../lib/fledge/cli"
require_relative "parity/difference"
require_relative "parity/justification"
require_relative "parity/reports"
require_relative "parity/mobile"

# The parity check (ADR 081 and ADR 086): an app's Ruby code must see the
# same Ruby under Fledge as it does run as its developer runs it.
#
# It builds the probe app in test/fixtures/parity with fledge build, from
# this computer's runtime, runs it, then runs the same main.rb with the
# very Ruby the runtime was made from (rv-ruby's, or RubyInstaller's,
# fetched by the pins in runtime/sources.yml and left as it ships), as
# ruby main.rb from the app's folder. Then it does the same for a
# gem-shaped app: examples/my_cool_app with the probe as its
# exe/my_cool_app, built with its locked gems, against bundle exec ruby
# exe/my_cool_app on the same Ruby, with the bundle installed there as
# its developer would install it (bundle install, into GEM_HOME); and
# again for test/fixtures/bundled_with, whose Gemfile.lock names a
# Bundler no runtime's Ruby ships, which bundle exec runs (ADR 063). Each
# pair gets the same arguments and the same environment: the caller's,
# without the caller's own Ruby settings, plus a GEM_HOME, a RUBYOPT, and
# two markers that stand for a person's. It normalizes paths (the app's
# folder, its project's root, each Ruby's prefix, the home folder, the
# work folder), and compares every fact.
#
# Every difference is either listed in JUSTIFIED, with the reason it is
# right, or fails the check. On Windows it runs the script check again
# under code page 437, as a console in the United States starts. On
# macOS and Linux it runs it again with no locale at all, as a desktop
# starts an app, and under LC_ALL=C and LC_CTYPE=C, which a person sets
# on purpose (ADR 087).
#
# Run it as rake parity, after rake runtime or with FLEDGE_RUNTIME_DIR set.
class Parity
  ROOT = File.expand_path("..", __dir__)
  PROBE = File.join(ROOT, "test", "fixtures", "parity")
  # The gem-shaped app whose exe/my_cool_app the probe stands in for.
  GEM_APP = File.join(ROOT, "examples", "my_cool_app")
  # The app whose Gemfile.lock names another Bundler than the runtime's,
  # whose exe/bundled_with the probe stands in for.
  BUNDLED_WITH_APP = File.join(ROOT, "test", "fixtures", "bundled_with")
  ARGUMENTS = ["one", "two words", "ünïcödé"].freeze

  # rv-ruby installs two gems a standard Ruby 4.1 does not, which a
  # runtime prunes (RuntimeBuilder::Pruning.prune).
  RV_RUBY_EXTRAS = /\A"(?:bootsnap|msgpack)(?: |"=)/

  # Where bundle install puts a gem's files for the person, and where
  # fledge build puts them in the app.
  PERSON_GEMS = %r{<work>/person-gems}
  APP_GEMS = %r{<prefix>/lib/ruby/gems/#{ABI}}o

  # The variables Bundler sets for the bundle it set up, whose values
  # name where the gems are (ADR 086).
  BUNDLE_LOCATIONS = /\A"(?<name>GEM_HOME|PATH)"=/

  # The variables bundle exec sets that name where its Bundler is, when
  # that is a gem bundle install installed for the person, or fledge
  # build for the app: its bundle program, its bundler/setup, and its lib
  # folder (Bundler::SharedHelpers#set_bundle_variables, #set_rubyopt, and
  # #set_rubylib, at Bundler 4.0.20; ADR 063).
  BUNDLER_VARIABLES = /\A"(?<name>BUNDLE_BIN_PATH|BUNDLER_SETUP|RUBYLIB|RUBYOPT)"="(?<before>[^"]*)/

  # The facts a C locale decides: the character set Ruby reads text,
  # paths, and arguments in.
  LOCALE_FACTS = ["Encoding.default_external", "Encoding.find('locale')", "Encoding.find('filesystem')"].freeze

  JUSTIFIED = [
    *%w[$0 __FILE__ $PROGRAM_NAME].map do |fact|
      Justification.new(fact:, reference: [/\A"main\.rb"\z/], app: [%r{\A"<app>/main\.rb"\z}], checks: %i[script],
        reason: "ruby main.rb names the script as typed. The launcher runs it by its absolute path, as " \
          "ruby /path/to/app/main.rb would, since a person may start the app from any folder.")
    end,
    *%w[$0 __FILE__ $PROGRAM_NAME].map do |fact|
      Justification.new(fact:, reference: [%r{\A"exe/(?:my_cool_app|bundled_with)"\z}], app: [%r{\A"<app>/(?:my_cool_app|bundled_with)"\z}],
        checks: %i[bundle],
        reason: "bundle exec ruby exe/my_cool_app names the program as typed. The launcher runs it by its absolute " \
          "path, since a person may start the app from any folder.")
    end,
    Justification.new(fact: "$LOAD_PATH", reference: [%r{\A"#{PERSON_GEMS}/(?<gem>(?:gems|extensions)/.*)\z}],
      app: [%r{\A"#{APP_GEMS}/(?<gem>(?:gems|extensions)/.*)\z}], checks: %i[bundle],
      reason: "bundle install put the gems in the person's GEM_HOME; fledge build put the same gems in the runtime's gem " \
        "folder, beside Ruby's own (doc/contributors/design/gems.md, \"Installing into the runtime's gem folder\"). " \
        "Bundler sets up the same gems, in the same order, from each, and a gem compiled as it installs, as sqlite3 " \
        "is on a Ruby its prebuilt gems do not yet support, adds its extensions folder from each."),
    Justification.new(fact: "$LOADED_FEATURES", reference: [%r{\A"#{PERSON_GEMS}/gems/(?<file>bundler-(?!.*/bundler/feature_flag\.rb"\z).*)\z}],
      app: [%r{\A"#{APP_GEMS}/gems/(?<file>bundler-.*)\z}],
      checks: %i[bundle],
      reason: "bundle exec runs the Bundler the lockfile names, which bundle install put in the person's GEM_HOME; " \
        "fledge build put the same Bundler in the runtime's gem folder, and the app runs it (ADR 063). The same files " \
        "load, in the same order, from each."),
    *["ENV", "child ENV"].map do |fact|
      Justification.new(fact:, reference: [%r{#{BUNDLER_VARIABLES}#{PERSON_GEMS}/gems/(?<after>bundler-.*)\z}],
        app: [%r{#{BUNDLER_VARIABLES}#{APP_GEMS}/gems/(?<after>bundler-.*)\z}], checks: %i[bundle],
        reason: "bundle exec names the Bundler it runs in BUNDLE_BIN_PATH, BUNDLER_SETUP, RUBYLIB, and RUBYOPT: the " \
          "lockfile's, in the person's GEM_HOME on their computer and in the runtime's gem folder in the app (ADR 063). " \
          "The rest of each value is the same in both.")
    end,
    *["ENV", "child ENV"].map do |fact|
      Justification.new(fact:, reference: [BUNDLE_LOCATIONS], app: [BUNDLE_LOCATIONS], checks: %i[bundle],
        reason: "Bundler points GEM_HOME and PATH at the bundle's gems, as bundle exec does: the person's GEM_HOME on " \
          "their computer, the runtime's gem folder in the app. Everything else Bundler sets, it sets over the " \
          "person's own values in both, and records theirs as BUNDLER_ORIG_*.")
    end,
    *["Bundler.frozen_bundle?", "Bundler.settings[:frozen]"].map do |fact|
      Justification.new(fact:, reference: [/\Anull\z/], app: [/\Atrue\z/], checks: %i[bundle],
        reason: "The app's .bundle/config freezes its bundle (BUNDLE_FROZEN, Warbler's setting for a packed app), so " \
          "that Bundler never touches or rewrites the lockfile in a folder the person may not write (ADR 086); a " \
          "developer's project, as bundle exec runs it, has no such setting.")
    end,
    Justification.new(fact: "$VERBOSE", reference: [/\Anull\z/], app: [/\Afalse\z/],
      reason: "The person's RUBYOPT (-W0 here) is hidden from the app's boot (AGENTS.md, Design precedence 1; ADR 040), " \
        "so it cannot change how the app runs; it still reaches the app's ENV and every program the app starts."),
    Justification.new(fact: "$LOADED_FEATURES", reference: [%r{\A"(?:<prefix>/lib/ruby/#{ABI}|#{PERSON_GEMS}/gems/bundler-[^/"]+/lib)/bundler/feature_flag\.rb"\z}o],
      checks: %i[bundle],
      reason: "With no setting that says where the bundle's gems are, Bundler asks its feature flags whether to use " \
        "Ruby's own gem folder; the app's settings say so (path.system, as Warbler's does), so it never asks."),
    Justification.new(fact: "Gem.path", reference: [%r{\A"<work>/person-gems"\z}, %r{\A"<home>/\.(?:gem|local/share/gem)/}],
      reason: "The app's gems are the runtime's alone (ADR 040): the person's GEM_HOME, GEM_PATH, and " \
        "Gem.user_dir never shadow them. Their ENV still reaches the app and its child processes."),
    Justification.new(fact: "Gem.dir", reference: [%r{\A"<work>/person-gems"\z}], app: [%r{\A"<prefix>/lib/ruby/gems/#{ABI}"\z}o],
      reason: "As for Gem.path: RubyGems installs into the runtime's gem folder, never the person's GEM_HOME."),
    Justification.new(fact: "gems", reference: [RV_RUBY_EXTRAS],
      reason: "rv-ruby adds bootsnap and msgpack, which no standard Ruby 4.1 installs; runtimes keep " \
        "Ruby's own default and bundled gems."),
    Justification.new(fact: "requireable", reference: [RV_RUBY_EXTRAS], reason: "As for gems."),
    Justification.new(fact: "$LOADED_FEATURES", app: [%r{\A"<prefix>/lib/ruby/#{ABI}/rubygems/defaults/operating_system\.rb"\z}o],
      platforms: ["arm64-darwin", "x86_64-linux", "aarch64-linux", "x86_64-linux-musl", "aarch64-linux-musl", *MOBILE],
      reason: "Fledge's RubyGems defaults keep RubyGems to the runtime's gems " \
        "(doc/contributors/design/runtimes.md, \"Fledge's RubyGems defaults\"); " \
        "rv-ruby ships no such file, nor does the Ruby a musl runtime is built from."),
    Justification.new(fact: "$LOADED_FEATURES", platforms: %w[x64-mingw-ucrt aarch64-mingw-ucrt],
      reference: [
        %r{\A"<prefix>/lib/ruby/site_ruby/#{ABI}/ruby_installer/runtime/(?:colors|dll_directory|msys2_installation)\.rb"\z}o,
        %r{\A"<prefix>/lib/ruby/#{ABI}/(?:x64|aarch64)-mingw-ucrt/(?:enc/|win32/dll_directory\.so"\z)}o,
      ],
      reason: "Fledge's RubyGems defaults replace RubyInstaller's (ADR 038; " \
        "doc/contributors/design/runtimes.md, \"Fledge's RubyGems defaults\"). Both require RubyInstaller's " \
        "runtime, which defines RubyInstaller and its autoloads; only RubyInstaller's then calls it to look for " \
        "MSYS2, which loads the files of the autoloads it uses (Colors, DllDirectory, Msys2Installation), " \
        "win32/dll_directory, and the encodings its " \
        "messages use. Each autoload loads when code first uses it, and Ruby loads an encoding when code first " \
        "needs it, so an app that uses one finds it either way."),
    Justification.new(fact: "Object.constants", platforms: %w[x64-mingw-ucrt aarch64-mingw-ucrt], reference: [/\A"Win32"\z/],
      reason: "As for RubyInstaller's files in $LOADED_FEATURES: win32/dll_directory defines Win32, and loads when " \
        "code first uses RubyInstaller::Runtime::DllDirectory."),
    *LOCALE_FACTS.map do |fact|
      Justification.new(fact:, reference: [/\A"US-ASCII"\z/], app: [/\A"UTF-8"\z/], checks: %i[no_locale],
        reason: "With no locale at all (no LC_ALL, LC_CTYPE, or LANG, or LANG=C), as a desktop, a service manager, " \
          "or env -i starts an app, ruby takes the C locale, whose character set is ASCII; the launcher and the " \
          "runtime's bin/ruby take a UTF-8 locale instead, as Python does under PEP 538. launchd gives a " \
          "double-clicked app no locale at all, and Ruby still boots in the C locale, but it gives a folder " \
          "named outside ASCII in the app's path, or the person's home, three encodings, so Bundler's setup " \
          "and the app's own code fail for a person who never meets Ruby (Design precedence 1; ADR 087, and " \
          "doc/contributors/research/2026-11-13-c-locale.md, Verdict). An explicit LC_ALL or LC_CTYPE, C included, is kept as ruby keeps it, and " \
          "nothing is exported: ENV and every program the app starts see the person's own locale.")
    end,
    *MOBILE_JUSTIFIED,
  ].freeze

  attr_reader :platform

  def initialize(platform: Fledge::Platform.local, work: File.join(ROOT, "tmp", "parity"),
    runtimes: ENV.fetch("FLEDGE_RUNTIME_DIR", File.join(ROOT, "tmp", "runtime")), out: $stdout
  )
    @platform = platform
    @work = File.expand_path(work)
    @runtimes = runtimes
    @out = out
    @builder = RuntimeBuilder.new(platform:)
  end

  # Runs the check and returns true when every difference is justified.
  def call
    FileUtils.rm_rf(@work)
    FileUtils.mkdir_p(@work)
    @launcher = build_app
    @ruby = unpack_reference
    @reference_app = File.join(@work, "reference-app")
    FileUtils.cp_r(PROBE, @reference_app)
    results = [check("", nil)]
    results << check(" under code page 437", "437") if platform.windows?
    unless platform.windows?
      results << check(" with no locale", nil, locale: {}, check: :no_locale)
      results << check(" under LC_ALL=C", nil, locale: { "LC_ALL" => "C" })
      results << check(" under LC_CTYPE=C", nil, locale: { "LC_CTYPE" => "C" })
    end
    results << (WITHOUT_GEM_APP.include?(platform.name) ? skip_bundle : check_bundle)
    results << check_bundle(BUNDLED_WITH_APP, "bundled_with", "BundledWith", " of an app whose lockfile names another Bundler")
    results.all?
  end

  # Platforms the gem-shaped probe cannot be bundled on: its Gemfile is
  # examples/my_cool_app's, whose sqlite3 publishes no aarch64-mingw-ucrt
  # build, and whose source build fails there, SQLite's own configure
  # not knowing aarch64-w64-windows-gnu (doc/contributors/design/parity.md,
  # "The gem-shaped run").
  WITHOUT_GEM_APP = %w[aarch64-mingw-ucrt].freeze

  private def skip_bundle
    @out.puts "Parity of a gem-shaped app with bundle exec on #{platform}: not checked, as sqlite3 cannot be " \
      "installed there (doc/contributors/design/parity.md, \"The gem-shaped run\")"
    true
  end

  # The gem-shaped check: the probe as the program exe/PROGRAM of
  # +source+ (examples/my_cool_app's exe/my_cool_app, unless given), built
  # with its locked gems as the app +name+, against bundle exec ruby
  # exe/PROGRAM, with the bundle installed into the person's GEM_HOME by
  # bundle install, which installs the Bundler the lockfile names, as it
  # does for a developer.
  private def check_bundle(source = GEM_APP, program = "my_cool_app", name = "MyCoolApp", label = " of a gem-shaped app with bundle exec")
    env = environment
    project = Parity.gem_probe(File.join(@work, "#{program}-app"), source:, program:)
    reference = Parity.gem_probe(File.join(@work, "reference-#{program}-app"), source:, program:)
    bundle = File.join(File.dirname(@ruby), "bundle")
    install = [@ruby, bundle, "install", "--quiet"]
    system(env.merge("BUNDLE_FROZEN" => "true"), *install, chdir: reference, unsetenv_others: true, exception: true)
    launcher = build_app(File.join(project, "exe", program), name)
    expected = run([@ruby, bundle, "exec", @ruby, "exe/#{program}", *ARGUMENTS], reference, env)
    actual = run([launcher, *ARGUMENTS], File.join(File.dirname(launcher), "app"), env)
    differences = Reports.compare(Reports.normalize(expected, work: @work), Reports.normalize(actual, work: @work),
      platform: platform.name, check: :bundle)
    report(label, env, differences)
    differences.all?(&:justified?)
  end

  # Writes the gem-shaped probe into the new folder +project+: a copy of
  # +source+ (examples/my_cool_app, unless given), without the
  # developer's .bundle, with the probe as its exe/PROGRAM, and with
  # +name+, when given, as the app's name in its fledge.yml. Returns
  # +project+. CI builds one for Delivery, and test/integration/built_app_test.rb for
  # the built app's tests.
  def self.gem_probe(project, name: nil, source: GEM_APP, program: "my_cool_app")
    FileUtils.cp_r(source, project)
    FileUtils.rm_rf(File.join(project, ".bundle"))
    FileUtils.cp(File.join(PROBE, "main.rb"), File.join(project, "exe", program))
    File.write(File.join(project, "fledge.yml"), "name: #{name}\n") if name
    project
  end

  # Runs both, on Windows under +code_page+ when it is given, and with
  # +locale+, when it is given, in place of the caller's locale variables
  # (LANG and LC_*), reports the differences, and returns whether all are
  # justified for +check+.
  private def check(label, code_page, locale: nil, check: :script)
    env = environment(locale)
    reference, app = with_code_page(code_page) do
      [run([@ruby, "main.rb", *ARGUMENTS], @reference_app, env), run([@launcher, *ARGUMENTS], File.join(File.dirname(@launcher), "app"), env)]
    end
    differences = Reports.compare(Reports.normalize(reference, work: @work), Reports.normalize(app, work: @work), platform: platform.name,
      check:)
    report(label, env, differences)
    differences.all?(&:justified?)
  end

  # Runs the block with the console's code page set to +code_page+, as
  # chcp sets it for a person, and then puts the old one back. Programs
  # this process starts share its console, and Ruby on Windows takes
  # Encoding.default_external from the console's code page.
  private def with_code_page(code_page)
    return yield unless code_page

    original = `chcp.com`[/\d+/] or raise "chcp printed no code page"
    system("chcp.com", code_page, out: File::NULL, exception: true)
    begin
      yield
    ensure
      system("chcp.com", original, out: File::NULL, exception: true)
    end
  end

  private def report(label, env, differences)
    lines = [
      "Parity on #{platform}#{label}: #{differences.count(&:justified?)} justified, " \
        "#{differences.count { |difference| !difference.justified? }} unjustified differences",
      "Both ran with the caller's #{env.size - PERSON.size - 1} variables, less their Ruby settings, " \
        "an empty HOME, and #{PERSON.join(', ')}",
      *differences.map(&:to_s),
    ]
    @out.puts lines
    summary = ENV.fetch("GITHUB_STEP_SUMMARY", nil)
    File.write(summary, "```\n#{lines.join("\n")}\n```\n", mode: "a") if summary
  end

  # Settings that stand for a person's own Ruby: an empty GEM_HOME, a
  # RUBYOPT that only quiets warnings, and RUBY_ and BUNDLE_ variables no
  # Ruby reads.
  PERSON = %w[GEM_HOME RUBYOPT RUBY_PARITY_PERSON BUNDLE_PARITY_PERSON].freeze

  # The caller's environment without their own Ruby settings (as for a
  # person who has none), with an empty home folder, so the caller's own
  # gems stay out of both runs, plus PERSON. With +locale+, the caller's
  # LANG and LC_* variables give way to it: {} stands for an app a
  # desktop starts, with no locale at all.
  private def environment(locale = nil)
    clean = ENV.to_h.reject { |name, _| name.upcase.start_with?("RUBY", "GEM_", "GEMRC", "BUNDLE_", "BUNDLER_") }
    clean = clean.reject { |name, _| name == "LANG" || name.start_with?("LC_") }.merge(locale) if locale
    home = File.join(@work, "home")
    person_gems = File.join(@work, "person-gems")
    FileUtils.mkdir_p([home, person_gems])
    clean.merge("HOME" => home, PERSON[0] => person_gems, PERSON[1] => "-W0", PERSON[2] => "1", PERSON[3] => "1")
  end

  private def run(command, chdir, env)
    out, err, status = Open3.capture3(env, *command, chdir:, unsetenv_others: true)
    raise "#{command.join(' ')} failed (#{status}):\n#{out}\n#{err}" unless status.success?

    Reports.report(out)
  end

  # Builds +path+ (default: the probe) with fledge build into the work
  # folder, which must exist, and returns its launcher, the program
  # +name+. The ruby/spec comparison (tasks/ruby_spec.rb) builds its app
  # with it too.
  def build_app(path = PROBE, name = "Parity")
    out = StringIO.new
    err = StringIO.new
    env = ENV.to_h.merge("FLEDGE_RUNTIME_DIR" => @runtimes)
    status = Fledge::CLI::Build.new(out:, err:, env:).call(["-o", File.join(@work, "dist"), path])
    raise "fledge build failed: #{err.string}" unless status.zero?

    File.join(@work, "dist", "#{name}-#{platform}", platform.executable(name))
  end

  # Unpacks the Ruby the runtime came from into the work folder, which
  # must exist, as it ships, and returns its ruby program: rv-ruby's or
  # RubyInstaller's release, or for musl Linux, whose Ruby the runtime
  # build compiles from source (ADR 017), the runtime itself, whose
  # bin/ruby is Ruby's own main.c linked against the same libruby. The
  # ruby/spec comparison runs its stock Ruby with it.
  def unpack_reference
    archive = if platform.musl?
      File.join(@runtimes, Fledge::Runtimes.file_name(platform))
    else
      pin = @builder.sources.fetch("ruby").fetch("platforms").fetch(platform.name)
      @builder.fetch_pin(pin)
    end
    into = File.join(@work, "reference")
    FileUtils.mkdir_p(into)
    if platform.windows?
      # 7-Zip on PATH, as 7zz, 7z, or the 7za that mise.toml pins on
      # Windows, or where its installer puts it, as on GitHub's runners.
      seven_zip = %w[7zz 7z 7za].lazy.filter_map { |name| tool(name) }.first ||
        [File.join(ENV.fetch("ProgramFiles", "C:/Program Files"), "7-Zip", "7z.exe")].find { |path| File.file?(path) }
      raise "unpacking #{archive} needs 7-Zip" unless seven_zip

      system(seven_zip, "x", "-y", "-bd", "-o#{into}", archive, out: File::NULL, exception: true)
    else
      system("tar", "-xzf", archive, "-C", into, exception: true)
    end
    if platform.musl?
      # Fledge's RubyGems defaults are Fledge's, not the Ruby's it built.
      FileUtils.rm_f(Dir.glob(File.join(into, "**", "rubygems", "defaults", "operating_system.rb")))
    end
    rubies = Dir.glob(File.join(into, "**", "bin", platform.executable("ruby")))
    raise "#{archive} holds no single ruby: #{rubies}" unless rubies.size == 1

    rubies.first.to_s
  end

  private def tool(name)
    ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).product(["", ".exe"]).map { |dir, ext| File.join(dir, name + ext) }
      .find { |path| File.file?(path) && File.executable?(path) }
  end
end

if $PROGRAM_NAME == __FILE__
  platform = ARGV.first ? Fledge::Platform.find(ARGV.first) : Fledge::Platform.local
  exit Parity.new(platform:).call
end
