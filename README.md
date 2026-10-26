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

An app is a folder with a `main.rb`. During development, run it with your own Ruby; build it to ship it.

## Status

Fledge is a walking skeleton under construction. `fledge --help` and `fledge --version` work; `fledge build` says it is not yet implemented. The first goal is an app that does nothing: [Plan 001](doc/contributors/plan/001.md) ships a "hello" app for macOS, Linux, and Windows, run on fresh machines with no Ruby, before Fledge does anything more useful. [ADR 001](doc/contributors/adr/001.md) records what Fledge is and why.

Fledge is not on RubyGems.org, and never will be under this plan. Releases are git tags and [GitHub Releases](https://github.com/setdef/Fledge/releases).

## Using Fledge

Once `fledge build` works, building looks like this:

<!-- SPDX-SnippetBegin -->
<!--
  SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
  SPDX-License-Identifier: MIT-0
-->
```bash
cd my_app            # a folder with a main.rb
fledge build -t arm64-darwin -t x86_64-linux -t x64-mingw-ucrt
ls dist
# my_app-arm64-darwin/      my_app-arm64-darwin.tar.gz
# my_app-x86_64-linux/      my_app-x86_64-linux.tar.gz
# my_app-x64-mingw-ucrt/    my_app-x64-mingw-ucrt.zip
```
<!-- SPDX-SnippetEnd -->

Targets use RubyGems' platform names. `fledge --help` prints the full usage.

Game, desktop, and terminal frameworks (Lota, Tokra, and Rooibos) are expected to call Fledge for their own packaging commands.

## Development

```bash
git clone https://github.com/setdef/Fledge.git
cd Fledge
bin/setup
bundle exec rake
```

`bin/setup` installs the tools pinned in `mise.toml` (Ruby, the REUSE tool, actionlint, and shellcheck), installs the bundle, and installs the pre-commit hook. `bundle exec rake` is the gate: it fixes what RuboCop and the REUSE tool can fix, then runs the tests, RuboCop, RubyCritic, RDoc coverage, REUSE, actionlint and shellcheck over the workflows and shellcheck over `bin/setup`, signature checks (no `untyped`, `rbs validate`, and parity between `sig/` and `lib/`), Steep, and the package check, which builds the gem, installs it into an empty `GEM_HOME`, and runs `fledge` from there. It passes with zero errors and zero warnings.

GitHub Actions runs `.github/workflows/ci.yml` on every push and pull request. The **Gate** job runs `bundle exec rake` on Linux and fails if the gate changed a file. The **Test** jobs run the tests on macOS 15 (Apple Silicon), Windows, and Linux.

Contributors, people and agents alike, start with [AGENTS.md](AGENTS.md) and the [documentation style guide](doc/contributors/documentation_style.md). Open questions for the maintainer live in [doc/contributors/questions.md](doc/contributors/questions.md).

## Copyright & License

Fledge is copyright 2026, Kerrick Long. The code is [AGPL-3.0-or-later](LICENSES/AGPL-3.0-or-later.txt), the documentation is [CC-BY-SA-4.0](LICENSES/CC-BY-SA-4.0.txt), and code examples in the documentation are [MIT-0](LICENSES/MIT-0.txt). Which license the launcher and the other files Fledge copies into your app will carry is an [open question](doc/contributors/questions.md).
