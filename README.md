<!--
  SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
  SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Fledge

Fledge ships a Ruby app to people who have never installed Ruby. Point it at the program you already run, such as `main.rb`, `bin/server`, or a gem's `exe/my_app`. Fledge copies the program, its project, and the gems its `Gemfile.lock` locks into a Ruby built to be moved, and writes a folder that runs where it lands. A windowed app also gets its platform's installer.

Fledge is pre-1.0. Version 0.1.0 is the latest release.

## What the people who run your app get

They download one file and run the program in it. They install no Ruby, and a Ruby they happen to have changes nothing: the launcher clears `RUBYOPT`, `RUBYLIB`, `GEM_HOME`, `BUNDLE_GEMFILE`, and the rest before Ruby starts.

| Kind | macOS | Windows | Linux |
| --- | --- | --- | --- |
| `console` (default) | `NAME-arm64-darwin.tar.gz` with the program `NAME` | `NAME-x64-mingw-ucrt.zip` with `NAME.exe` | `NAME-x86_64-linux.tar.gz` with `NAME` |
| `windowed` | `NAME.app`, signed ad hoc, and a `.dmg` to drag it from | `NAME.exe`, which opens no console, and an NSIS `-setup.exe` that installs without an administrator | a folder with a desktop entry and icons, an `.AppImage`, and, on glibc Linux, a `.deb` when `fledge.yml` lists it |

Every app carries the name, version, publisher, and icon you give it, where each system shows them. Its `notices/` folder holds `NOTICES.txt` and an SPDX software bill of materials for everything Fledge put in it.

A lone `main.rb` builds to an archive of 19 MB, 60 MB unpacked, for `arm64-darwin`.

## Other ways to ship Ruby, and where Fledge differs

- **A gem** asks the person to install Ruby first, at a version your gems accept.
- **A Docker image** asks the person to install Docker, and runs your program in Linux.
- **Single-file packers**, such as OCRAN and Tebako, unpack the app to a temporary folder or mount a virtual file system each time it starts. A Fledge app is a folder that runs in place, with Ruby's usual layout inside it. CI checks it with each system's tools: `codesign --verify` and Finder's `open` on macOS, Explorer and the Start menu on Windows, and `desktop-file-validate` on Linux.

Fledge follows prior art from other languages: LÖVE's fused games (a folder joined to a runtime), PyInstaller and Briefcase (console and windowed apps), python-build-standalone (prebuilt, relocatable interpreters), and the Tauri bundler (installers). [ADR 001](doc/contributors/adr/001.md) compares them.

## What CI checks on every push

[CI](.github/workflows/ci.yml) builds each platform's apps on a runner of that platform, then copies them to a fresh runner and runs them there. The Delivery jobs unpack each app under a path with spaces and non-ASCII characters, run it with no Ruby on `PATH`, and run it again with `RUBYOPT`, `RUBYLIB`, and `GEM_HOME` set to values that would break a Ruby that read them ([`deliver.sh`](.github/scripts/deliver.sh), [`deliver.ps1`](.github/scripts/deliver.ps1)). On Debian and Alpine, the apps run in containers with no Ruby installed at all. The Test jobs on each platform compare what a built app's Ruby sees with what `ruby main.rb` and `bundle exec` see on the same Ruby ([`tasks/parity.rb`](tasks/parity.rb)).

After each release, [`installed.yml`](.github/workflows/installed.yml) installs Fledge from the new git tag with Bundler, as you would, builds the examples with runtimes downloaded from the release, and delivers them the same way.

| Platform | Runs on | Delivered in CI on |
| --- | --- | --- |
| `arm64-darwin` | macOS 14 or newer, Apple silicon | `macos-15` |
| `x86_64-linux` | Linux with glibc 2.39 or newer | `ubuntu-24.04`, `debian:trixie-slim` |
| `aarch64-linux` | Linux with glibc 2.39 or newer | `ubuntu-24.04-arm`, `debian:trixie-slim` |
| `x86_64-linux-musl` | musl Linux, such as Alpine | `alpine:3.24` |
| `aarch64-linux-musl` | musl Linux, such as Alpine | `alpine:3.24` |
| `x64-mingw-ucrt` | Windows on x64 | `windows-latest` |
| `aarch64-mingw-ucrt` | Windows 11 on ARM64 | `windows-11-arm` |

## Where Fledge does not fit yet

- Each platform's app is built on a computer of that platform. A Mac builds the macOS app and a Windows computer builds the Windows app. A CI runner of each works ([ADR 010](doc/contributors/adr/010.md)).
- Fledge has no runtime for Intel Macs or 32-bit systems. On those, `fledge build` stops with `Fledge has no runtime for this computer's platform`.
- Gems compiled from source are proven on `arm64-darwin`, both glibc Linux platforms, and `x64-mingw-ucrt`. CI compiles none on musl Linux, and none on Windows on ARM64, where sqlite3 publishes no build and does not compile.
- On iPhone, iPad, and Android, an app's gems are pure Ruby for now, and what it prints goes to the system log.
- Fledge does not notarize macOS apps.

## Get started

Building takes Ruby 4.0.1 or newer and Bundler. Fledge installs from a git tag. Make a folder named `greeter` and give it this `Gemfile`, with Fledge in the development group, which `fledge build` leaves out of the app:

<!-- SPDX-SnippetBegin -->
<!--
  SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
  SPDX-License-Identifier: MIT-0
-->
```ruby
source "https://rubygems.org"

gem "fledge", git: "https://github.com/setdef/Fledge", tag: "v0.1.0", group: :development
```
<!-- SPDX-SnippetEnd -->

Write the program beside it:

<!-- SPDX-SnippetBegin -->
<!--
  SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
  SPDX-License-Identifier: MIT-0
-->
```ruby
# main.rb
puts "Hello, #{ARGV.first || "world"}!"
```
<!-- SPDX-SnippetEnd -->

Install Fledge, build, and run the result from somewhere else. On an Apple-silicon Mac:

<!-- SPDX-SnippetBegin -->
<!--
  SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
  SPDX-License-Identifier: MIT-0
-->
```console
$ bundle install
$ bundle exec fledge build
Downloading fledge-runtime-0.1.0-arm64-darwin.tar.gz from https://github.com/setdef/Fledge/releases/download/v0.1.0
dist/Greeter-arm64-darwin.tar.gz
$ tar -xzf dist/Greeter-arm64-darwin.tar.gz -C /tmp
$ /tmp/Greeter-arm64-darwin/Greeter Ruby
Hello, Ruby!
```
<!-- SPDX-SnippetEnd -->

The first build downloads this platform's runtime from the release and checks it against the SHA-256 that your version of Fledge pins. The app takes its name from the folder, camelized: `greeter` becomes `Greeter`. Send the `.tar.gz` (a `.zip` on Windows) to anyone with that platform.

`bundle exec fledge --help` prints the whole manual: every option, every `fledge.yml` key and its default, every file Fledge writes, and the exit statuses.

## From the first build to a release

1. **First build.** `fledge build` with no argument builds the current folder: the one executable its gemspec names, or else its `main.rb`. Pass a path to build a different program, and `--out DIR` to write somewhere other than `dist`. [ADR 005](doc/contributors/adr/005.md) says how Fledge finds the project and runs the program as `bundle exec` would.
2. **Other platforms.** Run the same command on a computer of each platform. The Build jobs in [`ci.yml`](.github/workflows/ci.yml) are one way to do it on GitHub Actions.
3. **Windowed apps and installers.** Add a `fledge.yml` beside your `Gemfile`. Give a windowed app an `identifier`, the reverse-DNS name macOS and Windows know it by. `installers` picks which of `dmg`, `nsis`, `appimage`, and `deb` to build; the default is the first three. See [`examples/windowed_app`](examples/windowed_app), [ADR 008](doc/contributors/adr/008.md), and [ADR 009](doc/contributors/adr/009.md).

   <!-- SPDX-SnippetBegin -->
   <!--
     SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
     SPDX-License-Identifier: MIT-0
   -->
   ```yaml
   name: My Cool App
   kind: windowed
   identifier: com.example.MyCoolApp
   version: "1.0.0"
   icon: icons/app # icons/app.icns, icons/app.ico, icons/app-16.png to -512.png
   ```
   <!-- SPDX-SnippetEnd -->

4. **Signing.** An app is unsigned unless you pass `--sign IDENTITY`: a keychain identity on macOS, such as `"Developer ID Application: NAME (TEAM)"`, or a certificate's SHA-1 thumbprint on Windows. Fledge signs every program and library, the bundle, and the installer. Gatekeeper and SmartScreen warn the people who download an unsigned app; how they judge a signed one is not yet proven (below). Fledge does not notarize. [ADR 016](doc/contributors/adr/016.md) has the details.
5. **Gems and native extensions.** Your `Gemfile.lock` lists the gems that ship, without the development and test groups. If the build asks, run `bundle lock --add-platform` for this platform and `bundle lock --add-checksums`. Precompiled platform gems ship as they are. Gems with an extension to compile are compiled against the runtime's Ruby, with your compiler: Xcode's command line tools on macOS, a C compiler and `make` on Linux, RubyInstaller's MSYS2 tools (`ridk install`) on Windows, and `cargo` for Rust. A gem that would not load on another computer stops the build with a message that names it. [ADR 006](doc/contributors/adr/006.md) and [ADR 020](doc/contributors/adr/020.md) cover git gems, path gems, mirrors, and credentials.
6. **Phones.** `fledge build ios` (on a Mac, with Xcode and XcodeGen) writes an Xcode project for iPhone and iPad. `fledge build android` (on a Mac, x86-64 Linux, or Windows) writes a Gradle project. You build, sign, and submit them with those tools. Gems are pure Ruby, and the lockfile locks `ruby` (`bundle lock --add-platform ruby`). See [`examples/mobile_app`](examples/mobile_app) and [ADR 012](doc/contributors/adr/012.md).
7. **Updating Fledge.** Change the tag in your `Gemfile` and run `bundle update fledge`. Each version downloads its runtimes and checks them against the SHA-256s it pins ([ADR 014](doc/contributors/adr/014.md)). The runtimes carry Ruby 4.0.9 today, and the CHANGELOG records each change to the pinned Ruby. Read the [CHANGELOG](CHANGELOG.md) first: before 1.0, a minor version can break your build.

## What is proven, and what is not yet

Proven in CI on every push:

- Console and windowed apps on all seven desktop platforms.
- Each installer installed on a fresh runner, and its app run.
- Gems compiled from source, with C and Rust extensions and from git, on `arm64-darwin`, both glibc Linux platforms, and `x64-mingw-ucrt`.
- iOS projects built and run in the iOS Simulator on an iPhone and an iPad.
- Android projects built with Gradle on Linux, macOS, and Windows, and run on x86-64 emulators with 4 KB and 16 KB pages.
- Apps signed with a test certificate, and verified by `codesign` and `signtool`.

Not yet proven:

- An app on a physical iPhone or iPad, and App Review.
- Signing with a certificate from Apple or a certificate authority, the verdicts Gatekeeper and SmartScreen give it, and notarization.
- Android's arm64-v8a library running on a device or emulator. CI builds and checks it, but no free runner boots an arm64-v8a emulator.

These wait on accounts and hardware that cost money. [Plan 003](doc/contributors/plan/003.md) lists what remains before 1.0.

## Cost and licensing

Fledge costs nothing to use. It is licensed AGPL-3.0-or-later, and setdef may also offer it under a commercial license; none is offered yet.

What this means for an app you build:

- Nothing Fledge puts in your app asks for your app's source code.
- Two files in a desktop app are Fledge's, under the AGPL: the launcher, which is the program your users run, and one RubyGems defaults file. On a phone, Fledge's embedding API and the host app template take their place. If you give the app to others, the AGPL asks you to convey the source of those files. The app's `NOTICES.txt` names it: Fledge's source at the tag that built the app.
- The rest of the runtime is under permissive licenses that ask you to keep their notices, which every app carries in `notices/`. Two LGPL libraries ship as separate shared libraries a person can replace: libxcrypt on glibc Linux and GNU MP on Windows. An AppImage's runtime links libfuse (LGPL), and a Windows setup program carries NSIS's LZMA module (CPL-1.0). Each release publishes their source beside the runtimes that carry them.
- Every runtime build runs a license audit against [`runtime/licenses.yml`](runtime/licenses.yml) and refuses to archive a runtime with anything it does not account for ([ADR 004](doc/contributors/adr/004.md)).

[`doc/licensing.md`](doc/licensing.md) lists every component on each platform and what its license asks of you. The licenses of your app's gems are your business: Fledge ships every gem you lock, whatever its license ([ADR 007](doc/contributors/adr/007.md)).

## Depending on Fledge

- Releases are git tags and [GitHub Releases](https://github.com/setdef/Fledge/releases). Each release carries every runtime with its NOTICES, SBOM, and LGPL sources, and a `SHA256SUMS` that matches the pins in the tagged gem, which `installed.yml` checks.
- Fledge downloads gems from your lockfile's server and checks each against the lockfile's checksum. A git gem ships at the commit the lockfile locks.
- Before 1.0, breaking changes come in minor versions, and the [CHANGELOG](CHANGELOG.md) records each one.
- AI agents wrote Fledge's code, tests, and documents with little line-by-line human review. The CI gates and the Delivery jobs are the review. [AGENTS.md](AGENTS.md) describes how the work is done and checked.

## Documentation

- `bundle exec fledge --help`: the manual, including the `fledge.yml` reference.
- [`doc/licensing.md`](doc/licensing.md): what ships in an app on each platform, and what its licenses ask of you.
- [`examples/`](examples): apps CI builds and delivers. Start with [`hello`](examples/hello), [`my_cool_app`](examples/my_cool_app) (a gem), [`windowed_app`](examples/windowed_app), and [`native_app`](examples/native_app) (gems compiled from source).
- [`doc/contributors/adr/`](doc/contributors/adr): the decisions behind each behavior. For app developers, start with [ADR 005](doc/contributors/adr/005.md) (which program ships, with which gems), [ADR 008](doc/contributors/adr/008.md) (windowed apps and identity), [ADR 010](doc/contributors/adr/010.md) (building on each platform), [ADR 012](doc/contributors/adr/012.md) (phones), and [ADR 016](doc/contributors/adr/016.md) (signing).
- [CHANGELOG.md](CHANGELOG.md): what changed in each release.

No guides exist yet. For what is coming, read [Plan 003](doc/contributors/plan/003.md) and the [handoff](doc/contributors/handoff.md), which says where the work stands.

## Contributing

Agents and people working on Fledge start with [AGENTS.md](AGENTS.md), then [`doc/contributors/`](doc/contributors): the handoff, the plans, the ADRs, and the [documentation style guide](doc/contributors/documentation_style.md). `bundle exec rake` runs the full gate. Issues are turned off on the GitHub repository for now.
