<!--
  SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
  SPDX-License-Identifier: CC-BY-SA-4.0
-->
# Fledge

[![CI](https://github.com/setdef/Fledge/actions/workflows/ci.yml/badge.svg?branch=trunk)](https://github.com/setdef/Fledge/actions/workflows/ci.yml) [![Release](https://img.shields.io/github/v/release/setdef/Fledge)](https://github.com/setdef/Fledge/releases) [![License](https://img.shields.io/badge/dynamic/regex?url=https%3A%2F%2Fraw.githubusercontent.com%2Fsetdef%2FFledge%2Ftrunk%2Ffledge.gemspec&search=spec%5C.license%20%3D%20%22(.*)%22&replace=%241&label=License&color=a2c93e)](https://spdx.org/licenses/AGPL-3.0-or-later.html) [![Ruby](https://img.shields.io/badge/dynamic/regex?url=https%3A%2F%2Fraw.githubusercontent.com%2Fsetdef%2FFledge%2Ftrunk%2Fruntime%2Fsources.yml&search=ruby%3A%5Cn%20%20version%3A%20(%5B0-9.%5D%2B)&replace=%241&label=Ruby&logo=ruby&color=a2c93e)](#compatibility) [![Platforms](https://img.shields.io/badge/platforms-macOS%20%7C%20Windows%20%7C%20Linux%20%7C%20iOS%20%7C%20Android-a2c93e)](#compatibility) [![Certified Shovelware](https://justin.searls.co/img/shovelware.svg)](https://justin.searls.co/shovelware/)

## Introduction

**Fledge** packages software written in Ruby so that people can run it without installing Ruby. Point it at the program you already run: a `main.rb`, a `bin/server`, or a gem's `exe/my_app`. Fledge copies the program, its project, and the gems your `Gemfile.lock` locks into a copy of Ruby that runs from any folder, and writes an app for the platform you build on.

Your users download one file, unpack it wherever they like, and run it. They install nothing, and they never need to know what Ruby is. If your app has windows, Fledge also builds an installer for each system.

## Why Fledge?

Fledge writes these for you, for each platform you build on:

| App kind | macOS | Windows | Linux |
| --- | --- | --- | --- |
| `console` (the default) | `.tar.gz` holding the program | `.zip` holding `NAME.exe` | `.tar.gz` holding the program |
| `windowed` | `NAME.app` and a `.dmg` | `NAME.exe`, which opens no console, and a `-setup.exe` that installs without an administrator | a folder with a desktop entry and icons, an AppImage, and a `.deb` if you ask for one |

A program that prints one line builds to a 20 MB archive (62 MB unpacked) on `arm64-darwin`. Your users run it with no Ruby on their `PATH`, and a Ruby they installed makes no difference: the launcher hides `RUBYOPT`, `RUBYLIB`, `GEM_HOME`, and the other variables a Ruby reads from the app's boot.

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

Your app gets the Ruby you run Fledge with. Fledge has a runtime for each Ruby it supports, Ruby 4.0 today, at the patch level the Ruby badge at the top shows, and on a Ruby it has no runtime for, `fledge build` stops and says so. Name your Ruby in a `.ruby-version` file, which version managers and CI's `setup-ruby` read, so that every computer that builds your app builds it with the same Ruby. A Gemfile that says `ruby file: ".ruby-version"` makes Bundler hold every computer to it as well.

Before you start:

- Build on a computer of each platform you ship to: a Mac for macOS, Windows for Windows, Linux for Linux. A CI runner of each works.
- There is no runtime for Intel Macs or 32-bit systems.
- Run Fledge with Bundler, on Ruby 4.0.1 or newer.

### How a Fledge app differs from running `ruby main.rb`

An app runs your code as `ruby main.rb` does, with the same requires, globals, `ENV`, and standard library. Fledge's CI runs a built app and `ruby main.rb` side by side on every platform and fails on any difference that [`tasks/parity.rb`](tasks/parity.rb) does not list with a reason. The listed differences that your code can see:

- **Your program's path.** `$0`, `__FILE__`, and `$PROGRAM_NAME` are the absolute path of the program inside the app, where `ruby main.rb` gives the path as typed. Your users can start the app from any folder, so a relative path would not hold. Ruby's other answers stay true: `__dir__`, `RbConfig.ruby`, and `Gem.dir` name where your program, its Ruby, and its gems are.
- **Your users' Ruby settings.** `RUBYOPT`, `RUBYLIB`, `GEM_HOME`, and the like do not change how the app boots, so a Ruby your users installed cannot break it. They still appear in `ENV` and reach every program your app starts. `$VERBOSE` is the visible effect: `RUBYOPT=-W0` sets it to `nil` under `ruby main.rb` and not in the app.
- **Your gems.** The app's gems are the runtime's, so `Gem.dir` and `Gem.path` name the runtime's gem folder and never your users' `GEM_HOME` or `~/.gem`. The `development` and `test` groups are left out. `.bundle/config` marks the bundle frozen, so Bundler never writes `Gemfile.lock`, even in a read-only folder, and Fledge's RubyGems defaults file loads at start. A bundled gem your lockfile does not lock, such as `irb`, still activates when Ruby asks for it, as under `bundle exec`. So on macOS and Linux, `binding.irb` works in an app with a Gemfile. On Windows it fails in the app and under `bundle exec` alike, because `irb` there needs `fiddle`, which a bundle that does not lock it leaves out.
- **The locale.** On macOS and Linux, when no locale variable is set, or `LANG` is `C` or `POSIX`, as a double-click launch gives, the launcher and the Ruby that `RbConfig.ruby` names use UTF-8, where `ruby` would stay in C. `Encoding.default_external`, `Encoding.find("locale")`, and `Encoding.find("filesystem")` are then UTF-8, not US-ASCII. Without it, a user whose home folder has a non-ASCII name would see Ruby and Bundler fail on the path. An `LC_ALL` or `LC_CTYPE` your user sets, `C` included, is used as `ruby` uses it, and nothing is added to `ENV`. To see it, print `Encoding.default_external` from your program and run the app with `env -i` and again with `env -i LC_ALL=C`. If this ever surprises you, open an issue.
- **Restarts.** On macOS and Linux, `exec RbConfig.ruby, $0, *ARGV` restarts the app as it first started, with the same setup. On Windows, start the app's `NAME.exe` again.
- **Headers.** The runtime carries Ruby's C headers, so `require "mkmf"` and `find_executable` work. It leaves out the static and import libraries, so an app cannot compile an extension. On a phone, `mkmf` cannot load.
- **What a standard Ruby installs and the runtime does not.** On macOS and Linux, the runtime has no `bootsnap` or `msgpack`, which the Ruby builds it starts from add. On Windows, RubyInstaller's own files do not load at start.

## Installation

Add Fledge to your `Gemfile`, in the `development` group so that `fledge build` leaves it out of your app:

<!-- SPDX-SnippetBegin -->
<!--
  SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
  SPDX-License-Identifier: MIT-0
-->
```ruby
gem "fledge", git: "https://github.com/setdef/Fledge", tag: "v0.4.0", group: :development
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
Downloading fledge-runtime-0.4.0-arm64-darwin.tar.gz from https://github.com/setdef/Fledge/releases/download/v0.4.0
dist/Greeter-arm64-darwin.tar.gz
$ tar -xzf dist/Greeter-arm64-darwin.tar.gz -C /tmp
$ /tmp/Greeter-arm64-darwin/Greeter
Hello, Ruby!
```
<!-- SPDX-SnippetEnd -->

The first time you build, Fledge downloads the runtime for your platform from the release, and checks it against a SHA-256 that it carries. That check makes any copy of the release as good as the release: to download from your own server, copy the release's files to it, one folder per tag, and set `FLEDGE_RUNTIME_MIRROR` to its address, so that `https://files.example.com/fledge` serves `https://files.example.com/fledge/v0.4.0/fledge-runtime-0.4.0-arm64-darwin.tar.gz`. The app takes its name from the folder, camelized. Send the `.tar.gz` (a `.zip` on Windows) to anyone on that platform. Beside it, `fledge build` writes the archive's own SHA-256, as `sha256sum` prints it, in `Greeter-arm64-darwin.tar.gz.sha256`, for the people and package managers that check what they download.

With no argument, `fledge build` builds the folder you are in: the one executable its gemspec names, or else its `main.rb`. Pass a path to build another program, and `--out DIR` to write somewhere other than `dist`. Your whole project ships in the app's `app/` folder, except `.git`, `.bundle`, `vendor/bundle`, `vendor/cache`, and the folders earlier builds wrote to. `bundle exec fledge --help` prints the whole manual.

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

macOS, Windows, and Linux show your app's name, icon, and version in their usual places. [`examples/windowed_app`](examples/windowed_app) is a complete example, and `--help` lists every key.

Your editor can check `fledge.yml` as you type. With Red Hat's YAML language server, which VS Code's YAML extension runs, make this the file's first line, with the tag your `Gemfile` names, and the editor completes each key and marks what `fledge build` would refuse:

<!-- SPDX-SnippetBegin -->
<!--
  SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
  SPDX-License-Identifier: MIT-0
-->
```yaml
# yaml-language-server: $schema=https://raw.githubusercontent.com/setdef/Fledge/v0.4.0/lib/fledge/config.schema.json
```
<!-- SPDX-SnippetEnd -->

`installers` chooses which of `dmg`, `nsis`, `appimage`, and `deb` to build. The default is the first three, and `deb` needs `dpkg-deb` on your computer. A `.deb` depends on `libc6`, and on the packages of any libraries you list as the Linux distribution's (see [Gems](#gems)), so `apt` installs it on a computer without a desktop too. A library a gem opens while your app runs, such as the X11, Wayland, or OpenGL libraries SDL opens, comes from the desktop, and Fledge cannot check that it is there.

### Several programs in one app

If your app has more than one way in, such as a window, a terminal interface, and a command line that all open the same save file, list them under `programs` in `fledge.yml`. Fledge builds them into one folder that shares one Ruby runtime, one copy of your project, and one set of gems. `fledge build` with no argument builds all of them; `fledge build PATH` with one of the listed files builds that program alone.

<!-- SPDX-SnippetBegin -->
<!--
  SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
  SPDX-License-Identifier: MIT-0
-->
```yaml
name: Shared Save
programs:
  - path: window.rb
    kind: windowed
    identifier: com.example.SharedSave
  - path: bin/shared-save
    kind: console
```
<!-- SPDX-SnippetEnd -->

At most one program is windowed. It takes the app's name unless you give it a `name` of its own, gets the installers, and on macOS holds the console programs inside its `.app` bundle. A console program takes its file's name, such as `shared-save`, the command your users type. [`examples/programs`](examples/programs) is a complete example.

### Signing

An app is unsigned unless you sign it. Without a signature, macOS's [Gatekeeper](https://support.apple.com/guide/security/gatekeeper-and-runtime-protection-sec5599b66df/web) and Windows' [SmartScreen](https://learn.microsoft.com/windows/security/operating-system-security/virus-and-threat-protection/microsoft-defender-smartscreen/) warn the people who download your app.

To sign with your own identity, pass `--sign`. On macOS, give a code signing identity from your keychain, such as `"Developer ID Application: NAME (TEAM)"`. On Windows, give the SHA-1 thumbprint of a code signing certificate in your certificate store. Fledge signs every program and library, the app bundle, and the installer.

Fledge's CI signs with a self-signed certificate. It has not yet tried a certificate from Apple or a certificate authority, so how Gatekeeper and SmartScreen treat one is unconfirmed. Fledge does not notarize; `xcrun notarytool` does that to a signed disk image.

### Gems

Your `Gemfile.lock` decides which gems ship. The `development` and `test` groups stay out, and an optional group ships only if your Bundler `with` setting names it. Lock each platform you build on, and every gem's checksum:

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

Precompiled gems ship as they are. Gems that ship as source, and gems from git, compile on your computer against the runtime's Ruby. Install a compiler first: Xcode's command line tools on macOS, a C compiler and `make` on Linux, or RubyInstaller's MSYS2 tools (`ridk install`) on Windows, and `cargo` for a Rust extension. If a gem would not load on another computer, the build fails and the error names the gem. Git gems, git submodules, path gems, mirrors, and credentials work as they do in Bundler; [`examples/real_gems`](examples/real_gems) uses each.

#### A gem that links a library from the Linux distribution

On Linux, a gem's compiled files may link only the libraries every distribution has, the ones the runtime carries, and the ones the gem carries itself. A wrapper of a desktop library, such as a webview's WebKitGTK and GTK, links libraries that a desktop's distribution provides and no gem carries, so the build refuses it and names each library. If every computer your app goes to has them, list them in `fledge.yml` by those names:

<!-- SPDX-SnippetBegin -->
<!--
  SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
  SPDX-License-Identifier: MIT-0
-->
```yaml
linux:
  system_libraries: [libwebkit2gtk-4.1.so.0, libgtk-3.so.0]
```
<!-- SPDX-SnippetEnd -->

The build then takes the gem, and refuses a library you list that no gem needs. A `.deb` depends on the packages that provide them, as `dpkg-shlibdeps` finds them, so building one needs `dpkg-dev`, which `build-essential` brings. An AppImage or `.tar.gz` does not carry them: on a computer that lacks one, the app says which library to install, and exits with status 72, before your code runs. [`examples/system_library`](examples/system_library) is a complete example.

#### A gem that only `vendor/cache` holds

A gem from a GitHub release, which is not on rubygems.org, has no checksum on any server. `bundle lock --add-checksums` fills in the gem Bundler installed on your computer and leaves an empty entry for each other platform's build, and `fledge build` refuses a lockfile with an empty entry. Print each `.gem` file's SHA-256 and write it after that build's entry in the `CHECKSUMS` section of `Gemfile.lock`:

<!-- SPDX-SnippetBegin -->
<!--
  SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
  SPDX-License-Identifier: MIT-0
-->
```console
$ shasum -a 256 vendor/cache/my_gem-*.gem
a40dd10e0d71ed27d8ad95aa0db9bb17f7076adaa8fdf45fefd712266759f102  vendor/cache/my_gem-1.0.0-x86_64-linux-gnu.gem
```
```
CHECKSUMS
  my_gem (1.0.0-x86_64-linux-gnu) sha256=a40dd10e0d71ed27d8ad95aa0db9bb17f7076adaa8fdf45fefd712266759f102
```
<!-- SPDX-SnippetEnd -->

If the gem's publisher lists a SHA-256 for each file, compare it with yours. Bundler keeps the checksums you write, and Bundler and Fledge both refuse a `.gem` that does not match.

### iPhone, iPad, and Android

For a phone, Fledge does not build the finished app. It writes an Xcode or Gradle project that holds your program and a Ruby runtime, and you build, sign, and submit that project the way you would any other phone app.

- `fledge build ios` writes an Xcode project for iOS 15 and later. Run it on a Mac with Xcode and [XcodeGen](https://github.com/yonaskolb/XcodeGen).
- `fledge build android` writes a Gradle project for Android 8.0 (API 26) and later. Run it on a Mac, x86-64 Linux, or Windows. Building the project takes a JDK and the Android SDK.

Lock `ruby` as a platform (`bundle lock --add-platform ruby`). [`examples/mobile_app`](examples/mobile_app) is a complete example.

**Gems with extensions.** A gem with a C or C++ extension compiles for the phone and links into the app: with Xcode on iOS, and with the [Android NDK](https://developer.android.com/ndk) on Android (set `ANDROID_NDK_ROOT`, or install the NDK in the SDK's `ndk/` folder). Load the extension with `require "name/name"`, not `require_relative`. An `extconf.rb` that runs CMake gets a toolchain file for each target in `CMAKE_TOOLCHAIN_FILE`, so the library it builds is built for the phone. Fledge refuses, and names the gem, a Rust extension and an extension that the gemspec says Rake, CMake, or configure builds without an `extconf.rb`. [`examples/native_phone`](examples/native_phone) and [`examples/cmake_phone`](examples/cmake_phone) show each case.

**Frameworks that start the app themselves.** A framework such as SDL3 needs its own startup files on each phone. Name a folder of them under `ios: host:` and `android: host:` in `fledge.yml`, and `fledge build` copies them over the project it writes. [`examples/sdl_phone`](examples/sdl_phone) is a game loop on SDL3.

Fledge's CI runs phone apps in the iOS Simulator on an iPhone and an iPad, and on x86-64 Android emulators. It has not run an app on a physical iPhone or iPad, and no app has been through App Review. For `arm64-v8a`, which most Android phones use, the CI builds the library and checks the APK but never runs it, because no free runner boots an arm64 emulator.

### Updating Fledge

Change the tag in your `Gemfile` and run `bundle update fledge`. Each version pins the SHA-256 of every runtime it downloads. A new version of Fledge may move your app's Ruby to a newer patch, such as 4.0.9 to 4.0.10, and the [CHANGELOG](CHANGELOG.md) records each move; only you move it to another minor version, by running Fledge with that Ruby. Fledge is 0.x: a minor version can break your build, so read the CHANGELOG before you update. From 1.0, only a major version will change the command, `fledge.yml`, or what a built app holds.

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

**Your app stays yours.** You can keep your app's source code private. Fledge's code is in two files of each app, the launcher your users run and one RubyGems defaults file, and on macOS and Linux in a third: `bin/ruby`, the Ruby that `RbConfig.ruby` names, which is Ruby's own with Fledge's code compiled in. It is under the AGPL, so when you give the app to people, you give them its source too. Each app's `notices/NOTICES.txt` says where it is: Fledge's source, at the tag that built the app. The rest of the runtime is under licenses that ask only that you keep their notices, and every app carries them, except for a few libraries under the LGPL on Linux and Windows, which your users may replace with builds of their own: each app carries their source in `notices/sources/`, so the source goes wherever the app goes. Your gems have licenses of their own, and you read them; Fledge ships every gem you lock, whatever its license. [What ships in your app](doc/licensing.md) lists every component, and is not legal advice. Setdef may also offer Fledge under a commercial license, for people who prefer not to follow the AGPL for those files.

Some parts of this program are copied from other sources under appropriate reuse licenses, and the copyright belongs to their respective owners. See the [REUSE Specification](https://reuse.software/spec-3.3/) for details.

This program is **requested**, and its maintainer describes the three ways code comes to exist like this:

> I use three words for how code comes to exist. Code I wrote, I typed by hand, with nothing generated. Code I wrought, an AI agent generated while I iterated with it, and I reviewed every change before committing it, so I take responsibility for every diff. Code I requested, an agent built with little or no review from me, in the style of a "dark factory."

All of Fledge is requested. The CI gates and the Delivery jobs, which run each built app on a clean computer, stand in for review. Each commit has a `Provenance:` trailer and a footer that names the model. On [declare-ai.org](https://declare-ai.org/1.0.0/assess.html)'s scale the assistance is [creative](https://declare-ai.org/1.0.0/creative.html), not none, non-creative, or total, because the agents made design and wording choices under the maintainer's direction.
