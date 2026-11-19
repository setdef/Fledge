<!--
SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>

SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Fledge's Architecture

This document names the parts of Fledge and how they fit, points to the design document for each, and indexes the Architecture Decision Records. A contributor who knows nothing of Fledge starts here, then reads `doc/contributors/handoff.md` for where things stand. ADR 001 decides the shape of a built app, ADR 010 that each platform's app is built on that platform, and ADR 093 that runtimes are prebuilt in Fledge's CI; the rest are indexed below.

## The parts

Fledge copies a program its developer already runs, with its project and the gems its `Gemfile.lock` locks, into a relocatable CRuby runtime for the platform it runs on, beside a small C launcher, and archives the result.

- **The command line.** `exe/fledge` is the command; its comment header is the help `fledge --help` prints. `Fledge::CLI` runs it and `Fledge::CLI::Build` runs `fledge build`, through streams a test can replace (`doc/contributors/design/public-interface.md`, "The command's conventions"). `Fledge::Config` reads the optional `fledge.yml`, which `lib/fledge/config.schema.json` describes (`doc/contributors/design/public-interface.md`, "The fledge.yml schema").
- **Assembly.** For a desktop build, `fledge build` finds the project's root and program (`Fledge::App`), reads the lockfile with Bundler and picks each gem's build for the platform (`Fledge::Bundle`), fetches, installs, and when needed compiles the gems into the runtime's gem folder, downloads the runtime and checks it against the pins the gem carries (`Fledge::Runtimes`), copies the project into `app/`, writes `fledge.cfg`, gives the app its identity, signs it on request (`doc/contributors/design/signing.md`), archives it with the computer's own tar, and writes its installers. `doc/contributors/design/desktop-apps.md` and `doc/contributors/design/gems.md` describe this.
- **Desktop runtimes.** A runtime is a relocatable CRuby, whole, with the launcher, Fledge's RubyGems defaults, the tools installers need, and the notices its licenses ask for. `tasks/runtime_builder/` builds one per platform from the inputs `runtime/sources.yml` pins (ADR 035), and the license audit (`tasks/license_audit/`, `runtime/licenses.yml`) passes each before it is archived. `doc/contributors/design/runtimes.md` and `doc/contributors/design/license-audit.md` describe them.
- **The launcher.** `runtime/launcher/` is the C program at the top of every desktop app, and `bin/ruby` beside it. It embeds CRuby (ADR 001), runs the program as `ruby` would (ADR 081), hides the person's Ruby settings from Ruby's boot, and sets up Bundler as `bundle exec` would, with the Bundler the lockfile names. `doc/contributors/design/launcher.md` describes it.
- **Phone runtimes.** On iOS, iPadOS, and Android, Ruby is a static library Fledge builds from source (ADR 079), with an embedding API in C, `runtime/mobile/`, that does the launcher's work (ADR 061). `fledge build ios` and `fledge build android` write a project the developer builds, signs, and submits with Xcode or Gradle (ADR 012). `doc/contributors/design/phone-runtimes.md` and `doc/contributors/design/phone-projects.md` describe them.
- **Proof.** The parity check, the ruby/spec comparison, and Delivery prove a built app runs as Ruby runs it, on a fresh computer with no Ruby (ADR 081). `doc/contributors/design/parity.md` describes them.
- **CI and releases.** `.github/workflows/fast.yml` runs the lint and the unit tests on Linux, macOS, and Windows on every push, in minutes, and `.github/workflows/ci.yml`, which a push to trunk never cancels, runs the gate, builds every runtime, runs the tests, the parity check, and ruby/spec, builds the example apps on each platform, delivers them on fresh runners and containers, and audits licenses. A tag runs `release.yml`, which publishes the runtimes its commit's CI built and tested, then `installed.yml`, which installs Fledge from the tag and delivers apps with the published runtimes, and `package-managers.yml`. `doc/contributors/design/releases.md` describes versions and releases, and `doc/contributors/design/public-interface.md` what a release promises.

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
| `doc/contributors/design/phone-runtimes.md` | how phone runtimes are built and what they hold |
| `doc/contributors/design/phone-projects.md` | the projects `fledge build` writes for phones, and the checks before a store |
| `doc/contributors/design/parity.md` | how Fledge proves an app runs as Ruby runs it |
| `doc/contributors/design/public-interface.md` | what a release promises, and what a wrapper may rely on |
| `doc/contributors/design/releases.md` | versions, Rubies, floors, and how a release is made |

## Architecture Decision Records

An ADR in `doc/contributors/adr/` records one decision that changed what Fledge is, and would cost much to undo: its context, the options weighed, the choice, and what it costs. Such decisions are rare. Every other choice, with its reasons, the options weighed, and its prior art, is recorded in the design document for its subject. Numbers are never reused, so the list has gaps.

Dated records, such as finished plans and research notes, cite ADRs by number and section as they stood on their dates; git keeps those versions. Everything else cites only an ADR that `doc/contributors/adr/` holds, and `test/adr_citations_test.rb` fails on any other, so deleting an ADR moves each of its citations to the design-document section that took its reasons.

| ADR | Title |
|---|---|
| [001](../adr/001.md) | Ship an app as a small C launcher that embeds CRuby |
| [010](../adr/010.md) | Build Each Platform's App on That Platform, With Its Own Tools |
| [012](../adr/012.md) | For a phone, `fledge build` writes a project the developer builds, signs, and submits |
| [022](../adr/022.md) | Compile a phone's extensions with mkmf against the phone Ruby, link them in, and register them |
| [025](../adr/025.md) | A phone project takes its host's files from the app's own project: `ios: host:` and `android: host:` |
| [027](../adr/027.md) | Aim an `extconf.rb`'s CMake at the phone through `CMAKE_TOOLCHAIN_FILE` |
| [035](../adr/035.md) | Take CRuby from rv-ruby on macOS and glibc Linux, and from RubyInstaller on Windows, x64 and ARM64 |
| [057](../adr/057.md) | Name phone targets so that no desktop gem fits them |
| [058](../adr/058.md) | On a phone, bundled gems with extensions stay gems |
| [061](../adr/061.md) | The phone runtime does the launcher's work, in C: `fledge_ruby_run_app` |
| [062](../adr/062.md) | Leave export compliance to the developer |
| [067](../adr/067.md) | On a phone, a bundled gem's extension keeps every symbol but its Init function to itself |
| [068](../adr/068.md) | On a phone, a bundled gem's linked extension is found only while its gem is active |
| [072](../adr/072.md) | On a phone, a gem's Rakefile runs as RubyGems runs it, and the extensions it builds with mkmf are linked in |
| [073](../adr/073.md) | On a phone, a gem's Rust extension is built by its own extconf.rb, as a static library, and linked in |
| [074](../adr/074.md) | fiddle and the ffi gem work on both phones |
| [078](../adr/078.md) | A phone app's standard streams reach the system log as they are printed, with nothing an app can read changed |
| [079](../adr/079.md) | On a phone, Ruby is a static library Fledge builds from source |
| [080](../adr/080.md) | On a phone, a Ruby file stands where a desktop has an extension's file, and requires the linked extension |
| [081](../adr/081.md) | An app's program runs as `ruby PROGRAM` runs it, with nothing of Fledge's between |
| [082](../adr/082.md) | On Android, the runtime carries a ruby program the installer extracts with the app's native libraries |
| [083](../adr/083.md) | On Android, RbConfig.ruby names the ruby program through a link at the path stock Ruby derives |
| [088](../adr/088.md) | On a phone, a require of a linked extension's file by its path finds the extension |
| [090](../adr/090.md) | Android's Ruby has YJIT and ZJIT, each off until the app enables it, as on a desktop |
| [093](../adr/093.md) | Prebuild Each Platform's Runtime in Fledge's CI, and Publish It with the Release |
