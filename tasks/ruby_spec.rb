# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require "fileutils"
require_relative "download_cache"
require_relative "parity"
require_relative "ruby_spec/results"
require_relative "ruby_spec/listing"

# The ruby/spec comparison: ruby/spec, run by MSpec, on stock Ruby and in
# a built app, with every example that fails on one side only either
# justified in JUSTIFIED or failing the check
# (doc/contributors/design/parity.md, "ruby/spec"; AGENTS.md, Design
# precedence 2).
#
# It downloads ruby/spec and MSpec at their pinned commits (SOURCES),
# each checked against its SHA-256, and writes a project of
# tasks/ruby_spec/main.rb with the two beside it. Stock Ruby is the Ruby
# this computer's runtime was made from, unpacked as it ships, as the
# parity check runs it (Parity#unpack_reference), running ruby main.rb
# in one copy of the project; the built app is another copy, built by
# fledge build from the runtime. Each runs mspec-run over DIRECTORIES,
# one process per directory, in the same clean environment: a PATH with
# no Ruby on it, an empty home folder, and no locale, as a desktop starts
# an app. A person's hostile Ruby settings are not part of it: they reach
# the child Rubies the specs start through RbConfig.ruby, as they would
# under ruby main.rb (ADR 040), and stock Ruby would read
# them at its own boot, where the launcher hides them.
#
# Each run's output is kept in the output folder, with a summary that
# also goes to the job summary in CI. The spec files are data downloaded
# for the run: nothing of ruby/spec or MSpec is committed or shipped.
#
# Run it as rake ruby_spec, after rake runtime or with FLEDGE_RUNTIME_DIR
# set; RUBY_SPEC_OUT names the output folder (default tmp/ruby-spec).
# RubySpec::Phone runs it in phone apps (ruby tasks/ruby_spec.rb ios,
# android-build, and android).
class RubySpec
  ROOT = File.expand_path("..", __dir__)

  # ruby/spec's directories that CRuby's own make test-spec runs.
  DIRECTORIES = %w[language core library command_line security].freeze

  # A repository of the ruby organization at a commit, as GitHub archives
  # it, and the SHA-256 of that archive.
  class Source < Data.define(:name, :commit, :sha256)
    def url
      "https://github.com/ruby/#{name}/archive/#{commit}.tar.gz"
    end

    # The host the archive URL redirects to, which serves the same bytes.
    def mirror
      "https://codeload.github.com/ruby/#{name}/tar.gz/#{commit}"
    end
  end

  # ruby/spec and MSpec, both MIT-licensed, at the commits the
  # experiment/ruby-spec spike ran (run 41776558621).
  SOURCES = [
    Source.new(name: "spec", commit: "47b10f1d7b1c29bda01d6903cceddd5b0b4c857d",
      sha256: "7587318e196940fe39bcb4eff27c54fdf17410d64786e313db6a3a1fffb7ae8a"),
    Source.new(name: "mspec", commit: "521207f313abfaffd56dca274475c56012f90221",
      sha256: "71c4b12fdaf37b06834fb568dccb11f355942d48e0cd97c4f6120759f5bf64f9"),
  ].freeze

  # Examples left out of both runs, by platform, each because it stops
  # the process for stock Ruby and the app alike (mspec-run -E).
  EXCLUDED = %w[x86_64-linux-musl aarch64-linux-musl].to_h do |platform|
    # CRuby 4.0.9 on musl crashes setting the name of a thread that has
    # ended (pthread_setname_np on a thread musl has freed), at
    # core/thread/to_s_spec.rb line 18, and the whole core run stops.
    [platform, ["Thread#to_s returns a description including a thread name if given any"]]
  end.freeze

  # The platforms of the phones' runs, as the mobile parity check names
  # them (MobileParity::IOS::TARGET, MobileParity::Android#target).
  ANDROID = %w[x86_64-linux-android aarch64-linux-android].freeze
  PHONES = ["arm64-ios-simulator", *ANDROID].freeze

  JUSTIFIED = [
    Justification.new(
      example: /\Acore: (?:Dir\.chdir|File\.readlink|File\.realpath) accepts a path in a non-UTF-8, ASCII-compatible encoding containing non-ASCII characters/,
      side: :stock, platforms: %w[arm64-darwin],
      reason: "With no locale, stock Ruby takes the C locale and reads paths as US-ASCII, and these macOS-only " \
        "examples fail converting one; the built app's launcher takes a UTF-8 locale in place of a bare C one " \
        "(ADR 041; Parity::JUSTIFIED), so they pass there.",
    ),
    Justification.new(
      example: /\Acore: Refinement#import_methods when methods are not defined in Ruby code raises ArgumentError when importing methods from C extension/,
      side: :stock, platforms: %w[x64-mingw-ucrt aarch64-mingw-ucrt],
      reason: "RubyInstaller's head build, which Windows' runtimes carry until Ruby 4.1.0 (ADR 066), ships a " \
        "zlib.so that imports libz-1.dll and not the DLL itself, which a developer's Ruby finds in MSYS2's " \
        "ucrt64\\bin through ridk; the comparison's clean environment has no MSYS2, so stock Ruby cannot " \
        "require zlib, which this example does, and the runtime adds the DLL (ADR 038).",
    ),
    Justification.new(
      example: %r{\Alibrary: loading library/zlib/},
      side: :stock, platforms: %w[x64-mingw-ucrt aarch64-mingw-ucrt],
      reason: "As for Refinement#import_methods: every spec file of library/zlib requires zlib, which stock " \
        "RubyInstaller head cannot load without MSYS2's libz-1.dll, and the runtime ships.",
    ),
    # The phones (RubySpec::Phone), against stock Ruby on the computer
    # that runs the simulator.
    Justification.new(
      example: /\Alibrary: RbConfig::CONFIG \['archdir'\] returns the directory containing standard libraries C extensions\z/,
      side: :app, platforms: PHONES,
      reason: "A phone runtime links every extension into the app, where Android and iOS load native code from, " \
        "so no archdir holds them (doc/contributors/design/phone-runtimes.md, \"What a phone runtime holds\").",
    ),
    Justification.new(
      example: /\Acore: (?:File|File::Stat|FileTest)[.#](?:setuid|setgid|sticky)\? /,
      side: :app, platforms: %w[arm64-ios-simulator],
      reason: "iOS's sandbox keeps an app from setting the set-user-ID, set-group-ID, and sticky bits on its files, " \
        "which these examples set with chmod and then read back.",
    ),
    Justification.new(
      example: /\A(?:core: (?:File|File::Stat|FileTest)[.#]grpowned\? takes non primary groups into account|core: Process\.(?:egid|euid)= sets the effective (?:group|user) id to its own [gu]id if given the username)/,
      side: :app, platforms: %w[arm64-ios-simulator],
      reason: "An iOS app's C library finds no user for the app's own user ID: Etc.getpwuid(Process.uid) raises " \
        "\"can't find user\", and Process.groups raises EINVAL, since Darwin's getgroups, which Ruby is built to " \
        "call, looks the user up with getpwuid and fails when it finds none (Libc, sys/getgroups.c, lines 35 to 58 " \
        "at Libc-1752.120.2). These examples ask for the process's groups or its user's name.",
    ),
    Justification.new(
      example: /\Alibrary: Etc\.getlogin returns the name associated with the current login activity\z/,
      side: :app, platforms: %w[arm64-ios-simulator],
      reason: "The example's one expectation for a login name compares it with what logname or id -un prints, and an " \
        "iOS app can start neither, so MSpec finds no expectation in it (doc/contributors/design/phone-projects.md, " \
        "\"Parity on a phone\").",
    ),
    Justification.new(
      example: /\Alibrary: RbConfig::CONFIG \['(?:AR|STRIP)'\] exists and can be executed\z/,
      side: :app, platforms: ANDROID,
      reason: "RbConfig names the NDK's archiver and strip the runtime was built with, on the computer that built " \
        "it; a phone has no toolchain, and an app needs one only to compile, which Fledge does on the developer's " \
        "computer (doc/contributors/design/phone-projects.md, \"Gems with extensions\").",
    ),
    Justification.new(
      example: /\Acore: Process\.maxgroups sets the maximum number of gids allowed in the supplemental group access list\z/,
      side: :app, platforms: ANDROID,
      reason: "The Android runtime's Ruby is configured without setgroups, which Android's seccomp filter for apps " \
        "forbids (RuntimeBuilder::Android::CONFIGURE), so Process.maxgroups= raises NotImplementedError, as Ruby " \
        "does wherever the call is missing.",
    ),
    Justification.new(
      example: /\Acore: Process\.egid= (?:raises TypeError if not passed an Integer or String|raises Errno::ERPERM if run by a non superuser trying to set the (?:root group id|group id from group name)|sets the effective group id to its own gid if given the username corresponding to its own gid)\z/,
      side: :app, platforms: ANDROID,
      reason: "Android's seccomp filter for apps stops a process that sets any of its group IDs, as setgid, setregid, " \
        "and setresgid do and bionic's setegid does through setresgid, so the Android runtime's Ruby is configured " \
        "without them (RuntimeBuilder::Android::CONFIGURE) and Process.egid= raises NotImplementedError, as Ruby " \
        "does wherever no call sets a group ID, where a desktop sets the group ID or refuses with EPERM.",
    ),
    Justification.new(
      example: /\Acore: Dir\.scan handles character devices\z/,
      side: :app, platforms: ANDROID,
      reason: "The example lists /dev, which Android's SELinux policy forbids an app to read (EACCES).",
    ),
    Justification.new(
      example: /\Alibrary: mkmf can be required with --enable-frozen-string-literal\z/,
      side: :app, platforms: ANDROID,
      reason: "The example requires mkmf in the runtime's ruby program (ADR 082), and mkmf aborts where Ruby's C " \
        "headers are missing, which a phone's app does not carry: they are for the computer that builds the app " \
        "(doc/contributors/design/phone-runtimes.md, \"Ruby's C headers on a phone\").",
    ),
    Justification.new(
      example: /\Acore: (?:Process\.spawn uses the passed env\['PATH'\] to search the executable|Kernel#system executes with `sh` if the command is executable but not binary and there is no shebang)\z/,
      side: :app, platforms: ANDROID,
      reason: "Each example writes a script into a temporary folder and runs it, and Android lets an app run no file " \
        "it writes into its own folders: \"Untrusted apps that target Android 10 cannot invoke execve() directly on " \
        "files within the app's home directory\" (developer.android.com, Android 10 behavior changes; ADR 082), so " \
        "execve fails with EACCES, which Process.spawn raises and Kernel#system answers with nil, where Ruby would " \
        "run the script, or hand one with no shebang to sh. The app's ruby program runs, since the package installer " \
        "extracts it.",
    ),
    # Examples that run on one side only (Listing.compare), beyond those
    # ruby/spec's platform guards leave out.
    Justification.new(
      example: /\Acore: (?:Dir\.scan handles block devices|(?:File\.|File::Stat#)ftype returns 'blockSpecial' when the file is a block)\z/,
      side: :stock, platforms: %w[arm64-ios-simulator], outcome: :runs,
      reason: "MSpec's with_block_device runs these only where find /dev /devices -type b finds a block device " \
        "(mspec/guards/block_device.rb, lines 4 to 11 at MSpec 521207f), and iOS lets no app start find: Apple's SDK " \
        "marks system() prohibited there, \"On iOS, process spawning is unavailable\" (iPhoneOS27.2.sdk, " \
        "usr/include/_stdlib.h, lines 205 to 208).",
    ),
    Justification.new(
      example: /\Acore: (?:Dir\.scan handles block devices|(?:File\.|File::Stat#)ftype returns 'blockSpecial' when the file is a block)\z/,
      side: :stock, platforms: ANDROID, outcome: :runs,
      reason: "MSpec's with_block_device runs these only where find /dev /devices -type b finds a block device " \
        "(mspec/guards/block_device.rb, lines 4 to 11 at MSpec 521207f), and Android's SELinux policy keeps an app " \
        "from reading /dev, as for Dir.scan's example of character devices, so the app finds none.",
    ),
    Justification.new(
      example: %r{\Acore: Time\.utc handles real leap seconds in zone 'right/UTC'\z},
      side: :stock, platforms: ANDROID, outcome: :runs,
      reason: "ruby/spec runs it only where the zone right/UTC counts a leap second (core/time/utc_spec.rb, lines 88 " \
        "to 92), and Android's time zone data has no right/ zones: AOSP compiles it with zic from the zones and links " \
        "of IANA's rearguard.zi alone, without zic's -L leapseconds (system/timezone, update-tzdata.py, lines 54 to 66 " \
        "and 178 at 0470df3d), so bionic finds no right/UTC and takes UTC, which has no leap seconds.",
    ),
    Justification.new(
      example: /\Acommand_line: Processing RUBYOPT (?:prints the version number for '-v'|ignores whitespace around the option)\z/,
      side: :stock, platforms: ANDROID, outcome: :runs,
      reason: "ruby/spec runs these only where RbConfig::CONFIG['CROSS_COMPILING'] is not \"yes\" " \
        "(command_line/rubyopt_spec.rb, line 25), and the Android runtime's Ruby is compiled with the NDK on the " \
        "computer that builds it, a cross build (doc/contributors/design/phone-runtimes.md, \"Building Ruby for a " \
        "phone\").",
    ),
    Justification.new(
      example: %r{\Acore: File\.expand_path when HOME is not set uses the user database when passed '~/?' if HOME is nil\z},
      side: :app, platforms: ANDROID, outcome: :runs,
      reason: "ruby/spec runs these only where Etc.getlogin names a user with USER unset (core/file/expand_path_spec.rb, " \
        "lines 221 to 233). glibc's getlogin names the user logged in on the process's controlling terminal, and stock " \
        "Ruby's run, in CI's clean environment, has none; bionic's names the user of getuid() " \
        "(libc/bionic/grp_pwd.cpp, lines 629 to 632 at 731631f), so the app runs them, and they pass.",
    ),
  ].freeze

  attr_reader :platform

  def initialize(platform: Fledge::Platform.local, work: File.join(ROOT, "tmp", "ruby-spec-work"),
    out: ENV.fetch("RUBY_SPEC_OUT", File.join(ROOT, "tmp", "ruby-spec")),
    runtimes: ENV.fetch("FLEDGE_RUNTIME_DIR", File.join(ROOT, "tmp", "runtime")), log: $stdout
  )
    @platform = platform
    @work = File.expand_path(work)
    @out = File.expand_path(out)
    @runtimes = runtimes
    @log = log
    @downloads = DownloadCache.new(File.join(ROOT, "tmp", "downloads"))
  end

  # Runs the comparison and returns true when every difference is
  # justified.
  def call
    FileUtils.rm_rf([@work, @out])
    FileUtils.mkdir_p([@work, @out])
    sources = SOURCES.to_h { |source| [source.name, unpack(source)] }
    parity = Parity.new(platform:, work: File.join(@work, "parity"), runtimes: @runtimes, out: @log)
    FileUtils.mkdir_p(File.join(@work, "parity"))
    ruby = parity.unpack_reference
    app = parity.build_app(project(File.join(@work, "build", "ruby_spec"), sources), "RubySpec")
    stock = run("stock", [ruby, "main.rb"], project(File.join(@work, "reference", "ruby_spec"), sources))
    built = run("app", [app], @work)
    differences = Results.compare(stock, built, platform: platform.name)
    report(stock, built, differences)
    differences.all?(&:justified?)
  end

  # Downloads +source+ into the download cache, checked against its
  # SHA-256, unpacks it into the work folder with the computer's own tar
  # (Fledge::Archive), and returns its folder.
  private def unpack(source)
    archive = @downloads.fetch(source.url, source.sha256, mirrors: [source.mirror])
    into = File.join(@work, "sources")
    FileUtils.mkdir_p(into)
    Fledge::Archive.unpack(archive, into:)
    File.join(into, "#{source.name}-#{source.commit}")
  end

  # A project in the new folder +into+: main.rb, with ruby/spec and MSpec
  # beside it as spec/ and mspec/, without their repositories' own files
  # or MSpec's own specs, and a fledge.yml naming the app.
  private def project(into, sources)
    FileUtils.mkdir_p(into)
    FileUtils.cp(%w[main.rb listing_config.rb].map { |file| File.join(__dir__, "ruby_spec", file) }, into)
    sources.each { |name, folder| FileUtils.cp_r(folder, File.join(into, name)) }
    FileUtils.rm_rf(Dir.glob(File.join(into, "{spec,mspec}", ".git*")) + [File.join(into, "mspec", "spec")])
    File.write(File.join(into, "fledge.yml"), "name: RubySpec\n")
    into
  end

  # Runs +command+ once per directory of DIRECTORIES from +chdir+, in the
  # clean environment, writes each output to the output folder under
  # +label+, and returns the Results::Run of each.
  private def run(label, command, chdir)
    env = environment(label)
    folder = File.join(@out, label)
    FileUtils.mkdir_p(folder)
    options = ["-B", "../listing_config.rb", "--timeout", "300", *EXCLUDED.fetch(platform.name, []).flat_map { |example| ["-E", example] }]
    DIRECTORIES.map do |directory|
      file = File.join(folder, "#{directory}.out")
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      pid = Process.spawn(env, *command, *options, directory, chdir:, unsetenv_others: true, out: file, err: %i[child out],
        in: File::NULL)
      Process.wait(pid)
      Results.read(directory, File.binread(file)).tap do |result|
        seconds = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
        @log.puts format("%-5s %-12s %4.0fs  %s", label, directory, seconds, result.totals || "did not finish")
      end
    end
  end

  # The environment both sides run in: a PATH with no Ruby, an empty home
  # folder of +label+'s own, a short folder for MSpec's temporary files
  # (a UNIX socket's path may hold no more than 104 bytes on macOS), and
  # no locale. On Windows, what a Windows program needs to start programs
  # (ComSpec, PATHEXT) and to find its folders.
  private def environment(label)
    home = File.join(@work, "home-#{label}")
    temporary = platform.windows? ? File.join(@work, "t-#{label}") : "/tmp/fledge-rs-#{label}"
    FileUtils.rm_rf([home, temporary])
    FileUtils.mkdir_p([home, temporary])
    return { "PATH" => path_without_ruby, "HOME" => home, "SPEC_TEMP_DIR" => temporary } unless platform.windows?

    system_root = ENV.fetch("SystemRoot")
    temp = File.join(@work, "temp-#{label}").tr("/", "\\")
    FileUtils.mkdir_p(temp)
    path = ["\\System32", "", "\\System32\\Wbem", "\\System32\\WindowsPowerShell\\v1.0"].map { |dir| "#{system_root}#{dir}" }
    {
      "SystemRoot" => system_root,
      "SystemDrive" => ENV.fetch("SystemDrive"),
      "windir" => system_root,
      "ComSpec" => ENV.fetch("ComSpec"),
      "PATHEXT" => ENV.fetch("PATHEXT"),
      "PATH" => path.join(";"),
      "USERPROFILE" => home,
      "TEMP" => temp,
      "TMP" => temp,
      "SPEC_TEMP_DIR" => temporary,
    }
  end

  # A folder of links to the system's programs, less any Ruby and its
  # tools, for PATH.
  private def path_without_ruby
    folder = File.join(@work, "path")
    return folder if File.directory?(folder)

    FileUtils.mkdir_p(folder)
    %w[/usr/local/bin /usr/bin /bin /usr/sbin /sbin].each do |dir|
      Dir.glob(File.join(dir, "*")).each do |program|
        name = File.basename(program)
        next if name.match?(/\A(?:ruby|gem|irb|erb|rake|rdoc|ri|bundle|bundler|rbs|typeprof|racc)[\d.]*\z/)

        link = File.join(folder, name)
        File.symlink(program, link) unless File.exist?(link) || File.symlink?(link)
      end
    end
    folder
  end

  # Prints the totals of the +stock+ and +built+ runs and the
  # +differences+ under +title+, and adds them to the summary in the
  # output folder and, in CI, to the job summary.
  private def report(stock, built, differences, title: "ruby/spec on #{platform}")
    lines = [
      "#{title}: #{differences.count(&:justified?)} justified, " \
        "#{differences.count { |difference| !difference.justified? }} unjustified differences",
      *stock.zip(built).map { |reference, app| "  #{reference.directory}: stock #{reference.totals || 'did not finish'}; app #{app.totals || 'did not finish'}" },
      *differences.map(&:to_s),
    ]
    @log.puts lines
    File.write(File.join(@out, "summary.txt"), "#{lines.join("\n")}\n", mode: "a")
    summary = ENV.fetch("GITHUB_STEP_SUMMARY", nil)
    File.write(summary, "```\n#{lines.join("\n")}\n```\n", mode: "a") if summary
  end
end

require_relative "ruby_spec/phone"

if $PROGRAM_NAME == __FILE__
  command, runtimes = ARGV
  options = { runtimes: }.compact
  passed = case command
  when "ios" then RubySpec::Phone.new("ios", **options).ios
  when "android-build" then RubySpec::Phone.new("android", **options).android_build
  when "android" then RubySpec::Phone.new("android").android
  else RubySpec.new(platform: command ? Fledge::Platform.find(command) : Fledge::Platform.local).call
  end
  exit passed
end
