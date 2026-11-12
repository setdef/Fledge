<!--
SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>

SPDX-License-Identifier: CC-BY-SA-4.0
-->

# The License Audit

This document says how Fledge checks that what it copies into apps meets the license policy, and what it writes from that check: the policy's categories and how an SPDX expression is judged, what the audit reads and with which tools, the checks and their violations, `NOTICES.txt` and the SBOM, `notices/sources/` and the source bundles, CI's proofs, the phones, and the generated licensing page. ADR 004 decides that every runtime passes this audit before it is archived; ADR 013 how compiled files are read; ADR 042 the two LGPL libraries; ADR 043 the sources each runtime carries; ADR 049 the installers' components. The policy covers Fledge's runtimes only: an app's own gems are its developer's (ADR 007), and `fledge build` judges no gem by its license. For app developers, `doc/licensing.md` is the page this audit generates.

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

1. **As its own shared library:** kind `shared_library`, with a source pin, every file it owns an ELF, Mach-O, or PE file, and its code compiled into no other file. libxcrypt and GNU MP ship so (ADR 042).
2. **Linked into another component** (it appears among that component's `embedded` files), when the LGPL component's source is published and every file it is linked into is owned by a component that is not `first_party` and whose own source Fledge publishes too. libfuse, linked into AppImage's runtime, ships so: publishing the runtime's complete source with libfuse's is what LGPL-2.1, section 6(a), asks of a work linked with the library, and it asks nothing of the app inside the AppImage, which only runs as a child of it (ADR 049).

Fledge's launcher, the program an app's developer ships as their own, may never hold LGPL code, so the second way is closed to every `first_party` component. A copyleft library's byte signature anywhere else fails as `static-copyleft`.

## The map: runtime/licenses.yml

`runtime/licenses.yml` is the one place a component's license and notice are recorded. Its header says each key; in outline:

- `system_libraries`: per operating system, the libraries the system provides, as patterns, which a runtime need not ship.
- `platforms`: per platform, its operating system, Ruby's `arch` and the gem extensions folder's name, the extension of a Ruby extension, and, where Ruby's tree does not start at the top, its `prefixes` (`ruby/` on Windows; each XCFramework slice on iOS).
- `signatures`: byte strings found only in a copyleft library's own code (libxcrypt's, GNU MP's, libfuse's).
- `components`: in the order that decides which owns a file two match, each with its `kind` (`program`, `shared_library`, `files`, `source`), `files`, `binaries` (which of its files may be compiled code), `embedded` (files it is compiled into, each with an `evidence` string), `source` (its pin in `runtime/sources.yml`), `sha256` (files pinned by hash), `first_party`, and `fallback`.
- `gems`: notes on gems whose license texts are not where the audit looks.
- `reviewed`: text files whose words name a copyleft license, each reviewed by a person, with why it is not copyleft code.

Patterns are `File.fnmatch` globs relative to the tree; `{prefix}`, `{arch}`, `{gem_arch}`, `{so}`, and `{fledge_version}` expand per platform (`LicenseAudit#expand`).

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
3. Fledge's own files, which they are, and where their source is, at the release's tag;
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

It writes these folders twice (ADR 043):

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

A Linux or Windows console app carries the installer tools' sources too, though it never holds the tools: `notices/` is one folder for every app.

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

## The licensing page

`doc/licensing.md` is generated, and never edited by hand. `tasks/licensing_page.rb` audits every platform's runtime (`LicensingPage::PLATFORMS`: every desktop platform, then each phone's) and writes, per platform, every component, its license, and how it ships; every gem by license; that an app's own gems are its developer's (ADR 007); and what the developer must do, with the LGPL's obligations stated as facts with their section numbers, MIT's for Fledge's own files, and a plain instruction to ask one's own lawyer.

- Regenerate it with `bundle exec rake "licensing[DIR]"`, where `DIR` holds every platform's runtime archive. Change the generator, never the page (AGENTS.md, Licensing).
- CI's "Licensing page is current" job runs `ruby tasks/licensing_page.rb --check` against the runtimes it built, fails when the committed page differs, and uploads the page it expected.

## When a pin moves

A pin that moves (a new rv-ruby, RubyInstaller, OpenSSL, or Rust) changes what the runtime holds. The runtime build fails, naming each violation, until `runtime/licenses.yml` follows: a new file pattern, a new evidence string, a new SHA-256, a new component and its notice in `runtime/notices/`. Then CI's "Licensing page is current" fails until the page is regenerated. Before a new component lands in `runtime/sources.yml`, check its license and record it in `runtime/licenses.yml` (AGENTS.md, Licensing).
