<!--
SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>

SPDX-License-Identifier: CC-BY-SA-4.0
-->

# The License Audit

This document says how Fledge checks that what it copies into apps meets the license policy, and what it writes from that check: the policy's categories and how an SPDX expression is judged, what the audit reads and with which tools, the checks and their violations, `NOTICES.txt` and the SBOM, `notices/sources/` and the source bundles, CI's proofs, the phones, and the generated licensing page. The rule it checks is the maintainer's: an app's developer owes nothing beyond notices for what Fledge copies in, and an LGPL library ships only with the library's own source on offer, never the app's (`decisions.md`, 2026-10-26, decisions 8 and 24, and the replies after them). Why the installers carry NSIS's and AppImage's own releases is in `doc/contributors/design/desktop-apps.md`, "The NSIS setup program" and "The AppImage". The policy covers Fledge's runtimes only: an app's own gems are its developer's (`doc/contributors/design/gems.md`, "Checks that are not about licenses"), and `fledge build` judges no gem by its license. For app developers, `doc/licensing.md` is the page this audit generates.

## Why the build runs the audit

Asked about a page that lists what ships on each platform, the maintainer answered "Better to automate this as part of the DevOps pipeline, yes?" (`decisions.md`, 2026-10-26, later). So the audit runs inside the runtime build, in `RuntimeBuilder#license`, after the recipe builds the folder and before anything is archived, and a runtime that breaks the policy is never produced: no CI artifact, test, Delivery, or release can hold one. The notices, the SBOM, and the licensing page come from what the audit found in the tree. Notices kept by hand, a `notices/README.txt` and folders of license texts with each source's notice in `runtime/sources.yml`, record only what someone meant to ship. An audit as a CI job beside the build could be skipped, or fall out of step with it. The model is cargo-deny's `licenses` check, which fails a Rust build on any dependency whose license is not allowed.

No maintained tool judges a whole runtime tree this way, so the audit's rules are Fledge's own code, in `tasks/license_audit/`. The map must be kept exact, every file with an owner and every compiled component with an evidence string, so a routine pin update costs a map edit ("When a pin moves").

## The policy and its categories

`Fledge::LicensePolicy` (`lib/fledge/license_policy.rb`) holds the policy. It puts every SPDX license expression in one of five categories, from least restrictive to most (`CATEGORIES`):

| Category | Licenses | Allowed for |
|---|---|---|
| `notice_only` | `NOTICE_ONLY`: permissive licenses, each with its reason in the file | any component |
| `file_level` | `FILE_LEVEL`: file-level copyleft | a component of kind `files`, shipped as unmodified files whose source form is the file itself, such as the CA bundle |
| `source_offer` | `SOURCE_OFFER`: a license that asks only that a binary say where its source is (CPL-1.0, section 3) | a component whose source Fledge publishes, such as NSIS |
| `shared_library` | `SHARED_LIBRARY`: the LGPL | a component of kind `shared_library` with a source pin in `runtime/sources.yml`, or one linked into another component as the next sections say |
| `forbidden` | everything else: the GPL and the AGPL, any copyleft not listed, an unknown license, an empty or malformed expression, and `NOASSERTION` (a gem that declares no license) | nothing |

A component of kind `source`, the published source of a pinned component in `notices/sources/`, is allowed under its own license whatever its category, since carrying source asks nothing of the app; see "notices/sources/ and the source bundles".

Fledge's own files in a runtime (the launcher, `bin/ruby`'s Fledge code, the RubyGems defaults, the phones' embedding API) are MIT (`decisions.md`, 2026-11-07), so `notice_only`. Their components in `runtime/licenses.yml` say `first_party: true`, which names them as Fledge's in `NOTICES.txt` and `doc/licensing.md` and forbids any LGPL library linked into them.

## How an SPDX expression is judged

`LicensePolicy::Expression` reads an expression as SPDX 2.3, annex D, reads one:

- `OR` takes the least restrictive alternative, since whoever ships may choose any: `Ruby OR BSD-2-Clause` is `notice_only`.
- `AND` takes the most restrictive part, since each must hold: `MIT AND MPL-2.0` is `file_level`.
- `WITH` an exception in `EXCEPTIONS` (GCC-exception-3.1, LLVM-exception, Bison-exception-2.2) makes the license it follows `notice_only`: `GPL-3.0-or-later WITH GCC-exception-3.1`, GCC's runtime library, is.
- A gem's licenses, as its specification lists them, are joined with `OR` (`LicensePolicy.gem_license`), since RubyGems lists the licenses a gem may be taken under; `BSDL` and `PSFL` are read as `BSD-2-Clause` and `PSF-2.0` (`ALIASES`).

## LGPL linked into a component that is not Fledge's

An LGPL component may ship in one of two ways (`LicenseAudit::Policy#check_shared_library`, `tasks/license_audit/policy.rb`):

1. **As its own shared library:** kind `shared_library`, with a source pin, every file it owns an ELF, Mach-O, or PE file, and its code compiled into no other file. libxcrypt and GNU MP ship so: libxcrypt as `lib/libcrypt.so.2` on glibc Linux (`doc/contributors/design/runtimes.md`, "libxcrypt on glibc Linux"), and GNU MP as RubyInstaller's `libgmp-10.dll`, unchanged, on Windows. Shipped so, the LGPL asks for a notice, the library's source, the means to replace it, and app terms that permit reverse engineering to debug such a replacement (LGPL-2.1, section 6; LGPL-3.0, section 4), and never for the app's source, which is what the maintainer's replies ask: "Source offer for... the app? Or the LGPL'ed library? Former won't be liked, latter is fine and normal." (`decisions.md`, 2026-10-26, later). A Windows Ruby without GNU MP would mean forking RubyInstaller's packaging onto MSYS2's rolling toolchain, so GNU MP stays, and a developer whose own policy forbids LGPL-3.0 has it to raise.
2. **Linked into another component** (it appears among that component's `embedded` files), when the LGPL component's source is published and every file it is linked into is owned by a component that is not `first_party` and whose own source Fledge publishes too. libfuse, linked into AppImage's runtime, ships so: publishing the runtime's complete source with libfuse's is what LGPL-2.1, section 6(a), asks of a work linked with the library, and it asks nothing of the app inside the AppImage, which only runs as a child of it. The maintainer accepted it on 2026-10-28 (`decisions.md`), over a runtime Fledge built without libfuse (`doc/contributors/design/desktop-apps.md`, "The AppImage").

Fledge's launcher, the program an app's developer ships as their own, may never hold LGPL code, so the second way is closed to every `first_party` component. The Linux launcher's typelib check holds none either: it links neither libgirepository nor GLib, both LGPL, and includes none of their headers; in a child process, and only for an app that lists typelibs, it opens the computer's own `libgirepository-1.0.so.1` by name and calls one function, whose prototype, and the three fields of GLib's `GError` it reads, it declares itself from their reference documentation (`doc/contributors/design/launcher.md`, "System libraries on Linux"). A runtime carries neither library. A copyleft library's byte signature anywhere else fails as `static-copyleft`.

## The map: runtime/licenses.yml

`runtime/licenses.yml` is the one place a component's license and notice are recorded. Its header says each key; in outline:

- `system_libraries`: per operating system, the libraries the system provides, as patterns, which a runtime need not ship.
- `platforms`: per platform, its operating system, Ruby's `arch` and the gem extensions folder's name, the extension of a Ruby extension, and, where Ruby's tree does not start at the top, its `prefixes` (`ruby/` on Windows; each XCFramework slice on iOS).
- `signatures`: byte strings found only in a copyleft library's own code (libxcrypt's, GNU MP's, libfuse's).
- `components`: in the order that decides which owns a file two match, each with its `kind` (`program`, `shared_library`, `files`, `source`), `files`, `binaries` (which of its files may be compiled code), `embedded` (files it is compiled into, each with an `evidence` string), `source` (its pin in `runtime/sources.yml`), `sha256` (files pinned by hash), `first_party`, `fallback`, and `ruby_build`. An entry marked `ruby_build: upstream` describes a runtime made from the Ruby rv-ruby or RubyInstaller publishes, one marked `ruby_build: fledge` a runtime made from Fledge's own build of Ruby (`doc/contributors/design/runtimes.md`, "Fledge's own Ruby builds"), and the audit, the source bundle, and the licensing page take only the entries of the build that the platform's Ruby pin in `runtime/sources.yml` names, `build: fledge` or nothing (`LicenseAudit.entries`). Where the two builds compile in another Rust or another OpenSSL, each has its own entry and its own evidence, so neither runtime passes on the other's.
- `gems`: notes on gems whose license texts are not where the audit looks.
- `reviewed`: text files whose words name a copyleft license, each reviewed by a person, with why it is not copyleft code.

Patterns are `File.fnmatch` globs relative to the tree; `{prefix}`, `{arch}`, `{gem_arch}`, `{so}`, `{abi}`, and `{fledge_version}` expand per platform (`LicenseAudit#expand`); `{abi}` is the name of the folders Ruby keeps its library and gems in, such as `4.1.0+5`, which the audit reads from the tree (`LicenseAudit#abi`).

## What the audit reads

`LicenseAudit#call` (`tasks/license_audit.rb`) derives the inventory from the tree, not from what the build meant to put there:

- **Every file and symbolic link,** relative to the tree, except the two files the audit writes (`notices/NOTICES.txt`, `notices/sbom.spdx.json`). An Android `.aar` is a zip, whose entries an app ships, so each entry is read with `unzip` and named `FledgeRuby.aar!ENTRY`.
- **Every gem's specification** in the tree, whose declared license makes the gem a component of its own (`LicenseAudit::Inventory`). A gem's executables in `bin/` belong to the gem.
- **Every cached `.gem`,** which holds files Ruby never installed into the gem's folder: each file inside is read as `GEM.gem!PATH`, for copyleft words, compiled code, and copyleft signatures (`LicenseAudit::CopyleftText`).
- **Every compiled file's links,** with the tools of "Which tools read compiled files": the libraries it needs, and on Windows the side-by-side assemblies its manifest names, found in its bytes, as `strings` would.
- **Every text file's words,** up to 4 MB, for a copyleft license's name (`LicenseAudit::COPYLEFT_WORDS`).

## Which tools read compiled files

`LicenseAudit.readers` chooses the readers (`Fledge::Binary::Readers`): LLVM's `llvm-objdump` and `llvm-readobj` from the folder `FLEDGE_LLVM` names, which read every format; or else the computer's own objdump, which reads ELF on Linux and ELF and Mach-O on a Mac. A recipe may choose its own (`Recipe#readers`).

| Where the audit runs | Reads with |
|---|---|
| The macOS runtime build | Xcode's command line tools' `objdump` (LLVM's) |
| The glibc Linux runtime builds | binutils' `objdump` |
| The musl runtime builds, in Alpine | binutils' `objdump`, from `alpine-packages.sh build` |
| The Windows runtime builds | the pinned llvm-mingw's LLVM tools, which compile the launcher |
| The Android runtime build | the NDK's LLVM tools, which compile Ruby |
| The iOS runtime build | Xcode's `objdump` |
| CI's "Licenses", upstream-tree, and licensing-page jobs, and the gate | the pinned llvm-mingw's LLVM tools, through `FLEDGE_LLVM`, on one Linux runner |

A file that begins as compiled code of a format no tool on the computer reads is a violation (`unreadable`): the audit fails rather than pass code it did not read. `fledge build`'s own readers, which `Fledge::Linkage` uses on an app's gems, are `doc/contributors/design/gems.md`, "The linkage check".

Fledge reads the tools' output, never the formats. It once parsed ELF, Mach-O, and PE itself, and the maintainer ruled that out: "Code is a liability and we should _not_ have 4k+ lines of things we could use existing tools for" (`decisions.md`, 2026-10-28). `objdump -p` prints one form for ELF and Mach-O, from GNU's binutils and from LLVM, whose objdump Xcode's command line tools install, so one parser reads both, and a Mac or Linux computer that compiles a gem already has one: `fledge build` there downloads nothing. Windows has no such tool, so each Windows runtime carries LLVM's own `llvm-readobj.exe` in `tools/` (`doc/contributors/design/runtimes.md`, "The tools folder"), which, unlike `llvm-objdump`, reads PE's delay import table. Weighed and not taken: `llvm-readobj` everywhere, which Linux and macOS would download, or every runtime carry, where binutils and Xcode already have a reader; `llvm-objdump` alone, which omits the delay imports; readelf, otool, and vtool, three output forms for what objdump prints in one; and llvm-mingw's `llvm-readobj` in the Windows runtime, which loads libLLVM, libc++, and libunwind, where LLVM's own release has one static file. The sizes weighed are in `doc/contributors/research/2026-11-10-findings-from-the-adrs.md`, "Readers of compiled files: sizes and lines". The costs: a Mac that builds an app with compiled gems needs Xcode's command line tools, and a Linux one binutils, and a missing tool fails the build saying what to install (`Fledge::Binary::Readers`); building a Windows runtime needs zstd or 7-Zip's `7zz`, which `mise.toml` pins, to unpack LLVM's release; and the code that finds the tools, runs them, and reads what they print is not much shorter than the readers it replaced, but knows no format.

## The checks, and the violations they report

Each check reports a violation with a rule, a path, and a message (`LicenseAudit::Violation`); `RuntimeBuilder#license` raises `LicenseAudit::Failure` naming them all.

| Rule | Fails when |
|---|---|
| `unaccounted` | a file belongs to no component and to no gem |
| `unresolved` | a compiled file needs a library neither the system (`system_libraries`) nor the tree provides, or names an assembly whose manifest is not in the tree |
| `unlisted-binary` | a compiled file is one its owner does not list among its `binaries`, so a library nobody reviewed cannot ride in under a broad pattern |
| `stale` | a component's `evidence` string is not in a file it is compiled into, or a file the map pins by SHA-256 moved (GNU MP's DLL, `tools/rcedit.exe`, `tools/llvm-readobj.exe`), so the map cannot go stale quietly |
| `static-copyleft` | a copyleft library's signature is in a file that is not that library's own shared library and that the map does not say it is linked into |
| `macos-floor` | a Mach-O file in a macOS runtime needs a macOS newer than `Fledge::Platform::MACOS_MINIMUM`, or names none, since only a major version raises a floor (`doc/contributors/design/releases.md`) |
| `copyleft-text` | a text file names a copyleft license, its owner's license is notice-only, and no entry in `reviewed` accounts for it |
| `unreadable` | a compiled file no tool reads, or a cached `.gem` the audit cannot open |
| `policy` | a component's license breaks the policy for how it ships |
| `missing-notice` | a component's license text is nowhere: not in its folder of `runtime/notices/`, not among a gem's own license files, and not Ruby's `COPYING` and `LEGAL` for a default gem (`LicenseAudit.problems`) |

## NOTICES.txt

`LicenseAudit::Notices` (`tasks/license_audit/notices.rb`) writes `notices/NOTICES.txt` from the audit's report. In order:

1. a header saying what the file is;
2. every component present, Fledge's first, then the rest, then the gems: its name, version, license, how it ships, and where its source is;
3. Fledge's own files, which they are, and where their source is, at the release's tag; on a desktop it says the first is the program the app's user runs, the launcher `fledge build` renames for the app, which the component `fledge` lists among its binaries there, and on a phone, whose runtime has no launcher, that the app's host, which its developer builds, starts Ruby through them (`Notices#started`);
4. for each LGPL library, that it is not part of the app's own code, that whoever receives the app may replace it, and where its exact source is: first the app's own `notices/sources/`, then the release's source bundle;
5. the source Fledge publishes for the app's installer tools (AppImage's runtime, NSIS), and where;
6. the full text of every license, so the file stands alone wherever it is copied, as the release copies it.

## The SBOM

`LicenseAudit::Spdx` (`tasks/license_audit/spdx.rb`) writes `notices/sbom.spdx.json`, an SPDX 2.3 SBOM: the runtime as one package, which contains a package per component and gem and every file, each file with its SHA-1 (which SPDX 2.3 requires) and SHA-256. Each component `CONTAINS` the files it owns; a file `STATIC_LINK`s each component compiled into it and `DYNAMIC_LINK`s each file in the runtime it loads. Its creation time is `SOURCE_DATE_EPOCH` when that is set, as reproducible-builds.org defines it, or else the time of the build. CI validates every SBOM with `pyspdxtools` from spdx-tools 0.8.3.

## notices/sources/ and the source bundles

`LicenseAudit::SourceBundle` (`tasks/license_audit/source_bundle.rb`) writes, for each component of `runtime/licenses.yml` that has a `source` pin and ships on the platform, a folder holding:

- the pinned source exactly as downloaded, checked against its SHA-256;
- its license texts;
- `BUILD.txt`, which says how the runtime's copy was built from that source and how to build a replacement.

It writes these folders twice:

- into the runtime's `notices/sources/` (`#copy_into`), before the audit, so the audit, the SBOM, and NOTICES see them, and every app, which copies `notices/` whole, carries them;
- into the release asset `fledge-runtime-VERSION-PLATFORM-lgpl-sources.tar.gz` (`#write`), with a `README.txt` beside the folders.

Each folder is owned by a component of kind `source` (`libxcrypt-source`, `gmp-source`, `appimage-runtime-source`, `libfuse-source`, `nsis-source`), whose license is the component's. The policy allows a `source` component only for a pinned source, and only for files of `notices/sources/` that are not compiled code (`Policy#check_source`), so any other file there fails as before.

What each platform carries, from `runtime/licenses.yml`:

| Platform | Folders |
|---|---|
| glibc Linux | libxcrypt, AppImage's runtime, libfuse |
| musl Linux | AppImage's runtime, libfuse |
| Windows, x64 and ARM64 | GNU MP (MSYS2's source package), NSIS |
| macOS, iOS, Android | none, and no `notices/sources/` |

The sources travel inside the runtime because the LGPL binds whoever conveys the library, and that is the app's developer, who conveys it inside the app. With the only copy on a host, their compliance would depend on that host keeping its terms and staying up, and on Fledge never deleting a release; inside the app, it depends on no host. LGPL-2.1, section 6(a), names this way: "Accompany the work with the complete corresponding machine-readable source code for the Library". GPL-3.0, section 6, which LGPL-3.0 uses for GNU MP, likewise lets source go with the object code on the same medium (6(a)) or "in the same way through the same place" (6(d)). The release's bundle alone, and upstream's own archives named by their pinned SHA-256, were weighed: each leaves a host as the only place the source can be had.

The cost is size, about that of the source bundle on each Linux and Windows runtime (`doc/contributors/research/2026-11-10-findings-from-the-adrs.md`, "Sources inside the runtime: sizes"); "Tiny filesize is not a priority" (`decisions.md`, 2026-10-26, decision 20). A Linux or Windows console app carries the installer tools' sources too, though it never holds the tools: `notices/` is one folder for every app.

`BUILD.txt` for GNU MP names MSYS2's source package, which holds GMP's release, MSYS2's patches, and the PKGBUILD, and says how to build a replacement for the platform's triple. The Windows "Runtime" job checks that MSYS2's binary package holds RubyInstaller's DLL byte for byte, which is what makes that source package its exact source. Releases are never deleted, since every NOTICES links its bundle there (AGENTS.md, Releasing).

## The replaceability jobs

CI proves the claim `doc/licensing.md` makes to developers, that whoever receives an app may replace each LGPL library:

- **Replace libcrypt** (`x86_64-linux`, `aarch64-linux`; `.github/scripts/replace-libcrypt.sh`): builds libxcrypt with only its strong hashes from the source in the built hello's own `notices/sources/libxcrypt/`, as a person who received only the app would, and musl's crypt from the `replaceability` pin; swaps each in for `lib/libcrypt.so.2`, and checks the app loads it and `String#crypt` behaves as each does, measuring what is lost without libxcrypt (LGPL-2.1, section 6(b)).
- **Build a replacement libgmp-10.dll** and **Replace GMP** (`x64-mingw-ucrt`, `aarch64-mingw-ucrt`; `.github/scripts/replace-gmp.ps1`): cross-builds an older GNU MP from the `replaceability` pin with the pinned llvm-mingw, swaps it in for `ruby\bin\ruby_builtin_dlls\libgmp-10.dll`, and checks `Integer::GMP_VERSION` changes while a large product does not (LGPL-3.0, section 4(d)(1)). It builds from upstream, not from the app's copy, since it shows a different version loading and needs no particular source.

## The upstream-tree audits

CI's "Licenses of the whole upstream tree" jobs run the audit on the whole tree each runtime comes from, rv-ruby's or RubyInstaller's, for `arm64-darwin`, both glibc Linuxes, and both Windows platforms, with `--expect .github/license-expectations/PLATFORM.yml`. The audit must find exactly the violations that file lists, no more and no fewer (`LicenseAudit::CLI`): what the runtime builder removes or replaces, such as rv-ruby's `bin/ruby` and `lib/libcrypt.a` with libxcrypt linked in, nkf's Java sources in its folder and its cached `.gem`, and MSYS2's GPL keyring. So the audit is shown catching the real thing on every push, not only planted files. musl's tree is Fledge's own build, and the phones' too, so they have no upstream tree to audit.

## The planted-GPL jobs

CI's "Licenses" jobs, one per platform including the phones, run on one Linux runner with LLVM's tools. Each:

1. unpacks the built runtime and checks that its `notices/` matches the release assets beside it: the SBOM and NOTICES byte for byte, and `notices/sources/` against the source bundle file by file, or that a platform with no such component has neither;
2. audits the runtime again;
3. validates the SBOM with `pyspdxtools`;
4. plants a GPL extension, in the platform's own binary format, where Ruby keeps its extensions, and a gem declaring GPL-3.0-only (`.github/scripts/plant_gpl.rb`), and requires the audit to fail naming both (`unlisted-binary` for the extension, `policy` for the gem).

## Phones

Each phone runtime passes the same audit before it is archived. Neither ships an LGPL library: GNU MP is configured out, iOS's `crypt` is its system's, and Android's `String#crypt` is Ruby's own `missing/crypt.c`; the signatures of libxcrypt, GNU MP, and libfuse find none of them. What each ships is in `runtime/licenses.yml` and `doc/licensing.md`; in outline, Ruby, OpenSSL, libyaml, on Android libffi and the NDK's compiler-rt builtins and libunwind, Mozilla's CA bundle as a file, and Fledge's embedding API (component `fledge-embedding`, first party).

Two things differ from a desktop runtime. An iOS runtime has a Ruby per XCFramework slice, so its platform names several `prefixes`, and each gem in them is a component. An Android runtime's AAR is read entry by entry, as "What the audit reads" says. A static archive counts as compiled code, and evidence strings find what is linked into one, as on the desktop.

## Notices a build adds

The audit covers the runtime, and an app's `notices/` is the runtime's, copied whole. One file reaches an app from a third party through `fledge build` and not through the runtime: on Android, the NDK's `libc++_shared.so`, which the build copies from the developer's NDK beside the app's C++ libraries, the extensions Fledge links and those a gem's own build links, all linked against it (`doc/contributors/design/phone-projects.md`, "The NDK's shared C++ runtime"). Its license, Apache-2.0 WITH LLVM-exception, is notice-only, and the exception does not cover the library shipped whole, so it asks for its license's text. The runtime's `NOTICES.txt` cannot carry it: written before any app exists, it would name a file the runtime does not hold, and miss it in the apps that do. So the build that copies the file adds its notice beside the runtime's, as `notices/libc++_shared.txt`, from the same NDK, and only in an app that carries the file ("The C++ runtime's notice", the same document). That holds to the maintainer's rule, that a developer owes nothing beyond the notices Fledge gives for what it copies in. A desktop build copies no such file: the linkage check refuses a gem file that needs a library neither the system, the runtime, nor the gem provides (`doc/contributors/design/gems.md`, "The linkage check"). A future build that copies another third party's file into an app adds its notice the same way, and the licensing page, which describes the runtimes, does not list it.

## The licensing page

`doc/licensing.md` is generated, and never edited by hand. `tasks/licensing_page.rb` writes, per platform (`LicensingPage::PLATFORMS`: every desktop platform, then each phone's), every component, its license, and how it ships; every gem by license; that an app's own gems are its developer's (`doc/contributors/design/gems.md`, "Checks that are not about licenses"); and what the developer must do, with the LGPL's obligations stated as facts with their section numbers, MIT's for Fledge's own files, and a plain instruction to ask one's own lawyer.

Most of the page comes from the repository: Fledge's version, which names the release's assets; each component's name, version, license, and words for how it ships, from `runtime/licenses.yml`, with its corrections of gems' licenses; the Ruby version `runtime/sources.yml` pins; and the generator's prose. Only a little comes from a runtime, and `runtime/audited.yml` records it, as `LicensingPage::Findings`, one entry per platform: the tree's `{prefix}` and `{abi}`; which of the components the map lists for the platform the runtime lacks (the upstream-only entries, such as rv-ruby's build metadata); the files the page names, those of each LGPL library and Fledge's own on `x86_64-linux`; and the license each gem's specification declares. The page is written from that record and the repository, in milliseconds, so `test/licensing_page_test.rb`, a unit test, fails before a push when the page is stale, and says what to do. Before it, the page was written from the runtimes alone, which only CI builds together: a stale page showed only in CI's full run, after the push, and turned `trunk` red 13 times between 2026-10-28 and 2026-11-13. A record of what the page reads, rather than the runtimes' SBOMs or NOTICES, which a contributor's computer has only for a release, keeps the check offline and the record small enough to read in a diff.

- When the unit test says the page is stale, run `mise x -- bundle exec rake licensing` and commit what it writes. It drops from `runtime/audited.yml` what the map no longer asks of it (an absent component the map no longer lists, the files of a component the page no longer names), which an audit under the same map would drop too.
- When the test raises that `runtime/audited.yml` lacks something (a new platform, the files of a component that became an LGPL library), only a runtime built with the change can say it: run `bundle exec rake "licensing[DIR]"`, where `DIR` holds every platform's runtime archive, which writes both files from the audit.
- CI's "Licensing page is current" job runs `ruby tasks/licensing_page.rb --check` against the runtimes it built, fails when either file differs from what they say, and uploads the files it expected; commit those.

The record predicts that a component newly mapped for a platform ships there, and cannot know what a change to a runtime's contents does: a pin that moves (new gems, a new `{abi}`), a file pattern that moves a file of Fledge's or of an LGPL library, or an upstream-only entry added to the map. Those show only in CI's job, as before, which is why it stays.

## When a pin moves

A pin that moves (a new rv-ruby, RubyInstaller, OpenSSL, or Rust) changes what the runtime holds. The runtime build fails, naming each violation, until `runtime/licenses.yml` follows: a new file pattern, a new evidence string, a new SHA-256, a new component and its notice in `runtime/notices/`. Then CI's "Licensing page is current" fails until `runtime/audited.yml` and the page are regenerated from the new runtimes ("The licensing page"). Before a new component lands in `runtime/sources.yml`, check its license and record it in `runtime/licenses.yml` (AGENTS.md, Licensing).
