# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require "tmpdir"
require_relative "../app"
require_relative "../app_gems"
require_relative "../assembly"
require_relative "../built_app"
require_relative "../bundle"
require_relative "../checksum"
require_relative "../error"
require_relative "../gem_fetcher"
require_relative "../git_checkout"
require_relative "../mobile_extensions"
require_relative "../mobile_platform"
require_relative "../mobile_project"
require_relative "../native_build"
require_relative "../platform"
require_relative "../runtime_contents"
require_relative "../runtimes"
require_relative "../signing"
require_relative "build/options"

module Fledge
  class CLI
    # The <tt>fledge build</tt> command.
    #
    # Shipping an app means copying it into a runtime for each platform
    # you want it to run on, and archiving each result (Plan 001). Doing
    # that by hand means knowing where each runtime lives, renaming its
    # launcher, and archiving without losing an executable bit.
    #
    # This command builds for the computer it runs on, as Tauri's and
    # Briefcase's builds do, since each platform's app is made with that
    # platform's own tools (ADR 010), or, given a phone's name first
    # (<tt>fledge build ios</tt>), writes that phone's project, with
    # Fledge::MobileProject, on a computer whose tools build it (ADR 012). It reads <tt>--out</tt> and the
    # program to ship from its arguments (Fledge::App), finds this
    # platform's runtime through Fledge::Runtimes, adds the gems the app's
    # Gemfile.lock locks for it (Fledge::Bundle and Fledge::AppGems),
    # compiling those that need it (Fledge::NativeBuild) in a work folder
    # it removes afterwards, builds the app with Fledge::Assembly, and
    # prints the path of its archive and of each installer
    # (Fledge::Installers) it wrote, one per line, the archive first,
    # writing beside each its checksum file (Fledge::Checksum), which it
    # does not print. A failed build becomes
    # lines beginning <tt>fledge build:</tt> on the error stream and exit
    # status 1; a mistake in its arguments raises Fledge::UsageError,
    # which Fledge::CLI turns into the usage and exit status 2.
    #
    # Use it through the +fledge+ executable, or through Fledge::CLI.
    #
    # === Examples
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 setdef <kerrick@setdef.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   # From a terminal:
    #   #   $ fledge build examples/my_cool_app/exe/my_cool_app
    #   #   dist/MyCoolApp-x86_64-linux.tar.gz
    #
    #   Fledge::CLI::Build.new(out: $stdout, err: $stderr).call(["examples/hello"]) # => 0
    #--
    # SPDX-SnippetEnd
    #++
    class Build
      # The output folder when you give no <tt>--out</tt>.
      DEFAULT_OUT = "dist"

      # Creates the command.
      #
      # [out] Where results go, such as <tt>$stdout</tt>.
      # [err] Where errors and progress go, such as <tt>$stderr</tt>.
      # [env] The environment Fledge::Runtimes reads (default: +ENV+).
      # [host] The Gem::Platform of the computer it builds for (default:
      #        Gem::Platform.local).
      # [ruby] The version of the Ruby running the build (default:
      #        +RUBY_VERSION+), whose minor version the runtime's Ruby
      #        must have (ADR 055).
      def initialize(out:, err:, env: ENV, host: Gem::Platform.local, ruby: RUBY_VERSION)
        @out = out
        @err = err
        @env = env
        @host = host
        @ruby = ruby
      end

      # Runs the command with the arguments after +build+, and returns
      # the exit status: 0 when every target built, 1 otherwise. Raises
      # Fledge::UsageError for arguments it cannot make sense of.
      #
      # === Example
      #
      #--
      # SPDX-SnippetBegin
      # SPDX-SnippetCopyrightText: 2026 setdef <kerrick@setdef.com>
      # SPDX-License-Identifier: MIT-0
      #++
      #   Fledge::CLI::Build.new(out: $stdout, err: $stderr).call(["--out", "/tmp/builds", "my_app"]) # => 0
      #--
      # SPDX-SnippetEnd
      #++
      def call(argv)
        options = Options.parse(argv)
        host = Platform.local(@host)
        from = options.from&.then { |path| BuiltApp.at(path, platform: host, runtimes: Runtimes.new(env: @env, log: @err)) }
        app = App.at(options.path)
        phone = MobilePlatform.find(options.phone.to_s)
        signing = phone ? nil : signing(options, host)
        if from then build_from(from.adopt(app), from, host, options.out, signing)
        # A phone's app runs one program: App#main (ADR 024;
        # doc/contributors/design/desktop-apps.md, "Several programs").
        elsif phone then build_project(app.with(programs: [app.main]), phone, host, options.out)
        else build(app, host, options.out, signing)
        end
        0
      rescue UsageError
        raise
      rescue Error => e
        e.message.each_line { |line| @err.puts "fledge build: #{line.chomp}" }
        1
      end

      # The signer +options+ ask for on +host+ (Fledge::Signing.for), or
      # +nil+. FLEDGE_SIGN_COMMAND stands for <tt>--sign-command</tt> in a
      # Windows build whose command line asks for no signing of its own,
      # as an environment variable gives a default an option overrides.
      private def signing(options, host)
        command = options.sign_command
        command ||= @env["FLEDGE_SIGN_COMMAND"].to_s.then { |value| value unless value.strip.empty? } if host.windows? && !options.sign
        Signing.for(host, options.sign, command:, notarize: options.notarize, env: @env, log: @err)
      end

      private def build(app, platform, out, signing)
        out_dir = out_dir(app, out)
        runtimes = Runtimes.new(env: @env, log: @err)
        Dir.mktmpdir("fledge-build") do |work|
          gems = gems_for(app, runtimes, work)
          runtime = runtimes.archive(platform)
          contents = same_ruby(RuntimeContents.read(runtime), platform)
          files = gems ? gems.for(platform, runtime: contents) : [] # : Array[Entry]
          app_files = gems ? gems.app_files : {} # : Hash[String, String]
          written(Assembly.new(app:, platform:, runtime:, out: out_dir, app_files:, files:, signing:, bundler: gems&.bundler, log: @err), out)
        end
      end

      # Builds +app+ from the built app +from+ (ADR 032): with its runtime
      # and gems, downloading, installing, and compiling nothing.
      private def build_from(app, from, platform, out, signing)
        written(Assembly.new(app:, platform:, runtime: from.path, out: out_dir(app, out), files: from.files, signing:, from:, bundler: from.bundler,
          log: @err), out)
      end

      # Writes +assembly+'s archive and installers, each with its checksum
      # file, and prints each one's path in the folder +out+.
      private def written(assembly, out)
        [assembly.call, *assembly.installers].each do |path|
          Checksum.write(path)
          @out.puts File.join(out, File.basename(path))
        end
      end

      # The folder +out+, as an absolute path, which may not be +app+'s.
      private def out_dir(app, out)
        out_dir = File.expand_path(out)
        raise Error, "--out can't be the app's own folder, #{out}" if out_dir == app.root

        out_dir
      end

      # Writes +phone+'s project for +app+ (Fledge::MobileProject), on the
      # computer +host+, with the app's gems, each its pure-Ruby build.
      private def build_project(app, phone, host, out)
        phone.check_host(host)
        out_dir = out_dir(app, out)

        runtimes = Runtimes.new(env: @env, log: @err)
        writer = MobileProject.for(phone)
        Dir.mktmpdir("fledge-build") do |work|
          gems = gems_for(app, runtimes, work)
          runtime = runtimes.archive(phone)
          contents = same_ruby(RuntimeContents.read(runtime, under: writer.ruby_under), phone)
          files = gems ? gems.for(phone, runtime: contents) : [] # : Array[Entry]
          app_files = gems ? gems.app_files(force_ruby_platform: true) : {} # : Hash[String, String]
          project = writer.new(app:, runtime:, out: out_dir, app_files:, files:, extensions: extensions(gems, phone, host, runtimes, work),
            bundler: gems&.bundler, log: @err).call
          @out.puts File.join(out, File.basename(project))
        end
      end

      # The runtime +contents+ for +platform+, when its Ruby has the minor
      # version of the Ruby running the build. Fledge has no default Ruby:
      # an app runs on the Ruby its developer runs it with, as Briefcase
      # and PyInstaller package the Python that runs them, at the patch
      # level of Fledge's runtime (ADR 055). Raises
      # Fledge::Error otherwise.
      private def same_ruby(contents, platform)
        return contents if minor(contents.ruby_version) == minor(@ruby)

        raise Error, "You are running Ruby #{@ruby}, and Fledge #{VERSION}'s runtime for #{platform} is Ruby #{contents.ruby_version}.\n" \
          "An app runs on the Ruby you build it with: run fledge build with Ruby #{minor(contents.ruby_version)}, " \
          "or use a Fledge release that has a runtime for Ruby #{minor(@ruby)}."
      end

      # The major and minor version of the Ruby version +version+.
      private def minor(version)
        version.split(".").first(2).join(".")
      end

      # The compiler of the app's gems' extensions for +phone+ (ADR 022), or
      # +nil+ for an app with none.
      private def extensions(gems, phone, host, runtimes, work)
        return nil unless gems

        packages = gems.extension_packages
        return nil if packages.empty?

        MobileExtensions.new(platform: phone, packages:, build_args: gems.extension_build_args, host:, runtimes:,
          work: File.join(work, "mobile-extensions"), log: @err, env: @env)
      end

      # The app's gems, for an app with a Gemfile: Fledge keeps the gems it
      # downloads beside its runtimes, in <tt>~/.cache/fledge/gems</tt>,
      # and the git repositories it fetches in <tt>~/.cache/fledge/git</tt>,
      # and compiles gems for the platform it runs on.
      private def gems_for(app, runtimes, work)
        return nil unless app.gemfile

        cache = File.dirname(runtimes.cache)
        fetcher = GemFetcher.new(cache: File.join(cache, "gems"), project: app.root, log: @err)
        checkouts = GitCheckout.new(cache: File.join(cache, "git"), work:, log: @err)
        AppGems.new(app:, bundle: Bundle.new(app), fetcher:, checkouts:, compiler: compiler(runtimes, work))
      end

      private def compiler(runtimes, work)
        NativeBuild.new(platform: Platform.local(@host), runtimes:, work:, log: @err, env: @env)
      end
    end
  end
end
