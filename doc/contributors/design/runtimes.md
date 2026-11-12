<!--
SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>

SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Desktop Runtimes

This document says what a desktop runtime holds and how `rake runtime` (`tasks/runtime_builder.rb`) builds one: the layout on each platform, where each input comes from and how it is pinned, what is kept and what is pruned, Fledge's RubyGems defaults, the `tools/` folder, the build-only companion, the platform names, and the release assets. ADR 034 decides that Fledge's CI prebuilds the runtimes, ADR 035 where their Ruby comes from, ADR 017 the musl build, ADR 039 what a runtime keeps, ADR 042 the two LGPL libraries, and ADR 038 the Windows layout. The license audit every runtime passes is `doc/contributors/design/license-audit.md`; the phones' runtimes are `doc/contributors/design/phone-runtimes.md`. For app developers, `doc/runtimes.md` says which runtime an app gets.

## What a runtime is

A runtime is a folder: Fledge's launcher at its top, a relocatable CRuby beside it in Ruby's own layout, the tools `fledge build` runs, and `notices/`. `fledge build` unpacks it, copies the app in, and archives the result. Nothing in a runtime records where it was built: on macOS and Linux, Ruby is configured `--enable-load-relative` and finds its library from the program that holds libruby; on Windows, Ruby finds its prefix from its DLL's own path.

Every runtime is a `.tar.gz` with one top folder, named as the asset is without its extension (`tasks/release_archive.rb`), on Windows too: only Fledge reads it.

The build runs in this order (`RuntimeBuilder#call`):

1. the platform's recipe builds the folder (`tasks/runtime_builder/`);
2. `LicenseAudit::SourceBundle#copy_into` writes `notices/sources/`;
3. `RuntimeBuilder#license` audits the folder and writes `notices/NOTICES.txt` and `notices/sbom.spdx.json`, or raises and archives nothing;
4. the folder is archived, and the SBOM, NOTICES, and source bundle are written beside it;
5. the build-only companion is archived.

A recipe builds only on the computers it names (`Recipe#hosts`): each Unix runtime on its own platform, since its launcher links that platform's libruby; the Windows runtimes on any computer llvm-mingw is pinned for.

## Layout on macOS and Linux

| Path | What it is |
|---|---|
| `launcher` | Fledge's launcher, `runtime/launcher/unix.c` and the rest, linked with the static libruby. `fledge build` renames it for the app. |
| `bin/ruby` | Ruby's own `main.c` (`runtime/launcher/ruby_main.c`), linked with the same libruby and the same link line, so `RbConfig.ruby` and `Gem.ruby` run. Given the app's own program, it hands it back to the app's launcher (ADR 026; `doc/contributors/design/launcher.md`). |
| `bin/*` | The default and bundled gems' executables, as rv-ruby installs them. |
| `include/ruby-X.Y.0/` | Ruby's C headers, which `require "mkmf"` reads at run time (ADR 039). |
| `lib/ruby/` | The standard library, `gems/X.Y.0` with every default and bundled gem, `site_ruby`, and `vendor_ruby`, as Ruby lays them out. |
| `lib/libcrypt.so.2` | libxcrypt, glibc Linux only (ADR 042). |
| `libexec/cert.pem` | Mozilla's CA bundle, which Ruby's `openssl.rb` points OpenSSL at unless `SSL_CERT_FILE` names others. |
| `tools/appimage-runtime` | Linux only, glibc and musl ("The tools folder"). |
| `notices/` | `NOTICES.txt`, `sbom.spdx.json`, and, on Linux, `sources/`. |

`X.Y.0` is the pinned Ruby's ABI folder.

How each program is linked (`tasks/runtime_builder/darwin.rb`, `linux.rb`, `musl.rb`):

- **macOS:** libruby linked whole with `-force_load`, `-mmacosx-version-min` set to the macOS floor, stripped with `strip -x`, and signed ad hoc, since Apple Silicon runs only signed code. The build fails if the program links anything outside `/usr/lib` and `/System/Library`.
- **glibc Linux:** libruby linked whole and its symbols exported (`-rdynamic`), so extensions find them; libgcc's unwinder taken statically (`-static-libgcc`); libxcrypt linked dynamically. Each program has an RPATH, never a RUNPATH, which `LD_LIBRARY_PATH` would override: `$ORIGIN/lib` for the launcher, `$ORIGIN/../lib` for `bin/ruby`. The build fails if a program needs a library beyond glibc's and libcrypt. Extensions are stripped of debug sections, and `patchelf` removes the RUNPATHs rv-ruby's build machine left in some (`zlib.so` names a Linuxbrew folder).
- **musl Linux:** as glibc Linux, but with no libxcrypt and no RPATH; the programs may need only musl's C library.

Each program builds with warnings as errors (`RuntimeBuilder::WARNINGS`) and under a static analyzer: clang's on macOS and Windows, gcc's `-fanalyzer` on Linux.

## Layout on Windows

| Path | What it is |
|---|---|
| `launcher.exe` | The console launcher (`runtime/launcher/windows.c`), which loads Ruby's DLL when it runs. |
| `launcherw.exe` | The same launcher built as a GUI program, for windowed apps (ADR 037). |
| `ruby\` | RubyInstaller's tree, its shape unchanged (ADR 038): `bin\` with Ruby's DLL (`x64-ucrt-ruby400.dll` or `aarch64-ucrt-ruby400.dll` for Ruby 4.0), `ruby.exe`, `rubyw.exe`, the gems' wrappers, and `ruby_builtin_dlls\`; `include\`; `lib\ruby\`. |
| `tools\nsis\`, `tools\rcedit.exe`, `tools\llvm-readobj.exe` | What `fledge build` runs ("The tools folder"). |
| `notices\` | `NOTICES.txt`, `sbom.spdx.json`, and `sources\`. |

The launchers may import only `KERNEL32.dll` and the universal C runtime's `api-ms-win-crt-*.dll`, and the windowed one `USER32.dll` for its message box. The build reads each one's PE Subsystem and imports with llvm-mingw's `llvm-readobj` and fails otherwise.

How the launcher loads Ruby's DLL, its manifest, and the variables it hides are `doc/contributors/design/launcher.md`.

## The Windows launcher, cross-compiled with llvm-mingw

The Windows launcher needs only Ruby's headers to build, never a library to link, since it loads Ruby's DLL at run time. So it cross-compiles with llvm-mingw's UCRT toolchain, pinned by version and SHA-256 in `runtime/sources.yml` for each computer that may build a Windows runtime (x86_64 and aarch64 Linux, Apple Silicon macOS). CI builds both Windows runtimes on Linux.

- **UCRT, not msvcrt.** The launcher must share RubyInstaller's C runtime, so that removing a variable from its environment removes it from the one Ruby reads. Ubuntu's own mingw-w64 targets the older msvcrt.
- **Pinned, not MSYS2's.** MSYS2's gcc on a Windows runner rolls and cannot be pinned.
- **One toolchain, two targets.** The triple is `x86_64-w64-mingw32` for `x64-mingw-ucrt` and `aarch64-w64-mingw32` for `aarch64-mingw-ucrt` (`RuntimeBuilder::Windows::TARGETS`).
- **Resources.** llvm-mingw's `windres` compiles `runtime/launcher/windows.rc`, which embeds the manifest (`windows.manifest`), into each launcher.
- **The audit's readers.** The Windows recipe's license audit reads the runtime with the same llvm-mingw's `llvm-objdump` and `llvm-readobj` (ADR 013).

## Sources and pins

Every input that comes from outside the repository is in `runtime/sources.yml`, pinned by version and SHA-256, and `DownloadCache#fetch` (`tasks/download_cache.rb`) refuses a download whose SHA-256 differs. The file's comments say what each pin is and why; its top-level keys group the pins by what they feed: each platform's Ruby (`ruby`, `musl-ruby`, `mobile`), the Windows launcher's compiler (`llvm-mingw`), the libraries a runtime adds (`libxcrypt`, `gmp`), the tools of a runtime's `tools/` folder (`rcedit`, `llvm-readobj`, `nsis`, `appimage-runtime`, `libfuse`), and what only CI's replaceability jobs read (`replaceability`). The phones' pins are described in `doc/contributors/design/phone-runtimes.md`.

`test/runtime_builder_test.rb` checks the pins' shape. CI's tools that build runtimes are pinned beside them: the Ubuntu packages and Xcode version in `ci.yml`'s Runtime job, and the Alpine image and packages for musl ("musl Linux's Ruby, built in Alpine").

The Ruby versions pinned today: `ruby`, `mobile.ruby`, and `musl-ruby.ruby` all name the same release, and the musl build runs in the Alpine Ruby image of that version. A move to a new Ruby moves all of them together.

## The glibc symbols rv-ruby's builds need

rv-ruby's Linux builds call functions glibc added in 2.38 and 2.39 (`pidfd_spawnp`, `pidfd_getpid`, `__isoc23_strtol`, `strlcpy`), so a glibc Linux app needs glibc 2.39 or newer: Ubuntu 24.04, Debian 13, Fedora 40, and later. That is the floor `Fledge::Platform::GLIBC_MINIMUM` names; the floors and when they may move are `doc/contributors/design/releases.md`, "Platform floors".

## libxcrypt on glibc Linux

rv-ruby links libxcrypt, which is LGPL-2.1-or-later, statically into its own `bin/ruby`. A glibc Linux runtime never ships that `bin/ruby`. It builds the same libxcrypt release from its pin with rv-ruby's configure options, shared instead of static (`RuntimeBuilder::Linux::LIBXCRYPT_CONFIGURE`), installs `libcrypt.so.2` into the runtime's `lib/`, stripped, and links the launcher and its own `bin/ruby` against it. The source bundle's `BUILD.txt` prints those options as the way the runtime's copy was built (ADR 042).

musl Linux ships no libxcrypt: musl's own `crypt(3)` serves `String#crypt` (ADR 017).

## The RubyInstaller signing key

Every Windows runtime build checks RubyInstaller's archive against its detached PGP signature (`RuntimeBuilder::Windows#verify`):

1. the signature and the key are downloaded and checked against their SHA-256s;
2. the key's ASCII armor is decoded (`RuntimeBuilder::Armor`, with its CRC-24 checked), since `gpgv` reads only a binary keyring;
3. `gpgv` checks the signature against a keyring of that one key;
4. the signature must be that key's, by the fingerprint the pin names (`VALIDSIG`).

The key is RubyInstaller's package signing key as `oneclick/rubyinstaller2` records it, `recipes/unpack/appveyor-repo-key.asc`, at a pinned commit. Both Windows archives are signed with it.

The pin records the key's expiry. `gpgv` does not judge a key's expiry, so an archive already pinned keeps verifying after that date. When the Ruby pin moves to a RubyInstaller release signed by a renewed or a new key, the agent who moves it pins that key the same way: its URL in `oneclick/rubyinstaller2` at a commit, its SHA-256, its fingerprint, and its expiry. `test/runtime_builder_test.rb` checks that every Windows pin has all four.

## Windows on ARM64

`aarch64-mingw-ucrt` is built as `x64-mingw-ucrt` is, from RubyInstaller's ARM64 archive of the same release, with llvm-mingw for `aarch64-w64-mingw32` (ADR 035). What differs:

- **GNU MP.** The audit pins the ARM64 `libgmp-10.dll` by its own SHA-256. It is byte for byte the DLL of MSYS2's CLANGARM64 package of the same source package as x64's, which CI's Runtime job checks, and the source bundle's `BUILD.txt` says how to build a replacement for `aarch64-w64-mingw32`.
- **No GCC runtime.** LLVM built RubyInstaller's ARM64 tree, so `runtime/licenses.yml` lists no libgcc for it. The MinGW-w64 runtime and winpthreads are as on x64.
- **The tools are x64 and x86 programs** (rcedit, NSIS, `llvm-readobj`), which Windows 11 on ARM64 runs under its own emulation. None ships in an app.
- **Temporary copies of the tools.** The emulator's cache service, XtaCache, holds an emulated program's file open for a while after it exits, so a folder that held the program cannot be deleted at once. So `Fledge::Nsis` runs makensis, `Fledge::WindowsResources` runs rcedit, and `Fledge::AppGems` runs `llvm-readobj` from a copy in the system's temporary folder (`Dir.mktmpdir`), which each removes as far as Windows lets it and leaves the rest to the temporary folder. They do so on every Windows computer, so the code has one path.

## musl Linux's Ruby, built in Alpine

`RuntimeBuilder::Musl` (`tasks/runtime_builder/musl.rb`) builds Ruby from source on a computer of each architecture, in Alpine (ADR 017). CI runs it in the Alpine Ruby image `ci.yml` pins by digest (`ALPINE_RUBY`), whose Ruby is the build's `--with-baseruby`, with the packages `.github/scripts/alpine-packages.sh build` pins by version: a C toolchain, Rust for YJIT, Perl for OpenSSL's build, and binutils, whose objdump the license audit reads with.

1. **Libraries.** zlib, libyaml, and libffi are built from their `musl-ruby` pins, static and position-independent (`-fPIC`), and OpenSSL `no-shared` the same way, so each links into the one extension that uses it, as rv-ruby's glibc builds link them.
2. **Certificates.** As rv-ruby does (`Formula/rv-portable-openssl.rb`, line 77; `Abstract/rv-ruby.rb`, lines 203 to 208, at 7a0e584), OpenSSL's `SSL_CERT_FILE` is renamed `PORTABLE_RUBY_SSL_CERT_FILE` in its source, so no other program's OpenSSL reads it, and the installed `openssl.rb` sets it to `SSL_CERT_FILE`, or else to `libexec/cert.pem` beside the Ruby, before it loads `openssl.so`. Each edit fails the build when the line it replaces is gone.
3. **Ruby.** From its release tarball, `--enable-load-relative --disable-shared --enable-yjit --without-gmp`, every extension a shared object, `win32` and `win32ole` left out, linked `-static-libgcc`, and installed with `make install-nodoc`.
4. **The CA bundle** from its pin, as `libexec/cert.pem`.
5. **The rest is the Unix recipe:** the launcher and `bin/ruby` linked against that `libruby-static.a`, the standard library, pruning, Fledge's RubyGems defaults, AppImage's runtime in `tools/`, and the audit.

The parity check's reference on musl is this build's own `bin/ruby` with Fledge's RubyGems defaults taken out (`doc/contributors/design/parity.md`).

## What a runtime keeps

Everything a standard Ruby of the pinned version installs that running Ruby code can reach (ADR 039):

- the standard library;
- every default gem, and every gem `runtime/sources.yml`'s `bundled_gems` lists that the Ruby installs (rv-ruby installs all but win32ole, which only Windows builds);
- each gem's executables, its `.gem` in the cache (`gem pristine` and `Gem::Specification#cache_file` read it), its build information, plugins, and C extensions, and the libraries those extensions carry;
- Ruby's own programs: Fledge's `bin/ruby` on macOS and Linux, and RubyInstaller's `ruby.exe` and `rubyw.exe` and the gems' command-line wrappers (`gem.cmd`, `bundle.bat`, and the rest) on Windows;
- Ruby's C headers, `include/`, since `require "mkmf"` aborts without `ruby/ruby.h` ("mkmf.rb can't find header files for ruby", `mkmf.rb` at Ruby 4.0.9);
- on Windows, every DLL, since an extension's manifest may name any of them, and RubyInstaller's own Ruby library in `site_ruby`.

## What a runtime prunes, and why nothing reads it

`RuntimeBuilder::Pruning.prune` (every Unix and phone runtime, and `ruby\lib\ruby` on Windows) and `prune_windows` give each removal its reason in their comments. The Unix recipe also copies only `bin/`, `lib/ruby`, `include/`, and `libexec/cert.pem` from rv-ruby's prefix, so `share/` (man pages and documentation) never comes along.

| Removed | Why no app can miss it |
|---|---|
| `*.dSYM` | macOS debug symbols, read by debuggers and crash reporters, never by Ruby. |
| `*.a`, `*.h` under `lib/ruby`, `pkgconfig/` | Static libraries, the C headers of gems' extensions, and pkg-config files, for compiling against Ruby. Ruby code never loads them, and Ruby's own headers in `include/` stay. |
| `lib/ruby/gems/X.Y.0/doc` | RDoc and ri documentation, read by the `rdoc` and `ri` tools a developer runs, never by an app's requires. |
| nkf's `ext/java/` | See "nkf's JRuby sources". |
| `portable_ruby_gems.rb`, and every gem that is neither a default gem nor in `bundled_gems` | rv-ruby's own additions, a load-path helper and the bootsnap and msgpack gems. No standard Ruby installs them, so an app that worked under `ruby` never needed them. Each goes with its specification, cache, build information, extensions, and executables. |
| Windows: `share\` | Ruby's HTML documentation and ri data. |
| Windows: `lib\*.a`, `lib\pkgconfig` | Import libraries and pkg-config files, for compiling against Ruby. The import library of Ruby's DLL goes to the build-only companion. |
| Windows: `packages\`, `ridk_use\`, `bin\ridk.cmd`, `bin\ridk.ps1`, `bin\setrbvars.cmd`, `bin\startmenu.rb` | The MSYS2 keyring and `ridk`, which install and select MSYS2 compilers for a developer, and the scripts that set up a developer's shell and Start menu. They work only beside an installed RubyInstaller and MSYS2. |

Extensions are also stripped of debug sections on Linux, and the programs Fledge links are stripped.

The parity check lists bootsnap and msgpack, which are pruned, among the differences it allows (`Parity::JUSTIFIED` in `tasks/parity.rb`).

## nkf's JRuby sources

`RuntimeBuilder::Pruning.prune_jruby` removes nkf's `ext/java`, the Java sources of JRuby's nkf, from the gem's folder and from its `.gem` in the cache (`Pruning::JRUBY_ONLY`). CRuby never compiles or loads them: `nkf.gemspec` adds them only to the java-platform gem, and `ext/nkf` is CRuby's. So no running Ruby code reads them. They are EPL-2.0 OR LGPL-2.1-or-later, the only copyleft text a runtime would otherwise carry that is not license data.

`RuntimeBuilder::GemRepack.repack` rewrites the cached `.gem` in RubyGems' own format, with the specification's file list and `checksums.yaml` changed to match, so `Gem::Package#verify` and `gem pristine nkf` accept it. The cached nkf `.gem` therefore differs from RubyGems.org's by those files.

## Fledge's RubyGems defaults

Every runtime ships `runtime/rubygems/operating_system.rb` as `lib/ruby/X.Y.0/rubygems/defaults/operating_system.rb` (`RuntimeBuilder#install_rubygems_defaults`), the hook RubyGems loads for whoever packages Ruby (`rubygems.rb` at Ruby 4.0.9). rv-ruby ships none; on Windows it replaces RubyInstaller's. The file's own comments give the reasons. It does two things:

- **The app's gems are the runtime's alone.** `Gem.default_path` is `[Gem.default_dir]`. Left alone, it puts `Gem.user_dir` first whenever the person's home folder exists, so a gem the person installed with their own Ruby of the same minor would shadow the app's, json included.
- **A bundled gem the Gemfile does not name activates under a frozen bundle.** While `Gem::BUNDLED_GEMS.force_activate` runs (for `binding.irb`, say), and only on its thread, Bundler is told its bundle is not frozen; the temporary bundle is still never locked. The reason, and the frozen `.bundle/config`, are `doc/contributors/design/gems.md`, "binding.irb and force_activate".

RubyInstaller's own `operating_system.rb` is for a developer's Ruby: it writes and deletes a file in the runtime's gem folder on every start, creates `%ProgramData%\gemrc`, searches for MSYS2 and adds its DLL folder, and leaves `Gem.user_dir` first in `Gem.path`. A runtime needs none of it: RubyInstaller's DLLs load through their manifests without its runtime, and compiling a gem enables MSYS2 through RubyInstaller's Ruby library, which the runtime keeps (`doc/contributors/design/gems.md`).

The parity check allows the defaults' trace in `$LOADED_FEATURES` (`Parity::JUSTIFIED`).

## The tools folder

`tools/` holds what `fledge build` runs or copies (ADR 009, ADR 010, ADR 013). An app holds none of it, unless its `fledge.yml` sets `build_tools` (`doc/contributors/design/desktop-apps.md`). Each file is pinned by SHA-256 in `runtime/sources.yml` and owned by a component of the license audit, which checks `rcedit.exe`'s and `llvm-readobj.exe`'s SHA-256 again in the runtime.

| Platform | File | What `fledge build` does with it |
|---|---|---|
| Linux, glibc and musl | `tools/appimage-runtime` | Writes it at the front of an AppImage. It is AppImage's released type 2 runtime for the architecture, static against musl, with libfuse linked in (ADR 049). |
| Windows | `tools/nsis/` | Runs `Bin/makensis.exe` to compile an installer. It is the part of NSIS's release that compiles one: `COPYING`, makensis and its `zlib1.dll`, the solid LZMA and zlib stubs and the uninstaller's icon, the System and nsDialogs plug-ins, the script headers, and Modern UI 2 (`RuntimeBuilder::Windows::NSIS`). |
| Windows | `tools/rcedit.exe` | Writes an app's version information and icon into its program. It is Electron's release of `rcedit-x64.exe`. `llvm-rc` and `llvm-windres` compile resources but cannot put them into a program already linked. |
| Windows | `tools/llvm-readobj.exe` | Reads what an app's compiled gems import and delay-load (ADR 013). It is the one file of LLVM's own Windows release, statically linked, which imports only Windows' DLLs; the build unpacks it with `zstd --long=31` and checks the file's own SHA-256. |
## The build-only companion

Each desktop runtime build writes a companion, `fledge-runtime-VERSION-PLATFORM-dev.tar.gz`, with the runtime's own top folder, so it unpacks over the runtime (`RuntimeBuilder::DevCompanion`). It holds the library a gem's extension builds link against, and `DEV-NOTICES.txt`:

- on macOS and Linux, the static libruby (`lib/libruby*-static.a`). A static Ruby's extensions link no libruby (mkmf leaves `LIBRUBYARG` empty unless Ruby is shared, `mkmf.rb` at Ruby 4.0.9), but mkmf links the test programs of `have_func` and the rest against `LIBRUBYARG_STATIC`, so an `extconf.rb` that checks for a function (nokogiri's) fails without it;
- on Windows, the import library of Ruby's DLL (`ruby/lib/*.dll.a`);
- `DEV-NOTICES.txt`, which says what the archive is, then Ruby's license, and beside a static libruby Rust's too, since YJIT compiles in Rust's standard library.

**Why it is apart from the runtime.** A runtime prunes what no running code reads, static and import libraries among it, and its SBOM lists every file it holds; it cannot carry them and still be exactly what ships. The companion holds only these, which `runtime/licenses.yml` already owns as Ruby's, and never rv-ruby's `lib/libcrypt.a`, which is libxcrypt. `Fledge::Runtimes#dev_archive` finds it as it finds a runtime, checked against the SHA-256 the gem pins (ADR 014), and `fledge build` fetches it only when it compiles a gem (ADR 006). Nothing in it is copied into an app. Phone runtimes have no companion: their libraries and headers are in the runtime itself.

## Platform names and asset names

A platform is named by its RubyGems platform: `arm64-darwin`, `x86_64-linux`, `aarch64-linux`, `x86_64-linux-musl`, `aarch64-linux-musl`, `x64-mingw-ucrt`, and `aarch64-mingw-ucrt`. A Ruby developer already meets these names in `Gemfile.lock` and in precompiled gems, and they decide which precompiled gem fits a runtime, so Fledge prints no other name for a platform: not in a runtime's asset, `fledge build`'s output, `dist/NAME-PLATFORM`, an error message, a CI job, or the license map. `Fledge::Platform::NAMES` lists them, `Fledge::Platform.local` maps `Gem::Platform.local` to one, and `test/platform_test.rb` checks the mapping. A build's target is the platform Fledge runs on (ADR 010). A phone's targets follow RubyGems' grammar but are chosen so that no desktop gem fits them (ADR 057).

RubyGems' names are irregular: `arm64` on macOS against `aarch64` on Linux and Windows, `x64` on Windows against `x86_64` elsewhere. A Mach-O gem may also be named for a macOS version (`arm64-darwin-23`), which fits a runtime only as RubyGems decides, so `fledge build` matches as RubyGems does, not by string. Other ecosystems name platforms differently (LLVM target triples such as `aarch64-apple-darwin`, Go's `darwin/arm64`, Python's wheel tags such as `manylinux_2_39_x86_64`, Electron's `--platform darwin --arch arm64`). Each is more regular, and none tells a Ruby developer which precompiled gem fits.

The assets:

`RuntimeBuilder#assets` names what a release publishes for each platform, and `RuntimeBuilder.release_assets` lists them all, which `release.yml` checks a release against.

| Asset | Name | Platforms |
|---|---|---|
| The runtime | `fledge-runtime-VERSION-PLATFORM.tar.gz` (`Fledge::Runtimes.file_name`) | every desktop and phone runtime |
| Its SBOM | `fledge-runtime-VERSION-PLATFORM.spdx.json` | every one |
| Its NOTICES | `fledge-runtime-VERSION-PLATFORM-NOTICES.txt` | every one |
| Its sources | `fledge-runtime-VERSION-PLATFORM-lgpl-sources.tar.gz` (`LicenseAudit::Notices.source_bundle`) | each platform that ships a component whose source Fledge publishes: glibc and musl Linux, and Windows |
| The build-only companion | `fledge-runtime-VERSION-PLATFORM-dev.tar.gz` (`Fledge::Runtimes.dev_file_name`) | every desktop runtime |

`PLATFORM` is the RubyGems name, or `ios` and `android` for the phones. The SBOM and NOTICES assets are copies of the files inside the runtime, which CI compares. The source bundle keeps its `lgpl-sources` name though it holds NSIS's source, under the CPL, too. `SHA256SUMS` covers them all (`doc/contributors/design/releases.md`).

## Where fledge build finds a runtime

`Fledge::Runtimes` (`lib/fledge/runtimes.rb`) looks for a runtime, and its companion, in this order:

1. the folder `FLEDGE_RUNTIME_DIR` names, which a contributor points at `tmp/runtime` after `rake runtime`. A runtime there is used as it is, unchecked against the pins, since it was built from this checkout; when the variable is set and the file is missing, the build fails rather than download;
2. the cache, `$XDG_CACHE_HOME/fledge/runtimes` or `~/.cache/fledge/runtimes`, when its SHA-256 matches the gem's pin;
3. a download from the version's GitHub Release, or from `FLEDGE_RUNTIME_MIRROR` (ADR 031), into the cache, checked against the pin.

## Download retries

`fledge build` downloads runtimes, companions, and gems through `Fledge::Download.save`. A download that fails with `Download::Unavailable` (408, 429, or a 5xx) or `Download::Unreachable` (a connection refused, reset, timed out, unresolvable, or broken off) is tried again after 2, 4, and 8 seconds (`Download::WAITS`), four tries in all, and the last failure is raised when they run out. Each try starts again from the first byte into the same `.part` file and is checked against the pin; nothing reaches the destination unless it matches. A 401 or 403, a 404 or 410, any other 4xx, and a SHA-256 mismatch would answer the same a moment later, so each fails at once. Before each wait, `Fledge::Runtimes` and `Fledge::GemFetcher` say on their log why and how long: `could not download URL: 503 Service Unavailable; trying again in 2 seconds (2 of 4)`.

A mirror (ADR 031) is retried the same way and then fails, still without trying the release.

Why these numbers:

- **Four tries** is Bundler's default: `download_gem` runs inside `Bundler::Retry` (`lib/bundler/rubygems_integration.rb`, line 384, at bundler 4.0.20), and `BUNDLE_RETRY` is 3 (`settings.rb`, line 84). Bundler's index requests likewise pass over a refused login, a 404, and other 4xx (`fetcher.rb`, lines 99 to 125).
- **The waits double**, as Bundler's do (`retry.rb`, lines 22 to 31 and 67 to 76), from 2 seconds rather than Bundler's 1, because a release host's outage outlasts a second more often than a gem index's hiccup. They stop at 8, so a host that is truly down fails the build in about 14 seconds.
- **No jitter**: one build's downloads run one after another and are no herd, and a fixed wait is what the log can promise.
- **No setting.** Reading `BUNDLE_RETRY` would tie runtime downloads, which are not Bundler's, to a Bundler setting, and a variable of Fledge's own would be one more name to freeze for a need no one has shown.

`Fledge::Download` starts Net::HTTP with `ignore_eof: false`. By default Net::HTTP reads a body that ends before its `Content-Length` as the whole body (`net/http.rb`, lines 1469 to 1472, net-http 0.9.1 in Ruby 4.0.9), so a connection that broke off mid-download would be a SHA-256 mismatch, which is never retried. With `ignore_eof: false` it raises `EOFError`, which is `Unreachable`. Net::HTTP's own retry of a GET does not "restart in the middle of a download" (lines 2458 to 2475), so it does not cover this.

CI's download cache (`tasks/download_cache.rb`) tries five times, after 5, 10, 20, and 40 seconds, on the same two errors, since a hosted runner can wait longer than a developer at a terminal. It passes `waits: []` to `Download.save`, so its tries replace the product's rather than multiply them.

## Pins that name mirrors

A pin in `runtime/sources.yml` may list `mirrors` after its `url`. `DownloadCache#fetch` tries the url, then each mirror in order, and checks every download against the pin's one `sha256`, so a mirror serves the pinned bytes or is refused and the next one tried. When none serves the file, the error names every URL and why it failed. The file keeps the url's name in the cache whichever URL served it.

One SHA-256 per pin, not one per mirror, keeps the component the same whichever host answered: the license audit and the source bundles read only that a source pin exists.

Only `.github/scripts/fetch_pin.rb` passes mirrors, and only the `replaceability` pins, which it alone reads, name them. `test/runtime_builder_test.rb` fails if any other pin names one, since the runtime builder would never try them, or if a mirror is not HTTPS. Each mirror is downloaded and matched against the pin before it is added.
