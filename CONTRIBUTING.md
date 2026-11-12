<!--
  SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
  SPDX-License-Identifier: CC-BY-SA-4.0
-->
# Contributing

Fledge's code, tests, and documents are written by LLM agents at the maintainer's direction. The gates in CI, and the Delivery jobs that run a built app on a clean computer, are the review.

## Ask for what you want

Open an [issue](https://github.com/setdef/Fledge/issues). Describe the problem or the feature, the platform you build on, the platform you run on, and what `bundle exec fledge --version` prints. The maintainer decides what Fledge does, and an agent builds it.

## Work on Fledge

Start with [AGENTS.md](AGENTS.md), which is binding, then read:

- [`doc/contributors/handoff.md`](doc/contributors/handoff.md): where the project stands, how to check it, and how to release it.
- [`doc/contributors/decisions.md`](doc/contributors/decisions.md): the maintainer's own words, which are the only authority.
- [`doc/contributors/plan/`](doc/contributors/plan): the plans, with the current one last.
- [`doc/contributors/adr/`](doc/contributors/adr): the decisions behind each behavior.
- [`doc/contributors/documentation_style.md`](doc/contributors/documentation_style.md): how to write the documents.

Install [mise](https://mise.jdx.dev/) and run `bin/setup`. It installs the tools `mise.toml` pins, each by version, and the gems the `Gemfile.lock` locks. Fledge runs on the Ruby its runtimes come from: on macOS and Linux, the Ruby release `runtime/sources.yml` names, from jdx/ruby's builds; on Windows, until RubyInstaller builds that release, the very archive of RubyInstaller's head build the Windows runtimes are built from, which mise downloads from Fledge's `inputs-rubyinstaller-head-*` pre-release and checks against the SHA-256 that `runtime/sources.yml` pins, with the two MSYS2 DLLs that build needs and lacks, pinned the same way. mise also installs, on Windows, the MSYS2 that compiles a gem's C for RubyInstaller's Ruby, the build of it that ruby/setup-ruby uses, pinned to one day's release, and points RubyInstaller at it with `MSYS2_PATH`. Run `bin/setup` there from a bash, such as Git's.

`bundle exec rake runtime` builds this computer's runtime, which the gate otherwise skips the checks of. On Linux it needs a C compiler, binutils, make, perl, and xz from your system, and patchelf 0.18.0, which mise installs from `mise.toml`, pinned by SHA-256.

Run `bundle exec rake rubocop:autocorrect_all`, then `bundle exec rake`. The second command is the gate: it must pass with zero errors and zero warnings. While you work, `bundle exec rake test TEST=test/foo_test.rb` runs just that file.
