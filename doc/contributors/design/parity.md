<!--
SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>

SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Parity: Proving an App Runs as Ruby Runs It

This document describes how Fledge proves that a built app's Ruby code sees what it would see under `ruby main.rb`, or `bundle exec`, and ends as Ruby ends: the parity check, its probe and its references, how a difference is justified, the gem-shaped run, the mobile parity, the console checks of Delivery, the restart checks, and the ruby/spec comparison. ADR 081 decides that nothing of Fledge's stands between Ruby and the program, and these checks are its Confirmation; ADR 040, ADR 087, ADR 095, and ADR 026 decide the differences they allow. `doc/differences_from_ruby.md` tells app developers each difference their code can see, and why; keep it true to `Parity::JUSTIFIED`.

## The parity check

`bundle exec rake parity` runs `tasks/parity.rb` for this computer's platform, with the runtime in `tmp/runtime` (from `bundle exec rake runtime`) or in `FLEDGE_RUNTIME_DIR`. It:

1. builds the probe, `test/fixtures/parity`, with `fledge build` (`Parity#build_app`), as the app `Parity`;
2. unpacks the reference Ruby (`Parity#unpack_reference`, see "The references");
3. runs the script check, then its variants (see "The environments");
4. runs the gem-shaped check (see "The gem-shaped run");
5. prints each check's differences, and appends them to the job summary in CI.

It fails when any difference is unjustified. CI runs it in the Test jobs (`arm64-darwin`, `x86_64-linux`, `aarch64-linux`), the Test (Windows) jobs (`x64-mingw-ucrt`, `aarch64-mingw-ucrt`), and the Parity (musl) jobs, which run `ruby tasks/parity.rb` in the pinned Alpine Ruby image.

## The probe

`test/fixtures/parity/main.rb` uses only Ruby's standard library. With no command it prints one line, `FLEDGE-PARITY ` and a JSON object of facts, with every string made valid UTF-8 (a path read in a C locale holds bytes outside US-ASCII; the encodings are facts of their own). The facts (`facts` in the probe) are:

- the program's names: `$0`, `__FILE__`, `__dir__`, `$PROGRAM_NAME`, and `ARGV`;
- what is loaded and loadable: `$LOAD_PATH`, `$LOADED_FEATURES`, every installed gem, and whether each gem's main feature loads (`requireable`, reported last, since requiring changes `$LOADED_FEATURES`; `debug` and `test-unit` are only resolved, since requiring them starts a debugger or runs tests);
- Ruby and RubyGems: `RbConfig.ruby`, whether it is a program and runs, `Gem.ruby`, `Gem.path`, `Gem.dir`;
- the encodings: `Encoding.default_external`, `default_internal`, `find('locale')`, `find('filesystem')`, and `$stdout.external_encoding`;
- the standard streams' `sync`, `$VERBOSE`, `$DEBUG`;
- `ENV`, and the `ENV` a child Ruby started through `RbConfig.ruby` sees;
- under Bundler, `Bundler.original_env`, `Bundler.unbundled_env`, the `ENV` a child Ruby sees inside `with_original_env` and `with_unbundled_env`, and whether Bundler takes the bundle as frozen, `Bundler.frozen_bundle?` and `Bundler.settings[:frozen]`;
- the constants defined at the top level, `Object.constants`;
- `RUBY_PLATFORM`, `RUBY_DESCRIPTION`, `RubyVM::YJIT.enabled?`, `RubyVM::ZJIT.enabled?`, and the `YJIT_SUPPORT` and `ZJIT_SUPPORT` that `RbConfig::CONFIG` records;
- on Windows outside Bundler, which leaves Fiddle out, `Windows`: the process's ANSI code page (`GetACP`), whether a copy of one of Ruby's DLLs under a folder named `Ünïcödé 日本` loads through `LoadLibraryExA`, as ffi loads a gem's DLL, and whether a child Ruby started through `RbConfig.ruby` finds the same code page and the same load as its parent. The parent's code page and load differ from `ruby main.rb`'s by ADR 070; a child that differs from its parent is the gap ADR 070 left open, and fails.

The report also carries the paths of the probe's folder, its project's root, Ruby's prefix, and the home folder, for normalizing. Its `fledge.yml` makes the probe's folder its own project root, inside Fledge's own gem, and gives it the identifier phones need.

Delivery, which has no Ruby to compare with, asks the probe one thing at a time: `child-env NAME`, `original-child-env NAME`, `unbundled-child-env NAME`, `gem-path`, `irb`, and `restart` (see "Restart checks").

## The references

The reference is the Ruby the runtime was made from, unpacked as it ships: rv-ruby's release on macOS and glibc Linux, and RubyInstaller's on Windows, fetched by the pins in `runtime/sources.yml` and checked against their SHA-256. On musl Linux, whose Ruby the runtime build compiles from source (ADR 017), the reference is the runtime's own `bin/ruby`, with Fledge's `rubygems/defaults/operating_system.rb` removed, since that file is Fledge's and not Ruby's.

The reference runs `ruby main.rb` from a copy of the probe's folder; the app runs its launcher from `ROOT/app`. Both get the arguments `one`, `two words`, and `ünïcödé`.

## The environments

Both runs get the same environment, and nothing else (`unsetenv_others`): the caller's, less every variable whose name begins with `RUBY`, `GEM_`, `GEMRC`, `BUNDLE_`, or `BUNDLER_` in any case; `HOME` an empty folder of the check's own, so the caller's gems stay out; and four variables that stand for a person's own Ruby (`Parity::PERSON`): `GEM_HOME`, an empty folder; `RUBYOPT=-W0`; and `RUBY_PARITY_PERSON=1` and `BUNDLE_PARITY_PERSON=1`, which no Ruby reads.

The script check runs once as is, and then:

- on Windows, under code page 437, the default of an English console, set with `chcp` and set back afterwards; programs this process starts share its console, and Ruby takes the console's code page as its locale's;
- on macOS and Linux, with no `LANG` or `LC_*` at all, as a desktop starts an app (the `no_locale` check);
- and under `LC_ALL=C` and under `LC_CTYPE=C`, which a person sets on purpose, where nothing may differ.

## Comparing two reports

`Parity::Reports.normalize` replaces each path with a token, longest first, in each spelling (as given, with `/` for `\`, and real): `<app>` for the probe's folder, `<project>` for its project's root when that is another folder, `<prefix>` for Ruby's prefix, `<home>`, and `<work>` for the check's work folder.

`Parity::Reports.compare` turns each fact into a list of strings: an Array's elements in order, a Hash's `KEY=VALUE` pairs sorted, or the one value of anything else. `ENV` is compared as a set, because its order is how the environment happened to be built, not something Ruby promises. A fact that differs is justified when every element found on one side only matches a justification that applies to that fact, platform, and check, and the elements both sides share come in the same order. Anything else is reported `DIFFERENT` and fails.

## Parity::JUSTIFIED

`Parity::JUSTIFIED` in `tasks/parity.rb`, with `Parity::MOBILE_JUSTIFIED` in `tasks/parity/mobile.rb`, lists every difference allowed, each a `Parity::Justification`:

- `fact`, the fact's name in the report;
- `reference` and `app`, patterns: an element only in the reference run is explained when it matches one of `reference`, and one only in the app when it matches one of `app`;
- `platforms`, when given, the platforms it applies to;
- `checks`, `:script` (against `ruby main.rb`), `:bundle` (against `bundle exec`), or `:no_locale` (the script check with no locale); the `no_locale` check also allows what `:script` allows;
- `reason`, printed beside each difference it explains.

Read the list there rather than here. `test/parity_justified.yml` records what each entry allows, without its reason, and `test/parity_justified_test.rb` fails when an entry allows something the file does not list, so a new difference from `ruby main.rb` is always a deliberate change to both. After 1.0 the list may only shrink (`doc/contributors/design/public-interface.md`). A reason's words may change freely.

## The gem-shaped run

The second check compares a gem-shaped app with `bundle exec`. `Parity.gem_probe` copies `examples/my_cool_app` without its `.bundle`, with the probe as its `exe/my_cool_app`; it does so twice, once to build and once as the reference. For the reference it runs `bundle install --quiet` with `BUNDLE_FROZEN=true` into the person's `GEM_HOME`, as a developer installs a bundle, and then `bundle exec ruby exe/my_cool_app` with the reference Ruby. The app is built with `fledge build` as `MyCoolApp` and run with the same environment. Its differences are those of the `:bundle` check: the program's path as typed; each gem's load path, `GEM_HOME`, and `PATH`, which name the person's `GEM_HOME` under `bundle exec` and the runtime's gem folder in the app; the development gems, which the app leaves out; RubyGems' YAML serializer, which reading the app's `.bundle/config` loads, and Bundler's feature flags, which that file spares it; and the project's version file, which Bundler's evaluation of the gemspec loads under `bundle exec` and the program loads in the app. `Bundler.original_env`, `Bundler.unbundled_env`, and what a child Ruby sees inside `with_original_env` and `with_unbundled_env` do not differ at all.

A third check does the same for `test/fixtures/bundled_with`, whose `Gemfile.lock` was written by Bundler 4.0.19, a version no runtime ships, with the probe as its `exe/bundled_with`, built as `BundledWith`. Its reference `bundle install` installs Bundler 4.0.19 into the person's `GEM_HOME` and `bundle exec` switches to it; the app runs the same Bundler from the runtime's gem folder (ADR 063). Beyond the `:bundle` differences above, it allows only where that Bundler's files are: its files in `$LOADED_FEATURES`, and `BUNDLE_BIN_PATH`, `BUNDLER_SETUP`, `RUBYLIB`, and `RUBYOPT`, which name them, in `ENV` and a child's `ENV`. It runs on every platform, since the fixture locks only concurrent-ruby. `Parity.gem_probe` takes the project and program to copy for it.

On `aarch64-mingw-ucrt` the `my_cool_app` run is skipped (`Parity::WITHOUT_GEM_APP`): `examples/my_cool_app` locks sqlite3, which publishes no build for that platform, and whose source build fails there.

CI's Delivery jobs build the same gem-shaped probe as `ParityBundle` for `deliver.sh` and `deliver.ps1`.

## The mobile parity

`tasks/mobile_parity.rb` builds the probe, with other example apps, as a developer would (`fledge build ios`, `fledge build android`, then Xcode and Gradle), runs each in the iOS Simulator and Android emulators, and reads each app's output back from the system log. The probe's report is read from its standard output alone: the embedding API forwards standard output and standard error through a pipe each, read by a thread each, so a line of standard error can land anywhere among the report's entries, and the report would not parse (`MobileParity::Logged`, `MobileParity.report`). A failed run still reports both streams (`MobileParity#check`). It compares the probe's report with `ruby main.rb` under the pinned desktop Ruby of the computer that runs the simulator, in a person's environment with a UTF-8 locale and an empty home. A phone gives an app an environment of its own, so the probe's `ENV`, and a child's, are compared instead with the one the system gave the app, which the probe's host logs before it starts Ruby (`MobileParity::Environment`). Every difference must be justified in `Parity::JUSTIFIED` for the phone targets, mostly by `Parity::MOBILE_JUSTIFIED`. CI runs it in the `mobile-apps-ios` and `mobile-apps-android` jobs. `doc/contributors/design/phone-projects.md`, "Parity on a phone", says what the probe cannot show on a phone, and the rest of that document covers the phone runtimes.

## Console checks

The console probe, `test/fixtures/console/main.rb`, prints `café ✓` to its terminal; records its locale's character set, its default external encoding, and `ready` in a log; and sleeps, with an `ensure` clause and an `at_exit` hook that record what ended it. The scripts run the built app in Delivery, and, with `--reference` (`-Reference` on Windows), `ruby main.rb` in the Test jobs, with the same expectations. `test/integration/built_app_test.rb` runs the Unix script on the built probe and on `ruby main.rb` wherever a runtime is.

**macOS and Linux**, `.github/scripts/deliver-console.sh`. Each scenario runs the probe in a terminal of its own, a pseudo-terminal that `script(1)` opens (BSD's on macOS, util-linux's on Linux), through a shell that records its process ID and the probe's exit status, with `env -i` and a UTF-8 locale. The shell traps SIGINT and SIGHUP so it outlives the probe; a trapped signal is reset to its default in the programs the shell starts, so the probe gets Ruby's own handling. The terminal runs in the foreground and what ends the probe in the background, because a program a script starts in the background starts with SIGINT ignored (POSIX, "Asynchronous Lists"), which Ruby keeps.

- *interrupt*: Ctrl-C is typed into the terminal, whose line discipline sends SIGINT to the foreground process group. The log must read `ensure ran (Interrupt: )`, `at_exit ran`, and `status 130`, and the terminal must show the probe's line byte for byte and Ruby's message for the `Interrupt`.
- *hangup*: SIGHUP is sent to the shell and the probe, the terminal's foreground process group, as a closing terminal sends it (POSIX, "Closing a Terminal Device File"). The log must read `ensure ran (SignalException: SIGHUP)`, `at_exit ran`, and `status 129`.

**Windows**, `.github/scripts/deliver-console.ps1`, which runs itself in a new console.

- *interrupt*, once under code page 65001 and once under 437: `GenerateConsoleCtrlEvent(CTRL_C_EVENT, 0)` from a PowerShell attached to the same console, which ignores Ctrl-C itself from after the probe started, so the probe does not inherit that. The log must hold `CP65001` or `CP437` as the locale, `UTF-8` as the external encoding, the `ensure` clause, and the `at_exit` hook, and the exit code must be 3. The console's screen buffer, read back with `ReadConsoleOutputCharacterW`, must show `café ✓` on both code pages.
- *close*: the probe runs on a pseudoconsole (`CreatePseudoConsole`); once it is ready, `ClosePseudoConsole`, through `Add-Type`, closes it, which is what Windows Terminal calls when a tab closes. The exit status must be 3221225786 (`0xC000013A`, STATUS_CONTROL_C_EXIT), and the log must hold exactly the locale, `external UTF-8`, and `ready`: no `ensure` and no `at_exit` run, for the built app as for `ruby.exe`. A real console window is not used because GitHub's Windows runners would not close one from a script. A pseudoconsole is a console to the program on it, with a conhost behind it, but not a window: it proves how the program handles CTRL_CLOSE_EVENT, which is the question, and not that a window's close button sends it, which Microsoft's "HandlerRoutine callback function" documents.
- *windowed*: the windowed example, typed into the console, must return the console at once and report that it had no console, as `rubyw.exe` does (ADR 037).

## Restart checks

The probe's `restart` command runs `exec RbConfig.ruby, $0, "restarted", FACTS`, where FACTS is JSON of what a restart must keep: the PID, except on Windows; the program the process runs, by its real path (`/proc/self/exe`, or `ps` on macOS); on macOS outside Bundler, the main bundle's identifier (`NSBundle.mainBundle`, through Fiddle); on Windows outside Bundler, through Fiddle, the program (`GetModuleFileNameW`), the ANSI code page, the AppUserModelID, and whether one of Ruby's DLLs under the app's folder loads through `LoadLibraryExA`; `$0`, `__FILE__`, `__dir__`; the default external encoding and `__FILE__`'s; `RbConfig.ruby`; `Gem.path`; the loaded gems; `Bundler.original_env`; and `ENV`. The restarted probe prints `restarted as itself` when nothing changed, and otherwise a line for each fact that did. Windows has no `exec` that keeps the process: Ruby's own starts the program, waits, and exits with its status, under `ruby.exe` as in an app, so there the PID is not asked.

- `.github/scripts/deliver.sh` restarts the probe, unpacked under a folder whose name is not ASCII, from `/`, with `env -i` and a `PATH` holding no Ruby, in a clean environment, a person's (`GEM_HOME`, `RUBYOPT=-W0`, `RUBYLIB`), and a hostile one (`RUBYLIB`, `RUBYOPT`, `RUBYSHELL`, `GEM_*`, `GEMRC`, `BUNDLE_*`, `BUNDLER_SETUP`, `RUBYGEMS_GEMDEPS`, `RUBY_YJIT_ENABLE`, `LD_LIBRARY_PATH`), on fresh macOS and Linux runners and in the Debian and Alpine containers, for the lone probe and for the gem-shaped one.
- `.github/scripts/deliver.ps1` restarts the probe, unpacked under a folder whose name is not ASCII, in a clean, a person's, and a hostile environment, on fresh x64 and ARM64 Windows runners, for the lone probe and the gem-shaped one.
- `test/integration/built_app_test.rb` restarts the probe as a lone script, as a gem-shaped program, and as a windowed app (a macOS `.app`, or on Windows the windowed launcher), and checks that `bin/ruby`, or `ruby.exe`, hands only the app's program to its launcher, that `ruby.exe` takes no program without the launcher's mark, such as an installer's `uninstall.exe`, for the launcher, and the status 70 of a launcher found and not started.

The parity check does not see restarts, because its child Rubies run `-e` code, which stays plain Ruby.

## ruby/spec

`tasks/ruby_spec.rb` (`bundle exec rake ruby_spec`) runs ruby/spec with MSpec on stock Ruby and in a built app, on the same computer, from the same runtime:

- ruby/spec and MSpec are downloaded at the commits `RubySpec::SOURCES` pins, each checked against its SHA-256, with `codeload.github.com` as a mirror, and unpacked with the computer's own tar. Nothing of them is committed or shipped.
- A project of `tasks/ruby_spec/main.rb`, with `spec/` and `mspec/` beside it, runs as `ruby main.rb` under the reference Ruby of "The references", and is built with `fledge build` as `RubySpec`.
- Each side runs `mspec-run` over `language`, `core`, `library`, `command_line`, and `security`, the directories CRuby's `make test-spec` runs, one process each, with a timeout of 300 seconds.
- Both sides run in the same clean environment: a `PATH` of links to the system's programs less any Ruby and its tools, an empty home folder, a short folder for MSpec's temporary files (a UNIX socket's path holds at most 104 bytes on macOS), and no locale; on Windows, what a Windows program needs to start programs and find its folders. A person's hostile settings are not part of it: they would reach the child Rubies the specs start, as under `ruby main.rb`, and stock Ruby would read them at its own boot, where the launcher hides them.
- Each side loads `tasks/ruby_spec/listing_config.rb`, which lists after MSpec's totals every example MSpec counted, with its spec file, the file and line of its block, and the guards that enclosed it or left it out (`RubySpec::Listing`). The comparison fails on a listing that is missing or does not add up to the totals, as a log that drops lines would leave it.
- A difference is an example that fails on one side only; an error outside any example on one side only, as MSpec prints it for a spec file that fails to load (named by its path inside ruby/spec, as `library: loading library/zlib/adler32_spec.rb`) or for an error in a `before :all` hook or a describe's body (named by the hook and the spec file and line it came through); or an example that ran on one side only, matched by its block, unless a failure on the other side kept it from running or a `platform_is` or `platform_is_not` guard of ruby/spec's left it out on the other side's platform. Each must match `RubySpec::JUSTIFIED`, by side, platform, outcome (`:fails`, or `:runs` for one that ran on one side only), and the example's exact directory and description, or the run fails; only the zlib files RubyInstaller's head build cannot load stay a pattern. Each example a justification names, and that pattern, must explain a difference in every run on the justification's platforms, as `Parity::JUSTIFIED`'s entries must, or the run fails. A difference that the computer running stock Ruby decides, not the platform, is justified only on a computer where it holds, by a condition that names it: Android's leap-second example where this computer's time zone data has `right/UTC` (`RubySpec::RIGHT_UTC`), and its `File.expand_path` examples of the user database where stock Ruby has no login UID for glibc's `getlogin` to name (`RubySpec::NO_LOGIN_UID`). `RubySpec::EXCLUDED` would leave out, by platform, examples that stop the process for stock Ruby and the app alike, and is empty: the musl runtimes, which crashed in `Thread#to_s`'s example on both sides, take the `thread_c` edit (`doc/contributors/design/runtimes.md`, "musl Linux's Ruby, built in Alpine").
- Each run's output and a summary go to `tmp/ruby-spec` (or `RUBY_SPEC_OUT`), and the summary to the job summary in CI.

### ruby/spec on phones

`RubySpec::Phone` (`tasks/ruby_spec/phone.rb`) runs the same comparison in a phone app, in the iOS Simulator on an iPhone and an iPad, and on Android emulators of API 36 with 4 KB and with 16 KB pages, against stock Ruby on the computer that runs the simulator:

- The project is the desktop's, with an identifier in its `fledge.yml`, built as a developer builds a phone app: `fledge build ios` and `xcodebuild` for the Simulator, or `fledge build android` and the project's Gradle wrapper for a debug APK (`MobileParity::IOS#build_app`, `MobileParity.projects`). It is installed and launched as the mobile parity check launches its probe, and its output is read back from os_log or logcat, as an app's output reaches its developer.
- Each side is read from MSpec's standard output alone, where MSpec prints `RUBY_DESCRIPTION`, the failures, and the totals. The embedding API forwards standard output and standard error through a pipe each, read by a thread each, so the log holds each stream's lines in order but the two interleaved as the threads happen to run. A line of standard error could land between a failure's number and its description, as MSpec's warning at exit that its temporary folder is not empty did on an iPad in run 43226291212, and that failure went unread. So the app's standard error is left out by its log level (an error in os_log, a warning in logcat; `MobileParity::IOS.messages`, `MobileParity::Android.messages`), and stock Ruby's goes to `stock.err`, apart from `stock.out`.
- A phone app takes no arguments and starts Ruby once a launch, so the app runs every directory in one `mspec-run`, with the arguments `main.rb` reads from `arguments.txt` beside it when it has none. `tasks/ruby_spec/phone_config.rb`, which `mspec-run` loads with `-B`, prints only the failures and the totals, as MSpec's summary formatter does, and names each failure's directory before its description, so the names match the desktop's. The app writes its listing of the examples it ran to a file and prints the file's path, which the check reads back from the simulator or emulator (`RubySpec::Phone.listed`), since logcat dropped a fifth of a listing printed on an emulator in run 43350707323. For a spec file of which only some examples run, `phone_config.rb` adds a filter of MSpec's exclude kind that knows the file it is asked about and leaves out every example of it but those `main.rb` reads from the `--ruby-spec-keep=FILE:DESCRIPTION` lines of `arguments.txt`. MSpec's temporary files go to a short folder of `/tmp` where the app may write there, as in the Simulator, and under `Dir.tmpdir` elsewhere, since the app's bundle is read-only on a device and a UNIX socket's path holds at most 104 bytes on Apple's systems.
- Stock Ruby is the release the desktop runtime of that computer is made from (rv-ruby's for `arm64-darwin` and `x86_64-linux`), unpacked as the desktop comparison unpacks it, running `ruby main.rb` with the same `arguments.txt` in the same clean environment, with a UTF-8 locale, as a phone's app has. Its version and revision, from `RUBY_DESCRIPTION`, must be the phone runtime's, or the check fails before it compares.
- No program can run on iOS, Ruby least of all, so the same configuration makes MSpec's `ruby_exe` helper, which starts the Ruby under test, skip its example there where `RbConfig.ruby` is not a program, as MSpec skips it on WASI; under stock Ruby it runs as MSpec's own. It is MSpec's helper, not Ruby's: the examples of Ruby's own ways to start a program run where a phone can. On Android `RbConfig.ruby` runs the runtime's ruby program (ADR 082), and `ruby_exe` never skips.
- `RubySpec::Phone::EXCLUDED` leaves out of both runs, by phone and with a reason for each, what a phone cannot run, as whole spec files or by example: on iOS, `command_line`, whose every example starts `ruby`; the examples of the files about Ruby's ways to start a program, which check each by starting the Ruby under test without `ruby_exe`, but those that start nothing, which run; the examples of `Process.kill` that signal Rubies they start; and `Process::Status`'s files, whose `before :each` hooks start a Ruby through `ruby_exe`, whose skip in a hook leaves the example uncounted; all of which Android runs with its ruby program. On iOS too, the examples that fork a child that goes on running Ruby, since whether a device lets an app fork is unchecked and the Simulator, which does, would not show it (`doc/contributors/design/phone-projects.md`, "Parity on a phone"), and the examples and files that start a program of the system's, among them `library/etc`'s that start `id` before any example, which Android has. Android excludes nothing. Every other difference must match `RubySpec::JUSTIFIED` for the phone's platform (`RubySpec::PHONES`: `arm64-ios-simulator`, `x86_64-linux-android`, `aarch64-linux-android`), as on the desktop. What ruby/spec found that was a bug, not a phone's rule, is mended in the runtime (`doc/contributors/design/phone-runtimes.md`, "Scripted edits to Ruby's source"); the entries of either list marked TEMPORARY are to be done.
- Each run's output, stock Ruby's, and a summary go to `tmp/ruby-spec-ios` or `tmp/ruby-spec-android` (or `RUBY_SPEC_OUT`), and the summary to the job summary in CI.

`ruby tasks/ruby_spec.rb ios RUNTIMES_DIR` runs it in the Simulator; `ruby tasks/ruby_spec.rb android-build RUNTIMES_DIR` runs stock Ruby and builds the APK, and `ruby tasks/ruby_spec.rb android` runs it on the emulator that is running.

### Where it runs

`.github/workflows/ruby-spec.yml` runs it. `ci.yml` calls it on every push for `x86_64-linux` and `arm64-darwin` and on the phones, and for all seven desktop platforms too on a release commit; every night, and when run by hand, it runs all of them on the runtimes of trunk's newest run of `ci.yml` that passed.
