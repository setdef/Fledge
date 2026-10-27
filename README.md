<!--
  SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
  SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Fledge

[![Certified Shovelware](https://justin.searls.co/img/shovelware.svg)](https://justin.searls.co/shovelware/)
[![CI](https://github.com/setdef/Fledge/actions/workflows/ci.yml/badge.svg?branch=trunk)](https://github.com/setdef/Fledge/actions)

Fledge ships a Ruby app to people who don't have Ruby.

Almost nobody who would play your game, open your desktop app, or run your terminal tool has Ruby installed. Asking them to install it, at the right version, with the right gems, loses most of them before your app starts. And the Ruby on your own computer can't travel with the app: it was built for your machine, with your machine's paths and libraries baked in, so a copy breaks anywhere else.

Fledge starts from a *runtime* instead: a Ruby built to be moved, plus a small launcher that embeds it and runs your app, prebuilt for each platform. `fledge build` copies your app into the runtime for each platform you ask for and archives the result. Whoever downloads it unpacks a folder and runs it. They never meet Ruby.

An app is a folder with a `main.rb`. During development, run it with `ruby main.rb`; build it to ship it. Your code runs the same either way: the same requires (load your own files with `require_relative`), the same globals, the same standard library and bundled gems.

## Status

Fledge is a walking skeleton under construction, and its first pre-release is `v0.0.1.pre.1`. `fledge build` builds apps for macOS on Apple Silicon (`arm64-darwin`), for Linux with glibc 2.39 or newer (`x86_64-linux`, `aarch64-linux`), and for 64-bit Windows 10 and 11 (`x64-mingw-ucrt`), from any of them. The first goal is an app that does nothing: [Plan 001](doc/contributors/plan/001.md) ships a "hello" app for macOS, Linux, and Windows, run on fresh machines with no Ruby, before Fledge does anything more useful. [ADR 001](doc/contributors/adr/001.md) records what Fledge is and why.

## Installing

Fledge is not on RubyGems.org, and never will be under this plan. Each release is a git tag, such as `v0.0.1.pre.1`, with a [GitHub Release](https://github.com/setdef/Fledge/releases) that carries its runtimes, so take the gem from its tag:

<!-- SPDX-SnippetBegin -->
<!--
  SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
  SPDX-License-Identifier: MIT-0
-->
```ruby
# Gemfile
gem "fledge", git: "https://github.com/setdef/Fledge", tag: "v0.0.1.pre.1"
```
<!-- SPDX-SnippetEnd -->

Then `bundle install`, and run it as `bundle exec fledge`. Fledge needs Ruby 4.0. The first `fledge build` for a platform downloads that version's runtime from its GitHub Release into `~/.cache/fledge/runtimes` (or `$XDG_CACHE_HOME/fledge/runtimes`), checked against the release's `SHA256SUMS`; later builds use the cache. With `FLEDGE_RUNTIME_DIR` naming a folder of runtimes, it uses those instead.

## Using Fledge

Building looks like this:

<!-- SPDX-SnippetBegin -->
<!--
  SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
  SPDX-License-Identifier: MIT-0
-->
```bash
cd my_app            # a folder with a main.rb
fledge build -t arm64-darwin -t x86_64-linux -t aarch64-linux -t x64-mingw-ucrt
ls dist
# my_app-aarch64-linux/     my_app-aarch64-linux.tar.gz
# my_app-arm64-darwin/      my_app-arm64-darwin.tar.gz
# my_app-x64-mingw-ucrt/    my_app-x64-mingw-ucrt.zip
# my_app-x86_64-linux/      my_app-x86_64-linux.tar.gz
./dist/my_app-arm64-darwin/my_app   # on a Mac, with or without Ruby
```
<!-- SPDX-SnippetEnd -->

Targets use RubyGems' platform names. `fledge --help` (or `-h`, or `-?`) prints the full usage, and `fledge -v` the version. `fledge` exits 0 when it succeeds, 1 when a build fails, and 2 when it cannot make sense of its arguments.

A built app is a folder: the program, named for your app (`my_app.exe` on Windows); your app in `app/`; Ruby, with its standard library, default gems, bundled gems, and its own `ruby` program, in `bin/` and `lib/` on macOS and Linux and in `ruby\` on Windows; and the licenses of everything Fledge put there, with an SBOM, in `notices/`. It ships as a `.zip` for Windows, which opens with a double-click, and as a `.tar.gz` elsewhere, which keeps the program executable. Whoever runs it needs no Ruby, and a Ruby they do have (`RUBYOPT`, `GEM_HOME`, gems in `~/.gem`, and the rest) does not change how your app starts or which gems it loads. Your app's `ENV`, and any Ruby it starts through `RbConfig.ruby`, still see their settings, as under `ruby main.rb`. The program exits with your app's status, or with 66 when its `app/main.rb` is missing and 70 when the rest of the folder is broken.

Game, desktop, and terminal frameworks (Lota, Tokra, and Rooibos) are expected to call Fledge for their own packaging commands.

## What ships in your app, and what it asks of you

Everything Fledge copies into your app besides your own code is either under a permissive license (MIT, BSD, Apache-2.0, Zlib, Ruby's, and the like), or is one of two libraries under the LGPL, each shipped as a separate shared library that whoever receives your app may replace: libxcrypt in Linux apps, and GNU MP in Windows apps. Fledge never needs your app's source or object files. Fledge publishes the exact source of both LGPL libraries with every release, and keeps every release published. The launcher, the program your users run, and the RubyGems defaults Fledge adds are Fledge's own code, under the AGPL-3.0-or-later; a commercial license will likely be offered for apps that don't want to follow the AGPL.

Every built app carries `notices/NOTICES.txt`, with every component, its license, and the full text of each license, and `notices/sbom.spdx.json`, an SPDX 2.3 software bill of materials. [doc/licensing.md](doc/licensing.md) lists, per platform, what ships and what each license asks of you, with the sections it comes from. CI writes all three from a license audit that every runtime must pass before it is archived, and fails when the page goes stale ([ADR 004](doc/contributors/adr/004.md)). They state facts, not legal advice: ask your own lawyer what any license requires of you.

## Development

```bash
git clone https://github.com/setdef/Fledge.git
cd Fledge
bin/setup
bundle exec rake
```

`bin/setup` installs the tools pinned in `mise.toml` (Ruby, the REUSE tool, actionlint, shellcheck, and clang-format), installs the bundle, and installs the pre-commit hook. `bundle exec rake` is the gate: it fixes what RuboCop and the REUSE tool can fix, then runs the tests, RuboCop, RubyCritic, RDoc coverage, REUSE, actionlint and shellcheck over the workflows and shellcheck over `bin/setup` and `.github/scripts`, clang-format over the launcher's C, signature checks (no `untyped`, `rbs validate`, and parity between `sig/` and `lib/`), Steep, and the package check, which builds the gem, installs it into an empty `GEM_HOME`, and runs `fledge` from there. It passes with zero errors and zero warnings.

`bundle exec rake runtime` builds this computer's runtime into `tmp/runtime/` from the sources pinned in `runtime/sources.yml`, with the release assets that describe it beside it, and `FLEDGE_RUNTIME_DIR=tmp/runtime` makes `fledge build` use it; it needs a C compiler, and on Linux `make`, `perl`, and `patchelf`. `bundle exec rake "runtime[x64-mingw-ucrt]"` builds the Windows runtime on macOS or Linux, with a pinned llvm-mingw it downloads; it needs `gpgv` (GnuPG), to check RubyInstaller's signature, and `7z` or `bsdtar`. With a runtime there, `bundle exec rake test` also builds `examples/hello` and runs it in a clean and a hostile environment, and `bundle exec rake parity` builds the probe in `test/fixtures/parity` and compares what it sees with `ruby main.rb` on the Ruby the runtime came from ([ADR 003](doc/contributors/adr/003.md)). The launcher's C is in `runtime/launcher/`.

GitHub Actions runs `.github/workflows/ci.yml` on every push and pull request. The **Gate** job runs `bundle exec rake` on Linux and fails if the gate changed a file. The **Runtime** jobs build a runtime on macOS 15 (Apple Silicon), Ubuntu 24.04, and Ubuntu 24.04 on arm64, and the Windows runtime, cross-compiled, on Ubuntu 24.04. The **Test** jobs run the tests and the parity check on each platform, Windows included, with its runtime. The **Build** job builds `examples/hello` and the parity probe for all four platforms on one Linux runner, and the **Delivery** jobs run each on a fresh runner, and in Debian 13 containers with no Ruby installed, with `.github/scripts/deliver.sh`, or on Windows `.github/scripts/deliver.ps1`. Every runtime build runs the license audit (`tasks/license_audit.rb`, against `runtime/licenses.yml`), and refuses to archive a runtime that breaks the policy. The **Licenses** jobs validate each runtime's SBOM with the SPDX tools and prove the audit still fails when a GPL library and a GPL gem are slipped in; the **Licenses of the whole upstream tree** jobs audit rv-ruby's and RubyInstaller's whole trees, which must fail exactly as `.github/license-expectations/` says; **Licensing page is current** regenerates `doc/licensing.md` from the four runtimes (`bundle exec rake "licensing[DIR]"` does it locally) and fails if it differs; and **Replace libcrypt** and **Replace GMP** prove that whoever receives an app can replace its LGPL libraries. `.github/workflows/release.yml` publishes the runtimes, their SBOMs and NOTICES, the LGPL source bundles, and `SHA256SUMS` to a GitHub Release when a `v*` tag is pushed, then `.github/workflows/installed.yml` installs Fledge from that tag on a fresh runner of each platform and builds and delivers hello with runtimes downloaded from the release.

Contributors, people and agents alike, start with [AGENTS.md](AGENTS.md) and the [documentation style guide](doc/contributors/documentation_style.md). The maintainer's decisions are in [doc/contributors/decisions.md](doc/contributors/decisions.md), open questions in [doc/contributors/questions.md](doc/contributors/questions.md), and the road to 1.0 in [Plan 002](doc/contributors/plan/002.md).

## Copyright & License

Fledge is copyright 2026, Kerrick Long. The code is [AGPL-3.0-or-later](LICENSES/AGPL-3.0-or-later.txt), the launcher and the other files Fledge copies into your app included, the documentation is [CC-BY-SA-4.0](LICENSES/CC-BY-SA-4.0.txt), and code examples in the documentation are [MIT-0](LICENSES/MIT-0.txt). Code adapted from elsewhere, such as Ruby's own `main.c`, keeps its source's license, marked with SPDX snippets. A commercial license is likely to be offered for apps that don't want to follow the AGPL. Each built app carries the licenses of the Ruby and libraries inside it in `notices/NOTICES.txt`, and [doc/licensing.md](doc/licensing.md) spells out, per platform, what each asks of you. Ask your own lawyer what any license requires of you.
