<!--
SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>

SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Fledge's Architecture

This document names the parts of Fledge and how they fit, points to the design document for each, and indexes every Architecture Decision Record. A contributor who knows nothing of Fledge starts here, then reads `doc/contributors/handoff.md` for where things stand. ADR 001 decides the shape of a built app, ADR 010 that each platform's app is built on that platform, and ADR 034 that runtimes are prebuilt in Fledge's CI; the rest are indexed below.

## The parts

Fledge copies a program its developer already runs, with its project and the gems its `Gemfile.lock` locks, into a relocatable CRuby runtime for the platform it runs on, beside a small C launcher, and archives the result.

- **The command line.** `exe/fledge` is the command; its comment header is the help `fledge --help` prints. `Fledge::CLI` runs it and `Fledge::CLI::Build` runs `fledge build`, through streams a test can replace (ADR 002). `Fledge::Config` reads the optional `fledge.yml` (ADR 044), which `lib/fledge/config.schema.json` describes (`doc/contributors/design/public-interface.md`, "The fledge.yml schema").
- **Assembly.** For a desktop build, `fledge build` finds the project's root and program (`Fledge::App`; ADR 005), reads the lockfile with Bundler and picks each gem's build for the platform (`Fledge::Bundle`), fetches, installs, and when needed compiles the gems into the runtime's gem folder (ADR 006), downloads the runtime and checks it against the pins the gem carries (`Fledge::Runtimes`; ADR 014), copies the project into `app/`, writes `fledge.cfg`, gives the app its identity (ADR 008), signs it on request (ADR 016), archives it with the computer's own tar (ADR 047), and writes its installers (ADR 009). `doc/contributors/design/desktop-apps.md` and `doc/contributors/design/gems.md` describe this.
- **Desktop runtimes.** A runtime is a relocatable CRuby, whole (ADR 039), with the launcher, Fledge's RubyGems defaults, the tools installers need, and the notices its licenses ask for. `tasks/runtime_builder/` builds one per platform from the inputs `runtime/sources.yml` pins (ADR 035, ADR 017), and the license audit (`tasks/license_audit/`, `runtime/licenses.yml`) passes each before it is archived (ADR 004). `doc/contributors/design/runtimes.md` and `doc/contributors/design/license-audit.md` describe them.
- **The launcher.** `runtime/launcher/` is the C program at the top of every desktop app, and `bin/ruby` beside it. It embeds CRuby (ADR 001), runs the program as `ruby` would (ADR 003), hides the person's Ruby settings from Ruby's boot (ADR 040), and sets up Bundler as `bundle exec` would (ADR 045), with the Bundler the lockfile names (ADR 063). `doc/contributors/design/launcher.md` describes it.
- **Phone runtimes.** On iOS, iPadOS, and Android, Ruby is a static library Fledge builds from source (ADR 011), with an embedding API in C, `runtime/mobile/`, that does the launcher's work (ADR 061). `fledge build ios` and `fledge build android` write a project the developer builds, signs, and submits with Xcode or Gradle (ADR 012). `doc/contributors/design/phone-runtimes.md` and `doc/contributors/design/phone-projects.md` describe them.
- **Proof.** The parity check, the ruby/spec comparison, and Delivery prove a built app runs as Ruby runs it, on a fresh computer with no Ruby (ADR 003). `doc/contributors/design/parity.md` describes them.
- **CI and releases.** `.github/workflows/fast.yml` runs the lint and the unit tests on Linux, macOS, and Windows on every push, in minutes, and `.github/workflows/ci.yml`, which a push to trunk never cancels (ADR 071), runs the gate, builds every runtime, runs the tests, the parity check, and ruby/spec, builds the example apps on each platform, delivers them on fresh runners and containers, and audits licenses. A tag runs `release.yml`, which publishes the runtimes its commit's CI built and tested (ADR 053), then `installed.yml`, which installs Fledge from the tag and delivers apps with the published runtimes, and `package-managers.yml`. `doc/contributors/design/releases.md` describes versions and releases, and `doc/contributors/design/public-interface.md` what a release promises.

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

Each ADR in `doc/contributors/adr/` records one decision: its context, the options weighed, the choice, and what it costs. Numbers are never reused, so the list has gaps.

Dated records, such as finished plans and research notes, cite ADRs by number and section as they stood on their dates; git keeps those versions.

| ADR | Title |
|---|---|
| [001](../adr/001.md) | Ship an app as a small C launcher that embeds CRuby |
| [002](../adr/002.md) | `fledge` and an app's launcher follow GNU's and sysexits' conventions |
| [003](../adr/003.md) | An app's program runs as `ruby PROGRAM` runs it, with nothing of Fledge's between |
| [004](../adr/004.md) | Every Runtime Passes a License Audit Before It Is Archived, and the Audit Writes Its Notices |
| [005](../adr/005.md) | Ship the Program the Developer Already Runs, With Its Project |
| [006](../adr/006.md) | Compile a Gem That Has No Fitting Build, on Its Own Platform, Against the Runtime's Own Ruby |
| [007](../adr/007.md) | An App's Gems Are Its Developer's, Licenses and All |
| [008](../adr/008.md) | An App Shows the Identity Its fledge.yml Gives It, With One Name Everywhere |
| [009](../adr/009.md) | A Windowed App Gets Its Platform's Installers Unless fledge.yml Says Otherwise, and a Console App Gets None |
| [010](../adr/010.md) | Build Each Platform's App on That Platform, With Its Own Tools |
| [011](../adr/011.md) | On a phone, Ruby is a static library Fledge builds from source |
| [012](../adr/012.md) | For a phone, `fledge build` writes a project the developer builds, signs, and submits |
| [013](../adr/013.md) | Read Compiled Files with the System's Own objdump, and llvm-readobj for PE |
| [014](../adr/014.md) | The Gem Pins Its Release's Runtimes by SHA-256, From a Pin Commit |
| [016](../adr/016.md) | Sign With the Developer's Own Identity, Through --sign and Each System's Signer |
| [017](../adr/017.md) | Build musl Linux's Ruby from Source in Alpine |
| [021](../adr/021.md) | Offer a .deb, Opt-In, Built by dpkg-deb |
| [022](../adr/022.md) | Compile a phone's extensions with mkmf against the phone Ruby, link them in, and register them |
| [024](../adr/024.md) | Ship a Project's Several Programs in One Folder, With One Runtime |
| [025](../adr/025.md) | A phone project takes its host's files from the app's own project: `ios: host:` and `android: host:` |
| [026](../adr/026.md) | A restart through `RbConfig.ruby` starts the app's launcher again |
| [027](../adr/027.md) | Aim an `extconf.rb`'s CMake at the phone through `CMAKE_TOOLCHAIN_FILE` |
| [028](../adr/028.md) | Version Fledge by SemVer, With a Major Whenever a Break Is Ready, After a Deprecation |
| [029](../adr/029.md) | Fledge's Public Interface Is Its Command and the Files It Reads and Writes |
| [030](../adr/030.md) | Libraries a Gem Loads From the Linux Distribution Are Listed by Soname and Expected of the Host |
| [031](../adr/031.md) | FLEDGE_RUNTIME_MIRROR Replaces the Release's Host, Checked Against the Pins, With No Fallback |
| [032](../adr/032.md) | Build a New App From an App Already Built, With --from |
| [033](../adr/033.md) | Notarize on Request, Through a notarytool Keychain Profile |
| [034](../adr/034.md) | Prebuild Each Platform's Runtime in Fledge's CI, and Publish It with the Release |
| [035](../adr/035.md) | Take CRuby from rv-ruby on macOS and glibc Linux, and from RubyInstaller on Windows, x64 and ARM64 |
| [037](../adr/037.md) | Two kinds of app, console and windowed, each with a launcher built for its kind |
| [038](../adr/038.md) | On Windows, keep RubyInstaller's tree whole and load Ruby's DLL at run time |
| [039](../adr/039.md) | A Runtime Is a Whole Standard Ruby, Pruned Only of What No Running Code Reads |
| [040](../adr/040.md) | Hide the person's Ruby settings from Ruby's boot, and restore them before the program runs |
| [041](../adr/041.md) | Turn a bare C locale into a UTF-8 one in every Ruby of a runtime, until a developer finds it a surprise |
| [042](../adr/042.md) | Ship libxcrypt and GNU MP as Shared Libraries a Person Can Replace |
| [043](../adr/043.md) | Each Runtime Carries the Sources Its Licenses Ask For, in notices/sources/ |
| [044](../adr/044.md) | Configure an App With an Optional fledge.yml |
| [045](../adr/045.md) | Run an App That Has a Gemfile Under the Real Bundler, as bundle exec Does |
| [046](../adr/046.md) | Refuse a Gem Whose Compiled Files Need a Library the App's Computer May Lack |
| [047](../adr/047.md) | Pack and Unpack Archives With the Computer's Own tar |
| [048](../adr/048.md) | Take Each System's Icon Files From the Developer |
| [049](../adr/049.md) | Installers Use NSIS's and AppImage's Own Releases, With the Sources Their Licenses Ask For |
| [050](../adr/050.md) | Sign a Mac App With the Hardened Runtime and Briefcase's Two Entitlements |
| [051](../adr/051.md) | Sign a Windows App Through the Developer's Own Command, Run Through cmd.exe as makensis Runs It |
| [052](../adr/052.md) | An App Declares the Files It Opens, and Is Offered for Them but Never Made Their Default |
| [053](../adr/053.md) | A Release Publishes the Runtimes Its Commit's CI Built and Tested, and Does Not Test Them Again |
| [054](../adr/054.md) | The JSON Schema's Address Is Its Release's Tag |
| [055](../adr/055.md) | An App Gets the Runtime of the Ruby Minor That Runs fledge build |
| [056](../adr/056.md) | Move Fledge to Ruby 4.1 Now, and Release 1.0 Only After Ruby 4.1.0 |
| [057](../adr/057.md) | Name phone targets so that no desktop gem fits them |
| [058](../adr/058.md) | On a phone, bundled gems with extensions stay gems |
| [059](../adr/059.md) | A phone app's standard streams reach the system log line by line |
| [061](../adr/061.md) | The phone runtime does the launcher's work, in C: `fledge_ruby_run_app` |
| [062](../adr/062.md) | Leave export compliance to the developer |
| [063](../adr/063.md) | Run the Bundler the Lockfile Names, as bundle exec Does |
| [064](../adr/064.md) | A Windowed App's Identifier Is the Developer's, and No Default Makes One Up |
| [065](../adr/065.md) | Keep an Input Whose URL Rolls Over as a Pre-release of Fledge |
| [066](../adr/066.md) | Keep Every Platform on One Ruby 4.1 Release at a Time |
| [067](../adr/067.md) | On a phone, a bundled gem's extension keeps every symbol but its Init function to itself |
| [068](../adr/068.md) | On a phone, a bundled gem's linked extension is found only while its gem is active |
| [069](../adr/069.md) | On Android, the runtime carries a ruby program the installer extracts with the app's native libraries |
| [070](../adr/070.md) | A Windows App Declares UTF-8 as Its ANSI Code Page |
| [071](../adr/071.md) | Trunk's Full CI Runs Are Never Cancelled, and a Fast Tier Judges Every Push |
| [072](../adr/072.md) | On a phone, a gem's Rakefile runs as RubyGems runs it, and the extensions it builds with mkmf are linked in |
