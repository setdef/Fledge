<!--
  SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
  SPDX-License-Identifier: CC-BY-SA-4.0
-->
# Gems in a Fledge app

[Fledge](../README.md) ships the gems your `Gemfile.lock` locks in every group `bundle exec` loads, `development` and `test` included, less the groups your Bundler `without` setting names (`bundle config set --local without test`, or `BUNDLE_WITHOUT`). An optional group ships only if your Bundler `with` setting names it. A gem of a group that ships must have a build for each platform you build on, as `bundle install` there would need; if it has none, and the app never needs it, leave its group out. Git gems, git submodules, path gems, mirrors, and credentials work as they do in [Bundler](https://bundler.io/). [`examples/real_gems`](../examples/real_gems) uses each of them.

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

`bundle exec` runs the Bundler your `Gemfile.lock` names under `BUNDLED WITH`, and so does your app: Fledge ships that Bundler beside Ruby's own, and checks it against its entry in `CHECKSUMS`, as it checks every gem. Bundler 2.6 and newer write that entry. If your lockfile has none, run `bundle install`, which installs that Bundler, then `bundle lock --add-checksums`.

## Gems with compiled extensions

Fledge ships precompiled gems as they are. It compiles gems that ship as source, and gems from git, on your computer, against the app's Ruby. Install a compiler first:

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
