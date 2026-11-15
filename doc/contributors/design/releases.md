<!--
SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>

SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Versions and Releases

This document says how Fledge is versioned, what each kind of release may change, which Rubies and platforms a release keeps, and how a release is made and published, with the reason for each. ADR 093 decides that the runtimes a release publishes are prebuilt in Fledge's CI. The steps a release takes are in `doc/contributors/handoff.md`, "How to release". What 1.x freezes is in `doc/contributors/design/public-interface.md`. App developers read the same rules in `doc/runtimes.md`.

## Versions

Fledge's versions are SemVer's MAJOR.MINOR.PATCH (decisions.md, 2026-11-02). Before 1.0 they are 0.MINOR.PATCH, and any 0.x release may break a build; the CHANGELOG says how. Agents cut 0.x releases as work accumulates, so that the newest 0.x release has what 1.0.0 will (decisions.md, 2026-11-08).

From 1.0, a breaking change is a change to what `doc/contributors/design/public-interface.md` freezes, and it ships in the next major whenever it is ready. A removal or a changed default is announced first, by a build-time message and a CHANGELOG entry, in at least one earlier minor release. No compatibility flag keeps the old behavior: the notice warns, and the major switches.

Majors come when a break is ready, not on a schedule as Ember's do, and no flag holds a break back. A built app is a frozen artifact, so a break fails loudly at the next build, not in an app already shipped. A flag costs a key in `Fledge::Config`, the schema, the help, the docs, and a test axis on every target, for as long as anyone uses it. And the old lines to patch are bounded by the live Rubies, not by the number of majors ("Support follows live Rubies"). The cost is that a store that forces a platform floor up forces a major, even in a year with no other break. The maintainer set SemVer's form and what takes a major (decisions.md, 2026-11-02 and 2026-11-03); when a major ships was left to the agents. How long a deprecation stands before its removal, beyond one minor, is not decided.

A prerelease tag takes SemVer's form, such as `v1.0.0-beta.1`, not RubyGems' `v1.0.0.pre.beta.1`. `release.yml` marks a version with anything but digits and periods in it a prerelease on GitHub.

## What a patch, minor, or major release may change

- **A patch release** fixes. It may move each runtime to a newer patch of its Ruby minor, such as 4.1.0 to 4.1.1, with a CHANGELOG entry: Ruby's patch releases fix bugs and security problems.
- **A minor release** adds what a 1.0 project does not use until it chooses to (`doc/contributors/design/public-interface.md`, "How 1.x adds"). It may add a runtime for a new Ruby minor, under the reserved asset names. It may move a runtime's patch, as a patch release may. A generated file may change in a minor release, since an upgrade does not regenerate it (decisions.md, 2026-11-03); Fledge writes no generated file a developer keeps.
- **A major release** may change anything frozen. Only a major drops the runtime of a Ruby minor, raises a platform floor, or stops `fledge build` running on an operating system version the last release ran on (decisions.md, 2026-11-03).

No release moves an app to a new Ruby minor. Ruby does not follow SemVer, so a new minor is expected to break what ran on the old one (decisions.md, 2026-11-03). Only the developer moves an app to it, by running `fledge build` with that Ruby ("Ruby minors and runtimes").

## Ruby minors and runtimes

A release carries one runtime of each Ruby minor it supports, for each platform, at one patch, the one `runtime/sources.yml` pins (on Windows, until RubyInstaller builds the release, a snapshot of Ruby's main branch: `doc/contributors/design/runtimes.md`, "Windows' Ruby until Ruby 4.1.0"). `fledge build` takes the runtime of the minor of the Ruby running it, and refuses a Ruby whose minor the release has no runtime for, naming both versions (`Fledge::CLI::Build#same_ruby`). The rule names a minor, not a patch: a developer who wants an exact patch writes `ruby "X.Y.Z"` in the Gemfile, and Bundler and Fledge then refuse every other.

Fledge has no default Ruby. The Ruby running `fledge build` is the one the developer chose and tested on, and every other way of naming an app's Ruby is a second statement of it that can disagree. A default would one day move to a new minor and break apps, which the maintainer allowed no minor release to do (decisions.md, 2026-11-03). A required Gemfile `ruby` line is what Heroku asks for, since no Ruby runs an app before Heroku builds it; Fledge always runs inside the developer's Ruby, and a lone `main.rb` would need a Gemfile only to say so. Reading `.ruby-version` would repeat what mise, rbenv, chruby, rv, `ruby/setup-ruby`, and Bundler's `ruby file:` already do. A `ruby` key in `fledge.yml` written by a generator, which the maintainer suggested, adds a command, a key, and a file that could name one minor on a computer running another. Briefcase and PyInstaller package the Python that runs them, the same way. The cost is that an app's Ruby follows the computer that builds it, so `doc/runtimes.md` tells developers to name it in `.ruby-version`, with `ruby file: ".ruby-version"` in the Gemfile.

The runtimes' asset names without a Ruby version mean the runtime of the Ruby minor 1.0 ships, for all of 1.x. A 1.x release that adds a second minor names that minor's assets with the reserved `-ruby-X.Y.Z-` part (`doc/contributors/design/public-interface.md`, "Reserved names"). Two minors side by side double the runtimes every CI run and release builds.

Before 1.0, a release may carry a preview of a Ruby minor, and any 0.x release may move it to a later preview or to the minor's final release; Windows runs RubyInstaller's head build of the day the preview appeared until RubyInstaller builds the release. 1.0 carries Ruby 4.1, which only a major drops, and waits for Ruby 4.1.0, by the maintainer's choice once Fledge's and Lota's agents agreed (decisions.md, 2026-11-09). Fledge's agents agreed because a 1.0 on Ruby 4.0 would have kept 4.0's runtimes through all of 1.x. So 1.0's date depends on Ruby's, which Fledge does not control.

## Platform floors

A floor is the oldest operating system version a platform's apps run on. Fledge's are:

- macOS 14, on Apple silicon (`Fledge::Platform::MACOS_MINIMUM`);
- Windows 10 on x64, and Windows 11 on ARM64;
- iOS 15 (`lib/fledge/templates/ios/project.yml`);
- Android 8.0, API 26 (`minSdk` in `lib/fledge/templates/android/build.gradle`);
- glibc 2.39 on `x86_64-linux` and `aarch64-linux` (`Fledge::Platform::GLIBC_MINIMUM`), which the maintainer accepted: "2.39 is fine, and even newer may be fine if there becomes good reason to raise the floor" (decisions.md, 2026-10-26, decision 7);
- musl 1.2 on the musl targets, the series PEP 656's `musllinux_1_2` tag names.

Linux has no single operating system version, so its floors are the C library's, as PEP 600's `manylinux_2_39` and PEP 656's `musllinux_1_2` tags name a Linux platform. Raising either drops whole distribution releases at once: glibc 2.40 would drop Ubuntu 24.04 and Debian 13. So each counts as an operating system version: raising glibc 2.39 or musl 1.2 is a major, and so is dropping a distribution release that meets them. A patch within an operating system or C library version is not a floor.

Raising a floor is a major, always, even when a store's rule forces it. A store's yearly rule that drops no version is not a floor: Google Play's target API level and the Xcode version App Store uploads need live in the phone templates, which any release may change, with a CHANGELOG entry. Android's `minSdk` and iOS's deployment target are floors.

The Windows 10 floor is unproven. GitHub's hosted runners cannot run Windows 10, so no CI job runs a Fledge app there, and the floor stands on the first report from a Windows 10 computer.

The same rule holds where `fledge build` runs: a release that stops building on an operating system version the last release built on is a major.

## Support follows live Rubies

For each Ruby minor that is not end-of-life, the last Fledge minor line to support it gets security fixes for the embedded runtime, and platform-deadline fixes where feasible, until that Ruby is end-of-life. The last minor before a Ruby is dropped says so at build time and in its CHANGELOG, and names itself the long-term line for that Ruby, with the date. That line's release branch, such as `release/1.7`, takes its fixes. A line that is the last for no live Ruby gets nothing. A new feature never goes to an old line.

So the patched lines number about one per live Ruby minor, three or four, however high the Fledge number climbs. A platform-deadline fix on an old line may need newer toolchains and rebuilt runtimes; that promise is best effort, and the CHANGELOG says when a fix cannot be made. End-of-life dates come from ruby-lang.org's maintenance page when a line becomes a long-term line.

## Where releases are

Every release is a git tag, `vX.Y.Z`, and a GitHub Release at https://github.com/setdef/Fledge made from it, which carries the prebuilt runtimes as assets, before 1.0 and after (decisions.md, 2026-11-04). Before 1.0 that is the only way a release can be found, and developers install Fledge from its tag with Bundler, as Ferro releases by tag.

Agents push `trunk`, push tags, and create GitHub Releases before 1.0 (decisions.md, 2026-10-26, decision 6). Agents never publish to RubyGems.org; that is a human-only activity, now and after Fledge is there (decisions.md, 2026-11-02, later). The gemspec's `allowed_push_host` points nowhere, and `tasks/package.rake` replaces `rake release` with one that refuses. From 1.0.0, the maintainer also publishes each release on RubyGems.org, by hand, and the tag and the GitHub Release stay (decisions.md, 2026-11-03 and 2026-11-04). `doc/contributors/releasing-1.0.md` is his checklist for the first push.

A GitHub Release holds, for each desktop platform:

- `fledge-runtime-VERSION-PLATFORM.tar.gz`, the runtime;
- `fledge-runtime-VERSION-PLATFORM.spdx.json`, its SPDX SBOM;
- `fledge-runtime-VERSION-PLATFORM-NOTICES.txt`, its notices;
- `fledge-runtime-VERSION-PLATFORM-lgpl-sources.tar.gz`, the sources its licenses ask for, on the platforms that ship such a component.

A phone runtime has the first three. A `SHA256SUMS` over all of them is the tagged commit's `lib/fledge/SHA256SUMS`. `RuntimeBuilder.release_assets` (`tasks/runtime_builder.rb`) is the list, and `release.yml` refuses any other set.

A release is never deleted. Each runtime's NOTICES links its source bundle at the release, after the copy in the app's own `notices/sources/` (ADR 043), and the schema's address names the release's tag (`doc/contributors/design/public-interface.md`, "The fledge.yml schema").

## The pins

`lib/fledge/SHA256SUMS` holds one line per release asset, sorted by name, in the form `sha256sum` writes and `sha256sum -c` reads: the hash in lowercase hex, two spaces, and the name. `Fledge::Runtimes` takes the SHA-256 of every runtime it downloads from this file, and checks a runtime in the cache against it too, downloading it again when it does not match. A version whose file names no SHA-256 for a runtime is a commit between releases, and `fledge build` says it is not a released Fledge, naming `FLEDGE_RUNTIME_DIR`. Runtimes in `FLEDGE_RUNTIME_DIR` are a developer's own builds and are not checked.

The pins come from the gem, never from the release: a `SHA256SUMS` fetched from the host that serves the file catches a damaged download, but not a release whose assets and sums were both replaced. A version cannot pin files built after its tag, and runtime builds are not reproducible, since each runner's tar writes the archives and each runner compiles the launcher. So the release commit's CI builds the runtimes and a child commit pins those very bytes, as Homebrew's `brew pr-upload` commits a formula's bottle hashes from the bottles its CI built and then uploads the same bottles (`Library/Homebrew/dev-cmd/pr-upload.rb` at Homebrew/brew 1f55ebf8). uv's pins of python-build-standalone fit files another project built earlier, not ones built for the very version that pins them. Reproducible builds would let one commit pin, at the cost of byte-identical output on every system, and nothing here rules them out. The file is `sha256sum`'s format because the release already publishes it and every system's tools read it.

`rake runtime:pin` (`tasks/runtime_pins.rb`) writes the file. It downloads the runtime artifacts of the release commit's CI run with the GitHub CLI, refuses unless that run passed on every job and its artifacts are exactly `RuntimeBuilder.release_assets` for the version, and writes their SHA-256s.

## How a release is made

A release is two commits and a tag, within the 14 days CI keeps a run's runtimes:

1. **The release commit** moves `Fledge::VERSION`, the CHANGELOG, and every file that names the version, the schema's `$id` and the documented modeline among them. Its CI run on `trunk` builds every runtime and delivers each on a fresh runner, as on every push, and also runs ruby/spec on all seven desktop platforms.
2. **The pin commit** changes only `lib/fledge/SHA256SUMS`, written by `rake runtime:pin` from the release commit's run. It runs the short CI below.
3. **The tag** goes on the pin commit, and `release.yml` publishes.

The pin commit changing only the pins is what ties the published runtimes to the tagged source: every file a runtime is built from is the same in both commits. So the pin commit is the release commit's child, and nothing else lands on `trunk` between them: from the release commit's push to the pin commit's, about the length of the release commit's run. Other pushes do not cancel that run (below). The commands are in `doc/contributors/handoff.md`, "How to release".

## Runs, batches, and the release commit

A push to `trunk` never cancels the run of `ci.yml` in progress there. GitHub keeps at most one run going and one waiting in a concurrency group, and a newer push replaces the waiting one. So every run that starts finishes, and it covers a batch: every commit pushed since the run before it started. A red run blames the whole batch. `.github/workflows/fast.yml`, the lint and the unit tests on Linux, macOS, and Windows, runs on every push in a few minutes, never cancelled on `trunk`, and its verdict on each push narrows the blame. A push to any other branch cancels that branch's runs of both workflows.

So every push gets a verdict, and nobody waits for CI to push, which trunk-based development forbids. Cancelling a trunk run for each newer push would leave trunk with no finished run while agents push every few minutes. Running all of `ci.yml` on every push, never replaced, would queue hours deep, since a run asks for about an hour of several macOS and Windows runners. Without the fast tier a push would wait up to two hours for a verdict, and a red batch would have nothing to narrow it. The fast tier is a workflow of its own because GitHub ends a run only when its slowest job ends, and the whole gate stays in `ci.yml`, since a pin commit's short run needs it. The costs are the batch's blame, and that the fast tier's macOS job waits for a macOS runner like any other, so a push's macOS verdict can come long after its Linux and Windows ones.

A run belongs to the commit at the head of its push. A commit pushed with others after it, or one whose waiting run a newer push replaced, has no run of its own, and `tasks/ci_runs.rb` finds nothing for it: it says so, and that the commit has to be pushed alone, as the head of its push. A batch's run proves its head, so a commit inside a batch cannot be a release commit, and cannot be a pin commit's parent.

The release commit and the pin commit are each pushed alone. Each gets a concurrency group of its own, named for its commit, when its message starts `chore: release ` or `chore: pin `, as `doc/contributors/handoff.md`, "How to release", writes them. Its run starts at once, beside any trunk run in progress, and no later push replaces it, so other agents keep pushing while it runs. A release commit with another message falls into trunk's group, where it can wait an hour and be replaced; `ruby-spec.yml` runs on all seven desktop platforms only for the `chore: release ` message too.

## A pin commit's short CI

A commit pushed to `trunk` with one parent and `lib/fledge/SHA256SUMS` as its only change runs two jobs of `ci.yml`:

- **The gate**, as on every commit, whose tests read the pins.
- **`Changes`**, which runs on every commit and tells a pin commit apart with `.github/scripts/pins-only.sh`. On a pin commit it finds the parent's newest run on the same branch in which every job ran and passed (`tasks/ci_runs.rb`), downloads its runtimes, and runs `.github/scripts/check-pins.sh`: the runtimes must be exactly `RuntimeBuilder.release_assets`, the pins must name exactly those, and each must match its pin under `sha256sum --strict -c`.

Every other job is skipped. A merge, a first commit, a pull request, a clone without the parent, and any commit that changes anything else run all of CI. The pin check is a step of `Changes`, not a job of its own, because a job of its own would be skipped on every other commit, and a release commit's run may skip none.

A pin commit is green for tagging when its own short run passed, counting skipped jobs, and its parent's run passed on every job with none skipped. Every file of the tagged commit was then tested by a run that passed on every job: the pins by the gate and the check against the runtimes they name, and everything else by the parent's run, since those files are the parent's.

A full run on the tag, or on the pin commit, would test the same bytes again, throw its runtimes away, and draw every flaky download a second time, and flakes in jobs that publish nothing have kept a release from going out (`doc/contributors/research/2026-11-03-ci-speed.md`). Skipping the pin commit's run with `on.push.paths` would leave it no run to look up.

## release.yml

`.github/workflows/release.yml` runs on a pushed tag `vX.Y.Z`. Before it writes anything, it checks:

- that the tag matches `Fledge::VERSION`;
- that the tagged commit changes nothing but `lib/fledge/SHA256SUMS` from its parent;
- that the tagged commit has a run of `ci.yml` on a push to `trunk` whose latest attempt of every job passed or was skipped;
- that its parent's newest such run passed on every job, none skipped, and that run's runtimes are exactly the release's and each matches its pin.

It asks GitHub's REST API through `tasks/ci_runs.rb`, which reads 50 jobs a page, asks again after a 5xx, and takes each job's latest attempt, so a run whose failed jobs were run again counts once they pass. A tag that fails a check fails before anything is published, naming the run and each job that did not pass. A run refused only because CI had not finished can be run again once it passes.

Only its Publish job writes: it checks the assets against the pins once more and creates the GitHub Release with them. Run by hand (`workflow_dispatch`) with an existing tag, it runs every check against that tag's commit and runtimes, with the workflow and scripts of the branch it runs from, keeps the assets it would publish as the run's artifact, and publishes nothing unless given `publish`. A change to `release.yml` is tried that way before a release depends on it.

## installed.yml

After publishing, `release.yml` calls `.github/workflows/installed.yml`, which can also be run by hand on any published tag. It checks the published `SHA256SUMS` against the tag's `lib/fledge/SHA256SUMS` and every asset against it. On a fresh runner of each platform, it installs Fledge from the tag with Bundler, never from RubyGems.org, and with no `FLEDGE_RUNTIME_DIR` and an empty cache builds the examples with runtimes downloaded from the release, compiles `examples/native_app`'s gems against the runtime alone, and delivers each app as CI does. It installs the windowed app's installer and runs the app, writes phones' projects from the tag and builds them with Xcode and Gradle, and builds the `.gem` from the tag and installs that file on each platform. A release is not verified until its jobs pass. `package-managers.yml` installs hello with the package managers' recipes from `doc/package_managers.md`.

`installed.yml` is where a change in the world between the push and the tag shows, since the release runs no CI of its own.

## From 1.0: release branches and a human publishing

Before 1.0, every commit and every release is on `trunk`, with no release branches: there is no older series to patch. Releases through 1.0.0 are made by hand, as `doc/contributors/handoff.md` says.

After 1.0, Fledge reuses the version and git tooling of RatatuiRuby and Rooibos, which works differently before 1.0.0 and after it (decisions.md, 2026-11-03), and the tooling is not in this repository yet (decisions.md, 2026-11-07). From then on:

- every change lands on `trunk` first, and each minor has a release branch, `release/X.Y`, cut from `trunk` when `X.Y.0` is released;
- a fix goes to each release branch that needs it by `git cherry-pick -x`, and the patch release is made from the branch; this is how a long-term line gets its fixes (see "Support follows live Rubies");
- every release has a SemVer tag, and `stable`, the repository's default branch, sits at the newest stable release;
- each release branch keeps its own CHANGELOG;
- a human publishes: `rake release` pushes the gem, so the maintainer runs it. Agents prepare the bump, the branch, the backports, the CHANGELOG, and green CI, and the maintainer's run makes the tag and moves `stable`, which AGENTS.md forbids agents to force-push.

Fledge's runtimes are not in the gem. A runtime is files Fledge copies into an app, built once per target by CI and checked against the gem's pins, so there is nothing to build per platform inside the gem. The tag and the GitHub Release stay, because they hold the runtimes and the source bundles each app's notices name. Plan 003, "1.0", describes the RatatuiRuby tooling Fledge will reuse and what waits on its extraction.
