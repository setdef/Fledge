<!--
  SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
  SPDX-License-Identifier: CC-BY-SA-4.0
-->
# Fledge

[![CI](https://github.com/setdef/Fledge/actions/workflows/ci.yml/badge.svg?branch=trunk)](https://github.com/setdef/Fledge/actions/workflows/ci.yml) [![Release](https://img.shields.io/github/v/release/setdef/Fledge)](https://github.com/setdef/Fledge/releases) [![License](https://img.shields.io/badge/license-AGPL--3.0--or--later-a2c93e)](https://spdx.org/licenses/AGPL-3.0-or-later.html)

## Introduction

**Fledge** packages software written in Ruby so that people can run it without installing Ruby. Point it at the program you already run: a `main.rb`, a `bin/server`, or a gem's `exe/my_app`. Fledge copies the program, its project, and the gems your `Gemfile.lock` locks into a copy of Ruby that runs from any folder, and writes an app for the platform you build on.

Your users download one file, unpack it wherever they like, and run it. They install nothing, and they never need to know what Ruby is. If your app has windows, Fledge also builds an installer for each system.

## Why Fledge?

Fledge writes these for you, for each platform you build on:

| App kind | macOS | Windows | Linux |
| --- | --- | --- | --- |
| `console` (the default) | `.tar.gz` holding the program | `.zip` holding `NAME.exe` | `.tar.gz` holding the program |
| `windowed` | `NAME.app` and a `.dmg` | `NAME.exe`, which opens no console, and a `-setup.exe` that installs without an administrator | a folder with a desktop entry and icons, an AppImage, and a `.deb` if you ask for one |

Building a program that prints one line gives you a 19 MB archive (60 MB unpacked) on `arm64-darwin`. Your users run the app with no Ruby on their `PATH`. If they have a Ruby of their own, it makes no difference: the launcher clears `RUBYOPT`, `RUBYLIB`, `GEM_HOME`, and the other variables a Ruby reads before Ruby starts. Ruby's own answers stay true inside the app: `$0`, `__dir__`, `RbConfig.ruby`, and `Gem.dir` name where your program, its Ruby, and its gems are, and on macOS and Linux `exec RbConfig.ruby, $0, *ARGV` restarts the app as it first started. On Windows, start the app's own `NAME.exe` again instead.

### Compared with other ways to ship a Ruby program

- **A gem.** Your users install Ruby first, at a version your gems accept.
- **A [Docker](https://www.docker.com/) image.** Your users install Docker, and your program runs inside Linux.
- **Single-file packagers**, such as [Tebako](https://github.com/tamatebako/tebako) and [Ocran](https://github.com/largo/ocran). They unpack the program to a temporary folder, or mount a virtual file system, every time it starts. A Fledge app is a folder that runs where it sits, with Ruby's usual layout inside.

Fledge follows designs that other languages have settled: [LÖVE](https://love2d.org/)'s fused games (a folder joined to a runtime), [PyInstaller](https://pyinstaller.org/) and [Briefcase](https://briefcase.readthedocs.io/) (console and windowed apps), [python-build-standalone](https://github.com/astral-sh/python-build-standalone) (prebuilt interpreters that move), and [Tauri](https://tauri.app/)'s bundler (installers).

## Compatibility

| Platform | Your users run it on |
| --- | --- |
| `arm64-darwin` | macOS 14 or newer, on Apple silicon |
| `x86_64-linux`, `aarch64-linux` | Linux with glibc 2.39 or newer (Ubuntu 24.04, Debian 13) |
| `x86_64-linux-musl`, `aarch64-linux-musl` | Linux with musl, such as Alpine |
| `x64-mingw-ucrt` | Windows 10 and 11 on x64 |
| `aarch64-mingw-ucrt` | Windows 11 on ARM64 |

On every push, Fledge's CI builds each platform's apps on a computer of that platform, copies them to a clean one that has no Ruby, and runs them there ([`ci.yml`](.github/workflows/ci.yml), [`deliver.sh`](.github/scripts/deliver.sh), [`deliver.ps1`](.github/scripts/deliver.ps1)). After each release, [`installed.yml`](.github/workflows/installed.yml) installs Fledge from the new tag the way you would, and builds and runs the examples.

Before you start:

- Build on a computer of each platform you ship to: a Mac for macOS, Windows for Windows, Linux for Linux. A CI runner of each works.
- There is no runtime for Intel Macs or 32-bit systems.
- Run Fledge with Ruby 4.0.1 or newer, and Bundler.

## Installation

Add Fledge to your `Gemfile`, in the `development` group so that `fledge build` leaves it out of your app:

<!-- SPDX-SnippetBegin -->
<!--
  SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
  SPDX-License-Identifier: MIT-0
-->
```ruby
gem "fledge", git: "https://github.com/setdef/Fledge", tag: "v0.2.1", group: :development
```
<!-- SPDX-SnippetEnd -->

You install Fledge from a git tag. The [releases page](https://github.com/setdef/Fledge/releases) lists the latest.

## Usage

Run `fledge build` in your project's folder. Here, the project is a folder named `greeter` whose `main.rb` prints `Hello, Ruby!`:

<!-- SPDX-SnippetBegin -->
<!--
  SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
  SPDX-License-Identifier: MIT-0
-->
```console
$ bundle install
$ bundle exec fledge build
Downloading fledge-runtime-0.2.1-arm64-darwin.tar.gz from https://github.com/setdef/Fledge/releases/download/v0.2.1
dist/Greeter-arm64-darwin.tar.gz
$ tar -xzf dist/Greeter-arm64-darwin.tar.gz -C /tmp
$ /tmp/Greeter-arm64-darwin/Greeter
Hello, Ruby!
```
<!-- SPDX-SnippetEnd -->

The first time you build, Fledge downloads the runtime for your platform from the release, and checks it against a SHA-256 that it carries. The app takes its name from the folder, camelized. Send the `.tar.gz` (a `.zip` on Windows) to anyone on that platform.

With no argument, `fledge build` builds the folder you are in: the one executable its gemspec names, or else its `main.rb`; if `fledge.yml` lists `programs`, every one of them. Pass a path to build another program, and `--out DIR` to write somewhere other than `dist`. `bundle exec fledge --help` prints the whole manual.

### Windowed apps and installers

Put a `fledge.yml` beside your `Gemfile`:

<!-- SPDX-SnippetBegin -->
<!--
  SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
  SPDX-License-Identifier: MIT-0
-->
```yaml
name: My Cool App
kind: windowed
identifier: com.example.MyCoolApp   # reverse-DNS; macOS and Windows know the app by it
version: "1.0.0"
icon: icons/app                     # icons/app.icns, icons/app.ico, icons/app-16.png to -512.png
installers: [dmg, nsis, appimage, deb]
```
<!-- SPDX-SnippetEnd -->

macOS, Windows, and Linux show your app's name, icon, and version in their usual places. Set `installers` to choose which of `dmg`, `nsis`, `appimage`, and `deb` to build. The default is the first three; `deb` takes `dpkg-deb` on your computer. [`examples/windowed_app`](examples/windowed_app) is a complete example, and `--help` lists every key.

### Several programs in one app

If your app has more than one way in, such as a window, a terminal interface, and a command line that all open the same save file, list them under `programs` in `fledge.yml`. Fledge builds them into one folder that shares one Ruby runtime, one copy of your project, and one set of gems:

<!-- SPDX-SnippetBegin -->
<!--
  SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
  SPDX-License-Identifier: MIT-0
-->
```yaml
name: Shared Save
programs:
  - path: window.rb
    name: Shared Save
    kind: windowed
    identifier: com.example.SharedSave
  - path: bin/shared-save
    kind: console
```
<!-- SPDX-SnippetEnd -->

At most one program is windowed. It gets the installers, and on macOS the console programs live inside its `.app` bundle. `fledge build PATH` with one of the listed files builds that program alone. [`examples/programs`](examples/programs) is a complete example.

### Signing

An app is unsigned unless you sign it. Without a signature, macOS's [Gatekeeper](https://support.apple.com/guide/security/gatekeeper-and-runtime-protection-sec5599b66df/web) and Windows' [SmartScreen](https://learn.microsoft.com/windows/security/operating-system-security/virus-and-threat-protection/microsoft-defender-smartscreen/) warn the people who download your app.

To sign with your own identity, pass `--sign`. On macOS, give a code signing identity from your keychain, such as `"Developer ID Application: NAME (TEAM)"`. On Windows, give the SHA-1 thumbprint of a code signing certificate in your certificate store. Fledge signs every program and library, the app bundle, and the installer.

Fledge's CI signs with a self-signed certificate. It has not yet tried a certificate from Apple or a certificate authority, so how Gatekeeper and SmartScreen treat one is unconfirmed. Fledge does not notarize; `xcrun notarytool` does that to a signed disk image.

### Gems

You choose which gems ship through your `Gemfile.lock`. The `development` and `test` groups stay out, and an optional group ships only if your Bundler `with` setting names it. Lock each platform you build on, and every gem's checksum:

<!-- SPDX-SnippetBegin -->
<!--
  SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
  SPDX-License-Identifier: MIT-0
-->
```console
$ bundle lock --add-platform arm64-darwin x86_64-linux x64-mingw-ucrt
$ bundle lock --add-checksums
```
<!-- SPDX-SnippetEnd -->

Precompiled gems ship as they are. Gems that ship as source, and gems from git, are compiled on your computer against the runtime's Ruby. Install a compiler first: Xcode's command line tools on macOS, a C compiler and `make` on Linux, or RubyInstaller's MSYS2 tools (`ridk install`) on Windows, and `cargo` for a Rust extension. If a gem would not load on another computer, the build fails and the error names the gem. Git gems, git submodules, path gems, mirrors, and credentials work as they do in Bundler; [`examples/real_gems`](examples/real_gems) uses each.

### iPhone, iPad, and Android

For a phone, Fledge does not build the finished app. `fledge build ios` and `fledge build android` write an Xcode or Gradle project that holds your program and a Ruby runtime. You build, sign, and submit that project with Xcode or Gradle, the way you would any other phone app.

- `fledge build ios` writes an Xcode project for iOS 15 and later. Run it on a Mac with Xcode and [XcodeGen](https://github.com/yonaskolb/XcodeGen).
- `fledge build android` writes a Gradle project for Android 8.0 (API 26) and later. Run it on a Mac, x86-64 Linux, or Windows; building the project takes a JDK and the Android SDK.

Lock `ruby` as a platform (`bundle lock --add-platform ruby`). A gem with a C or C++ extension compiles for the phone and links into the app, with Xcode on iOS and the [Android NDK](https://developer.android.com/ndk) on Android (set `ANDROID_NDK_ROOT`, or install the NDK in the SDK's `ndk/` folder). The gem loads it with `require "name/name"`, not `require_relative`. A Rust extension, or one that Rake, CMake, or configure builds, fails the build and names the gem. [`examples/mobile_app`](examples/mobile_app) and [`examples/native_phone`](examples/native_phone) show both. A library the extension's `extconf.rb` links, such as SDL3, links too, and an Android app carries the shared libraries it links; [`examples/sdl_phone`](examples/sdl_phone) is a game loop on SDL3, which needs a host of SDL's own on each phone: its `fledge.yml` names a folder of those files under `ios: host:` and `android: host:`, and `fledge build` copies them over the project it writes (ADR 025).

Fledge's CI runs phone apps in the iOS Simulator on an iPhone and an iPad, and on x86-64 Android emulators. The CI has not run an app on a physical iPhone or iPad, and no app has been through App Review. For `arm64-v8a`, which most Android phones use, the CI builds the library and checks the APK but never runs it, because no free runner boots an arm64 emulator.

### Updating Fledge

Change the tag in your `Gemfile` and run `bundle update fledge`. Each version pins the SHA-256 of every runtime it downloads, and today the runtimes carry Ruby 4.0.9. Fledge is 0.x: a minor version can break your build. Read the [CHANGELOG](CHANGELOG.md) before you update.

## Documentation

| Resource | Description |
| --- | --- |
| `bundle exec fledge --help` | The manual: every option, every `fledge.yml` key, every file Fledge writes, and the exit statuses |
| [`examples/`](examples) | Apps that CI builds and runs. Start with [`hello`](examples/hello), [`my_cool_app`](examples/my_cool_app) (a gem), [`windowed_app`](examples/windowed_app), [`programs`](examples/programs) (several programs in one app), and [`native_app`](examples/native_app) (gems compiled from source) |
| [What ships in your app](doc/licensing.md) | Every component Fledge puts in an app, on each platform, and what its license asks of you |
| [CHANGELOG](CHANGELOG.md) | What changed in each release |
| [Releases](https://github.com/setdef/Fledge/releases) | Each release's runtimes, with their notices and software bills of materials |

## Reporting problems

Open an [issue](https://github.com/setdef/Fledge/issues). Say which platform you built on, which platform you ran on, and what `bundle exec fledge --version` prints.

## Contributing

See [CONTRIBUTING.md](./CONTRIBUTING.md).

## Copyright & License

Fledge is copyright 2026, Kerrick Long, under the [AGPL-3.0-or-later](./LICENSES/AGPL-3.0-or-later.txt). Documentation is [CC-BY-SA-4.0](./LICENSES/CC-BY-SA-4.0.txt). Code snippets and examples are [MIT-0](./LICENSES/MIT-0.txt): copy and use them without attribution. See each file's SPDX comment for specifics.

**Your app stays yours.** You can keep your app's source code private. Two files in each app are Fledge's: the launcher your users run, and one RubyGems defaults file. They are under the AGPL, so when you give the app to people, you give them the source of those two files too. Each app's `notices/NOTICES.txt` says where it is: Fledge's source, at the tag that built the app. The rest of the runtime is under licenses that ask only that you keep their notices, and every app carries them. Your gems have licenses of their own, and you read them; Fledge ships every gem you lock, whatever its license. [What ships in your app](doc/licensing.md) lists every component, and is not legal advice. Setdef may also offer Fledge under a commercial license, for people who prefer not to follow the AGPL for those two files.

Some parts of this program are copied from other sources under appropriate reuse licenses, and the copyright belongs to their respective owners. See the [REUSE Specification](https://reuse.software/spec-3.3/) for details.

This program is **requested**. The maintainer uses three words for how code comes to exist. *Written*: typed by hand, with nothing generated. *Wrought*: an AI agent generated it while the maintainer iterated with it, and the maintainer reviewed every change before committing it. *Requested*: an agent built it with little or no review, in the style of a "dark factory." All of Fledge is requested, and the CI gates and the Delivery jobs, which run each built app on a clean computer, stand in for review. Each commit has a `Provenance:` trailer and a footer that names the model. Under [declare-ai.org](https://declare-ai.org/1.0.0/creative.html), this is creative assistance, requested.
