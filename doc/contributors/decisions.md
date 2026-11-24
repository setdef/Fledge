<!--
SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>

SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Fledge's Decisions

This file records the decisions that shape what Fledge is and does, each under the date it was made. They are the project's rules, and the only authority: the ADRs, the plans, the design documents, the help header, the error messages, and the layouts answer to them, and agents change those freely as long as they stay true to this file (AGENTS.md, Provenance). This file changes only when one of these decisions is made, changed, or withdrawn. When two entries seem to conflict, or one leaves something open, that is a `question` issue; never guess.

Each entry states the rule, and *Applied in* says where it is applied. Documents cite an entry by its date, and the numbered entries of 2026-10-26 by their number ("decision 8").

## From the start

- **Fledge is requested.** Every piece of work here is built by agents, as AGENTS.md, Provenance, defines the word. *Applied in:* AGENTS.md, Provenance.
- **Agents may push to `trunk`.** *Applied in:* AGENTS.md, Committing.
- **Agents never publish to RubyGems.org.** *Applied in:* AGENTS.md, Releasing; `fledge.gemspec`'s `allowed_push_host`; `doc/contributors/design/releases.md`, "Where releases are".
- **The walking skeleton walks on macOS, Windows, and Linux.** *Applied in:* Plan 001; `.github/workflows/ci.yml`.
- **High quality, tests, and linters.** *Applied in:* AGENTS.md, How to work, Commands, and Definition of done.

## 2026-10-26

The numbers are those of the list of questions these decisions settled, now the `question` issues. Numbers 1 and 11 of that list were settled later (number 1 by the license of 2026-11-07, number 11 below as it now reads).

**2.** An app's entry point is the executable the project already runs, with the project's root where its Gemfile or gemspec is, and NAME comes from the project, which configuration can override. *Applied in:* Plan 002, "Ship the executable you already run."

**3.** `exe/fledge` carries no provenance statement, for now. *Applied in:* `exe/fledge`; `test/cli_test.rb`.

**4.** The command follows the GNU and Unix conventions, and what Windows users expect, rather than inventing its own: `-h`, `-?`, `--help`, `-v`, and `--version` print to standard output and exit 0, and a usage error prints to standard error and exits 2. *Applied in:* `doc/contributors/design/public-interface.md`, "The command's conventions".

**5.** NAME, in `dist/NAME-PLATFORM`, is the app's primary class or module name, such as `MyCoolApp`. *Applied in:* `Fledge::App`; `doc/contributors/design/desktop-apps.md`.

**6.** Before 1.0, agents may push to `trunk`, create and push tags, and create GitHub Releases, but never release to RubyGems.org. *Applied in:* AGENTS.md, Committing and Releasing; `.github/workflows/release.yml`.

**7.** The oldest glibc a Linux app runs on is 2.39, and a newer floor is fine when there is good reason to raise it. *Applied in:* ADR 100; `doc/contributors/design/releases.md`, "Platform floors".

**8.** No third-party component of a runtime leaves an app's developer with a copyleft obligation beyond keeping notices. This governs Fledge's runtimes, not the app's own gems (2026-10-28). *Applied in:* AGENTS.md, Licensing; Plan 002, "Copyleft-free runtimes" and "Tell app developers what they owe, from CI."

**9.** An app's Ruby source is identical with Fledge and without it: what an app had to `require` before, it still requires, and what it did not have to `require` before, it still does not. *Applied in:* ADR 081; `doc/contributors/design/runtimes.md`, "What a runtime keeps"; `tasks/parity.rb`.

**10.** Every Ruby global is unsurprising to an app's developer, for the reason of decision 9: `$0`, `$LOAD_PATH`, `$LOADED_FEATURES`, and every other global an app sees. *Applied in:* ADR 081; `tasks/parity.rb`.

**11.** After Ruby has booted, an app and its child processes see the person's own Ruby environment variables (`RUBYOPT`, `GEM_*`, `BUNDLE_*`, and the rest) in `ENV`. *Applied in:* `doc/contributors/design/launcher.md`, "Hiding and restoring the person's Ruby settings"; `runtime/launcher/unix.c`; `runtime/launcher/windows.c`.

**12.** Linux on musl is supported eventually, since many CI platforms run only on it. It does not block the work before it, and may block 1.0. *Applied in:* Plan 002, "musl Linux."

**13.** The `fledge build` surface, its help header included, is the agents' to decide. *Applied in:* AGENTS.md, Questions.

**14.** ADR content is the agents' to decide and change. *Applied in:* AGENTS.md, Questions.

**15.** Plan content is the agents' to decide and change. *Applied in:* AGENTS.md, Questions.

**16.** Where there is prior art or an industry standard, agents follow it and cite it, and do not put the choice to the maintainer. *Applied in:* AGENTS.md, Questions; `doc/contributors/design/launcher.md`, "Messages and exit statuses".

**17.** A developer can make an app that Windows and macOS do not block, by signing and notarizing it, and an app built without that ceremony still works. *Applied in:* Plan 002, "Signing and notarization."

**18.** Everything an operating system shows of an app (the taskbar, the task manager, the Start menu, desktop icons, a window's corner and title bar, and their like) is the app's developer's to control. *Applied in:* Plan 002, "App identity."

**19.** The RubyInstaller signing key is the agents' to manage. *Applied in:* ADR 100; `doc/contributors/design/runtimes.md`, "The RubyInstaller signing key".

**20.** A tiny file size is not a priority; "my Ruby code just works" is a high one. A runtime prunes only what no running Ruby code can observe. *Applied in:* `doc/contributors/design/runtimes.md`, "What a runtime keeps" and "What a runtime prunes, and why nothing reads it".

**21.** Console code pages and Ctrl-C on Windows are the agents' to decide. *Applied in:* ADR 081; `doc/contributors/design/launcher.md`, "The locale"; Plan 002, "Ctrl-C and the console."

**22.** Windows on ARM and Linux on ARM are supported eventually. They do not block the work before them, and may block 1.0. *Applied in:* Plan 002, "Windows on ARM."

**23.** A runtime's internal layout is the agents' to decide, as long as an app's code needs no branch for each operating system because of it. *Applied in:* `doc/contributors/design/runtimes.md`, "Layout on Windows".

**24.** GMP, like every other component of a runtime, falls under decision 8. *Applied in:* Plan 002, "Copyleft-free runtimes."

## 2026-10-26, later

- **An LGPL library may ship in a runtime as a separate shared library,** with its own source offered beside the runtime, and never a source offer for the app. App developers are told plainly what they owe. This governs Fledge's runtimes, not the app's own gems (2026-10-28). *Applied in:* AGENTS.md, Licensing; Plan 002, "Copyleft-free runtimes" and "Tell app developers what they owe, from CI."
- **The page that lists, for each platform, the third-party components of a runtime, their licenses, and what an app's developer must do is generated in CI,** not written by hand. *Applied in:* Plan 002, "Tell app developers what they owe, from CI"; `tasks/licensing_page.rb`.

## 2026-10-27

- **iOS, iPadOS, and Android are in scope,** aimed at 1.0, unless they prove incredibly burdensome. *Applied in:* Plan 002, "iOS, iPadOS, and Android"; `doc/contributors/research/2026-10-27-mobile.md`.
- **Research that sessions share is kept in the repository.** *Applied in:* `doc/contributors/research/`.

## 2026-10-28

- **Fledge takes no position on the licenses of the gems an app depends on.** They are the app developer's choice and responsibility, and `fledge build` refuses no gem for its license. *Applied in:* `doc/contributors/design/gems.md`, "Checks that are not about licenses"; AGENTS.md, Licensing; `Fledge::AppGems`; `Fledge::Linkage`; `doc/licensing.md`, "Your app's own gems"; the README; `exe/fledge`'s help; Plan 002; `test/fixtures/native_app`; `test/fixtures/nokogiri_app`.
- **Agents proceed without an Apple Developer account,** which is opened at the last responsible moment, and raise it in a `question` issue when a story cannot be done without one. *Applied in:* Plan 002.
- **Code is a liability.** Fledge uses maintained existing tools rather than code of its own wherever such tools exist, and builds each target on its own operating system with that system's tools; it does not build one platform's app on another, since each target already needs a computer of its own to compile on. *Applied in:* AGENTS.md, How to work.

## 2026-11-02

- **No money is spent on Android's arm64-v8a proof,** neither a device cloud nor an Apple-silicon Mac for CI. *Applied in:* Plan 003, "Android on arm64"; ADR 099 and ADR 012.
- **No money is spent on an Apple Developer account for a real iPhone and iPad, or on a Windows code signing certificate or Azure Trusted Signing account;** the stories that need them wait. 2026-11-04 ends this. *Applied in:* Plan 003, "iOS on a real device, and App Review" and "Notarization and real trust chains"; `doc/contributors/design/signing.md`, "What CI proves, and the stand-ins".
- **There is no 1.0 until at least some of the unproven things are proven.** Releases use ordinary 0.MINOR.PATCH versions, from 0.1.0. *Applied in:* Plan 003.
- **Fledge depends on no wrapper's repository.** Lota, Tokra, and Rooibos depend on Fledge, not the other way around. *Applied in:* Plan 003; AGENTS.md, Project.
- **A `.deb` installer is built.** *Applied in:* Plan 003.
- **The work for release 0.2.0 is phones:** iPadOS, iOS, and Android. *Applied in:* Plan 003.

## 2026-11-02, later

- **Publishing to RubyGems.org is a person's act, whether or not Fledge is on it.** "Agents never publish to RubyGems.org" binds agents and is not a position of the project, so documents for developers do not say Fledge is never published there. *Applied in:* AGENTS.md, Releasing; `doc/contributors/design/releases.md`, "Where releases are".

## 2026-11-02, later again

- **Three words name how code and prose come to exist.** *Written* means the maintainer typed it by hand, with nothing generated. *Wrought* means an AI agent generated it while the maintainer iterated with it, and the maintainer reviewed every change before committing it, taking responsibility for every diff. *Requested* means an agent built it with little or no review, in the style of a "dark factory." *Applied in:* AGENTS.md, Provenance; the README.
- **Release 0.2.0 means a Ruby game on Lota can be playtested on an iPad and on an Android phone,** built through Fledge. *Applied in:* Plan 003, "A game plays on a tablet and a phone".
- **Fledge never surprises an app's developer with how it behaves, or with how it makes Ruby, its globals, built-ins, and standard library behave, compared with not using Fledge.** This is the purpose of Design precedence 2 and of the parity check: a difference from the same program run without Fledge is a bug unless it is justified and documented. *Applied in:* AGENTS.md, Design precedence 2; `doc/contributors/design/launcher.md`, "bin/ruby and restarts".

## 2026-11-03

- **From 1.0.0, Fledge is also released on RubyGems.org, by a person** (with 2026-11-04, below). *Applied in:* Plan 003, "Fledge on RubyGems.org, and runtimes that do not depend on one host" and "1.0"; AGENTS.md, Releasing.
- **The launcher's turning a bare C locale into a UTF-8 one stays until the first app developer reports it as a surprise,** and is then reversed. Every deviation from plain Ruby is documented plainly where app developers read, never hidden. *Applied in:* the README; `doc/contributors/design/launcher.md`, "The locale"; `Parity::JUSTIFIED`.
- **A minor release may add Rubies and change only a default Ruby's patch version.** Ruby does not follow SemVer, so its next minor is expected to break things. Dropping a Ruby, or an operating system version (macOS 26 against 27, not a patch), takes a major version. *Applied in:* `doc/contributors/design/releases.md`, "Versions" and "Ruby minors and runtimes"; `doc/contributors/design/public-interface.md`.
- **Fledge's versioning, tagging, release branches, and backports reuse RatatuiRuby's and Rooibos's,** and differ before and after 1.0.0; the tooling waits on its extraction (2026-11-07, below). *Applied in:* `doc/contributors/design/releases.md`, "Versions" and "From 1.0: release branches and a human publishing"; Plan 003, "1.0".
- **Package managers (winget, Chocolatey, Scoop, Homebrew, apt, pacman, dnf, and their like) are in scope for Fledge's console apps.** *Applied in:* `doc/contributors/research/2026-11-04-app-stores.md`; Plan 003.

## 2026-11-04

- **Nothing is pushed to RubyGems.org before 1.0.0,** so that the name is not held by a project that may not succeed. Before and after 1.0.0, every release has its git tag and the GitHub Release made from it. Before 1.0.0 that is the only place a release is found, so releases rely on it; from 1.0.0 a release is also on RubyGems.org, and the tag and GitHub Release are one way of finding it. *Applied in:* AGENTS.md, Releasing; `doc/contributors/design/releases.md`, "Where releases are" and "From 1.0: release branches and a human publishing"; `doc/contributors/design/public-interface.md`, "Frozen for 1.x"; Plan 003, "Fledge on RubyGems.org, and runtimes that do not depend on one host" and "1.0".
- **An agent never opens an account, free or paid, on any service,** a second host for release files included. When one is wanted, the agent asks in a `question` issue, with suggestions. *Applied in:* AGENTS.md, Questions.
- **Drag-to-fuse, as LÖVE's fused games have it, is in scope,** because supporting Lota, a faithful port of LÖVE to Ruby, is a main purpose of Fledge, and a command line can be daunting to a newcomer. *Applied in:* Plan 003, "Build from a built app, and the files an app opens".
- **Making an app for another system from an already built app is allowed** when it adds little code, complexity, and room for bugs, and above all needs no cross-compiling. *Applied in:* `doc/contributors/design/desktop-apps.md`, "Building from a built app".
- **The accounts and certificates that the stores need (Apple, Microsoft, Google, and the rest) are paid for,** which ends the entries of 2026-11-02 that no money is spent; an agent still never opens an account. *Applied in:* Plan 003's store and signing stories.

## 2026-11-07

- **setdef licenses Fledge under the MIT license.** Released tags through `v0.7.0` keep the license they were released under. *Applied in:* every file's SPDX header, `LICENSE`, the gemspec, each app's `notices/NOTICES.txt`, the README, AGENTS.md, Licensing.
- **Fledge's release tooling waits until RatatuiRuby's agents finish extracting `ratatui_ruby-devtools`, and its parts that are not RatatuiRuby's are extracted again** for Fledge, Lota, and the rest. Nothing is ported before then, and Fledge's agents do that second extraction only when explicitly told to. *Applied in:* Plan 003, "Fledge on RubyGems.org, and runtimes that do not depend on one host" and "1.0"; `doc/contributors/design/releases.md`, "From 1.0: release branches and a human publishing".

## 2026-11-08

- **Agents finish everything for 1.0.0 that the project's developer accounts do not block;** the rest is tested by the maintainer, or by an agent he directs. This does not say which tests must pass before 1.0.0 is tagged. *Applied in:* `doc/contributors/releasing-1.0.md`; Plan 003.
- **Agents cut 0.x releases as work accumulates,** so that the newest 0.x release has what 1.0.0 will. *Applied in:* AGENTS.md, Releasing; `doc/contributors/design/releases.md`, "Versions".
- **Agents keep a current, clear list of the tests that wait on the project's developer accounts.** Which of them block 1.0.0 is decided later, by the maintainer. *Applied in:* `doc/contributors/account-tests.md`; AGENTS.md, Releasing.

## 2026-11-09

- **Fledge's releases carry Ruby 4.1 preview runtimes in place of Ruby 4.0's,** Ruby 4.0 is dropped (but for the one release below), and Fledge 1.0.0 waits for Ruby 4.1.0. *Applied in:* `doc/contributors/design/releases.md`, "Ruby minors and runtimes"; Plan 003, "1.0".
- **One last Fledge release on Ruby 4.0.9 is made before the first on Ruby 4.1,** as long as it does not meaningfully delay the move to 4.1. *Applied in:* `doc/contributors/design/releases.md`, "Ruby minors and runtimes"; Plan 003, "1.0".

## 2026-11-12

- **Fledge builds an MSIX package for a Windows app,** so that a developer can ship through the Microsoft Store, which signs the package during certification, without a code-signing certificate of their own.
- **Gems whose extensions are written in Rust build for iOS and Android,** as they do for the desktops; Tauri shows it can be done.
- **Gems whose extensions build without an `extconf.rb` build for iOS and Android too,** as other languages' tools do it.
- **ffi gems work on iOS and Android, and fiddle is in the iOS runtime.**
- **A difference from `ruby main.rb` is accepted only when it is truly justified;** every difference that could be closed is a bug to fix, and a serious risk to the project.
- **Every agent works trunk-based, as trunkbaseddevelopment.com and the trunk-based development skill describe:** small green commits pushed straight to `trunk` within minutes, no long-lived or sideways branches, no push to find out whether CI passes, and a red `trunk` reverted at once. *Applied in:* AGENTS.md, Working as an agent.

## 2026-11-19

- **One 0.x release is the release candidate for 1.0.0, and has everything 1.0.0 will.** The maintainer's testing is done on it, and if all of it passes, 1.0.0 is made from it with nothing added. *Applied in:* `doc/contributors/design/releases.md`, "Versions".

## 2026-11-21

- **Fledge does not name Windows 10, whose support has ended, as a system its apps run on;** the oldest Windows it names is Windows 11. *Applied in:* `README.md`; `README.rdoc`; `doc/contributors/design/releases.md`, "Platform floors"; `doc/contributors/account-tests.md`.
- **1.0.0 ships with no bug the project knows of,** so the candidate has none. *Applied in:* `doc/contributors/design/releases.md`, "Versions".
- **Fledge is tested against a recent Ruby on every platform, not only Windows,** and supports Lota and Tokra in testing with its releases and shipping sample apps on recent Rubies. *Applied in:* `.github/workflows/ruby-master.yml`; `doc/contributors/design/runtimes.md`, "Testing against Ruby's master" and "Fledge's own Ruby builds".
- **An app's developer who has the right to distribute a file with their app can do it with Fledge.** Where distributing a file needs a right only the developer can hold, Fledge gives the developer a way to do it, and does not refuse the app for want of a right it cannot check; the right stays the developer's, as a gem's license does (2026-10-28).
- **Nothing setdef publishes carries Microsoft's Visual C++ runtime:** not the gem, a runtime, a release's files, a fixture, or an app that Fledge's CI builds and uploads. *Applied in:* `doc/contributors/design/gems.md`, "The Visual C++ runtime".
- **The repository holds no running account of the project's state for the next session.** *Applied in:* CONTRIBUTING.md, "After a push" and "When CI fails"; `doc/contributors/design/releases.md`, "How a release is made"; AGENTS.md, Project.
- **An app under `examples/` is a small realistic app that does something useful, however simple.** An app that only starts and exits is a fixture under `test/`. *Applied in:* `examples/libui_app`; `test/fixtures/libui`.

## 2026-11-22

- **A bug in someone else's project is not Fledge's bug.** *Applied in:* `doc/contributors/design/releases.md`, "Versions".
- **The candidate for 1.0.0 has automation that takes care of every update:** when an input a runtime is built from has a newer release upstream, Fledge moves the pin, proves the new runtimes in CI, and releases, with no person or agent in the loop on the happy path, and nobody notified. It governs a release an upstream has made, not one it has not: a library compiled into another project's Ruby build is as new as that build, and a lag there is a stated dependency (the entry on jdx/ruby, below). *Applied in:* `doc/contributors/design/releases.md`, "Versions"; `.github/workflows/pin-watch.yml`.
- **A deterministic process that a person has decided to trust, such as a GitHub Actions workflow that the maintainer has set RubyGems.org to trust, may publish Fledge there,** and that counts as the person's act; an agent never sets up that trust. *Applied in:* AGENTS.md, Releasing; `doc/contributors/design/releases.md`.
- **The oldest macOS a Fledge app runs on may be raised to 15, and to 26 if keeping 15 becomes costly.** The weighing is the agents', and they chose 26. *Applied in:* ADR 100; `doc/contributors/design/releases.md`, "Platform floors".
- **The glibc switch may land before the candidate, and whether to switch away from rv-ruby entirely is the agents' to judge.** *Applied in:* ADR 100.
- **There is no deadline; quality comes first.**
- **Fledge may carry, in a Mac app, libraries from the developer's computer that the app's gems link, when the app's developer chooses it.** The choice and the licenses are the developer's, as with the app's gems (2026-10-28), and neither setdef nor Fledge takes responsibility for them. Whether to build it is the agents' to judge; if built, it is in the candidate for 1.0.0. *Applied in:* `doc/contributors/design/gems.md`, "Libraries a Mac app carries".
- **CI is improved by whatever reduces wall-clock time, the risk of a red `trunk`, metered usage, and real-world regressions, and whatever shortens cycle time and raises confidence.**
- **Fledge publishes no copies of the files Gradle downloads, and keeps no pinned sets of them;** CI relies on Gradle's own retries. *Applied in:* `doc/contributors/design/phone-projects.md`, "Gradle's downloads in CI".
- **A question is about something that exists or is about to; nothing hypothetical is asked.** *Applied in:* AGENTS.md, Questions.
- **When a platform is added, the first check is whether a maintained project already publishes a portable Ruby for it,** before Fledge builds one. *Applied in:* AGENTS.md, How to work.
- **Intel Mac is a non-decision: Fledge builds no Intel Mac apps.** *Applied in:* ADR 100; `doc/contributors/design/runtimes.md`, "The Mac's Ruby is jdx/ruby's".
- **Fledge takes its macOS and glibc Linux Ruby from jdx/ruby and builds none of its own,** trusting a widely used project over build automation of its own that is unproven, on which a developer would rely just the same; a lag in that project's libraries is a stated dependency. *Applied in:* ADR 100; `doc/contributors/design/runtimes.md`, "Why Fledge builds no Ruby for macOS and glibc Linux".
- **The candidate carries whatever Ruby the runtimes carry on the day it is cut, and 1.0.0 waits for Ruby 4.1.0;** between them nothing is meant to change but the pin to Ruby 4.1.0 and what newer builds of Ruby force. *Applied in:* `doc/contributors/design/releases.md`, "Versions" and "The day Ruby 4.1.0 appears".
- **Fast, reliable tests are a maxim.** A test that is slow for its tier, or fails for no fault in the code, is a defect to fix. *Applied in:* CONTRIBUTING.md, "The tests" and "When CI fails"; AGENTS.md, Commands.
