<!--
  SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
  SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Fledge

[![Certified Shovelware](https://justin.searls.co/img/shovelware.svg)](https://justin.searls.co/shovelware/)
[![CI](https://github.com/setdef/Fledge/actions/workflows/ci.yml/badge.svg?branch=trunk)](https://github.com/setdef/Fledge/actions)

Fledge ships a Ruby app to people who don't have Ruby.

Almost nobody who would play your game, open your desktop app, or run your terminal tool has Ruby installed. Asking them to install it, at the right version, with the right gems, loses most of them before your app starts. And the Ruby on your own computer can't travel with the app: it was built for your machine, with your machine's paths and libraries baked in, so a copy breaks anywhere else.

Fledge starts from a *runtime* instead: a Ruby built to be moved, plus a small launcher that embeds it and runs your app, prebuilt for each platform. `fledge build` copies your app into the runtime for the computer it runs on and archives the result; build on a Mac for macOS, on Windows for Windows, and on Linux for Linux, as CI runners of each can. Whoever downloads it unpacks a folder and runs it. They never meet Ruby.

You build the program you already run: `exe/my_cool_app` in a gem, `bin/server` in an app with a Gemfile, or a lone `main.rb`. Its project ships with it, and so do the gems its `Gemfile.lock` locks, each as built for the platform it ships to, which Bundler sets up before your program runs, as `bundle exec` would. Your code runs the same either way: the same requires, the same globals, the same standard library, bundled gems, and locked gems.

## Status

Fledge is a walking skeleton under construction, and its latest pre-release is `v0.0.1.pre.7`. `fledge build` builds apps for macOS on Apple Silicon (`arm64-darwin`), for Linux with glibc 2.39 or newer (`x86_64-linux`, `aarch64-linux`), and for 64-bit Windows 10 and 11 (`x64-mingw-ucrt`), each on a computer of that platform. [Plan 001](doc/contributors/plan/001.md)'s walking skeleton shipped a "hello" app for macOS, Linux, and Windows, run on fresh machines with no Ruby; [Plan 002](doc/contributors/plan/002.md) is the road to 1.0, and Fledge now ships gem-shaped apps with their gems ([ADR 005](doc/contributors/adr/005.md)), compiling those that need it on the platform they are for and taking gems from git ([ADR 006](doc/contributors/adr/006.md)), whatever their licenses, which are the developer's to judge ([ADR 007](doc/contributors/adr/007.md)), as console or windowed apps that show the name, icon, and version their developer chose ([ADR 008](doc/contributors/adr/008.md)), and windowed apps with installers for every platform, a disk image, an NSIS setup program, and an AppImage ([ADR 009](doc/contributors/adr/009.md)), each built on its own platform with that platform's own tools ([ADR 010](doc/contributors/adr/010.md)). [ADR 001](doc/contributors/adr/001.md) records what Fledge is and why.

## Installing

Fledge is not on RubyGems.org, and never will be under this plan. Each release is a git tag, such as `v0.0.1.pre.7`, with a [GitHub Release](https://github.com/setdef/Fledge/releases) that carries its runtimes, so take the gem from its tag:

<!-- SPDX-SnippetBegin -->
<!--
  SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
  SPDX-License-Identifier: MIT-0
-->
```ruby
# Gemfile
gem "fledge", git: "https://github.com/setdef/Fledge", tag: "v0.0.1.pre.7"
```
<!-- SPDX-SnippetEnd -->

Then `bundle install`, and run it as `bundle exec fledge`. Fledge needs Ruby 4.0, and on each platform what that platform's apps are made with ([ADR 010](doc/contributors/adr/010.md)):

- **macOS 14 or newer** on Apple Silicon: nothing more. `tar`, `plutil`, `codesign`, `ditto`, and `hdiutil` come with macOS.
- **Windows 10 or 11** (x64): nothing more. Windows' own `tar.exe` writes the `.zip`, and the Windows runtime brings [rcedit](https://github.com/electron/rcedit), which writes a program's version information and icon, and [NSIS](https://nsis.sourceforge.io/), which compiles a setup program.
- **Linux** with glibc 2.39 or newer: `tar`, and, for a windowed app's AppImage, squashfs-tools' `mksquashfs` 4.4 or newer (`sudo apt install squashfs-tools`, `sudo dnf install squashfs-tools`).

To compile a gem with an extension you also need a compiler: Xcode's command line tools on macOS (`xcode-select --install`), a C compiler and `make` on Linux, RubyInstaller's MSYS2 tools (`ridk install`) on Windows, and cargo for a Rust gem. A missing tool fails the build, naming it and what to install. The first `fledge build` for a platform downloads that version's runtime from its GitHub Release into `~/.cache/fledge/runtimes` (or `$XDG_CACHE_HOME/fledge/runtimes`), checked against the release's `SHA256SUMS`; later builds use the cache. With `FLEDGE_RUNTIME_DIR` naming a folder of runtimes, it uses those instead.

## Using Fledge

Building looks like this:

<!-- SPDX-SnippetBegin -->
<!--
  SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
  SPDX-License-Identifier: MIT-0
-->
```bash
cd my_cool_app       # a gem: my_cool_app.gemspec, Gemfile, Gemfile.lock, exe/my_cool_app
bundle lock --add-platform arm64-darwin x86_64-linux aarch64-linux x64-mingw-ucrt
fledge build exe/my_cool_app              # on a Mac
ls dist
# MyCoolApp-arm64-darwin/      MyCoolApp-arm64-darwin.tar.gz
./dist/MyCoolApp-arm64-darwin/MyCoolApp   # on a Mac, with or without Ruby
```
<!-- SPDX-SnippetEnd -->

Platforms use RubyGems' names. Build on each platform you ship to, as Tauri and Briefcase do: each one's app is made with that system's own tools ([ADR 010](doc/contributors/adr/010.md)). `fledge build` with no path builds the one executable your gemspec names, or a folder's `main.rb`. The project is the nearest folder, from your program's up, with a `Gemfile`, `gems.rb`, gemspec, or `fledge.yml`; everything in it ships but `.git`, `.bundle`, `vendor/bundle`, `vendor/cache`, and the build's output. The app's name is your gemspec's name, or else the project folder's, camelized (`my_cool_app` is `MyCoolApp`). `fledge --help` (or `-h`, or `-?`) prints the full usage, and `fledge -v` the version. `fledge` exits 0 when it succeeds, 1 when a build fails, and 2 when it cannot make sense of its arguments. [examples/hello](examples/hello) is a lone script, [examples/my_cool_app](examples/my_cool_app) a gem with a pure-Ruby and a native dependency, and [examples/windowed_app](examples/windowed_app) a windowed app with an icon; CI builds all three on a runner of each platform. [examples/native_app](examples/native_app) needs a C gem published only as source, a Rust gem from git, ratatui_ruby, precompiled for three platforms and compiled for the fourth, and spreadsheet, a GPL gem, and [examples/nokogiri_app](examples/nokogiri_app) nokogiri compiled from source; CI builds each on the platform it is for.

Your `Gemfile.lock` must lock each platform you build for (`bundle lock --add-platform`) and each gem's checksum, which Bundler 4 does and `bundle lock --add-checksums` adds. Fledge leaves out the `development` and `test` groups, and downloads each gem's build for each platform from your lockfile's gem server, checked against its checksum, into `~/.cache/fledge/gems` (it looks in `vendor/cache` first, where `bundle cache --all-platforms` keeps them). A gem may be pure Ruby or locked precompiled for the platform, as sqlite3 and many other native gems are published. A gem with an extension to compile, one published only as source (redcarpet) or a Rust gem built with rb-sys (Tokra's, Ferro's), is compiled as you build, against the runtime's own Ruby, with your compiler (cargo, with libclang, for rb-sys); `bundle config build.NAME` options reach its `extconf.rb` ([ADR 006](doc/contributors/adr/006.md)). A precompiled build is always taken when there is one that fits; compiling only fills the gaps. Gems from git ship at the commit your lockfile locks, fetched into `~/.cache/fledge/git`. Fledge takes no position on your gems' licenses ([ADR 007](doc/contributors/adr/007.md)): every gem ships with its own files and notices, whatever its license and whatever its compiled files hold, and whether those licenses suit your app is yours to decide. Fledge refuses a gem only when it would not run where the app goes, such as a compiled file that needs a library the computer it goes to may not have. Most projects need no configuration. A `fledge.yml` at the project's root says what Fledge cannot know: whether your app opens windows, and how it presents itself to the people who run it ([ADR 008](doc/contributors/adr/008.md)):

<!-- SPDX-SnippetBegin -->
<!--
  SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
  SPDX-License-Identifier: MIT-0
-->
```yaml
# fledge.yml
name: Cool App                       # default: the gemspec's name, or the folder's, camelized
kind: windowed                       # or console, the default
identifier: com.example.CoolApp      # reverse-DNS; a windowed app needs one
version: "1.2.3"                     # default: the gemspec's, or 0.0.0
icon: icons/app                      # icons/app.icns, icons/app.ico, icons/app-16.png to -512.png
publisher: Example, Inc.             # default: the gemspec's authors
copyright: © 2026 Example, Inc.
installers: [dmg, nsis, appimage]    # the default for a windowed app; [] for none
```
<!-- SPDX-SnippetEnd -->

A *console* app runs in a terminal. A *windowed* app opens its own windows and shows no terminal: on macOS it is an `.app` bundle, `Cool App.app`, with your name, icon, version, and identifier in its `Info.plist`, signed ad hoc so it runs on Apple Silicon and passes `codesign --verify --strict --deep`; on Windows it is a program Windows starts without a console, which makes your identifier its AppUserModelID; on Linux it is the same folder with a desktop entry, `com.example.CoolApp.desktop`, and your icon in `share/icons/hicolor/`. Every Windows app, console or windowed, carries your name, version, publisher, copyright, and icon in its program, where Explorer and Task Manager show them. Your icon comes in each system's own format, named as Briefcase names them: `icons/app.icns` for macOS (`iconutil -c icns` makes one from PNGs), `icons/app.ico` for Windows, with images of 16, 32, 48, 64, and 256 pixels, and `icons/app-16.png`, `-32`, `-64`, `-128`, `-256`, and `-512` for Linux; each platform's build takes its own, made with that platform's tools. A windowed app built with Fledge is still unsigned for Gatekeeper and SmartScreen, which signing with your own credentials will address.

A windowed app also gets an installer beside each archive ([ADR 009](doc/contributors/adr/009.md)), made with its platform's own tools ([ADR 010](doc/contributors/adr/010.md)): `Cool App-arm64-darwin.dmg`, a disk image `hdiutil` makes of `Cool App.app`, still signed, and a link to Applications to drag it onto; `Cool App-x64-mingw-ucrt-setup.exe`, an NSIS installer, compiled by the NSIS the Windows runtime carries and compressed with LZMA, that installs for the person who runs it, with no administrator, into `%LOCALAPPDATA%\Programs\Cool App`, makes a Start menu shortcut whose AppUserModelID is your identifier, which Windows needs before it shows your app's notifications, offers a desktop shortcut (unchecked), registers an uninstaller in Settings, and installs silently with `/S`; and `Cool App-x86_64-linux.AppImage` (and `aarch64-linux`), one file that runs on any distribution once it is executable (`chmod +x`), with AppImage's own runtime at its front and a file system `mksquashfs` wrote, which mounts itself with FUSE, as every AppImage does, and on a computer with no FUSE runs with `APPIMAGE_EXTRACT_AND_RUN=1`. `installers: [dmg]` in `fledge.yml` builds only those you list, and `installers: []` none; a console app gets none.

A built app is a folder (on macOS, for a windowed app, a folder holding the bundle, whose `Contents/Resources` holds the rest): the program, named for your app (`MyCoolApp.exe` on Windows), and `fledge.cfg`, which says what it runs; your project in `app/`; Ruby, with its standard library, default gems, bundled gems, your app's gems, and its own `ruby` program, in `bin/` and `lib/` on macOS and Linux and in `ruby\` on Windows; and the licenses of everything Fledge put there, with an SBOM, in `notices/` (each gem keeps its own notices in its own folder). It ships as a `.zip` for Windows, which opens with a double-click, and as a `.tar.gz` elsewhere, which keeps the program executable. Whoever runs it needs no Ruby, and a Ruby they do have (`RUBYOPT`, `GEM_HOME`, `BUNDLE_GEMFILE`, `~/.bundle/config`, gems in `~/.gem`, and the rest) does not change how your app starts or which gems it loads. Your app's `ENV`, and any Ruby it starts through `RbConfig.ruby`, still see their settings, as under `ruby main.rb`, with Bundler's over them for your bundle, as under `bundle exec`, where `Bundler.with_original_env` and `with_unbundled_env` give them back whole. The program exits with your app's status, or with 66 when its program is missing and 70 when the rest of the folder is broken.

Game, desktop, and terminal frameworks (Lota, Tokra, and Rooibos) are expected to call Fledge for their own packaging commands.

## What ships in your app, and what it asks of you

Everything Fledge copies into your app besides your own code and gems is either under a permissive license (MIT, BSD, Apache-2.0, Zlib, Ruby's, and the like), or is one of two libraries under the LGPL, each shipped as a separate shared library that whoever receives your app may replace: libxcrypt in Linux apps, and GNU MP in Windows apps. A Linux app's AppImage begins with AppImage's own runtime, which has a third, libfuse, linked in; it is not your app, and Fledge publishes its source and libfuse's, as the LGPL asks. A Windows app's setup program is compressed with NSIS's LZMA module, under the Common Public License, which asks only that its source be available, and Fledge publishes NSIS's. Fledge never needs your app's source or object files. Fledge publishes the exact source of each of these with every release, and keeps every release published. Your app's own gems are another matter: which gems you use, and what their licenses ask of you, are your choice and your responsibility, and `fledge build` ships each one with its own notices, whatever its license (`bundle licenses` lists them). The launcher, the program your users run, and the RubyGems defaults Fledge adds are Fledge's own code, under the AGPL-3.0-or-later; a commercial license will likely be offered for apps that don't want to follow the AGPL.

Every built app carries `notices/NOTICES.txt`, with every component, its license, and the full text of each license, and `notices/sbom.spdx.json`, an SPDX 2.3 software bill of materials. [doc/licensing.md](doc/licensing.md) lists, per platform, what ships and what each license asks of you, with the sections it comes from. CI writes all three from a license audit that every runtime must pass before it is archived, and fails when the page goes stale ([ADR 004](doc/contributors/adr/004.md)). They state facts, not legal advice: ask your own lawyer what any license requires of you.

## Development

```bash
git clone https://github.com/setdef/Fledge.git
cd Fledge
bin/setup
bundle exec rake
```

`bin/setup` installs the tools pinned in `mise.toml` (Ruby, the REUSE tool, actionlint, shellcheck, and clang-format), installs the bundle, and installs the pre-commit hook. `bundle exec rake` is the gate: it fixes what RuboCop and the REUSE tool can fix, then runs the tests, RuboCop, RubyCritic, RDoc coverage, REUSE, actionlint and shellcheck over the workflows and shellcheck over `bin/setup` and `.github/scripts`, clang-format over the launcher's C, signature checks (no `untyped`, `rbs validate`, and parity between `sig/` and `lib/`), Steep, and the package check, which builds the gem, installs it into an empty `GEM_HOME`, and runs `fledge` from there. It passes with zero errors and zero warnings.

`bundle exec rake runtime` builds this computer's runtime into `tmp/runtime/` from the sources pinned in `runtime/sources.yml`, with the release assets that describe it beside it, and `FLEDGE_RUNTIME_DIR=tmp/runtime` makes `fledge build` use it; it needs a C compiler, and on Linux `make`, `perl`, and `patchelf`; the Linux runtime carries AppImage's released runtime, and the Windows runtime NSIS's release and rcedit, each downloaded and checked against its pinned SHA-256. `bundle exec rake "runtime[x64-mingw-ucrt]"` builds the Windows runtime on macOS or Linux, with a pinned llvm-mingw it downloads; it needs `gpgv` (GnuPG), to check RubyInstaller's signature, and `7z` or `bsdtar`. With a runtime there, `bundle exec rake test` also builds `examples/hello` and `examples/my_cool_app` (downloading its gems) and runs them in a clean and a hostile environment, and `bundle exec rake parity` builds the probe in `test/fixtures/parity` and compares what it sees with `ruby main.rb` on the Ruby the runtime came from, then builds it as `examples/my_cool_app`'s program and compares it with `bundle exec` ([ADR 003](doc/contributors/adr/003.md), [ADR 005](doc/contributors/adr/005.md)). The launcher's C is in `runtime/launcher/`.

GitHub Actions runs `.github/workflows/ci.yml` on every push and pull request. The **Gate** job runs `bundle exec rake` on Linux and fails if the gate changed a file. The **Runtime** jobs build a runtime on macOS 15 (Apple Silicon), Ubuntu 24.04, and Ubuntu 24.04 on arm64, and the Windows runtime, whose launcher a pinned llvm-mingw cross-compiles, on Ubuntu 24.04, each with its build-only companion of Ruby's headers and libraries. The **Test** jobs run the tests and the parity check on each platform, Windows included, with its runtime. The **Build** jobs build `examples/hello`, `examples/my_cool_app`, `examples/windowed_app`, the parity probes, and `examples/native_app` (redcarpet, compiled from source, ferro-idna, a Rust gem from git, ratatui_ruby, and spreadsheet) on a runner of each platform, as a developer on that platform would, and `examples/nokogiri_app` on macOS and Windows; and the **Delivery** jobs run each on a fresh runner, and in Debian 13 containers with no Ruby installed, with `.github/scripts/deliver.sh`, or on Windows `.github/scripts/deliver.ps1`, and the windowed app with `.github/scripts/deliver-windowed.sh` (codesign, plutil, and `open -W` on macOS, desktop-file-validate on Linux) and `deliver-windowed.ps1` (its version information, icon, subsystem, and AppUserModelID on Windows), and its installers: `deliver-dmg.sh` attaches the disk image, verifies the bundle in it, drags it to an Applications folder, and runs it; `deliver-installer.ps1` installs the setup program silently, reads back its Start menu shortcut's AppUserModelID through the shell's IPropertyStore, starts the app from that shortcut, checks the app's own AppUserModelID matches, reinstalls, and uninstalls; and `deliver-appimage.sh` runs the AppImage mounted with FUSE on Ubuntu, and in Debian containers, with no FUSE, checks that it says so and runs it extracted with `APPIMAGE_EXTRACT_AND_RUN=1`. Every runtime build runs the license audit (`tasks/license_audit.rb`, against `runtime/licenses.yml`), and refuses to archive a runtime that breaks the policy. The **Licenses** jobs validate each runtime's SBOM with the SPDX tools and prove the audit still fails when a GPL library and a GPL gem are slipped in; the **Licenses of the whole upstream tree** jobs audit rv-ruby's and RubyInstaller's whole trees, which must fail exactly as `.github/license-expectations/` says; **Licensing page is current** regenerates `doc/licensing.md` from the four runtimes (`bundle exec rake "licensing[DIR]"` does it locally) and fails if it differs; and **Replace libcrypt** and **Replace GMP** prove that whoever receives an app can replace its LGPL libraries. `.github/workflows/release.yml` publishes the runtimes, their SBOMs and NOTICES, the source bundles, and `SHA256SUMS` to a GitHub Release when a `v*` tag is pushed, then `.github/workflows/installed.yml` installs Fledge from that tag on a fresh runner of each platform and builds and delivers the examples, and installs the windowed app's installer, with what it downloads from the release.

Contributors, people and agents alike, start with [AGENTS.md](AGENTS.md) and the [documentation style guide](doc/contributors/documentation_style.md). The maintainer's decisions are in [doc/contributors/decisions.md](doc/contributors/decisions.md), open questions in [doc/contributors/questions.md](doc/contributors/questions.md), and the road to 1.0 in [Plan 002](doc/contributors/plan/002.md).

## Copyright & License

Fledge is copyright 2026, Kerrick Long. The code is [AGPL-3.0-or-later](LICENSES/AGPL-3.0-or-later.txt), the launcher and the other files Fledge copies into your app included, the documentation is [CC-BY-SA-4.0](LICENSES/CC-BY-SA-4.0.txt), and code examples in the documentation are [MIT-0](LICENSES/MIT-0.txt). Code adapted from elsewhere, such as Ruby's own `main.c`, keeps its source's license, marked with SPDX snippets. A commercial license is likely to be offered for apps that don't want to follow the AGPL. Each built app carries the licenses of the Ruby and libraries inside it in `notices/NOTICES.txt`, and [doc/licensing.md](doc/licensing.md) spells out, per platform, what each asks of you. Ask your own lawyer what any license requires of you.
