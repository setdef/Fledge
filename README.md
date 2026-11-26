<!--
  SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
  SPDX-License-Identifier: CC-BY-SA-4.0
-->
# Fledge

[![CI](https://github.com/setdef/Fledge/actions/workflows/ci.yml/badge.svg?branch=trunk)](https://github.com/setdef/Fledge/actions/workflows/ci.yml) [![Release](https://img.shields.io/github/v/release/setdef/Fledge)](https://github.com/setdef/Fledge/releases) [![License](https://img.shields.io/badge/dynamic/regex?url=https%3A%2F%2Fraw.githubusercontent.com%2Fsetdef%2FFledge%2Ftrunk%2Ffledge.gemspec&search=spec%5C.license%20%3D%20%22(.*)%22&replace=%241&label=License&color=a2c93e)](https://spdx.org/licenses/MIT.html) [![Ruby](https://img.shields.io/badge/dynamic/regex?url=https%3A%2F%2Fraw.githubusercontent.com%2Fsetdef%2FFledge%2Ftrunk%2Fruntime%2Fsources.yml&search=ruby%3A%5Cn%20%20version%3A%20(%5B0-9a-z.-%5D%2B)&replace=%241&label=Ruby&logo=ruby&color=a2c93e)](#compatibility) [![Platforms](https://img.shields.io/badge/platforms-macOS%20%7C%20Windows%20%7C%20Linux%20%7C%20iOS%20%7C%20Android-a2c93e)](#compatibility) [![Certified Shovelware](https://justin.searls.co/img/shovelware.svg)](https://justin.searls.co/shovelware/)

Ship a Ruby app to people who don't have Ruby.

You wrote a Ruby program for people who have never installed Ruby and never will. Fledge turns it into an app they download and open like any other: a Mac app on a disk image, a Windows setup program, a Linux [AppImage](https://appimage.org/), or a command they install with [Homebrew](https://brew.sh/) or [winget](https://learn.microsoft.com/windows/package-manager/winget/). For iPhone, iPad, and Android, Fledge writes the [Xcode](https://developer.apple.com/xcode/) or [Gradle](https://gradle.org/) project you build the app from.

You write your app in Ruby, with whatever front end your framework uses, on every platform, phones included, and never the native code a platform needs: Fledge supplies every line of it. If you want each system's widgets, your Ruby draws them, as it would under `ruby main.rb`: [AppKit](https://developer.apple.com/documentation/appkit) on a Mac, [GTK 4](https://www.gtk.org/) with [libadwaita](https://gnome.pages.gitlab.gnome.org/libadwaita/) on Linux, [WinUI 3](https://learn.microsoft.com/windows/apps/winui/winui3/) or [Win32](https://learn.microsoft.com/windows/win32/)'s controls on Windows, [UIKit](https://developer.apple.com/documentation/uikit) on iPhone and iPad, and [Android's views](https://developer.android.com/reference/android/view/View) on Android.

Your code runs as it does when you type `ruby main.rb` or [`bundle exec`](https://bundler.io/), with the same requires, globals, and standard library, and the gem versions in your `Gemfile.lock`, compiled gems included. If your users happen to have Ruby, your app ignores it, and its settings.

**Quick links:** [Guides](#documentation) • [Examples](examples) • [Changelog](CHANGELOG.md) • [Releases](https://github.com/setdef/Fledge/releases) • [Issues](https://github.com/setdef/Fledge/issues)

## Your first app

Here is a two-line `main.rb`, in a folder named `greet`, that prints a greeting as JSON:

<!-- SPDX-SnippetBegin -->
<!--
  SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
  SPDX-License-Identifier: MIT-0
-->
```ruby
require "json"
puts JSON.generate(greeting: "Hello, #{ARGV.fetch(0, "world")}!")
```
<!-- SPDX-SnippetEnd -->

Beside it is a `Gemfile` with the line from [Installation](#installation). In that folder, run `bundle exec fledge build`. Fledge builds the app for the computer you run it on. Here is the build on a Mac with Apple silicon:

<!-- SPDX-SnippetBegin -->
<!--
  SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
  SPDX-License-Identifier: MIT-0
-->
```console
$ bundle exec fledge build
Downloading fledge-runtime-0.17.0-arm64-darwin.tar.gz from https://github.com/setdef/Fledge/releases/download/v0.17.0
dist/Greet-arm64-darwin.tar.gz
```
<!-- SPDX-SnippetEnd -->

The first time you build on a computer, Fledge downloads the Ruby it puts in your apps, and keeps it for later builds. It names the app after the folder, so `greet` becomes `Greet`, and prints the path of the archive it wrote. Unpack the archive and run the app:

<!-- SPDX-SnippetBegin -->
<!--
  SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
  SPDX-License-Identifier: MIT-0
-->
```console
$ tar -xzf dist/Greet-arm64-darwin.tar.gz -C /tmp
$ /tmp/Greet-arm64-darwin/Greet Ruby
{"greeting":"Hello, Ruby!"}
```
<!-- SPDX-SnippetEnd -->

The archive is 29 MB, and 88 MB unpacked. Anyone with an Apple silicon Mac on macOS 26 or newer can run `Greet`, whether or not they have Ruby. On Windows, the same command writes `dist/Greet-x64-mingw-ucrt.zip`, which holds `Greet.exe`, and on Linux, a `.tar.gz` for your processor, such as `dist/Greet-x86_64-linux.tar.gz`.

### What Fledge builds

| Your app | macOS | Windows | Linux |
| --- | --- | --- | --- |
| Runs in a terminal (the default) | a `.tar.gz` | a `.zip` | a `.tar.gz` |
| Opens windows | a `.app` bundle, and a `.dmg` | a `.zip`, a setup program that installs without an administrator, and an [`.msix`](https://learn.microsoft.com/windows/msix/overview) for the [Microsoft Store](https://apps.microsoft.com/) if you ask for one | a `.tar.gz` with a [desktop entry](https://specifications.freedesktop.org/desktop-entry-spec/latest/), an [AppImage](https://appimage.org/), and a [`.deb`](https://manpages.debian.org/deb.5) if you ask for one |

For iPhone, iPad, and Android, Fledge writes an [Xcode](https://developer.apple.com/xcode/) or [Gradle](https://gradle.org/) project that you build, sign, and submit as you would any other phone app. Your Ruby can draw the app's screen with each phone's widgets, as [Draw windows with each system's widgets](#draw-windows-with-each-systems-widgets) says. Fledge compiles your gems' C, C++, and Rust extensions for the phone, and the [`ffi`](https://github.com/ffi/ffi) gem works there too.

## How Fledge compares

To run a program you distribute as a [gem](https://guides.rubygems.org/what-is-a-gem/), people have to install a compatible version of Ruby, and then install your gem. To run one you distribute as a [Docker](https://www.docker.com/) image, they have to install Docker, and your program runs inside Linux, where it can't open a window on their desktop.

Three other projects put a Ruby in your app, as Fledge does.

With [Traveling Ruby](https://github.com/trubygems/traveling-ruby)'s `truby` command, you can package your app for every system from one computer, on Ruby 3.3, 3.4, or 4.0. But you can use a gem with a C extension only if Traveling Ruby built that extension for its release, and you can't use a gem from git at all. Your users get an archive to unpack and a script to start, with no installer.

[Ocran](https://github.com/largo/ocran) packs your app into one executable for Windows, macOS, or Linux, and can also make a Mac app or a Windows installer. You have to change your code for it. Your program runs from a temporary folder, so you add a line to find the files beside it. Ocran also runs your program while it builds, so if your program has a main loop, you skip the loop when `defined?(Ocran)` is true. Every time someone opens the executable, they wait while it unpacks into that temporary folder, and Ocran's FAQ warns that antivirus programs commonly flag executables that unpack this way. You sign and notarize a Mac app yourself, with Apple's tools, and Ocran makes nothing for phones.

[Tebako](https://github.com/tamatebako/tebako) also packs your app into one executable, for macOS, Linux, and Windows, and unpacks nothing. The first time someone opens a Tebako app, it downloads its Ruby into a folder in their home, where every Tebako app on that computer shares it, and where it stays after they delete your app. You give your app a range of Ruby versions, and it runs on the newest one in that folder, which may be a Ruby another Tebako app brought and you never tried. On Windows on ARM64, a Tebako app runs under x64 emulation, and Tebako makes nothing for phones.

With Fledge, you change nothing in your code, and you keep the gems it uses today, because Fledge compiles them on each system you ship to. Your app carries the Ruby you built it with, so your users run the Ruby you tested. They open your app with no internet connection and no wait while anything unpacks. You sign it, and on a Mac have Apple notarize it, in the same command that builds it, and the same project builds for iPhone, iPad, and Android.

Fledge borrows its design from other languages: [LÖVE](https://love2d.org/)'s fused games, [PyInstaller](https://pyinstaller.org/) and [Briefcase](https://briefcase.readthedocs.io/) for Python, [python-build-standalone](https://github.com/astral-sh/python-build-standalone)'s relocatable interpreters, and [Tauri](https://tauri.app/)'s installers.

## Compatibility

Fledge and the apps it builds run on Ruby 4.1, the version on the Ruby badge, and until Ruby 4.1.0 is released, on its preview, 4.1.0-preview1. You build with [Bundler](https://bundler.io/).

| Platform | Your users run it on | You build it on |
| --- | --- | --- |
| `arm64-darwin` | macOS 26 or newer, on Apple silicon | a Mac with Apple silicon |
| `x86_64-linux`, `aarch64-linux` | Linux with [glibc](https://www.gnu.org/software/libc/) 2.28 or newer (RHEL 8, Debian 10, Ubuntu 20.04, and later), unless a gem you compile needs more | Linux with glibc, on that processor |
| `x86_64-linux-musl`, `aarch64-linux-musl` | Linux with [musl](https://musl.libc.org/), such as [Alpine](https://alpinelinux.org/) | Linux with musl, on that processor |
| `x64-mingw-ucrt` | Windows 11 on x64 | Windows on x64 |
| `aarch64-mingw-ucrt` | Windows 11 on ARM64 | Windows on ARM64 |
| iOS | iPhone and iPad, iOS 15 or newer | a Mac with [Xcode](https://developer.apple.com/xcode/) and [XcodeGen](https://github.com/yonaskolb/XcodeGen) |
| Android | Android 8.0 (API 26) or newer | a Mac, x86-64 Linux, or Windows, with a JDK, such as [Temurin](https://adoptium.net/), and the [Android SDK](https://developer.android.com/studio) |

- Fledge builds for the computer you run it on. To ship to three systems, build on three computers, such as a CI runner of each. Fledge builds nothing for Intel Macs or 32-bit systems, and nothing for the Mac App Store.
- On Windows, [RubyInstaller](https://rubyinstaller.org/) builds no Ruby preview, so until Ruby 4.1.0 is released, a Windows app runs on RubyInstaller's build of Ruby's development branch, a Ruby 4.1 newer than the preview. Test your app on Windows too. [Runtimes and Ruby versions](doc/runtimes.md) has the details.
- Your code can see [a few differences](doc/differences_from_ruby.md) from `ruby main.rb`, each listed with its reason.
- An app that draws with GTK 4 needs GTK 4 and libadwaita on the Linux computer, and one that draws with WinUI 3 needs the [Windows App Runtime](https://learn.microsoft.com/windows/apps/windows-app-sdk/) on the Windows one. The app carries neither. An app can draw Win32's controls where WinUI is missing or fails to start, as Basket does.
- Fledge makes each system's app with that system's tools. A Mac has them all. On Windows, Fledge brings [rcedit](https://github.com/electron/rcedit) and [NSIS](https://nsis.sourceforge.io/Main_Page), and to make an MSIX package, it uses [MakeAppx](https://learn.microsoft.com/windows/msix/package/create-app-package-with-makeappx-tool) from the Windows SDK, which you install. On Linux, install [squashfs-tools](https://github.com/plougher/squashfs-tools) 4.4 or newer for an AppImage, and [`dpkg-deb`](https://manpages.debian.org/dpkg-deb) for a `.deb`. If a tool is missing, `fledge build` stops and names what to install.

## Installation

On a computer with Ruby 4.1, add Fledge to your project's `Gemfile`, in the `development` group:

<!-- SPDX-SnippetBegin -->
<!--
  SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
  SPDX-License-Identifier: MIT-0
-->
```ruby
gem "fledge", git: "https://github.com/setdef/Fledge", tag: "v0.17.0", group: :development
```
<!-- SPDX-SnippetEnd -->

Then run `bundle install`, and `bundle exec fledge --version` prints `fledge 0.17.0`. [Bundler](https://bundler.io/) installs Fledge from a git tag, and the [releases page](https://github.com/setdef/Fledge/releases) lists every tag. Each release also carries the `.gem` built from its tag, attached to it as `fledge-X.Y.Z.gem`, which `gem install` takes from a file if a registry or git host is down.

Each app you build from this `Gemfile` carries Fledge too, as it carries your other development gems. Bundler installs a gem from git as its whole repository, so Fledge adds about 3 MB to the archive your users download, and 8 MB once they unpack it. You can't leave it out with Bundler's `without` setting, because `without development` would leave Fledge out of your bundle as well. To build apps without Fledge in them, put the same line in a `Gemfile` in a folder outside your project, run `bundle install` there, and from that folder, build your project by its path:

<!-- SPDX-SnippetBegin -->
<!--
  SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
  SPDX-License-Identifier: MIT-0
-->
```console
$ cd ~/fledge
$ bundle exec fledge build ~/code/greet
```
<!-- SPDX-SnippetEnd -->

Fledge writes the app to `dist` in the folder you run it from, here `~/fledge/dist`, unless you pass `--out`. Built this way, the `greet` archive is 26 MB.

## Usage

### Build

In your project's folder, run `bundle exec fledge build`. Fledge builds the executable you list in your [gemspec](https://guides.rubygems.org/specification-reference/), or else `main.rb`. To build another program, name it, as in `bundle exec fledge build bin/server`. To write the app somewhere other than `dist`, pass `--out DIR`.

Fledge names the app after your gemspec, or else your project's folder, so `my_cool_app` becomes `MyCoolApp`. Your project is the program's folder, or the nearest folder above it, that holds a `Gemfile`, `gems.rb`, a gemspec, or `fledge.yml`, as long as it is inside the same git repository. Fledge puts all of it in the app, in `app/`, except `.git`, `.bundle`, `vendor/bundle`, `vendor/cache`, and the folders Fledge writes to.

Beside the archive, Fledge leaves the app unpacked, in `dist/NAME-PLATFORM/`. There, `NAME`, or `NAME.exe` on Windows, starts your program, and `notices/` holds the licenses of everything Fledge put in. People can start the program from any folder, or through a link on their `PATH`. Beside each archive and installer, Fledge writes a `.sha256` file with its SHA-256, for people and package managers who check what they download.

### Lock your gems

Fledge ships the gems `bundle exec` would load, from every group in your `Gemfile`. That includes `development` and `test`, because some programs require a gem from those groups when they run, such as `debug` or `dotenv`. To make your app smaller, leave out the groups it doesn't use, as you would for any deployment, with [Bundler's `without` setting](https://bundler.io/man/bundle-config.1.html): `bundle config set --local without test`. With [`bundle lock`](https://bundler.io/man/bundle-lock.1.html), lock each platform you build on, and every gem's checksum:

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

Fledge ships a gem's precompiled build as it is when one of the gem's builds fits your platform and admits the app's Ruby. When none does, Fledge compiles the gem on your computer, for the app's Ruby: a gem published only as source, a gem from git, and a gem whose precompiled builds all require another Ruby, such as sqlite3 2.10.2, whose builds stop below Ruby 4.1. For that last kind, lock `ruby` as a platform too (`bundle lock --add-platform ruby`), so that your lockfile holds the gem's source build. Install a compiler first: [Xcode's command line tools](https://developer.apple.com/xcode/resources/) on a Mac, a C compiler and `make` on Linux, [RubyInstaller](https://rubyinstaller.org/)'s [MSYS2](https://www.msys2.org/) tools ([`ridk install`](https://github.com/oneclick/rubyinstaller2/wiki/The-ridk-tool)) on Windows, and [`cargo`](https://doc.rust-lang.org/cargo/) for a Rust extension. If a gem won't run on the app's Ruby, or links a library another computer may lack, `fledge build` stops and names the gem. On Linux, a gem compiled on your computer may need your computer's glibc, such as Ubuntu 24.04's 2.39, and then so does your app: `fledge build` warns you, and you can build on an older Linux, such as AlmaLinux 8, to lower it. [Gems in a Fledge app](doc/gems.md) covers gems that link a library from the Linux distribution, gems that link one you installed on your Mac, which the app can carry, and gems from `vendor/cache`.

### Describe your app

To give your app a name, a version, and an icon, and to make it open windows, add `fledge.yml` beside your `Gemfile`. Without it, you get a console app, named after your gemspec or your project's folder, at your gemspec's version or `0.0.0`.

<!-- SPDX-SnippetBegin -->
<!--
  SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
  SPDX-License-Identifier: MIT-0
-->
```yaml
# yaml-language-server: $schema=https://raw.githubusercontent.com/setdef/Fledge/v0.17.0/lib/fledge/config.schema.json
name: Hello Window
kind: windowed
identifier: com.example.HelloWindow
version: "1.2.3"
publisher: Example, Inc.
icon: icons/icon
```
<!-- SPDX-SnippetEnd -->

On a Mac, with icons in `icons/` and this `fledge.yml`, `bundle exec fledge build` makes `dist/Hello Window-arm64-darwin.tar.gz`, which holds `Hello Window.app`, and `dist/Hello Window-arm64-darwin.dmg`. With the first line in place, an editor that runs the [YAML language server](https://github.com/redhat-developer/yaml-language-server), such as VS Code with [Red Hat's YAML extension](https://marketplace.visualstudio.com/items?itemName=redhat.vscode-yaml), completes each key and marks mistakes. `bundle exec fledge --help` prints every key. For icon sizes, the files your app opens, and several programs in one app, see [Desktop apps](doc/desktop_apps.md).

### Draw windows with each system's widgets

To make an app look and behave as other apps for its system do, draw its windows with that system's widgets, from your Ruby. Your Ruby opens the system's libraries with [`fiddle`](https://github.com/ruby/fiddle), which Ruby bundles (on Android, with `zlib` and `digest`, which Ruby bundles too), on the process's main thread, where those widgets have to be used. Fledge adds no widget, library, or binding for it, and no key in `fledge.yml` that turns it on.

| System | Your Ruby draws with |
| --- | --- |
| macOS | AppKit |
| Linux | GTK 4 and libadwaita |
| Windows | WinUI 3, or Win32's common controls |
| iOS and iPadOS | UIKit |
| Android | Android's views |

[`basket`](examples/basket) is a shopping list that does this on all five, with each system's screen in a separate file: a window with a table and a menu bar on a Mac, a header bar and a boxed list with an Undo toast on Linux, a text box and a list in Fluent's styles on Windows, a table under a large title on iPhone and iPad, and a list under the app bar on Android. The Ruby that calls each system's libraries is Basket's, in files you can copy and change. [Desktop apps](doc/desktop_apps.md#draw-the-window-with-each-systems-widgets) and [iPhone, iPad, and Android](doc/phones.md#your-apps-screen) say how each one works.

### Sign

When people download an app you didn't [sign](doc/desktop_apps.md#sign-your-app), macOS's [Gatekeeper](https://support.apple.com/guide/security/gatekeeper-and-runtime-protection-sec5599b66df/web) and Windows' [SmartScreen](https://learn.microsoft.com/windows/security/operating-system-security/virus-and-threat-protection/microsoft-defender-smartscreen/) warn them. Pass `--sign` with your macOS [signing identity](https://developer.apple.com/help/account/certificates/create-developer-id-certificates/) or your Windows certificate's [thumbprint](https://learn.microsoft.com/dotnet/framework/wcf/feature-details/how-to-retrieve-the-thumbprint-of-a-certificate), and Fledge signs every program, library, bundle, and installer. On a Mac, add `--notarize`, and Fledge has Apple [notarize](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution) the app and [staples Apple's ticket](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow#Staple-the-ticket-to-your-distribution) to it, so Gatekeeper accepts the app even on a computer with no internet connection:

<!-- SPDX-SnippetBegin -->
<!--
  SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
  SPDX-License-Identifier: MIT-0
-->
```console
$ bundle exec fledge build --sign "Developer ID Application: Example (ABCDE12345)" --notarize my-notary-profile
```
<!-- SPDX-SnippetEnd -->

On Windows, to sign with a certificate in a cloud or hardware service, pass `--sign-command` with the command that signs. For both systems, see [Sign your app](doc/desktop_apps.md#sign-your-app).

### Build for a phone

On a Mac, `bundle exec fledge build ios` writes an [Xcode](https://developer.apple.com/xcode/) project. On a Mac, Linux, or Windows, `bundle exec fledge build android` writes a [Gradle](https://gradle.org/) project. Fledge prints the project's path, and you build, sign, and submit it with Xcode or Gradle. First, lock the `ruby` platform (`bundle lock --add-platform ruby`), and give the app an `identifier` in `fledge.yml`. What your program prints goes to the phone's system log. Your Ruby runs on the phone's main thread, as under `ruby main.rb`, where it can draw the app's screen with the phone's widgets. For your app's screen, gems with extensions, what a phone forbids, and the App Store and Google Play, see [iPhone, iPad, and Android](doc/phones.md).

### Publish

Put your archives and installers on your website, or on a [GitHub Release](https://docs.github.com/repositories/releasing-projects-on-github/about-releases), for people to download. From there:

- People who use a terminal can install a console app with [Scoop](https://scoop.sh/), [Homebrew](https://brew.sh/), [winget](https://learn.microsoft.com/windows/package-manager/winget/), [Chocolatey](https://chocolatey.org/), or the [AUR](https://aur.archlinux.org/). For each recipe, see [Publishing with a package manager](doc/package_managers.md).
- For the [Microsoft Store](https://apps.microsoft.com/) and Linux, see [Publish to a store](doc/desktop_apps.md#publish-to-a-store). For the [App Store](https://developer.apple.com/app-store/) and [Google Play](https://play.google.com/console/about/), see [iPhone, iPad, and Android](doc/phones.md).
- If you make a framework, you can ship an app that your users build their apps from, with no Ruby on their computers. See [Building from an app already built](doc/building_from_an_app.md).

### Update

Change the tag in your `Gemfile` and run `bundle update fledge`. A new Fledge may move your app to a newer patch of Ruby 4.1. Fledge is 0.x, so read the [CHANGELOG](CHANGELOG.md) first: any new version can break your build. From 1.0, only a major version can, and [What 1.x keeps](doc/runtimes.md#what-1x-keeps) lists what minor versions and patches leave alone.

## Documentation

| Resource | Description |
| --- | --- |
| `bundle exec fledge --help` | The manual: every option, every `fledge.yml` key, every file Fledge writes, and the exit statuses |
| [Gems in a Fledge app](doc/gems.md) | Locking, compiled gems, gems that link a Linux library or a library from your Mac, and gems from `vendor/cache` |
| [Desktop apps](doc/desktop_apps.md) | Names, icons, installers, drawing windows with each system's widgets, file associations, several programs in one app, a server that other computers open in the browser, signing, and publishing to a store |
| [iPhone, iPad, and Android](doc/phones.md) | Phone projects, your app's screen in UIKit and Android's views, gems with C, C++, and Rust extensions or libraries for `ffi`, and what a phone forbids |
| [Publishing with a package manager](doc/package_managers.md) | A Scoop manifest, a Homebrew formula, winget's files, a Chocolatey package, and a `PKGBUILD` for a console app |
| [Building from an app already built](doc/building_from_an_app.md) | `fledge build --from` and `build_tools`, for frameworks |
| [Runtimes and Ruby versions](doc/runtimes.md) | Which Ruby your app gets, where Fledge downloads it from, mirrors, building offline, updating, and what stays the same from 1.0 |
| [How a Fledge app differs from `ruby main.rb`](doc/differences_from_ruby.md) | Each difference your code can see, and why it is there |
| [What ships in your app](doc/licensing.md) | Every component Fledge puts in an app, on each platform, and what you owe under its license |
| [`examples/`](examples) | Apps to start from: [`hello`](examples/hello), the smallest; [`libui_app`](examples/libui_app), a work timer in a window; [`file_drop`](examples/file_drop), a file drop that phones and computers on your network open in the browser; [`markdown_to_html`](examples/markdown_to_html), a droplet that writes the HTML of Markdown files dropped on it, with a command for the terminal; [`lectern`](examples/lectern), a Markdown reader for the terminal, in one download with no Ruby; and [`basket`](examples/basket), a shopping list for macOS, Linux, Windows, iPhone, iPad, and Android, drawn with each system's widgets |
| [CHANGELOG](CHANGELOG.md) | What changed in each release |

## Reporting problems

Open an [issue](https://github.com/setdef/Fledge/issues). Say which platform you built on, which platform you ran the app on, and what `bundle exec fledge --version` prints.

## Contributing

To ask for a change, or to set up, test, and work on Fledge, see [CONTRIBUTING.md](CONTRIBUTING.md).

## Copyright & License

Fledge is copyright 2026, setdef. The code is [MIT](LICENSE), and the documentation is [CC-BY-SA-4.0](LICENSES/CC-BY-SA-4.0.txt). Code snippets and examples are [MIT-0](LICENSES/MIT-0.txt): copy and use them without attribution. See each file's SPDX comment for specifics.

**Your app stays yours.** Fledge's license puts no terms on your app's code. Each app carries a `notices/` folder, whose `NOTICES.txt` holds Fledge's MIT notice, for the launcher and Fledge's other files in the app, and the notices of the runtime's third-party components. Keep that folder with the app. For Fledge, and for most of the runtime, that is all you owe. On Linux and Windows, a few libraries are under the LGPL, under which you owe a little more, and each app carries their source in `notices/sources/`. [What ships in your app](doc/licensing.md) lists every component and what you owe under its license. It is not legal advice.

Some parts of this program are copied from other sources under appropriate reuse licenses, and the copyright belongs to their respective owners. See the [REUSE Specification – Version 3.3](https://reuse.software/spec-3.3/) for details.

## How Fledge is made

I use four words for how code and prose comes to exist. Code or prose I wrote, I typed by hand, with nothing generated. Code or prose I wrought, an AI agent generated while I iterated with it, and I reviewed every change before committing it, so I own every diff. Code or prose I requested, an agent built with little or no review from me, but I take ownership of the outcome or product because I tested and iterated. Code or prose I rushed, an agent built with little or no feedback from me, and may or may not be useful (or safe).

Fledge's code, tests, workflows, documentation, and design records are requested. In place of review, CI runs gates on every change, above all the delivery jobs that run each built app on a clean computer with no Ruby. [declare-ai.org](https://declare-ai.org/1.0.0/creative.html)
