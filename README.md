<!--
  SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
  SPDX-License-Identifier: CC-BY-SA-4.0
-->
# Fledge

[![CI](https://github.com/setdef/Fledge/actions/workflows/ci.yml/badge.svg?branch=trunk)](https://github.com/setdef/Fledge/actions/workflows/ci.yml) [![Release](https://img.shields.io/github/v/release/setdef/Fledge)](https://github.com/setdef/Fledge/releases) [![License](https://img.shields.io/badge/dynamic/regex?url=https%3A%2F%2Fraw.githubusercontent.com%2Fsetdef%2FFledge%2Ftrunk%2Ffledge.gemspec&search=spec%5C.license%20%3D%20%22(.*)%22&replace=%241&label=License&color=a2c93e)](https://spdx.org/licenses/AGPL-3.0-or-later.html) [![Ruby](https://img.shields.io/badge/dynamic/regex?url=https%3A%2F%2Fraw.githubusercontent.com%2Fsetdef%2FFledge%2Ftrunk%2Fruntime%2Fsources.yml&search=ruby%3A%5Cn%20%20version%3A%20(%5B0-9.%5D%2B)&replace=%241&label=Ruby&logo=ruby&color=a2c93e)](#compatibility) [![Platforms](https://img.shields.io/badge/platforms-macOS%20%7C%20Windows%20%7C%20Linux%20%7C%20iOS%20%7C%20Android-a2c93e)](#compatibility) [![Certified Shovelware](https://justin.searls.co/img/shovelware.svg)](https://justin.searls.co/shovelware/)

## Introduction

**Fledge** turns a Ruby program you already run into an app that people without Ruby can download and run. It copies your program, your project, and the gems your `Gemfile.lock` locks into a Ruby that runs from any folder, adds a launcher that starts your program as `bundle exec` would, and archives the result. Your users unpack one file and run it. They install nothing, and never learn what Ruby is.

Fledge is for Ruby developers with a working program, such as a command-line tool, a terminal app, a game, or a windowed app, who want to give it to people who have never heard of Ruby. [Lota](https://github.com/setdef/Lota)'s `lota fuse` builds its games with Fledge.

**Quick links:** [Guides](#documentation) • [Examples](examples) • [Changelog](CHANGELOG.md) • [Releases](https://github.com/setdef/Fledge/releases) • [Issues](https://github.com/setdef/Fledge/issues)

### Compared with other ways to ship a Ruby program

- **A gem.** Your users install Ruby first, at a version your gems accept, and then your gem.
- **A [Docker](https://www.docker.com/) image.** Your users install Docker, and your program runs inside Linux.
- **[Tebako](https://github.com/tamatebako/tebako) and [Ocran](https://github.com/largo/ocran)** pack a program into a single file, which unpacks itself to a temporary folder, or mounts a virtual file system, each time it starts. A Fledge app is a folder that runs where it sits, with Ruby's usual layout inside.

Fledge borrows its design from other languages: [LÖVE](https://love2d.org/)'s fused games, [PyInstaller](https://pyinstaller.org/) and [Briefcase](https://briefcase.readthedocs.io/) for Python, [python-build-standalone](https://github.com/astral-sh/python-build-standalone)'s relocatable interpreters, and [Tauri](https://tauri.app/)'s installers.

## A first app

This folder, `greeter`, holds a one-line `main.rb` that prints `Hello, Ruby!`, and a `Gemfile` with Fledge in it (see [Installation](#installation)):

<!-- SPDX-SnippetBegin -->
<!--
  SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
  SPDX-License-Identifier: MIT-0
-->
```console
$ bundle exec fledge build
Downloading fledge-runtime-0.7.0-arm64-darwin.tar.gz from https://github.com/setdef/Fledge/releases/download/v0.7.0
dist/Greeter-arm64-darwin.tar.gz
$ tar -xzf dist/Greeter-arm64-darwin.tar.gz -C /tmp
$ /tmp/Greeter-arm64-darwin/Greeter
Hello, Ruby!
```
<!-- SPDX-SnippetEnd -->

The archive is 20 MB, and 62 MB unpacked. Anyone with an Apple silicon Mac on macOS 14 or newer can run `Greeter`, with no Ruby on their computer.

### What Fledge builds

| Your app | macOS | Windows | Linux |
| --- | --- | --- | --- |
| Runs in a terminal (the default) | a `.tar.gz` | a `.zip` | a `.tar.gz` |
| Opens its own windows | a `.app` bundle, and a `.dmg` | a `.zip`, and a setup program that needs no administrator | a `.tar.gz` with a desktop entry, an AppImage, and a `.deb` if you ask for one |

For iPhone, iPad, and Android, Fledge writes an Xcode or Gradle project that you build and submit as you would any other phone app.

## Compatibility

| Platform | Your users run it on | You build it on |
| --- | --- | --- |
| `arm64-darwin` | macOS 14 or newer, on Apple silicon | a Mac with Apple silicon |
| `x86_64-linux`, `aarch64-linux` | Linux with glibc 2.39 or newer (Ubuntu 24.04, Debian 13) | Linux with glibc, on that processor |
| `x86_64-linux-musl`, `aarch64-linux-musl` | Linux with musl, such as Alpine | Linux with musl, on that processor |
| `x64-mingw-ucrt` | Windows 10 and 11 on x64 | Windows on x64 |
| `aarch64-mingw-ucrt` | Windows 11 on ARM64 | Windows on ARM64 |
| iOS | iPhone and iPad, iOS 15 or newer | a Mac with Xcode |
| Android | Android 8.0 (API 26) or newer | a Mac, x86-64 Linux, or Windows |

- Fledge builds for the computer it runs on. To ship to three systems, build on three computers, such as a CI runner of each. There is no runtime for Intel Macs or 32-bit systems.
- Fledge runs on Ruby 4.0.1 or newer, with Bundler. Your app gets the Ruby you run Fledge with, at the patch level on the Ruby badge above. See [Runtimes and Ruby versions](doc/runtimes.md).
- Your code runs as it does under `ruby main.rb`. Fledge's CI compares the two on every platform. Your code can see [a few differences](doc/differences_from_ruby.md), each with its reason.
- On every change, CI builds each desktop app and runs it on a clean computer that has no Ruby. CI runs phone apps in the iOS Simulator and Android emulators, and a game has run on a real iPad and iPhone. See [What has run where](doc/phones.md#what-has-run-where).
- CI signs apps with a self-signed certificate only. Signing with a certificate from Apple or a certificate authority is untested.

## Installation

Add Fledge to your `Gemfile`, in the `development` group, so that it stays out of your app:

<!-- SPDX-SnippetBegin -->
<!--
  SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
  SPDX-License-Identifier: MIT-0
-->
```ruby
gem "fledge", git: "https://github.com/setdef/Fledge", tag: "v0.7.0", group: :development
```
<!-- SPDX-SnippetEnd -->

Then run `bundle install`, and `bundle exec fledge --version` prints `fledge 0.7.0`. Fledge installs from a git tag. You'll find the latest on the [releases page](https://github.com/setdef/Fledge/releases).

## Usage

### Build

In your project's folder, run `bundle exec fledge build`. Fledge builds the executable your gemspec names, or else `main.rb`. Name another program to build it instead, such as `fledge build bin/server`, and pass `--out DIR` to write somewhere other than `dist`.

Fledge names the app after your gemspec, or else after your folder: `greeter` becomes `Greeter`. Your whole project goes in the app, except `.git`, `.bundle`, `vendor/bundle`, `vendor/cache`, and the folders Fledge writes to. Beside each archive, Fledge writes its SHA-256 in a `.sha256` file, for the people and package managers that check downloads.

### Lock your gems

Fledge ships the gems your `Gemfile.lock` locks, without the `development` and `test` groups. Lock each platform you build on, and every gem's checksum:

<!-- SPDX-SnippetBegin -->
<!--
  SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
  SPDX-License-Identifier: MIT-0
-->
```console
$ bundle lock --add-platform arm64-darwin x86_64-linux x64-mingw-ucrt
$ bundle lock --add-checksums
```
<!-- SPDX-SnippetEnd -->

Fledge compiles a gem that ships as source on your computer, so install a compiler first. For compilers, gems that link a Linux library, and gems from `vendor/cache`, see [Gems in a Fledge app](doc/gems.md).

### Describe your app

`fledge.yml` is an optional file at the top of your project, beside your `Gemfile`. In it, you give your app the name, version, and icon each system shows, and make it a windowed app with installers:

<!-- SPDX-SnippetBegin -->
<!--
  SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
  SPDX-License-Identifier: MIT-0
-->
```yaml
# yaml-language-server: $schema=https://raw.githubusercontent.com/setdef/Fledge/v0.7.0/lib/fledge/config.schema.json
name: My Cool App
kind: windowed
identifier: com.example.MyCoolApp
version: "1.0.0"
icon: icons/app
```
<!-- SPDX-SnippetEnd -->

With the first line, an editor that runs the [YAML language server](https://github.com/redhat-developer/yaml-language-server), such as VS Code with [Red Hat's YAML extension](https://marketplace.visualstudio.com/items?itemName=redhat.vscode-yaml), completes each key and marks mistakes. For every key, the files and folders your app opens, and several programs in one app, see [Desktop apps](doc/desktop_apps.md). `bundle exec fledge --help` prints them all.

### Sign

Pass `--sign` with your macOS signing identity or your Windows certificate's thumbprint, and Fledge signs every program, library, bundle, and installer. Without a signature, Gatekeeper and SmartScreen warn the people who download your app. See [Sign your app](doc/desktop_apps.md#sign-your-app).

### Publish

Put the archives and installers wherever your users download things, such as a GitHub Release. From there:

- People who use a terminal can install a console app through Scoop, Homebrew, or winget. For a recipe for each, see [Publishing with a package manager](doc/package_managers.md).
- For iPhone, iPad, and Android, see [iPhone, iPad, and Android](doc/phones.md).
- A framework can ship an app that its users build their apps from, with no Ruby on their computer. See [Building from an app already built](doc/building_from_an_app.md).

### Update

Change the tag in your `Gemfile` and run `bundle update fledge`. Fledge is 0.x, so read the [CHANGELOG](CHANGELOG.md) first: any new version can break your build. From 1.0, only a major version can, and [What 1.x keeps](doc/runtimes.md#what-1x-keeps) lists what minor versions and patches leave alone.

## Documentation

| Resource | Description |
| --- | --- |
| `bundle exec fledge --help` | The manual: every option, every `fledge.yml` key, every file Fledge writes, and the exit statuses |
| [Gems in a Fledge app](doc/gems.md) | Locking, compiled gems, gems that link a Linux library, and gems from `vendor/cache` |
| [Desktop apps](doc/desktop_apps.md) | Names, icons, installers, file associations, several programs in one app, and signing |
| [iPhone, iPad, and Android](doc/phones.md) | Phone projects, gems with C extensions on phones, and what has run on devices |
| [Publishing with a package manager](doc/package_managers.md) | A Scoop manifest, a Homebrew formula, and winget's files for a console app |
| [Building from an app already built](doc/building_from_an_app.md) | `fledge build --from` and `build_tools`, for frameworks |
| [Runtimes and Ruby versions](doc/runtimes.md) | Which Ruby your app gets, where Fledge downloads it from, mirrors, building offline, updating, and what stays the same from 1.0 |
| [How a Fledge app differs from `ruby main.rb`](doc/differences_from_ruby.md) | Each difference your code can see, and why it is there |
| [What ships in your app](doc/licensing.md) | Every component Fledge puts in an app, on each platform, and what you owe under its license |
| [`examples/`](examples) | Apps that CI builds and runs, from [`hello`](examples/hello) to [`windowed_app`](examples/windowed_app) |
| [CHANGELOG](CHANGELOG.md) | What changed in each release |

## Reporting problems

Open an [issue](https://github.com/setdef/Fledge/issues). Say which platform you built on, which platform you ran on, and what `bundle exec fledge --version` prints.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

## Copyright & License

Fledge is copyright 2026, setdef. The code is [AGPL-3.0-or-later](LICENSES/AGPL-3.0-or-later.txt), and the documentation is [CC-BY-SA-4.0](LICENSES/CC-BY-SA-4.0.txt). Code snippets and examples are [MIT-0](LICENSES/MIT-0.txt): copy and use them without attribution. See each file's SPDX comment for specifics.

**Your app stays yours.** Your app's code stays under your terms, whether or not you buy a commercial license. The AGPL reaches only code that copies or changes Fledge, and your program does neither. Fledge's code in your app is its launcher, one RubyGems defaults file, on macOS and Linux the app's `bin/ruby`, and Fledge's Ruby code if your app ships Fledge as a gem. When you give the app to people, the AGPL requires three things of you for those files:

- Offer their source. You'll find its address in each app's `notices/NOTICES.txt`.
- Keep the app's `notices/` folder with the app.
- If the app comes installed on a device you sell to consumers, give its owners what they need to install a changed launcher.

For the rest of the runtime, you need only keep the notices. On Linux and Windows, a few libraries are under the LGPL, and each app carries their source in `notices/sources/`.

If you change Fledge itself and give it to others, or offer a changed Fledge as a service, you must release your changes under the AGPL. A commercial license from Setdef frees you from these terms. You'll find the details in [What ships in your app](doc/licensing.md), which is not legal advice.

Some parts of this program are copied from other sources under appropriate reuse licenses, and the copyright belongs to their respective owners. See the [REUSE Specification – Version 3.3](https://reuse.software/spec-3.3/) for details.

## How Fledge is made

I use three words for how code and prose comes to exist. Code or prose I wrote, I typed by hand, with nothing generated. Code or prose I wrought, an AI agent generated while I iterated with it, and I reviewed every change before committing it, so I take responsibility for every diff. Code or prose I requested, an agent built with little or no review from me, in the style of a "dark factory."

All of Fledge is requested: the code, tests, workflows, design records, and this README. In place of review, CI runs gates on every change, above all the delivery jobs that run each built app on a clean computer with no Ruby. Every commit ends with a `Provenance: requested` trailer. Under [declare-ai.org](https://declare-ai.org/1.0.0/creative.html), this is creative assistance.
