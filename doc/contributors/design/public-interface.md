<!--
SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>

SPDX-License-Identifier: CC-BY-SA-4.0
-->

# The Public Interface

This document lists what Fledge promises from 1.0: what 1.x freezes, what any release may change, how 1.x adds without breaking anyone, the names held for later, and what a framework wrapper may rely on. ADR 029 decides that the interface is the command and the files it reads and writes; ADR 028 that a change to it takes a major; ADR 054 the schema's address; ADR 031 the mirror. Which Rubies and platform floors 1.x keeps is in `doc/contributors/design/releases.md`. App developers read the short form in `doc/runtimes.md`, "What 1.x keeps".

Before 1.0, everything here may still change, with a CHANGELOG entry. From 1.0, each frozen item changes only in a major.

## What counts as compatible

A change is compatible when every project that builds with 1.0 builds with a later 1.x to the same output, and every app it built behaves the same. Turning a refusal into an acceptance is compatible: a new key, a new value of `kind`, lifting an "at most one". Changing a default, a file name, a printed line, or the meaning of a value Fledge accepts is not.

## Frozen for 1.x

- **The command.** `fledge build [OPTIONS] [PATH]`, `fledge build --from APP [OPTIONS] [PATH]` (ADR 032), `fledge build ios|android [OPTIONS] [PATH]` (`doc/contributors/design/phone-projects.md`, "The operand"), `--help` (`-h`, `-?`), `--version` (`-v`), `-o`/`--out`, `--from APP`, `--sign` (ADR 016), `--sign-command COMMAND` (Windows only; ADR 051), `--notarize PROFILE` (macOS only, with `--sign`; ADR 033), and `--`, with their meanings and defaults (`.` for PATH, `dist` for `--out`). `--sign` with `--sign-command` is a usage error, and so is `--notarize` without `--sign`. `FLEDGE_SIGN_COMMAND`, which stands for `--sign-command` on a Windows build whose command line gives neither it nor `--sign`, is frozen with them. A bare word Fledge reads as a platform, today `ios` and `android`, is read as one; a folder of that name is written `./NAME` (see "Reserved names").
- **Exit statuses** (ADR 002). `fledge`: 0; 1 for a failed build; 2 for a usage error. A built program: its Ruby program's status; 66 when its entry, `fledge.cfg`, or its section of `fledge.cfg` is missing; 72 on Linux when a library `linux: system_libraries` lists is not on the computer (ADR 030); 70 for other damage. `bin/ruby`: 70 when it cannot run the app's launcher (ADR 026). The phone runtimes: `FLEDGE_RUBY_NO_APP` and `FLEDGE_RUBY_SOFTWARE` (`runtime/mobile/fledge_ruby.h`).
- **Standard output.** One path per line: the archive `fledge build` writes, then each installer, or a phone project's folder. `--help` and `--version` print there too. Nothing else goes to standard output, the checksum files included.
- **`fledge.yml`.** Every key, every value it accepts, every default, and the refusal of a key it does not know. The keys are `Fledge::Config::KEYS`, and `lib/fledge/config.schema.json` describes each: among them `installers` and its default (`dmg`, `nsis`, `appimage`; ADR 009), `programs` (ADR 024), `ios` and `android` with `host` (ADR 025), `linux` with `system_libraries` (ADR 030) and `deb_changelog`, `macos` with `build`, `file_associations` and what each system makes of it (ADR 052), and `build_tools` (ADR 032).
- **The schema's address.** `$id` and the documented modeline name the file at the release's tag (ADR 054), and that address keeps serving the release's file.
- **What `fledge build` writes.** `DIR/NAME-PLATFORM/`; its archive, `.tar.gz`, or `.zip` on Windows; `NAME-arm64-darwin.dmg`, `NAME-PLATFORM-setup.exe`, `NAME-PLATFORM.AppImage`, and `NAME-PLATFORM.deb`; beside the archive and each installer its checksum file, `FILE.sha256`; `DIR/NAME-ios/`, `DIR/NAME-android/`; and `DIR/CACHEDIR.TAG`.
- **What a built app holds.** `app/`, the project as copied, so an app's code finds its files through `__dir__`; `notices/NOTICES.txt` and `notices/sbom.spdx.json`; on Linux and Windows `notices/sources/`, the source of each component whose license asks for it (ADR 043), whose folders follow what the runtime ships; each program's name and where it sits; on macOS a windowed program's `NAME.app`, with the console programs in the bundle of the first windowed program (ADR 024); on Linux `IDENTIFIER.desktop` and `share/icons/hicolor/`.
- **Where an installer puts the app.** On Windows `%LOCALAPPDATA%\Programs\NAME`, the shortcut's AppUserModelID, and the uninstall key `HKCU\...\Uninstall\IDENTIFIER` (ADR 009); a `.deb`'s package name, the identifier in lower case, and its folder `/usr/lib/PACKAGE` (ADR 021). Each system knows the app by its identifier, so changing `identifier` makes a new app as far as that system is concerned, and the help says so.
- **How a built app differs from `ruby main.rb`.** `Parity::JUSTIFIED` (`tasks/parity.rb`) and `MOBILE_JUSTIFIED` (`tasks/parity/mobile.rb`) may only shrink in 1.x. A new difference is a change in how Ruby behaves under Fledge, the surprise Design precedence 2 forbids; removing one is a bug fixed toward `ruby main.rb`.
- **Phone projects.** The project folder's names and `fledge/`; the paths in the templates a host may replace (ADR 025); the `@@NAME@@` marks Fledge fills; and the embedding API: `fledge_ruby_run`, `fledge_ruby_run_app`, `fledge_ruby_add_extension`, and `fledge_ruby_forward_output` in `runtime/mobile/fledge_ruby.h`, and `org.setdef.fledge.FledgeRuby.startApp` on Android.
- **Releases and runtimes.** The tag form `vX.Y.Z`, with a prerelease in SemVer's form, such as `v1.0.0-beta.1`; the asset names `fledge-runtime-VERSION-PLATFORM.tar.gz`, `-dev.tar.gz`, `-NOTICES.txt`, `.spdx.json`, and `-lgpl-sources.tar.gz`, with VERSION Fledge's; `SHA256SUMS` in `sha256sum`'s format; `FLEDGE_RUNTIME_DIR` as a folder of those names; and `FLEDGE_RUNTIME_MIRROR` as the base URL of a copy of the releases that holds them as `vVERSION/NAME`, checked against the pins and never passed over for the release (ADR 031).
- **Ruby and the platform floors.** The rule that an app gets the runtime of the Ruby minor that runs `fledge build`, and the refusal of a minor with no runtime (ADR 055); every Ruby minor 1.0 has a runtime for; and the platform floors (`doc/contributors/design/releases.md`).

Every frozen item is tested where it is built: the CLI's tests, the schema test, `Parity`, and the Delivery jobs. A test that would let one change without failing is a bug in that test.

## Not frozen

Each item below may change in any release, with a CHANGELOG entry when a developer could notice.

- **Fledge's Ruby code.** `Fledge::CLI`, `Fledge::Config`, `Fledge::App`, and every other class and module under `lib/`, their methods, and their RDoc. They document how Fledge works, for its contributors. A wrapper runs `fledge build` as a command.
- **Standard error's wording.** Progress lines, warnings, and every `fledge build: ...` message improve from release to release. A wrapper tells success from failure by the exit status, and finds the files by standard output.
- **`fledge.cfg`.** `fledge build` writes it, and the launchers of the same release read it; nothing else should. Its keys and sections may change in any release, and runtimes of another release named by `FLEDGE_RUNTIME_DIR` are not supported.
- **The `tools` folder's layout.** What `build_tools: true` puts in an app, and where. Only a `fledge build --from` of the same release reads it. The key and its effect are frozen; the folder's contents are not.
- **The runtime's tree** below what Ruby itself answers: `RbConfig.ruby`, `RbConfig::CONFIG`, `Gem.dir`, `Gem.bindir`, and `__dir__`. An app that asks Ruby where things are keeps working when a folder moves.
- **The templates' contents.** The files a phone project starts from may change in any release; a host's copy of one is the developer's to keep in step, and the build names each copy it uses (ADR 025). Google Play's target API level and the Xcode version App Store uploads need live there.
- **The caches.** `~/.cache/fledge/` and what it holds. On Windows a later release may move it to `%LOCALAPPDATA%`, which costs one download.
- **How Fledge is built and tested**: CI, `tasks/`, the runtimes' sources and pins, and the build-only companion's contents.

## How 1.x adds

- A new option, key, value, `kind`, command, or environment variable is compatible, since today's parser and `fledge.yml` refuse every one they do not know.
- A new installer is opt-in for all of 1.x, as `deb` is (ADR 021). A new default would print a new line and need a new tool on a computer that built yesterday.
- A new icon size for a target is optional: a build that passed keeps passing.
- A new line on standard output comes only with a file the developer asked for, such as an opt-in installer. The built folder is not printed: a wrapper derives it from the archive's name. A file written beside every archive, as the checksum file is, is not printed either, and adding one is compatible.
- A limit lifted ("at most one windowed program", one PATH, one `--sign`, one `host`) is compatible, as long as what a project with one builds stays the same. When several windowed programs come, the console programs stay in the first one's bundle.
- A runtime for a new Ruby minor comes under the reserved names, and a runtime's patch may move (`doc/contributors/design/releases.md`).

## The checksum file

`fledge build` writes `FILE.sha256` beside the archive and each installer, always, in `sha256sum`'s format, and 1.x keeps both. What it holds and why is in `doc/contributors/design/desktop-apps.md`, "The folder and the archive".

## The fledge.yml schema

`lib/fledge/config.schema.json` is draft-07, the draft every editor reads, and holds what `Fledge::Config` enforces and nothing it does not . It is written by hand, not generated from `Fledge::Config` as Tauri generates `tauri.conf.json`'s schema from the Rust types it parses: Config is Ruby that checks each value and raises with a message, not a set of types, so a generator would need every description, pattern, and rule between keys as literals, which is the schema written in Ruby plus a task and tests of its own. `test/config_schema_test.rb` keeps the two from disagreeing. It compares the schema's keys, kinds, installers, default installers, and identifier rules with Config's constants, runs a table of documents through both the schema and Config (with `Fledge::Identity`) and fails when either accepts what the other refuses, checks the schema against draft-07's meta-schema, and checks every `fledge.yml` in the repository against both. It needs json_schemer, a development dependency that nothing Fledge ships loads. Submitting the schema to SchemaStore's catalog, which would match every `fledge.yml` without a modeline, is a change in another project's repository and is left to the maintainer. Its descriptions come from the `fledge.yml` section of `exe/fledge`'s help. Where Config's Ruby and JSON Schema differ, the schema says the same thing another way, and a reader should not "fix" these:

- `additionalProperties: false`, since Config refuses an unknown key.
- A value may be text or empty (YAML's `name:` with nothing after it), which Config reads as absent. Text that is blank to Ruby's `String#strip` is refused by a pattern that needs one character outside Ruby's whitespace and NUL.
- Patterns are read as ECMA-262 reads them, as editors do, so Config's `\A` and `\z` are written `^` and `$`.
- `version` is RubyGems' `Gem::Version::ANCHORED_VERSION_PATTERN`, which `Gem::Version.correct?` uses, less its leading whitespace, since Config also needs a leading digit. Its atomic group is written as a plain one, since the group's characters never overlap what follows it, and Ruby's `\s` is spelled as its six ASCII characters. A YAML number is refused, as Config refuses `version: 1.2`.
- The rules between keys, such as `installers` only for a windowed app and a windowed app's required `identifier` (which `Fledge::Identity` checks), are `if`/`then` rules.

What the schema does not hold: a file that is not valid YAML is the language server's to report, and a value `YAML.safe_load` refuses (a date, say) is refused by Config as invalid YAML where the schema sees no such type.

Every `fledge.yml` in `examples/` and the test fixtures starts with a modeline that names the schema beside it by a relative path, such as `$schema=../../lib/fledge/config.schema.json`. A modeline is a YAML comment, so neither Config nor a built app reads it.

## Reserved names

Each name below is held, so that the feature it names arrives under it and nothing else takes it first.

- **`ios: build`**, a string of one to three whole numbers separated by periods, the shape `macos: build` has for the same Apple key, for `CFBundleVersion` and `CURRENT_PROJECT_VERSION`; and **`android: version_code`**, a whole number for `versionCode`. Each overrides the number Fledge derives from `version`, as Tauri's `bundleVersion` and `versionCode` and Briefcase's `build` and `version_code` do. Without them both stores see `1.0.0.pre.1` and `1.0.0` as one build, and refuse a second upload of a version. The derivation (`lib/fledge/mobile_project/ios.rb` and `android.rb`) stays the default, frozen; only the override is to come.
- **Runtime asset names with the Ruby's version**: `fledge-runtime-VERSION-ruby-X.Y.Z-PLATFORM.tar.gz`, and the same `-ruby-X.Y.Z-` part in each companion asset's name, for the runtime of a Ruby minor that a 1.x release adds. Throughout 1.x, the names without it mean the runtime of the Ruby minor 1.0 ships (`doc/contributors/design/releases.md`, "Ruby minors and runtimes").
- **Platform words in PATH.** A bare word that names a platform Fledge may write a project for (`ios` and `android` today; `visionos`, `tvos`, `watchos`, or another later) is read as that platform by every release that adds it. `fledge --help` says to write `./NAME` for a folder of such a name, so a developer who follows the help is never broken by a new platform. Briefcase reads `briefcase build iOS` the same way.

Waiting for a developer or a framework to ask, and compatible when they come, since each turns a refusal into an acceptance (ADR 032):

- a copy-only `fledge build --from` for an APP built for another system;
- a single Windows file that runs without unpacking by hand (ADR 032).

## A framework wrapper's view

Lota, Tokra, and Rooibos call Fledge so that a developer who uses one ships an app without learning how. Fledge depends on no wrapper's repository; wrappers depend on Fledge (decisions.md, 2026-11-02). A wrapper relies on the frozen list above, and on nothing in "Not frozen". In a wrapper's terms:

- **The command.** `fledge build [PATH]` builds the program at PATH (default: the current directory; a folder means its gemspec's executable, or its `main.rb`) on the computer it runs on, for that computer's platform, with `-o DIR` choosing the output folder (default `dist`). It runs as `bundle exec fledge build` from a project whose Gemfile names Fledge by tag, in the `development` group, which Fledge leaves out of the app. The app runs on the runtime's Ruby, the minor of the Ruby running `fledge build` (ADR 055), whatever Rubies the wrapper supports otherwise. The first build downloads the release's runtime, checked against the gem's pins (ADR 014), into `$XDG_CACHE_HOME/fledge/runtimes`; `FLEDGE_RUNTIME_DIR` names a folder of runtimes instead.
- **The project.** The nearest folder from the program up with a Gemfile, `gems.rb`, gemspec, or `fledge.yml` (not above a git repository's top) ships whole, but for `.git`, `.bundle`, `vendor/bundle`, `vendor/cache`, and the output folder, with the gems the lockfile locks outside the `development` and `test` groups, each as built for the platform (ADR 005). The lockfile locks each platform the wrapper ships to, with checksums (`bundle lock --add-platform`, `bundle lock --add-checksums`). Gems a project uses to develop or test it, and Fledge itself, belong in those groups; a gem outside them ships, and Fledge compiles it when it must (ADR 006).
- **`fledge.yml`.** A wrapper may write it for its developer or read the developer's. An unknown key is refused, naming it, so a wrapper never sees a key silently ignored. A wrapper whose app is one of several programs, as `lota fuse` would be for a game's GUI, names its entry point as one of the `programs` and builds the project, or builds that program alone by its path (ADR 024).
- **Output and statuses.** On standard output, the path of each file `fledge build` writes, one per line, and nothing else. Progress, the downloads, compiler output, and every error and warning go to standard error, an error as `fledge build: ...`, one line for each thing that is wrong. `NAME` is the `fledge.yml` name, else the gemspec's, else the project folder's, camelized. A wrapper tells success from failure by the exit status.
- **What a built app is.** A folder `NAME-PLATFORM/` whose program, `NAME` or `NAME.exe`, needs no Ruby and is unaffected by a Ruby the person has (ADR 040). Its `ENV`, `$0`, and load path are as under `bundle exec ruby main.rb` (ADR 003, ADR 045), so a wrapper's checks such as `__FILE__ == $0` behave as under `ruby`. Ctrl-C and a closed terminal reach the app as they reach `ruby` (ADR 003).
- **Each platform on its own computer.** Fledge builds each platform's app on that platform (ADR 010). A wrapper's CI runs one build job on a runner of each platform it ships to, and a delivery job on a fresh runner of each, which takes the archive and runs it.
- **Not to rely on.** Fledge's Ruby classes, standard error's wording, and `fledge.cfg`. A wrapper that runs `Fledge::CLI` in its own process does so without a promise.

A wrapper whose CI tests its unreleased source names Fledge, or itself, as a git gem at a commit. A library's own repository is not an app: building one of its examples from the repository's root ships the tools its Gemfile keeps outside the `development` group.

### Building from a built app

For a framework's drop-to-make-an-app (decisions.md, 2026-11-04), Fledge gives general primitives and knows no framework's concepts (ADR 032).

**Fledge provides**, frozen with the rest: `fledge build --from APP`, its refusals, statuses, and output; `file_associations` and what each system makes of it; `build_tools`; and that an app built `--from` keeps APP's runtime, gems, `Gemfile.lock`, and `notices/` unchanged, and holds the new project as plain files, so `__dir__`, `__FILE__`, `require_relative`, and backtraces name real files. `--from` builds for the computer's own platform only.

**A framework provides**: the app it publishes for people to build from, built with `fledge build` in its own CI, with its gems, Fledge in its Gemfile outside the `development` and `test` groups, `build_tools`, and `file_associations`; receiving a drop, through its GUI library's events, and the screen that asks for one; turning what was dropped into a project, which may mean unpacking a zip, reading its own configuration, writing `fledge.yml` with a name and a unique identifier, and writing the program that starts the dropped content; running `fledge build --from` and saying where the output went; and everything its programs do at run time, such as where they save. A framework runs the `fledge` that RubyGems writes into the app's `Gem.bindir`, with `RUBYOPT=-rbundler/setup` and no `RUBYLIB`, so the person's own `RUBYOPT` and `RUBYLIB` do not reach it as they would reach a child under `bundle exec`. `doc/contributors/research/2026-11-05-drag-to-fuse.md` maps one framework's needs onto these primitives as an example.

### Phones

A framework that ships to an iPhone, an iPad, or an Android device through Fledge may rely on what follows from a Fledge release; it is part of Fledge's public interface, and changes only as this document says. How each part works is in `doc/contributors/design/phone-runtimes.md` and `doc/contributors/design/phone-projects.md`.

**Fledge provides:**

- `fledge build ios`, on a Mac with Xcode and XcodeGen, and `fledge build android`, on a Mac, x86-64 Linux, or Windows, which write an Xcode or Gradle project holding the project, its gems, and a runtime. The framework's team builds, signs, and submits that project with Xcode or Gradle.
- A gem with a C or C++ extension built by an `extconf.rb` is compiled for each of the phone's targets, linked into the app, and registered, so `require "name/name"` finds it. Static libraries an `extconf.rb` links are linked per iOS slice; shared ones are carried into the Android app.
- An `extconf.rb` that runs CMake finds each target's toolchain file in `CMAKE_TOOLCHAIN_FILE`.
- `ios: host: DIR` and `android: host: DIR` in `fledge.yml` name a folder of files that `fledge build` copies over the project it writes, so a framework that must own the app's startup supplies its own files and keeps them across builds (see `doc/contributors/design/phone-projects.md`, "Host files"). The templates' file paths and marks stay, so a host's copy keeps working.
- The embedding API, `fledge_ruby_forward_output` and `fledge_ruby_run_app` (and on Android `FledgeRuby.startApp`), which a framework's host calls wherever its framework runs the main function.

**The framework provides:**

- A Ruby program that starts the app, and the gems it needs in the project's `Gemfile.lock`, locked for `ruby` (`bundle lock --add-platform ruby`). A phone runs no shell script, and the gems must be in the lockfile, not found on the build computer's paths.
- An extension that an `extconf.rb` builds with mkmf, calling `create_makefile` once, in C or C++, loaded with `require "name/name"` or `require "name/name.so"`, never `require_relative`, with its Init function named `Init_NAME` for the target's basename, as mkmf expects (Fledge renames it). The `extconf.rb` requires nothing but Ruby's standard library, since it runs with `--disable-gems`.
- No `dlopen` of a file it ships, no code that writes executable files, and no `fork` or `exec`.
- When the `extconf.rb` runs CMake first: run `cmake` with a new build folder each time, inside the folder the `extconf.rb` runs in, and let CMake find its toolchain in `CMAKE_TOOLCHAIN_FILE`; pass no `CMAKE_SYSTEM_NAME`, sysroot, or compiler of its own, but `CMAKE_BUILD_TYPE` and the project's options as on a desktop; link what CMake built through `$LOCAL_LIBS` by path; build static libraries position-independent (`POSITION_INDEPENDENT_CODE ON`); name the C++ runtime as on a desktop (`-lc++` or `-lstdc++`) when the extension is C over C++, and Fledge links the phone's; and have CMake 3.21 or later on the build computer's `PATH`.
- Its native libraries, built for the phone's targets: a static library per iOS slice (or an XCFramework), and a shared library per Android ABI, found by the `extconf.rb` through `dir_config` or Bundler's `build.NAME` options (`bundle config build.NAME --with-NAME-dir=...`), which Fledge passes as `extconf.rb` arguments for every target.
- Its host files, when its framework owns startup, in the `host:` folder: on iOS any of `Host/main.m`, `Host/Info.plist`, `Host/PrivacyInfo.xcprivacy`, the asset catalog, and `project.yml`; on Android `MainActivity.java` at its package's path, the manifest, the Gradle files, `strings.xml`, and any Java sources of its own.

Fledge refuses, naming the gem, an extension that the gemspec says Rake, CMake, configure, or Cargo builds with no `extconf.rb`, and a Rust extension.

**Known limits:**

- CI runs the apps in the iOS Simulator and on x86_64 Android emulators. It builds and checks the iOS device slice and the arm64-v8a library, but runs neither: no free GitHub-hosted runner boots an arm64-v8a emulator. Games built with `fledge build` have run on a physical iPad Pro, iPhone 13 mini, and OnePlus Nord N30 5G (arm64-v8a).
- An SDL host on iOS runs Ruby on the main thread and asks for a 64 MB main-thread stack in the project's linker flags. Apple documents 1 MB for a device's main thread. An iPhone 13 mini granted the 64 MB; an iPad's grant is not measured, so a deep recursion in Ruby could still fail there.
