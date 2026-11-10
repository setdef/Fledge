<!--
SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>

SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Fledge's Architecture

This document names the parts of Fledge and how they fit, points to the design document for each, and indexes every Architecture Decision Record. A contributor who knows nothing of Fledge starts here, then reads `doc/contributors/handoff.md` for where things stand. ADR 001 decides the shape of a built app, ADR 010 that each platform's app is built on that platform, and ADR 034 that runtimes are prebuilt in Fledge's CI; the rest are indexed below.

## The parts

Fledge copies a program its developer already runs, with its project and the gems its `Gemfile.lock` locks, into a relocatable CRuby runtime for the platform it runs on, beside a small C launcher, and archives the result.

- **The command line.** `exe/fledge` is the command; its comment header is the help `fledge --help` prints. `Fledge::CLI` runs it and `Fledge::CLI::Build` runs `fledge build`, through streams a test can replace (ADR 002). `Fledge::Config` reads the optional `fledge.yml` (ADR 044), which `lib/fledge/config.schema.json` describes (ADR 023).
- **Assembly.** For a desktop build, `fledge build` finds the project's root and program (`Fledge::App`; ADR 005), reads the lockfile with Bundler and picks each gem's build for the platform (`Fledge::Bundle`), fetches, installs, and when needed compiles the gems into the runtime's gem folder (ADR 006), downloads the runtime and checks it against the pins the gem carries (`Fledge::Runtimes`; ADR 014), copies the project into `app/`, writes `fledge.cfg`, gives the app its identity (ADR 008), signs it on request (ADR 016), archives it with the computer's own tar (ADR 047), and writes its installers (ADR 009). `doc/contributors/design/desktop-apps.md` and `doc/contributors/design/gems.md` describe this.
- **Desktop runtimes.** A runtime is a relocatable CRuby, whole (ADR 039), with the launcher, Fledge's RubyGems defaults, the tools installers need, and the notices its licenses ask for. `tasks/runtime_builder/` builds one per platform from the inputs `runtime/sources.yml` pins (ADR 035, ADR 017), and the license audit (`tasks/license_audit/`, `runtime/licenses.yml`) passes each before it is archived (ADR 004). `doc/contributors/design/runtimes.md` and `doc/contributors/design/license-audit.md` describe them.
- **The launcher.** `runtime/launcher/` is the C program at the top of every desktop app, and `bin/ruby` beside it. It embeds CRuby (ADR 001), runs the program as `ruby` would (ADR 003), hides the person's Ruby settings from Ruby's boot (ADR 040), and sets up Bundler as `bundle exec` would (ADR 045). `doc/contributors/design/launcher.md` describes it.
- **Phone runtimes.** On iOS, iPadOS, and Android, Ruby is a static library Fledge builds from source (ADR 011), with an embedding API in C, `runtime/mobile/`, that does the launcher's work (ADR 061). `fledge build ios` and `fledge build android` write a project the developer builds, signs, and submits with Xcode or Gradle (ADR 012). `doc/contributors/design/phones.md` describes them.
- **Proof.** The parity check, the ruby/spec comparison, and Delivery prove a built app runs as Ruby runs it, on a fresh computer with no Ruby (ADR 003). `doc/contributors/design/parity.md` describes them.
- **CI and releases.** `.github/workflows/ci.yml` runs the gate, builds every runtime, runs the tests, the parity check, and ruby/spec, builds the example apps on each platform, delivers them on fresh runners and containers, and audits licenses. A tag runs `release.yml`, which publishes the runtimes its commit's CI built and tested (ADR 053), then `installed.yml`, which installs Fledge from the tag and delivers apps with the published runtimes, and `package-managers.yml`. `doc/contributors/design/releases.md` describes versions and releases, and `doc/contributors/design/public-interface.md` what a release promises.

## Design documents

| Document | What it describes |
|---|---|
| `doc/contributors/design/architecture.md` | the parts, how they fit, and the index of ADRs |
| `doc/contributors/design/launcher.md` | the desktop launcher and `bin/ruby` |
| `doc/contributors/design/runtimes.md` | what a desktop runtime holds, and how it is built |
| `doc/contributors/design/license-audit.md` | the license policy, the audit, and the notices it writes |
| `doc/contributors/design/gems.md` | how `fledge build` reads, fetches, compiles, and ships an app's gems |
| `doc/contributors/design/desktop-apps.md` | what `fledge build` writes on a desktop: folders, archives, identity, installers |
| `doc/contributors/design/signing.md` | signing and notarization |
| `doc/contributors/design/phones.md` | phone runtimes and the projects `fledge build` writes for phones |
| `doc/contributors/design/parity.md` | how Fledge proves an app runs as Ruby runs it |
| `doc/contributors/design/public-interface.md` | what a release promises, and what a wrapper may rely on |
| `doc/contributors/design/releases.md` | versions, Rubies, floors, and how a release is made |

## Architecture Decision Records

Each ADR in `doc/contributors/adr/` records one decision: its context, the options weighed, the choice, and what it costs. Numbers are never reused; 015, 018, 019, and 020 were retired, their decisions folded into other ADRs.

Dated records, such as finished plans and research notes, cite ADRs by number and section as they stood on their dates; git keeps those versions.

| ADR | Title |
|---|---|
| [001](../adr/001.md) | Ship an app as a small C launcher that embeds CRuby |
| [002](../adr/002.md) | `fledge` and an app's launcher follow GNU's and sysexits' conventions |
| [003](../adr/003.md) | An app's program runs as `ruby PROGRAM` runs it, with nothing of Fledge's between |
| [004](../adr/004.md) | Every runtime passes a license audit, which writes its notices |
| [005](../adr/005.md) | Ship the program the developer already runs, with its project |
| [006](../adr/006.md) | Compile a gem that has no fitting build, on its own platform, against the runtime's Ruby |
| [007](../adr/007.md) | An app's gems are its developer's, licenses and all |
| [008](../adr/008.md) | An app shows the identity its `fledge.yml` gives it |
| [009](../adr/009.md) | A windowed app gets its platform's installers unless `fledge.yml` says otherwise; a console app gets none |
| [010](../adr/010.md) | Build each platform's app on that platform, with its own tools |
| [011](../adr/011.md) | On a phone, Ruby is a static library Fledge builds from source |
| [012](../adr/012.md) | For a phone, `fledge build` writes a project the developer builds, signs, and submits |
| [013](../adr/013.md) | Read compiled files with the system's own objdump, and llvm-readobj for PE |
| [014](../adr/014.md) | Each Fledge version pins its runtimes by SHA-256 in the gem |
| [016](../adr/016.md) | Sign with the developer's own identity, through `--sign` and each system's signer |
| [017](../adr/017.md) | Build musl Linux's Ruby from source in Alpine |
| [021](../adr/021.md) | Offer a `.deb`, opt-in, built by dpkg-deb |
| [022](../adr/022.md) | Compile a phone's extensions with mkmf against the phone Ruby, link them in, and register them |
| [023](../adr/023.md) | Write `fledge.yml`'s JSON Schema by hand, and test it against Config |
| [024](../adr/024.md) | Ship a project's several programs in one folder, with one runtime |
| [025](../adr/025.md) | A phone project takes its host's files from the app's own project |
| [026](../adr/026.md) | A restart through `RbConfig.ruby` starts the app's launcher again |
| [027](../adr/027.md) | Aim an `extconf.rb`'s CMake at the phone through `CMAKE_TOOLCHAIN_FILE` |
| [028](../adr/028.md) | Version Fledge by SemVer, with a major whenever a break is ready, after a deprecation |
| [029](../adr/029.md) | Fledge's public interface is its command and the files it reads and writes |
| [030](../adr/030.md) | Libraries a gem loads from the Linux distribution are listed by soname and expected of the host |
| [031](../adr/031.md) | `FLEDGE_RUNTIME_MIRROR` replaces the release's host, with no fallback |
| [032](../adr/032.md) | Build a new app from an app already built (`--from`) |
| [033](../adr/033.md) | Notarize on request, through a notarytool keychain profile |
| [034](../adr/034.md) | Prebuild each platform's runtime in Fledge's CI, and publish it with the release |
| [035](../adr/035.md) | Take CRuby from rv-ruby on macOS and glibc Linux, and from RubyInstaller on Windows, x64 and ARM64 |
| [036](../adr/036.md) | Name targets by their RubyGems platform |
| [037](../adr/037.md) | Two kinds of app, console and windowed, each with a launcher built for its kind |
| [038](../adr/038.md) | On Windows, keep RubyInstaller's tree whole and load Ruby's DLL at run time |
| [039](../adr/039.md) | A runtime is a whole standard Ruby, pruned only of what no running code reads |
| [040](../adr/040.md) | Hide the person's Ruby settings from Ruby's boot, and restore them before the program runs |
| [041](../adr/041.md) | Turn a bare C locale into a UTF-8 one in every Ruby of a runtime, until a developer finds it a surprise |
| [042](../adr/042.md) | Ship libxcrypt and GNU MP as shared libraries a person can replace |
| [043](../adr/043.md) | Each runtime carries the sources its licenses ask for |
| [044](../adr/044.md) | Configure an app with an optional `fledge.yml` |
| [045](../adr/045.md) | Run an app that has a Gemfile under the real Bundler, as `bundle exec` does |
| [046](../adr/046.md) | Refuse a gem whose compiled files need a library the app's computer may lack |
| [047](../adr/047.md) | Pack and unpack archives with the computer's own tar |
| [048](../adr/048.md) | Take each system's icon files from the developer |
| [049](../adr/049.md) | Installers use NSIS's and AppImage's own releases, with the sources their licenses ask for |
| [050](../adr/050.md) | Sign a Mac app with the hardened runtime and Briefcase's two entitlements |
| [051](../adr/051.md) | Sign a Windows app through the developer's own command |
| [052](../adr/052.md) | An app declares the files it opens, and is offered for them but never made their default |
| [053](../adr/053.md) | A release publishes the runtimes its commit's CI built and tested, and does not test them again |
| [054](../adr/054.md) | The JSON Schema's address is its release's tag |
| [055](../adr/055.md) | An app gets the runtime of the Ruby minor that runs `fledge build` |
| [056](../adr/056.md) | Move Fledge to Ruby 4.1 now, and release 1.0 only after Ruby 4.1.0 |
| [057](../adr/057.md) | Name phone targets so that no desktop gem fits them |
| [058](../adr/058.md) | On a phone, bundled gems with extensions stay gems |
| [059](../adr/059.md) | A phone app's standard streams reach the system log line by line |
| [060](../adr/060.md) | `fledge build` takes the phone as its first operand |
| [061](../adr/061.md) | The phone runtime does the launcher's work, in C |
| [062](../adr/062.md) | Leave export compliance to the developer |
