<!--
  SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
  SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- `fledge build ios` writes an Xcode project for an app on iPhone and iPad (iOS 15 and later, arm64), on a Mac with Xcode and XcodeGen, and `fledge build android` a Gradle project for Android (API 26 and later, targeting API 36, native libraries aligned for 16 KB pages), with Gradle 9.8.2's wrapper, on a Mac, x86-64 Linux, or Windows: `DIR/NAME-ios/` and `DIR/NAME-android/`, around the release's mobile runtime, with the app's project, its gems, the runtime's notices, and a small host app that runs the app's program and sends its output to os_log or logcat. Neither signs anything; you sign and submit the app.
- A phone's app takes `fledge.yml`'s `identifier` (required) as its bundle identifier or `applicationId`, its `name`, its `version` (Android's `versionCode` from its first three numbers), and its icon: `ICON-1024.png` for iOS, and `ICON-48.png`, `-72`, `-96`, `-144`, and `-192` for Android.
- A phone's app ships each gem's `ruby` build, set up by Bundler with `force_ruby_platform`, so its `Gemfile.lock` must lock `ruby`; a gem with an extension to compile fails the build.
- An iOS project's privacy manifest names the required-reason APIs Ruby calls: file timestamps (C617.1) and system boot time (35F9.1).
- The mobile runtimes' embedding API gains `fledge_ruby_run_app`, and on Android `FledgeRuby.runApp` and `startApp`, which run the app `fledge.cfg` names, with Bundler set up for its Gemfile, as the desktop launcher does.

## [0.0.1.pre.9] - 2026-10-28

### Added

- Mobile runtimes, as release assets beside the desktop ones, with their SBOMs and NOTICES: `fledge-runtime-VERSION-ios.tar.gz`, holding `FledgeRuby.xcframework` for iOS and iPadOS devices and the Simulator (`arm64-ios`, `arm64-ios-simulator`), and `fledge-runtime-VERSION-android.tar.gz`, holding `FledgeRuby.aar` for Android's arm64-v8a and x86_64 (`aarch64-linux-android`, `x86_64-linux-android`). Each is CRuby 4.0.9 built from source as an interpreter, with its extensions linked in, OpenSSL 3.6.5, libyaml 0.2.5, on Android libffi 3.5.2, every default and bundled gem as a gem (fiddle left out on iOS), Mozilla's CA certificates, and a UTF-8 locale, started by a small embedding API (`fledge_ruby_run`, `fledge_ruby_forward_output`, and on Android `org.setdef.fledge.FledgeRuby`) that sends standard output and standard error to os_log or logcat. `fledge build` does not build mobile apps yet.

## [0.0.1.pre.8] - 2026-10-28

### Changed

- **Breaking:** `fledge.yml`'s `icon` names the icon's files without an extension, as Briefcase's does (`icon: icons/app`), and each platform takes its own, as you make it: `icons/app.icns` on macOS, `icons/app.ico` on Windows, and `icons/app-16.png`, `-32`, `-64`, `-128`, `-256`, and `-512` on Linux. Fledge no longer makes them from one PNG; an `icon` that ends in `.png` fails, saying what to write.
- **Breaking:** on a computer with no FUSE, an AppImage says so and runs only when asked to extract itself (`APPIMAGE_EXTRACT_AND_RUN=1` or `--appimage-extract-and-run`), as every AppImage does; it no longer extracts itself unasked.
- A built app's archive is written, and a runtime unpacked, by the computer's own tar: GNU tar on Linux, bsdtar on macOS, and `System32\tar.exe` on Windows 10 and 11, which writes the `.zip`.
- On macOS, a windowed app's `Info.plist` is written by `plutil`, the bundle is signed ad hoc by `codesign`, and its disk image is made by `hdiutil`, all of which come with macOS. The disk image is a Mac OS Extended volume, as create-dmg makes, rather than the case-sensitive one Fledge wrote.
- On Windows, a program's version information and icon are written by rcedit 2.0.0 (MIT), which Windows runtimes carry in `tools/rcedit.exe` and no app holds; the runtime's folder of build tools, `installer/`, is now `tools/`. Linux apps' hicolor icons are the six sizes Briefcase asks for, no longer eight.
- A Linux app's AppImage begins with AppImage's own type 2 runtime, release 20251108, as AppImage publishes it (MIT, with libfuse 3.15.0, LGPL-2.1, squashfuse, zstd, zlib, mimalloc, and musl linked in), and its file system is written by `mksquashfs` with appimagetool's options, so building one needs squashfs-tools 4.4 or newer (`apt install squashfs-tools`). Each Linux release's source bundle now holds the runtime's source and libfuse's, and every Linux app's notices name them.
- A Windows app's NSIS installer is compressed with LZMA, NSIS's default, in place of zlib, and compiled by NSIS 3.13's own `makensis.exe`, which the Windows runtime now carries in `tools/nsis` with the stub, plug-ins, and Modern UI. NSIS's LZMA module is under the Common Public License 1.0; each Windows release's source bundle now holds NSIS's source, and every Windows app's notices say where it is.

### Removed

- **Breaking:** `fledge build` builds only for the computer it runs on; `-t` and `--target` are gone, and say so. Build the macOS app on a Mac, the Windows app on Windows, and each Linux app on Linux, as Tauri and Briefcase do.
- The `fledge-makensis-VERSION-PLATFORM.tar.gz` release assets, and the download of makensis: a Windows installer is built on Windows with the runtime's NSIS.

## [0.0.1.pre.7] - 2026-10-28

### Added

- Installers for windowed apps, each built beside its archive from any computer: `NAME-arm64-darwin.dmg`, a disk image of the app's bundle with a link to Applications, which hdiutil verifies and whose bundle stays signed; `NAME-x64-mingw-ucrt-setup.exe`, an NSIS installer that installs for the person who runs it, with no administrator, into `%LOCALAPPDATA%\Programs\NAME`, makes a Start menu shortcut carrying the app's identifier as its AppUserModelID (so Windows shows the app's notifications), offers an unchecked desktop shortcut, registers an uninstaller, and installs silently with `/S`; and `NAME-PLATFORM.AppImage` for Linux, which runs from its own FUSE mount, or extracts itself and runs where there is no FUSE.
- `fledge.yml` takes `installers`, a list of `dmg`, `nsis`, and `appimage`, or `[]`; a windowed app gets all three by default, and a console app none.
- `fledge build` prints each installer's path after its archive's.
- Linux runtimes carry `installer/appimage-runtime`, Fledge's build of AppImage's type 2 runtime (MIT), with squashfuse (BSD-2-Clause) and zlib compiled in and no libfuse, which it loads from the computer; the Windows runtime carries `installer/nsis/`, NSIS 3.13's stubs, plug-ins, and Modern UI (zlib license). No app's folder or archive holds either.
- Each release carries `fledge-makensis-VERSION-PLATFORM.tar.gz`, NSIS 3.13's makensis for each computer that builds apps, which `fledge build` downloads for an NSIS installer.

## [0.0.1.pre.6] - 2026-10-28

### Added

- Windowed apps: `kind: windowed` in `fledge.yml` builds an `.app` bundle for macOS, signed ad hoc so it runs on Apple Silicon and passes `codesign --verify --strict --deep`; a program Windows starts without a console, from the new `launcherw.exe` every Windows runtime carries; and, for Linux, the folder with `IDENTIFIER.desktop` and the icon in `share/icons/hicolor/`. Each builds from any computer.
- `fledge.yml` takes `kind`, `identifier`, `version`, `icon`, `publisher`, and `copyright`. A windowed app needs an `identifier`; `version` defaults to the gemspec's (or `0.0.0`), and `publisher` to its authors.
- Every Windows app's program carries version information (FileDescription, which Task Manager shows, ProductName, CompanyName, LegalCopyright, and the versions) and, with an `icon`, the app's icon.
- `icon` is one square PNG of at least 1024x1024 pixels, which Fledge makes into an `.icns` for macOS, icon resources for Windows, and hicolor PNGs for Linux.
- On Windows, an app with an `identifier` takes it as its AppUserModelID when it starts.

## [0.0.1.pre.5] - 2026-10-28

### Removed

- `fledge build` no longer judges an app's gems by their licenses, which are the app developer's to decide: a GPL, AGPL, MPL, or LGPL gem, a gem whose license is unknown, and one that declares none all ship, and an LGPL gem no longer needs its source pinned.
- A native gem's compiled files may hold any library: nokogiri's precompiled builds for `arm64-darwin` and `x64-mingw-ucrt`, and its build from source on Windows, which link GNU libiconv in, now ship. Compiled code no longer needs a review in Fledge's map or a `compiled` entry in `fledge.yml`, and a Rust extension's crates are no longer read with `cargo metadata` or judged.
- `notices/GEMS.txt`, and the warning for a gem that ships no license file. Each gem ships with its own files, its license files among them, in its own folder; `notices/` holds the notices of what Fledge itself puts in an app.
- **Breaking:** `fledge.yml`'s `licenses` and `compiled` keys. A `fledge.yml` that still has either fails the build, as any key Fledge does not know does; `name` is the one key left.

## [0.0.1.pre.4] - 2026-10-27

### Added

- `fledge build` compiles a gem with an extension to compile (one published only as source, such as redcarpet, or one from git) when the target is the platform it runs on, against the runtime's own Ruby: Xcode's command line tools on macOS (for macOS 14 and later), the C compiler on Linux, RubyInstaller's MSYS2 UCRT64 tools on Windows, and cargo for a Rust extension. `bundle config build.NAME` options reach the gem's `extconf.rb`, and `notices/GEMS.txt` says each gem was compiled, with which options.
- For any other target, such a gem fails the build, naming it and saying to build on that platform or choose a precompiled version.
- nokogiri ships for `arm64-darwin` when built from source on a Mac (`force_ruby_platform: true`, with `bundle config build.nokogiri --disable-xml2-legacy`), using macOS's own iconv.
- Git gems ship, from any computer, at the commit the lockfile locks, fetched into `~/.cache/fledge/git`: each gem's own folder of the checkout, where Bundler keeps it, with its gemspec evaluated, and none of the rest of its repository; a git gem's extension compiles as above.
- A Rust extension's crates, read from its build's `Cargo.lock` with `cargo metadata`, are listed in `notices/GEMS.txt` (those compiled in, and those that ran only while it compiled), and each must be under a license that asks nothing beyond notices.
- Each release carries `fledge-runtime-VERSION-PLATFORM-dev.tar.gz`, the runtime's build-only companion of Ruby's headers and libraries, which `fledge build` downloads only to compile a gem, and never ships.
- An LGPL gem ships, as its own files that whoever receives the app may replace, when its exact source is pinned: the gem itself when it is built for every platform or from git, and for a precompiled build its source package of the same version, which the lockfile must lock (`bundle lock --add-platform ruby`); `notices/GEMS.txt` names the source and what the LGPL asks. ratatui_ruby 1.5.2 ships this way.
- ratatui_ruby's precompiled builds are reviewed: each one's Rust crates, for its operating system, are listed in `notices/GEMS.txt`.
- `Unicode-3.0`, `Unicode-DFS-2016`, and `WTFPL` are notice-only licenses.
- `notices/GEMS.txt` quotes the license texts in a gem's `LICENSES/` folder.

### Changed

- A gem's compiled file that needs a shared library neither its operating system (on Linux, what manylinux_2_39 allows), the runtime, nor the gem itself provides fails the build.
- A path gem inside the project whose gemspec has an extension fails the build, since Bundler never compiles one.
- Which lockfile platforms, and which builds of a gem, fit a target is judged as the built app's Bundler judges it, from the runtime's own platform (`arm64-darwin-23` on macOS): a lockfile platform or gem built for `arm64-darwin-23` now fits `arm64-darwin`, and one built for `arm64-darwin-24` does not.

## [0.0.1.pre.3] - 2026-10-27

### Added

- `fledge build` reads every compiled file of every native gem an app ships, and fails, naming the gem, the files, the library, and its license, when one has an LGPL or GPL library compiled in; nokogiri's builds for `arm64-darwin` and `x64-mingw-ucrt` compile in GNU libiconv, so they are refused, and its Linux builds ship.
- Compiled code in a gem Fledge has not reviewed fails the build until `fledge.yml` says what it holds, under `compiled`; sqlite3, nokogiri, ffi, pg, google-protobuf, and prism are reviewed.
- An LGPL library a gem ships as its own shared library, which another of its files loads, ships when `fledge.yml` names its file (`shared_library`) and where its source is (`source`).
- `notices/GEMS.txt` lists, under each gem, the libraries its compiled files hold, their licenses, and their files.
- `blessing` (SQLite), `PostgreSQL`, and `LicenseRef-krb5` (MIT Kerberos's NOTICE) are notice-only licenses.

### Changed

- In an app with a Gemfile, `ENV` is what `bundle exec` gives: Bundler's settings over the person's own, so `RUBYOPT` is `-r.../bundler/setup` followed by the person's `RUBYOPT`, and `BUNDLER_ORIG_*` records the person's values; `Bundler.original_env`, `with_original_env`, `unbundled_env`, and `with_unbundled_env` give the person's environment, with their `RUBYOPT`, `GEM_HOME`, and the rest. They gave an environment without the person's Ruby settings.

## [0.0.1.pre.2] - 2026-10-27

### Added

- `fledge build PATH` builds the program you already run: a file such as `exe/my_cool_app`, `bin/server`, or `main.rb`, or a folder, which means its gemspec's one executable or its `main.rb`. Its project, the nearest folder up with a `Gemfile`, `gems.rb`, gemspec, or `fledge.yml`, ships as `app/`, without `.git`, `.bundle`, `vendor/bundle`, `vendor/cache`, or the output folder.
- An app with a Gemfile ships the gems its `Gemfile.lock` locks for each target, without the `development` and `test` groups, installed beside Ruby's own gems, and runs with Bundler set up as `bundle exec` would, with Warbler's settings for a packed app (frozen, system gems, no auto-install, no version switch) in `app/.bundle/config`. The project's gemspecs ship evaluated.
- Gems download from the lockfile's gem server into `~/.cache/fledge/gems` (or `$XDG_CACHE_HOME/fledge/gems`), checked against the lockfile's `CHECKSUMS`; `vendor/cache` and RubyGems' own caches are looked in first.
- `fledge build` refuses, naming each gem and what to do: a target the lockfile does not lock, a gem without a checksum, a gem from git or from a folder outside the project, a gem with an extension that would have to be compiled, a gem that does not support Ruby 4.0.9, a Gemfile `ruby` other than 4.0.9, a lockfile the Gemfile has moved past, and a gem whose license asks more than keeping its notices (or declares none).
- An optional `fledge.yml` at the project's root: `name`, the app's name, and `licenses`, a gem's license where its gemspec declares none or the wrong one.
- `notices/GEMS.txt` in an app with gems: each gem, its license, where it came from, and the text of its license files; `fledge build` warns when a gem ships none.
- A built app's `fledge.cfg`, beside its program, names the program and Gemfile it runs; the program exits 66 when either it or its program is missing, and 70 when it is damaged or Bundler cannot set up the gems.

### Changed

- NAME, the built folder's and the program's name, is the gemspec's name, or else the project folder's, camelized (`my_cool_app` is `MyCoolApp`, `hello` is `Hello`), unless `fledge.yml` names it; it was the app folder's name as it was.
- A build failure may print several `fledge build:` lines, one for each problem.

## [0.0.1.pre.1] - 2026-10-27

### Added

- `fledge --help` (`-h`, `-?`) and `fledge --version` (`-v`), on standard output with exit status 0. A bare `fledge` and every usage error print a short usage and `Try 'fledge --help'.` on standard error and exit 2; a failed build exits 1.
- `fledge build [-t PLATFORM]... [-o DIR] [PATH]`: copies the app in PATH into a runtime for each target and writes `DIR/NAME-PLATFORM/` and `DIR/NAME-PLATFORM.tar.gz` (`.zip` for Windows), printing each archive's path. Targets: `arm64-darwin`, `x86_64-linux`, `aarch64-linux`, `x64-mingw-ucrt`.
- Windows (`x64-mingw-ucrt`) apps: `NAME.exe` beside RubyInstaller 4.0.9-1's Ruby in `ruby\`, in a `.zip`, built from any platform.
- Runtimes download from the GitHub Release of Fledge's version into `~/.cache/fledge/runtimes` (or `$XDG_CACHE_HOME/fledge/runtimes`), checked against the release's `SHA256SUMS`; `FLEDGE_RUNTIME_DIR` names a folder of runtimes to use instead.
- Runtimes carry Ruby 4.0.9 from rv-ruby release `20261023` with its standard library, default gems, and bundled gems (not rv-ruby's extra bootsnap and msgpack), Ruby's own `bin/ruby` and the gems' executables, libxcrypt 4.5.2 as a shared library on Linux, libffi 3.5.2 in fiddle on Linux, and, in `notices/`, `NOTICES.txt` (every component, its license, how it ships, its source, and every license text) and `sbom.spdx.json` (an SPDX 2.3 SBOM), both from the license audit every runtime passes before it is archived. Linux apps need glibc 2.39 or newer.
- The Windows runtime carries Ruby 4.0.9 from RubyInstaller 4.0.9-1 (checked against its PGP signature) with its standard library, default gems, bundled gems, `ruby.exe`, `rubyw.exe`, the gems' wrappers, and DLLs (OpenSSL 3.6.5, libyaml 0.2.5, zlib 1.3.2, GMP 6.3.0, libffi, winpthreads), and Fledge's RubyGems defaults in place of RubyInstaller's.
- A built app runs `app/main.rb` as `ruby main.rb` would: no `-I` for the app's folder (load its files with `require_relative`) and no `--yjit`. The person's `RUBY*`, `GEM_*`, `GEMRC`, `BUNDLE_*`, and `BUNDLER_*` variables are hidden from Ruby's boot and the app's gems are the runtime's, but they are back in `ENV` before `main.rb` runs, so child processes see them.
- A built app's program exits 66 when its `app/main.rb` is missing and 70 when the rest of the runtime is broken, with `NAME: message` on standard error.
- Runtimes leave out nkf's JRuby-only Java sources (`ext/java`), from the gem's folder and from its cached `nkf-0.2.0.gem`.
- Each release attaches, per platform, the runtime, its SBOM (`.spdx.json`) and NOTICES (`-NOTICES.txt`), and for Linux and Windows the source of their LGPL libraries, libxcrypt and GNU MP (`-lgpl-sources.tar.gz`), with `SHA256SUMS` over all of them.
- `doc/licensing.md`: what ships in an app on each platform, under which license, and what each license asks of app developers.

[Unreleased]: https://github.com/setdef/Fledge/compare/v0.0.1.pre.9...HEAD
[0.0.1.pre.9]: https://github.com/setdef/Fledge/releases/tag/v0.0.1.pre.9
[0.0.1.pre.8]: https://github.com/setdef/Fledge/releases/tag/v0.0.1.pre.8
[0.0.1.pre.7]: https://github.com/setdef/Fledge/releases/tag/v0.0.1.pre.7
[0.0.1.pre.6]: https://github.com/setdef/Fledge/releases/tag/v0.0.1.pre.6
[0.0.1.pre.5]: https://github.com/setdef/Fledge/releases/tag/v0.0.1.pre.5
[0.0.1.pre.4]: https://github.com/setdef/Fledge/releases/tag/v0.0.1.pre.4
[0.0.1.pre.3]: https://github.com/setdef/Fledge/releases/tag/v0.0.1.pre.3
[0.0.1.pre.2]: https://github.com/setdef/Fledge/releases/tag/v0.0.1.pre.2
[0.0.1.pre.1]: https://github.com/setdef/Fledge/releases/tag/v0.0.1.pre.1
