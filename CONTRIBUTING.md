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

Install [mise](https://mise.jdx.dev/) and run `bin/setup`. It installs the tools `mise.toml` pins, each by version, and the gems the `Gemfile.lock` locks. Fledge runs on the Ruby its runtimes come from: on macOS and Linux, the Ruby release `runtime/sources.yml` names, from jdx/ruby's builds, which mise downloads and never compiles; on Windows, until RubyInstaller builds that release, the very archive of RubyInstaller's head build the Windows runtimes are built from, which mise downloads from Fledge's `inputs-rubyinstaller-head-*` pre-release and checks against the SHA-256 that `runtime/sources.yml` pins, with the two MSYS2 DLLs that build needs and lacks, pinned the same way. mise also installs, on Windows, the MSYS2 that compiles a gem's C for RubyInstaller's Ruby, the build of it that ruby/setup-ruby uses, pinned to one day's release, and points RubyInstaller at it with `MSYS2_PATH`. Run `bin/setup` there from a bash, such as Git's.

mise puts that Ruby first on `PATH` only in a shell it has activated (`eval "$(mise activate zsh)"`, or bash's, in your shell's startup file), and only once that shell is in this folder; there `ruby -v` prints the version `mise.toml` pins. A script, an editor's task, or an agent's shell runs none of the hooks `mise activate` installs, so it keeps whatever Ruby its `PATH` already had, and `bundle exec` there stops with Bundler's stack trace, because the gemspec needs that very Ruby. Start each command there with `mise x --`, as `bin/setup` does: `mise x -- bundle exec rake`.

`bundle exec rake runtime` builds this computer's runtime, which the gate otherwise skips the checks of. On Linux it needs a C compiler, binutils, make, perl, and xz from your system, and patchelf 0.18.0, which mise installs from `mise.toml`, pinned by SHA-256.

Run `bundle exec rake rubocop:autocorrect_all`, then `bundle exec rake`. The second command is the gate: it runs every test, and must pass with zero errors and zero warnings.

### Android on Linux

On an x86-64 Linux computer with KVM (`/dev/kvm`, which your user can read and write), you can build the Android runtime and Android apps, and run them on an emulator, as CI's Runtime (android) and Mobile apps (Android emulator) jobs do. `mise.android.toml` pins what that needs, each by its SHA-256: Temurin's JDK 21, the NDK the Android runtime is built with, and the packages of Android's SDK CI uses (platform-tools, the API 36 platform, build-tools, the emulator, and the API 36 system images with 4 KB and 16 KB pages). mise reads it only when `MISE_ENV` is `android`, so `mise install` leaves out its five gigabytes otherwise. `bin/android-sdk` lays its packages out as one SDK in `tmp/android/sdk`, which `ANDROID_HOME` names, and downloads nothing. `bin/android-emulator TARGET -- COMMAND` boots an API 36 emulator with no window from the system image `google_apis` (4 KB pages) or `google_apis_ps16k` (16 KB), runs the command, and shuts it down.

```sh
export MISE_ENV=android
mise install
mise x -- bin/android-sdk
mise x -- ruby tasks/runtime_builder.rb x86_64-linux   # whose Ruby compiles a gem's extension for the phone
mise x -- ruby tasks/runtime_builder.rb android
mise x -- bash -c 'BUNDLETOOL=$(ruby .github/scripts/fetch_pin.rb mobile bundletool) ruby tasks/mobile_parity.rb android-build tmp/runtime'
mise x -- bash -c 'BUNDLETOOL=$(ruby .github/scripts/fetch_pin.rb mobile bundletool) bin/android-emulator google_apis -- ruby tasks/mobile_parity.rb android'
```

## The tests

Fledge's tests come in two tiers, by folder, as Rails keeps its system tests in `test/system` and Hanami and dry-rb keep `spec/unit` apart from `spec/integration`.

- **Unit tests** are every test file under `test/` but those in `test/integration/`. Each runs in milliseconds, in the test's own Ruby process, on any computer, with or without a runtime. It may write a temporary folder, read the repository, serve a `LoopbackServer` in its own process, and run a short-lived tool such as tar. It builds no runtime, reads none that `rake runtime` built, builds no app that it then runs, compiles nothing, starts no Ruby or shell script, runs no signing or disk image tool, and reaches nothing past this computer. A wait the code under test would make, such as a retry's, is made short by passing the waits in, as `Fledge::Download` and `Fledge::Dmg` take them.
- **Integration tests**, in `test/integration/`, are the rest: a real runtime, a built app run as a person runs it, a compiler, `exe/fledge` or a script in a process of its own, codesign, hdiutil, makensis, gpg, a repository that git makes, or the network. They take seconds, some take minutes, and many skip on a computer without what they need.

A new test file is a unit test unless you put it in `test/integration/`. When a unit test needs one of the things above, or takes more than about a tenth of a second on your computer, make it fast without weakening it, or move it. Tests of one class can be in both tiers: `test/assembly_test.rb` and `test/integration/assembly_tools_test.rb` share `test/support/assembly.rb`.

While you work:

- `bundle exec rake test` runs the unit tests, in seconds. Run it as often as you like. CI's fast tier, `.github/workflows/fast.yml`, runs them on Linux, macOS, and Windows on every push.
- `bundle exec rake test:integration` runs the integration tests, and `bundle exec rake test:all` runs both, as the gate and CI do. Build a runtime first (`bundle exec rake runtime`), or the tests that need one skip.
- `bundle exec rake test TEST=test/foo_test.rb` runs just that file, of either tier; several files, or globs, go comma-separated.
- `N=/name/` runs just the tests whose names match, and `A=-v` names each test with its time as it runs.
