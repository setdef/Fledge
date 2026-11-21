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

Install git and [mise](https://mise.jdx.dev/), 2026.10.11 or later, the mise CI runs; you need nothing else, not even a Ruby. Then run `bin/setup`. It installs the tools `mise.toml` pins, each by version, and the gems the `Gemfile.lock` locks, and builds the API documentation. Like a Rails app's `bin/setup`, it is safe to run at any time ([Rails' template](https://github.com/rails/rails/blob/v8.0.2/railties/lib/rails/generators/rails/app/templates/bin/setup.tt#L10-L11)): once it has run, it installs nothing, asks nothing, and finishes in seconds, and it needs no administrator's rights. It runs no `mise trust`, because `mise install` and `mise exec` trust this folder's `mise.toml` themselves, and record that trust as `mise trust` would: running them is already your decision to run the project's code ([mise's security page, "Implicit trust"](https://mise.jdx.dev/security.html#implicit-trust)). So read `mise.toml` before your first run if you want to know what that decision covers: beyond the downloads it pins, it sets environment variables from its `[env]` table and the files in `.config/mise/`, and on Linux runs your C compiler once to find its headers. Fledge runs on the Ruby its runtimes come from: on macOS and Linux, the Ruby release `runtime/sources.yml` names, from jdx/ruby's builds, which mise downloads and never compiles; on Windows, until RubyInstaller builds that release, the very archive of RubyInstaller's head build the Windows runtimes are built from, which mise downloads from Fledge's `inputs-rubyinstaller-head-*` pre-release and checks against the SHA-256 that `runtime/sources.yml` pins, with the two MSYS2 DLLs that build needs and lacks, pinned the same way. mise also installs, on Windows, the MSYS2 that compiles a gem's C for RubyInstaller's Ruby, the build of it that ruby/setup-ruby uses, pinned to one day's release, and points RubyInstaller at it with `MSYS2_PATH`. Run `bin/setup` there from a bash, such as Git's, or `bin\setup.ps1` from PowerShell, which does the same.

mise puts that Ruby first on `PATH` only in a shell it has activated (`eval "$(mise activate zsh)"`, or bash's, in your shell's startup file), and only once that shell is in this folder; there `ruby -v` prints the version `mise.toml` pins. A script, an editor's task, a CI job, or a shell you have not activated runs none of the hooks `mise activate` installs, so it keeps whatever Ruby its `PATH` already had, or none, and `bundle exec` there stops with Bundler's stack trace, because the gemspec needs that very Ruby. Start each command there with `mise x --`, as `bin/setup` does. `mise x` puts the pinned tools first on `PATH` for that one command, and installs first any of them that is missing ([`mise exec`](https://mise.jdx.dev/cli/exec.html)).

`bundle exec rake runtime` builds this computer's runtime, which the gate otherwise skips the checks of. On Linux it needs a C compiler, binutils, make, perl, and xz from your system, and patchelf 0.18.0, which mise installs from `mise.toml`, pinned by SHA-256.

Building `examples/native_app` compiles its gems, and ferro-idna among them is a Rust gem, whose build runs bindgen, which loads libclang to read Ruby's headers. On macOS and Linux mise installs the Rust it needs. A Mac has libclang with Xcode's command-line tools; on Linux mise installs LLVM's libclang 18.1.1, from PyPI's `libclang` wheel (a 25 MB download), pinned by SHA-256, names its folder in `LIBCLANG_PATH`, and gives bindgen your C compiler's headers, which the wheel lacks. On Windows mise installs neither, and CI's runners supply both. mise sets these only under `mise x --` or in a shell it has activated.

### Before a push

Run `mise x -- ruby bin/check`. It is one command, the same in bash, zsh, cmd, and PowerShell, on Linux, macOS, and Windows, and it works on a computer that has nothing but git and mise, as a fresh clone on a fresh CI runner does: `mise x` installs whatever tool `mise.toml` pins that is missing, the Ruby among them, and starts `bin/check` with that Ruby. The first run downloads and installs everything, which takes some minutes; after that, setting up takes seconds. `bin/check` runs `bin/setup` (`bin\setup.ps1` on Windows), then checks the commits since `origin/trunk` (or since the commit you name after it): it fails one whose `Provenance: requested` trailer git does not parse, and runs each of the gate's lints that reads a file they change, on just the files they change where it can: RuboCop on the Ruby files (on every file when they change its configuration or `Gemfile.lock`), shellcheck on the shell scripts, actionlint on the workflows, and clang-format on the C; then the REUSE lint, Steep and the RBS checks when they change `lib/` or `sig/`, RDoc's coverage when they change the Ruby it counts, and the unit tests. Among those is the check that `doc/licensing.md`, which is generated, is current: a change to Fledge's version, to `runtime/licenses.yml`, or to the page's generator changes the page, and when the check fails, `mise x -- bundle exec rake licensing` writes it again, with `runtime/audited.yml` ([`doc/contributors/design/license-audit.md`](doc/contributors/design/license-audit.md), "The licensing page"). On a change that touches all of them it takes about half a minute once set up. It leaves to the gate RubyCritic, which fails nothing, the check of the packaged gem, and the integration tests. Run beside it the one test of the behavior your change alters, which no command can guess: `TEST=test/gem_app_build_test.rb` for how `fledge build` lays out a gem-shaped app's gems, `TEST=test/integration/launcher_environment_test.rb` for what the launcher hides from Ruby, and `bundle exec rake parity`, after `bundle exec rake runtime`, for a change to what a runtime holds. Check it on the system where the behavior lives, or on whichever you have when it is the same everywhere, and on several only for a change about how the systems differ.

After the push, CI runs the gate, `bundle exec rake`, on every system: every test and every lint, with zero errors and zero warnings. Its Mac jobs run on `macos-15`, the oldest macOS GitHub has, when they build or run a Mac's apps or need Xcode 16.4, and on `macos-26` when they need Xcode 26.5 or any Mac will do; [`doc/contributors/design/releases.md`](doc/contributors/design/releases.md), "Which macOS each job runs on", says why, so a new Mac job follows the same rule.

### Android on Linux

On an x86-64 Linux computer with KVM (`/dev/kvm`, which your user can read and write), you can build the Android runtime and Android apps, and run them on an emulator, as CI's Runtime (android) and Mobile apps (Android emulator) jobs do. `mise.android.toml` pins what that needs, each by its SHA-256: Temurin's JDK 21, the NDK the Android runtime is built with, the CMake that `examples/cmake_phone` runs, and the packages of Android's SDK CI uses (platform-tools, the API 36 platform, build-tools 36.0.0 and 37.0.0, the emulator, and the API 36 system images with 4 KB and 16 KB pages). mise reads it only when `MISE_ENV` is `android`, so `mise install` leaves out its five gigabytes otherwise. `bin/android-sdk` lays its packages out as one SDK in `tmp/android/sdk`, which `ANDROID_HOME` names, and downloads nothing. `bin/android-emulator TARGET -- COMMAND` boots an API 36 emulator with no window from the system image `google_apis` (4 KB pages) or `google_apis_ps16k` (16 KB), runs the command with `ANDROID_SERIAL` naming the emulator, and shuts it down. The last two commands run the Android integration tests, as the Mobile apps (Android emulator) jobs do: those that need no device, then `test/integration/mobile_extension_symbols_test.rb`, which runs its program on the emulator.

```sh
export MISE_ENV=android
mise install
mise x -- bin/android-sdk
mise x -- ruby tasks/runtime_builder.rb x86_64-linux   # whose Ruby compiles a gem's extension for the phone
mise x -- ruby tasks/runtime_builder.rb android
mise x -- bash -c 'BUNDLETOOL=$(ruby .github/scripts/fetch_pin.rb mobile bundletool) ruby tasks/mobile_parity.rb android-build tmp/runtime'
mise x -- bash -c 'BUNDLETOOL=$(ruby .github/scripts/fetch_pin.rb mobile bundletool) bin/android-emulator google_apis -- ruby tasks/mobile_parity.rb android'
mise x -- bundle exec rake test:integration TEST=test/integration/mobile_extensions_build_test.rb,test/integration/mobile_default_gems_test.rb
mise x -- bin/android-emulator google_apis -- bundle exec rake test:integration TEST=test/integration/mobile_extension_symbols_test.rb
```

## The tests

Fledge's tests come in two tiers, by folder, as Rails keeps its system tests in `test/system` and Hanami and dry-rb keep `spec/unit` apart from `spec/integration`.

- **Unit tests** are every test file under `test/` but those in `test/integration/`. Each runs in milliseconds, in the test's own Ruby process, on any computer, with or without a runtime. It may write a temporary folder, read the repository, serve a `LoopbackServer` in its own process, and run a short-lived tool such as tar. It builds no runtime, reads none that `rake runtime` built, builds no app that it then runs, compiles nothing, starts no Ruby or shell script, runs no signing or disk image tool, and reaches nothing past this computer. A wait the code under test would make, such as a retry's, is made short by passing the waits in, as `Fledge::Download` and `Fledge::Dmg` take them.
- **Integration tests**, in `test/integration/`, are the rest: a real runtime, a built app run as a person runs it, a compiler, `exe/fledge` or a script in a process of its own, codesign, hdiutil, makensis, gpg, a repository that git makes, or the network. They take seconds, some take minutes, and many skip on a computer without what they need. CI runs each where it has what that test needs, and there a skip for want of it fails instead: the Test jobs run them all on each desktop platform with its runtime (`FLEDGE_REQUIRE_RUNTIME`), the Mobile apps (Android emulator) jobs run the Android tests with the Android runtime, the NDK, CMake, Rust's Android targets, and an emulator (`FLEDGE_REQUIRE_ANDROID`, `test/support/android.rb`), and the Mobile apps (iOS Simulator) job runs the iOS tests with the iOS runtime, the Xcode `runtime/sources.yml` pins, XcodeGen, CMake, and Rust's iOS targets (`FLEDGE_REQUIRE_IOS`, `test/support/ios.rb`). "Android on Linux", above, says how to run the Android tests yourself. On a Mac, `bin/setup` installs the XcodeGen and the Rust targets the iOS tests need, and they run once `bundle exec rake runtime` and `bundle exec rake runtime[ios]` have built this Mac's runtime and the iOS one, with Xcode and CMake installed.

A new test file is a unit test unless you put it in `test/integration/`. When a unit test needs one of the things above, or takes more than about a tenth of a second on your computer, make it fast without weakening it, or move it. Tests of one class can be in both tiers: `test/assembly_test.rb` and `test/integration/assembly_tools_test.rb` share `test/support/assembly.rb`.

While you work:

- `bundle exec rake test` runs the unit tests, in seconds. Run it as often as you like. CI's fast tier runs them on every push: `.github/workflows/fast.yml` on Linux and Windows, beside the lint, and `.github/workflows/fast-macos.yml` on macOS, a workflow of its own because a macOS runner often takes twenty minutes or more to come.
- `bundle exec rake test:integration` runs the integration tests, and `bundle exec rake test:all` runs both, as the gate and CI do. Build a runtime first (`bundle exec rake runtime`), or the tests that need one skip.
- `bundle exec rake test TEST=test/foo_test.rb` runs just that file, of either tier; several files, or globs, go comma-separated.
- `N=/name/` runs just the tests whose names match, and `A=-v` names each test with its time as it runs.
