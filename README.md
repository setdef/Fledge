# Fledge

[![Release](https://img.shields.io/github/v/release/setdef/Fledge?include_prereleases&sort=semver)](https://github.com/setdef/Fledge/releases)
[![CI](https://github.com/setdef/Fledge/actions/workflows/ci.yml/badge.svg?branch=trunk)](https://github.com/setdef/Fledge/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

Ship a Ruby app to people who don't have Ruby.

Fledge builds the Ruby program you run, its project, and the gems its `Gemfile.lock` locks into an app that carries a Ruby: a folder that runs on macOS, Windows, or Linux with nothing installed, and a project Xcode or Gradle builds into an iPhone or Android app. The app runs your program as `bundle exec ruby` would, so the program you test is the program you ship, and it calls nothing of Fledge's. It's for a developer with a working Ruby program, a command-line tool, a game, or a desktop app, who wants to hand it to people who will never install Ruby.

How it compares with what you may have tried:

- **[`gem install`](https://guides.rubygems.org/command-reference/#gem-install)** reaches only people who have Ruby, the right version of it, and a compiler for any gem that needs one. A Fledge app needs none of those.
- **[Tebako](https://github.com/tamatebako/tebako)** packs an app that downloads its Ruby the first time it opens on a computer, into `~/.tebako`, a folder in the person's home that every Tebako app there shares. A Fledge app carries its Ruby, so it needs no network to start.
- **[OCRAN](https://github.com/largo/ocran)** packs an app and the Ruby the developer runs into one executable file, which unpacks into a temporary folder each time it starts. A Fledge app is a folder that starts as `ruby` starts, and a windowed app gets the installers each system expects.
- **Copying your Ruby** fails on another computer: a Ruby from a version manager or a package manager records the absolute paths it was built for, and links the libraries of the computer that built it. A Fledge runtime is built to run from any folder.

## A first example

A two-line program, `main.rb`, in a folder named `greet`:

<!-- SPDX-SnippetBegin -->
<!--
  SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
  SPDX-License-Identifier: MIT-0
-->
```ruby
name = ARGV.first || "world"
puts "Hello, #{name}!"
```
<!-- SPDX-SnippetEnd -->

With Fledge in the project's `Gemfile`, build it on Linux:

<!-- SPDX-SnippetBegin -->
<!--
  SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
  SPDX-License-Identifier: MIT-0
-->
```console
$ bundle exec fledge build
Downloading fledge-runtime-0.17.0-x86_64-linux.tar.gz from https://github.com/setdef/Fledge/releases/download/v0.17.0
Writing the gems' executables for x86_64-linux
dist/Greet-x86_64-linux.tar.gz
```
<!-- SPDX-SnippetEnd -->

Then unpack it anywhere, and run it with an environment that holds no Ruby:

<!-- SPDX-SnippetBegin -->
<!--
  SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
  SPDX-License-Identifier: MIT-0
-->
```console
$ tar -xzf dist/Greet-x86_64-linux.tar.gz -C /tmp
$ env -i PATH=/usr/bin:/bin /tmp/Greet-x86_64-linux/Greet Ada
Hello, Ada!
```
<!-- SPDX-SnippetEnd -->

[The tutorial](docs/tutorial.md) goes on from there: naming the app, adding gems, and handing it over.

## Compatibility

| Platform | Runs on | Built on | You hand people |
| - | - | - | - |
| macOS | macOS 26.0 and later, on Apple silicon | a Mac with Apple silicon | a `.tar.gz`, and a `.dmg` for a windowed app |
| Windows | Windows 11 and later, on x64 or ARM64 | Windows 11 on the same processor | a `.zip`, and a setup program or an MSIX package for a windowed app |
| Linux, glibc | glibc 2.28 and later, on x86-64 or ARM64 | Linux on the same processor | a `.tar.gz`, and an AppImage or a `.deb` for a windowed app |
| Linux, musl | musl Linux, such as Alpine, on x86-64 or ARM64 | musl Linux on the same processor | a `.tar.gz`, and an AppImage for a windowed app |
| iOS and iPadOS | 15.0 and later | a Mac with Apple silicon, with Xcode and XcodeGen | an Xcode project, which you build and sign |
| Android | 8.0 (API 26) and later | a Mac with Apple silicon, x86-64 Linux, or x64 Windows | a Gradle project, which you build and sign |

Each platform's app is built on a computer of that platform: to ship for three desktops, build on three computers, or on three of a CI service's runners. Every app carries Ruby 4.1, and you build with Ruby 4.1. Windows 10, a Mac with an Intel processor, and 32-bit systems are not among Fledge's platforms. [Platforms](docs/reference/platforms.md) has the details, and what each build computer needs.

## Installation

Fledge is a gem, installed from its release tag on GitHub. Add it to the project's `Gemfile`:

<!-- SPDX-SnippetBegin -->
<!--
  SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
  SPDX-License-Identifier: MIT-0
-->
```ruby
gem "fledge", github: "setdef/Fledge", tag: "v0.17.0"
```
<!-- SPDX-SnippetEnd -->

Then run `bundle install` with Ruby 4.1. Bundler fetches a gem from GitHub with [Git](https://git-scm.com), so `git` has to be on your `PATH`.

On macOS or Linux, a version manager installs Ruby 4.1: with [mise](https://mise.jdx.dev), run `mise use ruby@4.1.0-preview1`. On Windows, install the head build of [RubyInstaller](https://github.com/oneclick/rubyinstaller2), `rubyinstaller-head`, the Ruby 4.1 that Fledge's Windows runtime is made from.

## Usage

In your project's folder, build the app for the computer you're on:

<!-- SPDX-SnippetBegin -->
<!--
  SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
  SPDX-License-Identifier: MIT-0
-->
```console
$ bundle exec fledge build
```
<!-- SPDX-SnippetEnd -->

fledge prints the path of each file it wrote, in `dist`, and writes each one's SHA-256 beside it. From there:

1. **Say how the app presents itself** in a `fledge.yml` beside the `Gemfile`: its name, version, icon, and, for a desktop app, that it opens windows. Every line is optional.

   <!-- SPDX-SnippetBegin -->
   <!--
     SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
     SPDX-License-Identifier: MIT-0
   -->
   ```yaml
   name: Cool App
   version: "1.2.3"
   kind: windowed
   identifier: com.example.CoolApp
   icon: icons/app
   installers: [dmg, nsis, appimage]
   ```
   <!-- SPDX-SnippetEnd -->

   A windowed app gets a macOS bundle and disk image, a Windows setup program, and a Linux desktop entry and AppImage. See [Make a windowed app](docs/how-to/windowed-app.md), and [the fledge.yml reference](docs/reference/fledge-yml.md) for every key.

2. **Ship gems with C extensions.** fledge compiles them for the app's Ruby, and refuses one whose compiled file couldn't load on another computer, saying what to change. See [Ship gems with C extensions](docs/how-to/native-gems.md).

3. **Sign the app** for macOS and Windows, and have Apple notarize it:

   <!-- SPDX-SnippetBegin -->
   <!--
     SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
     SPDX-License-Identifier: MIT-0
   -->
   ```console
   $ bundle exec fledge build --sign "Developer ID Application: Example, Inc. (ABCDE12345)" --notarize notary
   ```
   <!-- SPDX-SnippetEnd -->

   See [Sign and notarize an app](docs/how-to/signing.md).

4. **Build on each platform** you ship for, and hand people the archive or installer each build printed.

5. **Write the phone apps' projects**, on a Mac for iOS, and build them with Xcode or Gradle:

   <!-- SPDX-SnippetBegin -->
   <!--
     SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
     SPDX-License-Identifier: MIT-0
   -->
   ```console
   $ bundle exec fledge ios project
   $ bundle exec fledge android project
   ```
   <!-- SPDX-SnippetEnd -->

   See [Build for iPhone and Android](docs/how-to/phones.md).

## Documentation

- [The tutorial](docs/tutorial.md): build a command-line tool into an app, from nothing.
- [How-to guides](docs/how-to/README.md): windowed apps, file associations, several programs, native gems, private gem servers, signing, phones, and building offline.
- [The `fledge` command](docs/reference/fledge.usage.kdl): every command, flag, environment variable, and exit status, as a [Usage](https://usage.jdx.dev) spec.
- [fledge.yml](docs/reference/fledge-yml.md): every key of the file that says how an app presents itself.
- [Platforms](docs/reference/platforms.md) and [what a built app holds](docs/reference/built-app.md).
- [How Fledge works](docs/explanation/how-fledge-works.md) and [Ruby on a phone](docs/explanation/phones.md): why an app is shaped as it is.
- [The changelog](CHANGELOG.md): what changed in each release.

## Questions and problems

Ask questions, and report bugs, on [the Fledge forum](https://forum.setdef.com/c/fledge). Include the Fledge version (`bundle exec fledge --version`), the systems you built on and ran on, the project's `fledge.yml`, the command you ran, and everything it printed. Report a vulnerability privately, as [the security policy](SECURITY.md) says.

## Contributing

[CONTRIBUTING.md](CONTRIBUTING.md) has the project's rules, setup, and checks. [Fledge's design](docs/contributors/design/architecture.md) maps its parts for anyone changing them.

## License

Fledge is released under the [MIT License](LICENSE), copyright setdef.

Your app's code is yours to license as you choose. The app carries Fledge's runtime, whose parts keep their licenses; each app holds their notices in its `notices` folder, and the release publishes the source of each LGPL part. The gems your app depends on are your choice, and their licenses yours to comply with. [What ships inside an app, and what its licenses ask of you](docs/reference/licensing.md) lists each component of the runtime and what its license asks of you.

## How this was made

I use four words for how code and prose comes to exist. Code or prose I wrote, I typed by hand, with nothing generated. Code or prose I wrought, an AI agent generated while I iterated with it, and I reviewed every change before committing it, so I own every diff. Code or prose I requested, an agent built with little or no review from me, but I take ownership of the outcome or product because I tested and iterated. Code or prose I rushed, an agent built with little or no feedback from me, and may or may not be useful (or safe).

Fledge's code, tests, and documentation, this README included, were requested. Agents built them from my goals and decisions, with little review of the diffs. In place of review, the project's rules require every change to pass its gates with zero errors and zero warnings: the unit and integration tests, RuboCop, Steep's type checks, RubyCritic, and `reuse lint`. They also require each desktop platform's built app to run on a fresh computer that has never had Ruby. [declare-ai.org](https://declare-ai.org/1.0.0/creative.html).
