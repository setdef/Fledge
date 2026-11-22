<!--
  SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
  SPDX-License-Identifier: CC-BY-SA-4.0
-->
# Gems in a Fledge app

[Fledge](../README.md) ships the gems your `Gemfile.lock` locks in every group `bundle exec` loads, `development` and `test` included, less the groups your Bundler `without` setting names (`bundle config set --local without test`, or `BUNDLE_WITHOUT`). Bundler leaves those groups out of your own bundle too, so `without development` cannot keep Fledge itself out of your apps without leaving you no Fledge to run; run Fledge from a bundle of its own instead, as [Installation](../README.md#installation) shows. An optional group ships only if your Bundler `with` setting names it. A gem of a group that ships must have a build for each platform you build on, as `bundle install` there would need; if it has none, and the app never needs it, leave its group out. Git gems, git submodules, path gems, mirrors, and credentials work as they do in [Bundler](https://bundler.io/). [`examples/real_gems`](../examples/real_gems) uses each of them.

Ruby's bundled gems, such as `fiddle`, `csv`, and `irb`, load in your app as they load for you. Without a `Gemfile`, `require "fiddle"` finds the runtime's fiddle, as `ruby main.rb` does. With a `Gemfile`, it finds fiddle only if your `Gemfile` names it: otherwise Ruby warns that fiddle is no longer a default gem and raises `LoadError`, in your app and under `bundle exec` alike. Add `gem "fiddle"` and lock it, and it loads in both.

## Lock every platform and checksum

Lock each platform you build on, and every gem's checksum:

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

For iPhone, iPad, and Android, lock `ruby` as a platform too (`bundle lock --add-platform ruby`).

## The Bundler that wrote your lockfile

`bundle exec` runs the Bundler your `Gemfile.lock` names under `BUNDLED WITH`, and so does your app: Fledge ships that Bundler beside Ruby's own, and checks it against its entry in `CHECKSUMS`, as it checks every gem. Bundler writes that entry only when it was installed as a gem, so a lockfile written by the Bundler that came with your Ruby has none. If yours has none, install the Bundler it names under `BUNDLED WITH` as a gem, then add the checksums:

<!-- SPDX-SnippetBegin -->
<!--
  SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
  SPDX-License-Identifier: MIT-0
-->
```console
$ gem install bundler -v 4.1.0.beta2
$ bundle lock --add-checksums
```
<!-- SPDX-SnippetEnd -->

## Gems with compiled extensions

Fledge ships precompiled gems as they are. It compiles gems that ship as source, and gems from git, on your computer, against the app's Ruby, and the app holds each such gem's folder as `gem install` leaves it, with every file its build wrote there. Install a compiler first:

- **macOS:** Xcode's command line tools.
- **Linux:** a C compiler and `make`, such as Debian's and Ubuntu's `build-essential`.
- **Windows:** RubyInstaller's MSYS2 tools (`ridk install`).
- **Any system:** `cargo`, for a gem with a Rust extension.

If a gem would not load on another computer, `fledge build` stops and names the gem. [`examples/native_app`](../examples/native_app) compiles gems from source. For phones, see [iPhone, iPad, and Android](phones.md).

## A gem that links a library from the Linux distribution

On Linux, a gem's compiled files may link only the libraries every distribution has, the libraries the app carries, and the libraries the gem carries itself. A wrapper of a desktop library, such as a webview's WebKitGTK and GTK, links libraries that the desktop's distribution provides and no gem carries. `fledge build` refuses such a gem and names each library. If every computer your app goes to has them, list them in `fledge.yml` by those names:

<!-- SPDX-SnippetBegin -->
<!--
  SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
  SPDX-License-Identifier: MIT-0
-->
```yaml
linux:
  system_libraries: [libwebkit2gtk-4.1.so.0, libgtk-3.so.0]
```
<!-- SPDX-SnippetEnd -->

Fledge then ships the gem, and refuses a library you list that no gem needs. A `.deb` depends on the packages that provide them, as `dpkg-shlibdeps` finds them, so building one needs `dpkg-dev`, which `build-essential` brings. An AppImage or `.tar.gz` does not carry them. On a computer that lacks one, the app says which library to install and exits with status 72, before your code runs. [`examples/system_library`](../examples/system_library) is a complete example.

## A gem whose DLL needs the Visual C++ runtime

On Windows, a DLL built with Visual Studio needs Microsoft's Visual C++ runtime, `vcruntime140.dll` and `msvcp140.dll`, unless it links the runtime statically. LibUI's DLL is one. Windows does not include the runtime: a computer has it once something installs Microsoft's Visual C++ Redistributable. `fledge build` refuses such a gem until you say in `fledge.yml` how your app gets the runtime:

<!-- SPDX-SnippetBegin -->
<!--
  SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
  SPDX-License-Identifier: MIT-0
-->
```yaml
windows:
  visual_c_runtime: local    # or central
```
<!-- SPDX-SnippetEnd -->

- **`local`** copies the runtime's DLLs that your gems need from this computer's `System32` into the app, so the app runs on a computer without the Redistributable. Install the Redistributable on the computer that builds the app. You distribute Microsoft's files when you ship the app: Microsoft's page [Redistribute Visual C++ files](https://learn.microsoft.com/en-us/cpp/windows/redistributing-visual-cpp-files) says "Distribution of the Visual C++ Runtime Redistributable package, merge modules, and individual binaries is limited to licensed Visual Studio users and is subject to Microsoft Software License Terms." Whether you hold that right, and what its terms ask of you, is yours to check; Fledge cannot. Microsoft also recommends against copies in the app's folder, which Windows Update does not update: build the app again to ship a newer runtime.
- **`central`** ships no runtime, for computers that have the Redistributable. Microsoft recommends this way. A person who starts the app from its `.zip` without the Redistributable meets Windows' error for a missing DLL, so tell them to install it first. The setup program and MSIX package do not install it yet.

Or use a build of the gem that links the runtime statically (`/MT`), which needs neither.

## A gem that only `vendor/cache` holds

A gem from a GitHub release, which is not on rubygems.org, has no checksum on any server. `bundle lock --add-checksums` fills in the checksum of the gem Bundler installed on your computer, and leaves an empty entry for each other platform's build. `fledge build` refuses a lockfile with an empty entry. Print each `.gem` file's SHA-256, and write it after that build's entry in the `CHECKSUMS` section of `Gemfile.lock`:

<!-- SPDX-SnippetBegin -->
<!--
  SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
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

## Licenses

Your gems' licenses are yours to read. Fledge ships every gem you lock, whatever its license, and says nothing about it. For what Fledge itself puts in an app, see [What ships in your app](licensing.md).
