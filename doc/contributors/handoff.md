<!--
SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>

SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Handoff

Start here if you are a session with no memory of the ones before you. This page says where Fledge stands, how to check it, how to release it, and what to do next. Agents wrote it and keep it current (AGENTS.md, Provenance); when you finish a story or cut a release, update it in the same commit as the plan.

Read these next, in order: `AGENTS.md` (how to work here, and binding), `doc/contributors/decisions.md` (the maintainer's own words, the only authority; never write to it except to add an answer from `questions.md`), `doc/contributors/questions.md`, the plan of record (`doc/contributors/plan/003.md`), and the ADRs its stories cite.

## Where Fledge stands

The latest release is [`v0.3.0`](https://github.com/setdef/Fledge/releases/tag/v0.3.0), which restarts an app through `RbConfig.ruby` as it first started (ADR 026). The one before it, [`v0.2.1`](https://github.com/setdef/Fledge/releases/tag/v0.2.1), is the first published release of the 0.2.0 changes: `v0.2.0` is a tag without a GitHub Release, because its release run failed when a runtime source's host was down, and it is neither used nor deleted. Releases before `v0.1.0` were `0.0.1.pre.N`, and versions are ordinary 0.MINOR.PATCH from `v0.1.0` on (decisions, 2026-11-02). Every release is a git tag and a GitHub Release carrying the prebuilt runtimes; Fledge is never published to RubyGems.org.

`fledge build` builds an app on the computer it runs on, for that computer's platform, with that platform's own tools (ADR 010): `arm64-darwin`, `x86_64-linux`, `aarch64-linux`, `x86_64-linux-musl`, `aarch64-linux-musl`, `x64-mingw-ucrt`, and `aarch64-mingw-ucrt`. `fledge build ios` and `fledge build android` write an Xcode or Gradle project around the mobile runtimes for a pure-Ruby app (ADR 012).

Plan 001 (the walking skeleton) and Plan 002 (toward 1.0) are done. What each Plan 002 story delivered, with its ADR and first release:

- **Ship the executable you already run** and **Vendor an app's gems** (ADR 005, `v0.0.1.pre.2` and `pre.3`): a gem-shaped program runs as `bundle exec` would run it, with the gems its Gemfile.lock locks.
- **Copyleft-free runtimes** and **Tell app developers what they owe, from CI** (ADR 004, `pre.1`): every runtime passes a license audit; each carries NOTICES and an SPDX SBOM; LGPL sources are published beside it; `doc/licensing.md` is generated from the runtimes. An app's own gems are the developer's business (ADR 007).
- **Pin runtimes by hash** (ADR 014, `pre.12`): the gem carries `lib/fledge/SHA256SUMS` and checks every runtime against it.
- **Native gems from source** (ADR 006, `pre.4`): gems with extensions compile on the platform they are for; git gems ship where Bundler keeps them.
- **Signing and notarization** (ADR 016, `pre.14`): `--sign` with the developer's own identity; notarization and real trust chains wait on accounts.
- **App identity**, **Windowed apps**, **Installers** (ADR 008 and ADR 009, `pre.6` and `pre.7`): name, icon, version, and identifier on every system; `.app`, GUI program, desktop entry; `.dmg`, NSIS setup program, AppImage.
- **Each target on its own system, with its own tools** (ADR 010 and ADR 013, `pre.8` and `pre.11`): Fledge's own format writers were replaced by maintained tools.
- **musl Linux** (ADR 017, `pre.15`): Ruby built from source in Alpine.
- **iOS, iPadOS, and Android**, **Mobile runtimes**, **Mobile apps from fledge build** (ADR 011 and ADR 012, `pre.9` on): proven in the iOS Simulator and on x86-64 Android emulators.
- **A `.deb` for windowed apps on glibc Linux** (ADR 021, `v0.1.0`): `dpkg-deb`, asked for with `installers: [appimage, deb]`, delivered by apt in Debian and Ubuntu containers.
- **Windows on ARM** (ADR 018, `pre.16`): RubyInstaller's ARM64 Ruby, delivered natively on `windows-11-arm`.
- **Ctrl-C and the console** (ADR 015, `pre.13`; closing a Windows console, proven through a pseudoconsole, `pre.17`).
- **The gems real apps lock** (ADR 020, `pre.17`): credentialed and mirrored gem servers, git submodules, path gems outside the project and with extensions, Bundler's optional groups, and gems' executables in the runtime's `bin/`; `examples/real_gems` needs a loopback mirror (`.github/scripts/gem-mirror.rb`) and a fixture branch, `experiment/submodule-gem`, which must stay.

## What is left before 1.0

Plan 003 holds it. In short:

- **Waiting on money** (decisions, 2026-11-02: none is spent now): an Apple Developer account, for a real iPhone and iPad and for App Review; the accounts and certificates for notarization, Developer ID, and Windows code signing; and a way to run Android's arm64-v8a build. The maintainer ruled that 1.0 waits until at least some of those proofs exist (decisions, 2026-11-02); until then releases are ordinary 0.MINOR.PATCH versions, from `v0.1.0`.
- **Unproven**: a real iPhone or iPad; App Review; Android's arm64-v8a build, which no GitHub runner can emulate with hardware acceleration (tried 2026-11-02, ADR 011; no money is spent on a device cloud or a machine, decisions 2026-11-02); Gatekeeper's and SmartScreen's verdicts on a real certificate.
- **0.2.0, the maintainer's priority (decisions, 2026-11-02): phones.** Native gems on phones (ADR 022, Plan 003) are done for C and C++ extensions (run 41492629986 on experiment/phones) and first released in `v0.2.1`; what is left is in the ADR (Rust extensions, `require_relative`). The SDL3 spike ran (ADR 025, `examples/sdl_phone`, branch `experiment/sdl-phones`): a game whose SDL3 owns the main loop runs with Ruby inside on both phones, given a host of SDL's own; the `host` key in `fledge.yml` (ADR 025, section 5), first released in `v0.2.1`, lets a project supply that host, and the story "A game plays on a tablet and a phone" waits on Lota's side, and on devices.
- **One project, several programs** (ADR 024), done and first released in `v0.2.1`: `programs` in `fledge.yml` ships a project's programs from one folder with one runtime, one project, and one set of gems. `examples/programs` builds and delivers on every desktop platform (`trunk`'s run 41584541749; Plan 003). A JSON Schema of `fledge.yml` for editors (ADR 023) is in `v0.2.1` too.
- **Open problems from the ADRs**: the musl and ARM64 Windows builds of `examples/real_gems`, and `Gem.bindir` on an app's `PATH` (ADR 020); installer polish, which Plan 003 defers past 1.0 until a developer asks, and `diskutil image create`, which waits for `hdiutil create` to stop working (it still works on macOS 26 and 27; ADR 010); emulated tools and sqlite3 on ARM64 Windows (ADR 018); native gems on phones are in `v0.2.1` (ADR 022).

## How to check it

- **The gate**: `bundle exec rake` on your computer, after `bundle exec rake rubocop:autocorrect_all`. It must pass with no errors and no warnings. It skips what needs a runtime unless you build one with `bundle exec rake runtime`.
- **CI**: every push to `trunk` runs `.github/workflows/ci.yml`, about 30 minutes: the gate, every runtime, the tests and parity on each platform, each platform building its own apps, and Delivery on fresh runners. `gh run list --branch trunk --limit 3`, then `gh run view RUN --json conclusion,jobs --jq '.jobs[]|select(.conclusion!="success")|.name'` to see what did not pass, and `gh run view RUN --log-failed | tail -80` to read why.
- **ruby/spec**: `ci.yml` calls `ruby-spec.yml`, which runs ruby/spec on stock Ruby and in a built app from each runtime and fails on an example that fails on one side only, unless `RubySpec::JUSTIFIED` (`tasks/ruby_spec.rb`) explains it: on every push for x86_64-linux and arm64-darwin, on a release commit for all seven desktop platforms, and every night for all seven on trunk's newest green runtimes. `bundle exec rake ruby_spec` runs it here after `bundle exec rake runtime`; each run's MSpec output is in `tmp/ruby-spec`, and in CI in the `ruby-spec-PLATFORM` artifact.
- **Releases**: `gh release view vX.Y.Z` lists the assets; `gh run list --workflow release.yml --limit 2` shows the release run, which ends by calling `installed.yml`.
- **installed.yml**: it installs Fledge from the tag on a fresh runner of every platform, downloads the release's runtimes, checks them against the tag's pins, and builds and delivers the examples. Its jobs are part of the release run; a release is not verified until they pass.

## How to release

A release is two commits and a tag (AGENTS.md, Releasing; ADR 014):

1. **The release commit**, `chore: release X.Y.Z`: set `Fledge::VERSION` in `lib/fledge/version.rb`; change the old version to the new one in `Gemfile.lock`, the README, and `doc/licensing.md`; move the CHANGELOG's Unreleased entries under `## [X.Y.Z] - DATE` and add its link; mark each story it ships "First released in" in the plan. Run the gate, push, and wait for CI to pass on every job.
2. **The pin commit**, `chore: pin X.Y.Z's runtimes`: `bundle exec rake runtime:pin` downloads the runtimes the release commit's CI run built and writes `lib/fledge/SHA256SUMS`. It refuses unless that run passed on every job. Commit that file alone (`git commit lib/fledge/SHA256SUMS`), push, and wait for CI: a pin commit's run is short, the gate and the `Changes` job, which checks the pins against the release commit's runtimes, with every other job skipped (ADR 014, section 5).
3. **The tag**: `git tag -a vX.Y.Z -m "Fledge X.Y.Z" PIN_COMMIT && git push origin vX.Y.Z`. `release.yml` does not run CI again: it refuses a tag whose commit changes anything but the pins, whose short CI run on `trunk` has not passed (or is still running), whose parent's run did not pass on every job, or whose pins do not match the runtimes of the parent's run. Watch its run, then `gh release view vX.Y.Z`. A run refused only because a CI run had not finished can be run again once it passes, with `gh run rerun RUN`. After any change to `release.yml`, try it before the next tag depends on it: `gh workflow run release.yml --ref BRANCH -f tag=vLAST` runs every check of a release against the last tag and its runtimes, with the workflow and scripts of BRANCH, and publishes nothing unless given `-f publish=true`.

Do all three within 14 days, while CI keeps the runtimes. Never delete a release: each runtime's NOTICES links its LGPL sources there. During a release, pushing to `trunk` cancels the CI run in progress there, and the pin commit needs that run's runtimes, so do not push between the release commit and its CI run's end. Outside a release, push whenever a step is done.

## Known CI flakes, and what to do

- **A macOS job cancelled before any step ran**: the runner never started. Re-run the failed jobs with `gh run rerun RUN --failed`.
- **A run cancelled outright**: a later push to the same branch superseded it (`concurrency` in `ci.yml`); the later run is the one that counts.
- **Mobile jobs that time out**: the iOS Simulator and Android emulators sometimes boot slowly. Read the log; if the app never started, re-run the job, and if it did start, it is a real failure.
- **`apk` says `unable to select packages` and `breaks: world[NAME=VERSION]`** in a musl job: not a flake. Alpine keeps only the newest build of each package in a branch, so when it publishes a new one, the pin in `.github/scripts/alpine-packages.sh` stops resolving. A re-run fails the same way. Find the version Alpine now has (`apk policy NAME` in the pinned image), move the pin, and run each role of the script in that image before pushing.
- **mise's Ruby download timing out after 20 seconds**: a flake of the download; re-run the failed jobs.
- **Anything else**: root-cause it before re-running (AGENTS.md, How to work). A failure that passes on a re-run is still worth a sentence in this list once you know why.

## Spikes and their branches

Spike code is thrown away; findings are kept. The mobile and permissive spikes' findings are in `doc/contributors/research/2026-10-27-mobile-spike.md` and `2026-10-27-permissive-spike.md`; the Windows launcher spike's are in ADR 001, section 8. Spikes of musl Linux and Windows on ARM ran on the `experiment/signing` branch's experiment workflow, and ADR 017 and ADR 018 record what they found. To try a CI change without disturbing `trunk`, push it to such an experiment branch, with a workflow that runs only the jobs in question.

## Where to start next

1. Read Plan 003 and take its first story not waiting on money. The wrapper story is done on Fledge's side (ADR 019): wrappers depend on Fledge, and Fledge depends on no wrapper's repository, so nothing here waits on Rooibos, Tokra, or Lota. The unsent drafts in `doc/contributors/drafts/` are optional FYIs. The experiment's workflow and delivery scripts (`wrapper.yml`, `deliver-tui.py`, `deliver-tui.ps1`) are on the `experiment/wrapper` branch.
2. The gems real apps lock are done for the desktop platforms CI compiles on (ADR 020, `examples/real_gems`); what is left of that story is in its plan entry. Take the next story not waiting on an account.
3. Watch `questions.md` (empty now): when the maintainer answers an entry, quote the answer in `decisions.md`, apply it, and take the story it unblocks.
