<!--
SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>

SPDX-License-Identifier: CC-BY-SA-4.0
-->

> Requested: written by an agent and not reviewed line by line. These findings were moved out of the ADRs on 2026-11-10, when the ADRs were rewritten to one decision each and their detail moved to `doc/contributors/design/`. Each finding keeps the date it was found and the runs and branches the old ADR gave for it. The old ADRs themselves are in git history.

# Findings from the ADRs

Spikes, measurements, and CI runs that the ADRs once carried as evidence. The ADRs and design documents cite this note where a fact rests on one of them.

## The launcher and parity

### The Windows launcher spike: importing Ruby's DLL, and the layouts tried (2026-10-26)

From old ADR 001, section 8 (Plan 001, spike 2; branch `spike/windows`, commit ebd438d for the launcher it produced). A launcher at the top of the app that imported RubyInstaller's Ruby DLL failed to start with `0xC0000135` (STATUS_DLL_NOT_FOUND): Windows resolves imports before any code runs, searching the program's folder, System32, and `PATH`, never a folder below. Loading the DLL with `LoadLibraryExW` by absolute path worked. Past `MAX_PATH`, `LoadLibraryExW` failed with `ERROR_FILENAME_EXCED_RANGE` even in a process whose manifest is `longPathAware`, and worked again with the `\\?\` form of the path. Without `longPathAware`, RubyGems failed to load from an app unpacked deep in a folder tree. Two other layouts also worked and were judged worse for the person who opens the folder: the launcher inside `ruby\bin`, and a side-by-side manifest that reshapes the tree.

### Runtime sizes once the standard library shipped whole (2026-10-26)

From old ADR 003, Consequences. When runtimes began to keep every default and bundled gem and `bin/ruby`, their archives about doubled, as CI built them on 2026-10-26: macOS 8.6 MB to 18.7 MB (its folder 28 MB to 58 MB); Linux about 10 MB to 21.0 MB on x86_64 and 21.2 MB on aarch64; Windows 9.3 MB to 16.8 MB. (The runtimes fragment may carry the same numbers from old ADR 003, section 2.)

### Ctrl-C's exit code for ruby.exe (2026-11-01)

From old ADR 015, Context. On Windows, UCRT turns the console's CTRL_C_EVENT into SIGINT, Ruby raises `Interrupt`, and `ruby_default_signal`'s `raise(SIGINT)` with the default action ends the process with exit code 3, as CI measured for `ruby.exe` before any built app was checked.

### Closing a Windows console from CI (2026-11-01 and 2026-11-02)

From old ADR 015, section 2. On GitHub's Windows runners, CI could not make a real console window close: `WM_SYSCOMMAND` with `SC_CLOSE` and `WM_CLOSE` posted to the console's window, and stopping its `conhost.exe`, each left the process running (the `experiment/signing` branch's runs, 2026-11-01). On 2026-11-02 the `experiment/windows-close` branch's runs 41381658378 and 41382172103 started `ruby.exe main.rb` and a built console probe on a pseudoconsole (`CreatePseudoConsole`), waited for the probe's `ready`, and closed it with `ClosePseudoConsole`. On `windows-latest` (x64) and `windows-11-arm`, each ended within a second with exit code 3221225786 (`0xC000013A`), and its log held `locale`, `external`, and `ready` only: neither `ensure` nor `at_exit` ran, for `ruby.exe` and the app alike. Not tried, since this worked: a console hosted by Windows Terminal, one started by a scheduled task or a service, UI Automation on the window's close button, and `TerminateProcess` of its host.

### The launcher's size per program (2026-11-02)

From old ADR 024, section 3. A launcher copy per program costs its size per program: 6.3 MB in 0.1.0's `arm64-darwin` runtime, where it holds libruby, and tens of kilobytes on Windows, where Ruby is a DLL.

### The path probe: what Ruby's answers and a restart do in a built app (2026-11-03)

From old ADR 026, Context. The `experiment/path-probe` branch built three probes with Fledge 0.2.1 and its released runtimes (a lone `main.rb`, the same with a Gemfile, and a windowed app), ran each where it was built and on a fresh runner of every desktop platform, and had each restart itself twice, three ways: with `exec RbConfig.ruby, $0`, by running its own launcher again, and with `RbConfig.ruby` after clearing every Ruby variable (CI run 41747218312, every job green, its artifacts the report). It ran each in a clean environment, in a person's (`LANG`, `RUBYOPT=-W0`, `RUBYLIB`, `GEM_HOME`), in Delivery's hostile one, and in a C locale, from a folder named `My Apps/Ünïcödé 日本`. Every answer Ruby gave before a restart was true. A restart through `RbConfig.ruby` broke five ways:

1. The person's Ruby settings reached the restarted app, since `bin/ruby` hid nothing: a `RUBYLIB` file shadowed the runtime's `json`, and a hostile `BUNDLER_SETUP` raised a `LoadError`, on every platform.
2. The restart read the app's folder as US-ASCII: the launcher coerced the C locale in its own process only, so in a C locale `$0`, `__FILE__`, and `__dir__` came back US-ASCII with invalid bytes, and for an app with a Gemfile, Bundler's vendored Thor raised "invalid multibyte character" as it loaded, on macOS and glibc Linux.
3. In a macOS `.app`, `$0` and `__FILE__` named `Contents/MacOS/app/main.rb`, through the link, while `__dir__`, `RbConfig::CONFIG["prefix"]`, and `RbConfig.ruby` named `Contents/Resources`; `File.dirname(__FILE__) == __dir__` was false.
4. On macOS the restarted app lost its bundle: after `exec` of `Contents/Resources/bin/ruby`, `NSBundle.mainBundle` no longer read the app's `Info.plist`.
5. On Windows the restart was a new console process: a windowed app restarting through `ruby.exe` got a console window and lost its AppUserModelID.

Running the launcher again had none of these problems on any platform. On Windows, restarting by running `NAME.exe`, found with `GetModuleFileNameW(NULL, ...)` through Fiddle, passed in every environment, the hostile one included, and a windowed probe kept running without a console.

### The restart's trial on fresh runners (2026-11-03)

From old ADR 026, Consequences. Delivery's restarts through `RbConfig.ruby` on fresh macOS and Linux runners and in the Debian and Alpine containers passed in a trial on the `experiment/true-paths` branch, run 41758130321, before the change landed.

### ruby/spec finds the coerced LC_ALL=C (2026-11-04)

From old ADR 026, section 1. The launcher first coerced every C locale, explicit `LC_ALL=C` and `LC_CTYPE=C` included. ruby/spec's `Encoding.locale_charmap when setting LC_ALL=C` failed in a built app on macOS and glibc Linux (branch `experiment/ruby-spec`, run 41776558621), which led to leaving an explicit `LC_ALL` or `LC_CTYPE` alone.

## Runtimes and licenses

### Runtime sizes

2026-10-26, from old ADR 003, Consequences. Keeping the bundled gems and adding `bin/ruby` (old ADR 003, section 2) about doubled runtime archives, as CI built them that day: macOS 8.6 MB to 18.7 MB (its folder 28 MB to 58 MB); Linux about 10 MB to 21.0 MB on x86_64 and 21.2 MB on aarch64; Windows 9.3 MB to 16.8 MB.

### Ruby's headers in the runtime: the finding and its cost

2026-11-04, from old ADR 003, section 2. ruby/spec's `library/mkmf` found, in a built app on every desktop platform, that `require "mkmf"` aborts without `ruby/ruby.h` ("mkmf.rb can't find header files for ruby", `mkmf.rb` at Ruby 4.0.9) (branch `experiment/ruby-spec`, run 41776558621). Until then the build-only companion carried the headers. Moving them into the runtime cost about 1.9 MB unpacked and 0.36 MB in the macOS runtime's archive (19,240,933 bytes before, 19,599,221 after). The phones were left as they were: an app there starts no programs, so `find_executable` could find nothing it may run, and no phone app had been seen to require mkmf. (Checked 2026-11-10: the phone runtimes do hold Ruby's headers, in each iOS XCFramework slice's `Headers/` and in the Android runtime's `include/`, for native code that links Ruby; but a phone app carries only the runtime's `lib/` and `libexec/`, so `require "mkmf"` in a phone app still finds no headers.)

### Sources inside the runtime: sizes

2026-11-04, from old ADR 004, section 5. Measured against `trunk`'s run 41966470848, the runtime archives of the experiment's run 41971986753, which added `notices/sources/`, grew by 5.34 MB on `x86_64-linux` (22.3 to 27.6 MB) and 5.32 MB on `aarch64-linux`, 4.64 MB on each musl Linux, and 3.95 MB on each Windows, about the size of each source bundle, since the sources are already compressed.

### The build-only companions: sizes

2026-10-27, from old ADR 006, Consequences (the 006 owner may record this too). Each release carries the build-only companions, as CI built them that day: 0.5 MB for Windows, 19.3 MB for macOS, and 26.6 MB and 27.4 MB for x86_64 and aarch64 Linux, nearly all of it static libruby, downloaded only when compiling a gem.

### The permissive spike: what the first license audit found

2026-10-27, from old ADR 004, Context (the full findings are in `doc/contributors/research/2026-10-27-permissive-spike.md`; spike/permissive's `FINDINGS.txt` at 58edf27). An audit in Ruby's standard library alone, run on the four runtimes of the day and on the whole trees they came from, found every runtime within the rule; rv-ruby's own Linux `bin/ruby` outside it (libxcrypt, LGPL-2.1-or-later, linked statically); and nkf's JRuby sources (EPL-2.0 OR LGPL-2.1-or-later) the one copyleft text a runtime carried. It priced the alternatives to the two LGPL libraries: musl's crypt in place of libxcrypt silently computes a wrong (DES) hash for yescrypt, the default password hash of current Debian, Ubuntu, and Fedora; a Windows Ruby built without GMP means forking RubyInstaller's packaging onto MSYS2's rolling toolchain. When the audit landed on trunk it confirmed that `bin/ruby` was Fledge's own build of Ruby's `main.c`, needing `libcrypt.so.2` from the runtime's `lib/` through its RPATH (`$ORIGIN/../lib`), with no libxcrypt code in it, and that rv-ruby's own `bin/ruby` never shipped. The audit then added each runtime's SBOM (about 2 MB unpacked) and NOTICES (160 to 230 KB), and took a few seconds per runtime.

### Readers of compiled files: sizes and lines

2026-11-01, from old ADR 013. Before ADR 013, `Fledge::Binary` read ELF, Mach-O, and PE itself in 547 lines (251 of them code), and the tests had 96 lines of writers of each format. What replaced them is 192 lines of code that find a computer's tools, run them, and pick out what they print, and 33 more in the audit; the tests' 32 fixtures are files a real linker made, by a script of 145 lines that runs clang, lld, and llvm-dlltool. Sizes weighed: llvm-mingw, for each computer that builds the Windows runtime, is 78 to 124 MB, with a 149 MB `libLLVM` its tools load; LLVM's own release for Windows is a 277 MB archive in which `llvm-readobj.exe` is one static 8 MB file importing only Windows' DLLs (3 MB compressed); LLVM's releases for Linux and macOS are 0.9 to 1.2 GB; llvm-mingw's `llvm-readobj` in a runtime would bring libLLVM, libc++, and libunwind, 33 MB compressed. Facts about the tools then: GNU binutils' `objdump -p` prints ELF's `NEEDED` and `GLIBC_X.Y` version references and reads PE but, on Ubuntu, no Mach-O; `llvm-objdump -p` prints ELF's in GNU's form and Mach-O's load commands as `otool -l` does, and a PE import table but not its delay import table; `llvm-readobj --coff-imports` prints both PE tables, `--file-headers` the Subsystem; `llvm-readobj --elf-output-style=JSON` prints JSON for ELF only. Windows' shell's `SHGetFileInfo` with `SHGFI_EXETYPE` tells a console from a GUI program, but nothing on Windows names a file's DLLs. A Mach-O file names its oldest macOS only for platform macOS; an iOS file names none.

### musl Linux: the Alpine build spike

2026-11-01, from old ADR 017, Context. rv-ruby's musl builds of Ruby 4.0.9 (`ruby-4.0.9.x86_64_linux_musl.tar.gz` and `arm64_linux_musl`, release 20261023) are configured `--with-static-linked-ext` (`alpine/4.sh`, spinel-coop/rv-ruby at 7a0e584), and ship only `libruby-static.a` without the extensions; Plan 001's spike 1 found this first. A spike on the `experiment/signing` branch (runs of 2026-11-01) built Ruby 4.0.9 from its release tarball in Alpine, configured as rv-ruby's glibc builds but with each extension a shared object, linked Fledge's unchanged Unix launcher against its `libruby-static.a` with `-rdynamic`, and ran an app that required `json`, `openssl`, `psych`, `fiddle`, and `bigdecimal` and enabled YJIT, on x86-64 and ARM64, from a folder with a space in its name, in a bare Alpine with no Ruby. GitHub's `ubuntu-24.04` and `ubuntu-24.04-arm` runners run Alpine containers with `docker run`; their JavaScript actions cannot run inside an Alpine container on ARM, which rv-ruby's own `build-alpine.yml` notes too. At the time, the build used Alpine 3.24's Rust 1.96.1 and GCC 15.2.0, and OpenSSL 3.6.5. `examples/native_app` was not built for musl: its lockfile locks no musl platform, and its Rust gem's toolchain in Alpine was left for another story.

### Windows on ARM64: the spike

2026-11-01, from old ADR 018. RubyInstaller-4.0.9-1 publishes `rubyinstaller-4.0.9-1-arm.7z` beside its x64 archive, signed with the same key. Its tree: `bin\aarch64-ucrt-ruby400.dll`, `ruby.exe`, `rubyw.exe`, `bin\ruby_builtin_dlls\` with GNU MP and winpthreads, and OpenSSL, libyaml, zlib, and libffi beside the extensions that load them. MSYS2's CLANGARM64 environment built it with LLVM, so no libgcc is in it; its `libgmp-10.dll` is byte for byte the one in MSYS2's `mingw-w64-clang-aarch64-gmp-6.3.0-2` package, from the same source package as x64's. GitHub's `windows-11-arm` runners run ARM64 Windows, and `ruby/setup-ruby` installs RubyInstaller's ARM64 Ruby there with its MSYS2. A spike on the `experiment/signing` branch (runs of 2026-11-01, the last of them, 41338082425, green on every job) built an `aarch64-mingw-ucrt` runtime on a Mac and on Linux, passed it through the license audit, and built and delivered hello, the console probe, and the windowed app with its installer on a `windows-11-arm` runner, with parity between the built probe and `ruby.exe main.rb` on both code pages. sqlite3 2.10.2 published no `aarch64-mingw-ucrt` build, and its source did not compile there (SQLite's own `configure` does not know `aarch64-w64-windows-gnu`), so `examples/my_cool_app` and the gem-shaped parity probe do not run on ARM64 Windows.

## Gems

### Builds shipped inside later builds (2026-11-03)

From old ADR 005, section 1. Leaving out only the current `--out` shipped earlier builds: a build into `dist`, then one into `out`, put the first app and its archive inside the second, which grew from 19 MB to 58 MB for a lone `main.rb`. This led to the `CACHEDIR.TAG` rule (Cache Directory Tagging Specification, https://bford.info/cachedir/; written as Cargo tags `target`, `crates/cargo-util/src/paths.rs` lines 746 to 782 and 800 to 813 at Cargo 0.92.0).

### binding.irb in a frozen bundle (2026-11-04)

From old ADR 005, section 5. ruby/spec's `library/irb/irb_spec.rb` (`Binding#irb`) found that `binding.irb` failed in a gem-shaped app with "You have added to the Gemfile: * irb" (branch `experiment/ruby-spec`), where `bundle exec` opens IRB; Ruby's master had the same `lib/bundled_gems.rb` code on 2026-11-04. On Windows the same call fails under `bundle exec` too: reline 0.6.3 requires `fiddle/import` there (`lib/reline/io/windows.rb`, line 1), and fiddle, a bundled gem since Ruby 4.0, is a dependency of neither irb nor reline. Stock Ruby 4.0.9 on both Windows runners raised that LoadError, and opened IRB with `fiddle` in the Gemfile (branch `experiment/win-irb`, run 41842939667).

### Build-only companion sizes (2026-10-27)

From old ADR 006, Consequences. As CI built them on 2026-10-27: 0.5 MB for Windows, 19.3 MB for macOS, and 26.6 MB and 27.4 MB for x86_64 and aarch64 Linux, nearly all of it static libruby.

### Gems that motivated compiling (2026-10-27)

From old ADR 006, Context. Tokra compiles its Rust extension with rb-sys at install (`tokra.gemspec`: `spec.extensions = ["ext/tokra/extconf.rb"]`, `spec.add_dependency "rb_sys"`). Ferro's gems bind Rust crates, each shipping its Cargo.lock (`gems/idna/ferro-idna.gemspec`; `ext/ferro_idna/extconf.rb`, `create_rust_makefile` with `--locked`), consumed from git tags (`gem "ferro-idna", git: "https://github.com/setdef/Ferro", tag: "ferro-idna/v0.1.0.pre.1", glob: "gems/*/*.gemspec"`). ratatui_ruby 1.5.2 publishes precompiled `arm64-darwin`, `x86_64-linux`, and `x64-mingw-ucrt` builds, each a fat gem with one binary per Ruby from 3.2 to 4.0 (`lib/ratatui_ruby/4.0/ratatui_ruby.bundle`), and its source, but none for `aarch64-linux`; 1.5.1 named its macOS build `arm64-darwin-23`. nokogiri 1.19.4's precompiled `arm64-darwin` and `x64-mingw-ucrt` builds compile GNU libiconv in statically; its `extconf.rb` builds GNU libiconv from source when it cross-compiles or builds on Windows (`if cross_build_p || windows?`, line 767, and `unless unix?`, line 827), and a native build on a Mac takes macOS's own `iconv.h` (line 853).

### The linkage check's first real case (2026-10-27)

From old ADR 006, section 8. nokogiri's vendored libxml2, built from source on a Mac with Homebrew, linked Homebrew's `liblzma`; `build.nokogiri --disable-xml2-legacy` keeps it from linking any of the build computer's libraries.

### RubyGems.org answers 403 for a missing gem file (2026-11)

From old ADR 020, section 2. `curl -I https://rubygems.org/gems/NAME-VERSION.gem` for a made-up name, in November 2026, answered 403 `AccessDenied` from RubyGems.org's storage bucket, not 404.

### A wrapper's own Gemfile clashed with the runtime's rdoc plugin (2026-11-01)

From old ADR 019, section 3. Building Rooibos 0.8.0's repository directly failed with `fledge build: lib/ruby/gems/4.0.0/plugins/rdoc_plugin.rb is in ... already, so the build can't add its own`: its Gemfile puts its tools (`irb`, `rubocop`, `rubycritic`, and others) outside the `development` group, and irb asks for an rdoc newer than the runtime's.

### A .deb's Depends for examples/system_library (2026-11-04)

From old ADR 030, section 3. Built on Ubuntu 24.04, `examples/system_library`'s `.deb` declared `Depends: libc6 (>= 2.39), libpng16-16t64 (>= 1.6.2)`. Ubuntu 24.04's package names matched Debian 13's for every library CI tried; libjpeg's (`libjpeg-turbo8` against `libjpeg62-turbo`) do not.

## Desktop apps, installers, and signing

### hdiutil's "Resource busy" race on GitHub's macOS runners

2026-11-04 (old ADR 010, section 3). `hdiutil create -srcfolder` mounts its scratch volume at `/Volumes/NAME` while it copies and detaches it before writing the image (seen on macOS 27.0.1). It failed with "create failed - Resource busy" in Fledge's CI run 41966470848, job Test (arm64-darwin). The runner image's maintainers traced it to `XProtectBehaviorService` holding the new image and recommended trying again (actions/runner-images#7522, comment of 2023-05-22; the issue was closed with no change to the image). This hdiutil, on macOS 27, has no `-nospotlight`. The race could not be provoked on demand: holding a file of the scratch volume open for 20 seconds, on macOS 27.0.1, left `hdiutil create` to succeed. Prior art read: create-dmg retries create and detach on "Resource busy", noting create exits 1 for it where detach exits 16, five tries with waits of 2, 4, 8, and 16 s (`create-dmg`, lines 34 and 49 to 86, at a2b71d0); electron-builder retries every hdiutil command up to five times for exit codes it calls transient, 1 among them (`packages/dmg-builder/src/hdiuil.ts`, lines 18 and 54 to 62, at b98e1f2); dmgbuild retries `hdiutil detach` twelve times with growing waits (`src/dmgbuild/core.py`, lines 840 to 865, at a805b92).

### hdiutil create's deprecation on macOS 26 and newer

2026-11-02 (old ADR 010, section 3 and Consequences). `hdiutil create` still succeeded on macOS 26.6.2 and 27, printing on standard error that `diskutil image create` replaces it. macOS 14 and 15, which Fledge's runners and its oldest supported Macs ran, had only `hdiutil`. The move to `diskutil image create` was deferred until `hdiutil create` stops working.

### Apple's timestamp server failing a signed build

2026-11-07 (old ADR 016, section 6). CI's signed build of `examples/windowed_app` failed once on Apple's timestamp server and passed when run again: run 42126058497, attempt 1, job Build (arm64-darwin), where `codesign` stopped on Ruby's `enc/windows_1254.bundle` with "A timestamp was expected but was not found." That is the description of `errSecTimestampMissing` (-67882) in `<Security/SecBase.h>` (line 693 of the macOS 27.0 SDK); line 696 describes `errSecTimestampServiceNotAvailable` (-67885) as "The timestamp service is not available." Prior art read: VS Code (`build/darwin/sign.ts`, lines 44 to 75, at microsoft/vscode b4bd9bd: five tries, 10 s doubling, also retrying "The specified item could not be found in the keychain."); Defold (`build_tools/codesigning.py`, lines 146 to 160, at defold/defold d4ca5d4: five tries, 5 s doubling); Datadog's agent (`omnibus/config/software/datadog-agent-finalize.rb`, lines 260 and 261, at DataDog/datadog-agent 6c2b960). `codesign --sign Nobody` says "Nobody: no identity found" on macOS 27.0.1.

### YJIT under a self-signed identity's hardened runtime

2026-11-01 and 2026-11-08 (old ADR 016, section 2; old ADR 033, section 5). CI found YJIT writing code under the hardened runtime with no entitlement at all when the identity was self-signed. Whether a Developer ID's hardened runtime is stricter is unknown; the maintainer's walk-through (`doc/contributors/signing-test.md`) has an optional step that signs `examples/windowed_app` again without entitlements under his Developer ID and runs its YJIT check. Tebako's signing specification (`docs/spec/31-macos-signing-notarization.md`, tamatebako/tebako at d65a127) gives YJIT `allow-jit` "for MAP_JIT on arm64", which Ruby 4.0.9's `jit.c` does not bear out.

### The signing and notarization experiment

2026-11-08 (old ADR 033, Status and section 6). The stand-in notary, stand-in signer, and real-signtool checks passed on `experiment/signing-ready` in run 42461943288, all nine jobs green (Test, Build, and Delivery on arm64-darwin, x64-mingw-ucrt, and aarch64-mingw-ucrt), with trunk's runtimes from run 42453865685. notarytool 1.1.4 (Xcode on macOS 27.0) exits 69 with "Error: No Keychain password item found for profile: NAME" for a missing profile, with `--output-format json` or without. Stand-in stapling to `Contents/CodeResources` was left alone by `codesign --verify --strict --deep` on macOS 27.0.

### A launcher copy's size

2026-11-02 (old ADR 024, section 3). A launcher was 6.3 MB in 0.1.0's `arm64-darwin` runtime, where it holds libruby, and tens of kilobytes on Windows, where Ruby is a DLL.

### fledge build --from inside a built app (the first proof)

2026-11-05 (old ADR 032, sections 1 and 8). The spike (run 41978615197 on `experiment/drag-to-fuse`) built an app inside a built app, with only Ruby's standard library and the system's tools, on fresh macOS and Windows runners with no Ruby reachable, in 1.4 to 2.3 s; the result ran and passed `codesign --verify --deep --strict`. A self-extracting exe of 19.5 MB unpacked 2,906 files, 50.8 MB, in 1.13 s with Windows' own `tar.exe` on a CI runner, and Windows' `tar.exe -xf` read a zip appended to an exe with `copy /b`. What `--from` wrote on the person's computer carried no quarantine (`xattr` empty); the macOS app was 63 MB.

Run 42059830583 on `experiment/build-from` (`.github/build_from/`), every job green on all seven desktop platforms: a console app whose Gemfile held this Fledge as an ordinary gem (packed with `gem build`, unpacked beside it, `path: "../fledge"`, so in the app's `vendor/cache`), built with `fledge build`, was unpacked on a fresh runner that never ran `fledge build`, in `Mein Ort/Prüfung 日本`, with no Ruby on `PATH` (only `tar` and `gzip`, and `codesign` on macOS; on Windows `System32`) and `RUBYOPT=-rbogus`, `RUBYLIB`, `GEM_HOME`, and `GEM_PATH` set. Its program ran the `fledge` RubyGems wrote into `Gem.bindir` (`bin/fledge`, `ruby/bin/fledge.bat` on Windows) with `build --from` on its own folder and a project beside it, in 2.3 to 4.9 s on macOS and Linux and 8.6 and 16.7 s on Windows, and the app it wrote ran from its unpacked archive, reading its asset through `__dir__`, with the game's name in its Windows version information. On Windows the first attempt, with no runtime at hand, failed with status 1 naming where to put one; the second had `FLEDGE_RUNTIME_DIR`. Two things it met: Windows' `tar.exe` reads its arguments in the ANSI code page, so it could not change into a folder named outside ASCII, and its error, in the console's code page, raised an encoding error in `Fledge::Command` (fixed: tar runs in the folder that holds what it packs, and on Windows reads archives from standard input; a tool's output is quoted with what is not UTF-8 replaced); and the person's `RUBYOPT` and `RUBYLIB` reach a child Ruby as under `bundle exec`, so `RUBYOPT=-rbogus` stopped `fledge` run as a child with a `LoadError`, and the proof ran `fledge` with `RUBYOPT=-rbundler/setup` and no `RUBYLIB`.

### build_tools and file associations (the second proof)

2026-11-05 (old ADR 032, sections 3 and 4). On `experiment/file-associations` (`.github/file_associations/`), on the runtimes of trunk's run 42089720531, run 42102622918: a console builder app with `build_tools: true` and this Fledge as an ordinary gem, unpacked on a fresh runner in `Mein Ort/Prüfung 日本`, with no Ruby on `PATH`, no Fledge runtime anywhere, and `RUBYOPT=-rbogus`, `RUBYLIB`, `GEM_HOME`, and `GEM_PATH` set, ran its own `fledge build --from` on a windowed game with `file_associations` and the installers `dmg`, `nsis`, `appimage`, and `deb`. On Windows x64 and ARM64 it wrote the `.zip` and the setup program with the builder's launchers, rcedit, and NSIS in 27 and 35 s; on glibc Linux, x86_64 and aarch64, the archive, the AppImage (which ran extracted), and the `.deb`, in about 20 s, with the system's `mksquashfs` and `dpkg-deb`; on musl Linux, in Alpine with only `squashfs-tools` added, the archive and the AppImage, in about 7 s; on macOS, the bundle and the disk image in 63 s, most of it `hdiutil`. The game's folder held no `tools`. Windows' Delivery of `examples/windowed_app` hung opening a folder through the shell from PowerShell's thread; run 42121489631 (Windows x64 and ARM64) proved it by calling the shell from a single-threaded apartment of its own and naming the `Directory` class that holds the verb. On the maintainer's Mac (macOS 27), in the hidden test session, `open -a "Hello Window.app" FOLDER` and `open -a "Hello Window.app" FILE.hellowindow` started the app with no arguments (`"arguments":0`). Launch Services leaves out an app in a temporary folder such as mktemp's, so Delivery registers a copy in the home folder. Run 42128094310, on trunk 82f60e8, passed all 21 jobs with the app metadata keys beside the file associations, in `examples/windowed_app` and in a game built `--from`.

build_tools' cost, measured on the builder app (Fledge as a gem, no other gems): on Windows 5.5 MB unpacked (4,966 KB of tools: rcedit 1.3 MB, NSIS, and two launchers of 28 KB) and 1.5 MB in the `.zip` (x64: 25.4 MB against 23.9 MB; ARM64: 24.9 MB against 23.4 MB); on Linux 0.9 MB unpacked and 0.5 MB in the `.tar.gz` (x86_64 27.9 MB against 27.4 MB, musl alike); on macOS nothing.

### The Windows ProgID, and --from's Delivery on trunk

2026-11-08 (old ADR 032, section 3 amendment, and Consequences). Proved by `deliver-installer.ps1` in run 42497235236 on `experiment/one-point-oh`, with the runtimes of trunk's run 42477767268, on Windows x64 and ARM64, under a 97-character hyphenated identifier: the registry held the compliant ProgID and no default, the shell opened a file through it and a folder through the verb, and the uninstaller left none of it. The Delivery of `fledge build --from` on trunk's CI was first run as run 42495843691 on `experiment/from-delivery`, on `arm64-darwin`, `x86_64-linux`, and `x64-mingw-ucrt`.

## Phones

### What the mobile spike left to the runtime story (2026-10-27)

From old ADR 011, Status and Context. The mobile spike (branch `spike/mobile`, `spike/mobile/FINDINGS.txt`, kept in `doc/contributors/research/2026-10-27-mobile-spike.md`; CI runs 40630328845 and 40630328941) built CRuby 4.0.9 for iOS and Android, statically and interpreter only, and ran a script in the iOS Simulator and on Android emulators. It found: iOS reports `arm64-darwin`, as macOS does, so a target named after `RUBY_PLATFORM` would let Bundler pick macOS's native gems; the bundled gems with C extensions could link in only by ceasing to be gems (it moved bigdecimal, debug, nkf, racc, and syslog into the standard library, so `Gem.loaded_specs["bigdecimal"]` was nil, and left rbs out); iOS's Ruby started in a US-ASCII locale; HTTPS failed for want of CA certificates. Its first Ruby booted with no RubyGems, because a cross build leaves out the builtin binary and `mini_builtin.c` never loads `gem_prelude.rb`. Linking libruby's `dmyext.o` and `dmyenc.o` made the linker take their empty `Init_ext` and `Init_enc` before `extinit.o`'s and `encinit.o`'s, and `require "json"` failed. The spike's Android HTTPS failure was OpenSSL refusing environment variables under `AT_SECURE`; setting `SSL_CERT_FILE` alone failed the same way on an emulator.

### Android first-launch unpack time (2026-10-28)

From old ADR 011, section 2. Unpacking the app's stored zip asset into the files folder on the first launch of an installed version took 1.5 to 2.8 seconds on CI's emulators, then milliseconds on later launches, as the spike's host measured.

### Phone runtime and check times in CI (2026-10-28)

From old ADR 011, Consequences. In run 40787414670, building the iOS runtime took 13 minutes on a macOS runner and the Android runtime 9 on a Linux one; checking them in the Simulator and on emulators took 8 macOS minutes, and 3 and 4 Linux minutes: about 21 macOS and 16 Linux minutes in all.

### arm64-v8a on an Apple-silicon Mac (2026-10-28)

From old ADR 011, Consequences. While the former ADR 011, now ADR 079 was written, the parity check passed with the arm64-v8a library, and hello.rb reached rubygems.org, on an arm64-v8a API 36 emulator on an Apple-silicon Mac. This is not a gate.

### No free GitHub-hosted runner runs an arm64-v8a emulator (2026-11-02)

From old ADR 011, Consequences. Tried on branch `experiment/android-arm64`, runs 41375979155, 41376276036, 41378120610, and 41378398866. No free GitHub-hosted runner runs an arm64-v8a emulator with hardware acceleration, for this public repository:

- `ubuntu-24.04-arm` (Neoverse-N2, Hyper-V guest) has no `/dev/kvm`, and its kernel logs `kvm [1]: HYP mode not available`.
- `macos-14`, `macos-15`, and `macos-26` are `Apple M1 (Virtual)` guests (`VirtualMac2,1`, `kern.hv_vmm_present: 1`; `kern.hv_support: 0` on macos-26). Google's emulator 37.2.13 booting an arm64-v8a API 36 image there stops with `HVF error: HV_UNSUPPORTED` and `failed to initialize HVF`, on macos-15 and macos-26 alike.
- `windows-11-arm` (Cobalt 100) has the Windows Hypervisor Platform feature disabled, and `WHvGetCapability(HypervisorPresent)` answers 0.
- Independently, Google's repository (`repository2-3.xml`, emulator 37.2.13 and 37.3.6) lists the emulator for Linux x64, macOS x64 and aarch64, and Windows x64 hosts only, so `sdkmanager` finds no `emulator` package on the two ARM64 hosts in any channel.

The arm64-v8a library is still built and its APK checked. Running it needs a device cloud or a Mac with hardware virtualization. At the time the maintainer ruled that no money is spent on either (`decisions.md`, 2026-11-02); `decisions.md`, 2026-11-04, ended that ruling. A runner with nested virtualization on ARM64 would end this; recheck when GitHub announces one. A Fledge-built game later ran on a physical arm64-v8a phone (below).

### Native gems on phones, verified (2026-11-02)

From old ADR 022, section 8. Branch `experiment/phones`, run 41492629986, every job green: it trimmed `ci.yml` to the mobile jobs, and the Mobile apps jobs built and ran `examples/native_phone`, a gem `adder` with `adder.c` and `total.cc`, which prints `NativePhone adds 5 and totals 10 with a C extension (C and C++) on PLATFORM`.

- iOS Simulator, iPhone 17 Pro (iOS 26.5) and iPad Pro 13-inch (M5): the line on `arm64-darwin`, status 0, from os_log. The same app, built on a Mac with Xcode 27.2, ran on an iPhone 17 and an iPad Pro 13-inch (iOS 26.1 Simulator). Xcode built the project for the Simulator and, unsigned, for devices with no warning, and the device slice linked with the extension.
- Android x86_64 emulator, API 36, with 4 KB and 16 KB pages: the line, on `x86_64-linux-android`. `libfledgeext.so` was in the APK, which `zipalign -c -P 16` accepted for both ABIs.
- arm64-v8a: `libfledgeext.so` compiled and linked by the NDK, in the debug and the unsigned release APK, passing `zipalign -c -P 16`; not run.
- mkmf's `have_func("rb_str_new", "ruby.h")` linked `libfledgeruby` on both systems; without `-lz` on iOS the test failed, as the library needs it.
- A C++ source compiled and linked with the NDK's `libc++` linked statically (`-static-libstdc++`); without it the library needed `libc++_shared.so`, which the package does not carry, caught by reading `NEEDED` with `llvm-readelf`. `libfledgeext.so`'s `NEEDED` entries were `libfledgeruby.so`, `liblog.so`, `libm.so`, `libdl.so`, and `libc.so`.
- A path gem needed no `gem.build_complete` mark. The marks for gems from a server and from git were tested for their paths (`test/mobile_build_test.rb`, with fake runtimes), but no CI app had such a gem.

Not verified then: a server or git gem with an extension in a running app; `extconf.rb` arguments from `bundle config build.NAME` (later used by `examples/sdl_phone`); an `extconf.rb` that needs a gem or `pkg-config`; an Android build on Windows (refused) or with NDK versions other than r30; iOS device slices on a device; Rust extensions; `require_relative` of an extension.

### SDL3 owning the main loop, on phones (2026-11-02)

From old ADR 025, sections 3, 4, and 6. Spike `examples/sdl_phone`: a path gem `sdl_demo` whose C extension opens a full-screen window and runs a frame loop calling a Ruby block each frame. SDL 3.4.18 from its release tarball (SHA-256 `9c75cf16330322c217dedd2e0609f1124f1b54b8633e763467b4684d0f4334a3`).

Arrangements tried on iOS, in the iOS 26.1 Simulator with Xcode 27.2, on a Mac:

- Fledge's host unchanged (Ruby on Fledge's 64 MB thread): `SDL_Init` refused, `SDL_Init: Application didn't initialize properly, did you include SDL_main.h in the file containing your main() function?`.
- Ruby's thread calling `SDL_SetMainReady` first: the app died with `EXC_BREAKPOINT` as soon as SDL's video started; the faulting thread was Ruby's, in `SDL_InitSubSystem`, `SDL_VideoInit`, `UIKit_SuspendScreenSaver`, and `-[UIApplication _setIdleTimerDisabled:forReason:]`, ending in `BSServiceMainRunLoopQueue` with "threading violation: expected the main thread".
- SDL's host (`SDL_RunApp` with a main function that calls `fledge_ruby_run_app`, and `SDLUIKitSceneDelegate`): drew and took touches.

Stack measurements on iOS (`pthread_get_stacksize_np`, main thread under SDL's host): 8176 KB in the Simulator with no flag; 65536 KB with `-Wl,-stack_size,0x4000000`; the unsigned device build's `LC_MAIN` held `stacksize 67108864`. Ruby's thread under Fledge's host had 65548 KB. Recursion depth before `SystemStackError`, through a C method at every level (a lambda calling itself from `Array#each`): 3970 levels in all three, because Ruby's VM stack, 1 MB for the main thread, ran out first. On the Mac's desktop Ruby 4.0.9 with `ulimit -s` setting the main thread's stack: 392 levels at 512 KB, 807 at 1 MB, 3970 at 8 MB (6601 at 8 MB with `RUBY_THREAD_VM_STACK_SIZE` at 64 MB), about 1.25 KB a level. ld took `-stack_size` only for a main executable ("-stack_size option can only be used when linking a main executable"), and Xcode's Debug configuration linked the app's code into `NAME.debug.dylib` (`ENABLE_DEBUG_DYLIB`).

Stack measurements on Android, x86_64 emulators, API 36 (`pthread_getattr_np`): Ruby's 64 MB thread had 66593 KB and recursed 3970 levels, with 4 KB and 16 KB pages. SDLThread, with Java's default stack size, had 1057 KB; with 4 KB pages Ruby there recursed 867 levels, and with 16 KB pages the probe's `rescue SystemStackError` did not hold: the program ended with `main.rb:28:in 'each': stack level too deep (SystemStackError)` and status 1, in two runs of two. Why the rescue missed was not established.

The local run with `fledge build ios`, the spike's `host/apply.rb`, and `xcodebuild test` with a UI test that taps the screen (`host/ios/UITests/TapTest.m`), with the runtimes of trunk's CI run 41508388336 (b6629ae), on an iPhone and an iPad:

```
SdlDemo runs Ruby on the main thread with a stack of 65536 KB, and recurses 3970 levels deep, on arm64-darwin with SDL 3.4.18
SdlDemo touch down at 398, 865 in 1206x2622, frame 966
SdlDemo drew 1057 frames in all, after a touch
SdlPhone exited with status 0
```

CI, branch `experiment/sdl-phones`, workflow running only these jobs with the same runtimes, driver `.github/scripts/sdl_phone.rb` there: run 41541037904, every job green. SDL3 built with the runners' CMake (4.4.4 on macOS, 3.31.6 on Ubuntu), Xcode 26.5, and the pinned NDK r30.

- iOS Simulator, iPhone 17 Pro and iPad Pro 13-inch (M5), iOS 26.5, tapped by the UI test with a screenshot of each: `SdlDemo runs Ruby on the main thread with a stack of 65536 KB, on arm64-darwin with SDL 3.4.18`, `SdlDemo recurses 3970 levels deep`, `SdlDemo touch down at 398, 865 in 1206x2622, frame 1178`, `SdlDemo drew 1269 frames in all, after a touch`, `SdlPhone exited with status 0`; on the iPad `touch down at 681, 908 in 2064x2752, frame 1126` and `drew 1217 frames`. The unsigned Release build for devices linked (`platform IOS, minos 15.0`), and its `LC_MAIN` asked for 67108864 bytes.
- Android x86_64 emulator, API 36, 4 KB and 16 KB pages, tapped with `adb shell input tap` once Android's one-time "Viewing full screen" notice was marked seen (`settings put secure immersive_mode_confirmations confirmed`; an earlier run's tap landed on the notice): `SdlDemo runs Ruby on a thread of its own with a stack of 66593 KB, on x86_64-linux-android with SDL 3.4.18`, `recurses 3970 levels deep`, `touch down at 106, 385 in 320x640, frame 368`, `drew 459 frames in all, after a touch` (16 KB pages; with 4 KB pages `frame 430` and `521 frames`), status 0.
- arm64-v8a, built and checked: the debug and the unsigned release APK held `lib/arm64-v8a/` and `lib/x86_64/` `libSDL3.so`, `libfledgeext.so`, and `libfledgeruby.so`, and passed `zipalign -c -P 16`; `libfledgeext.so` needed `libfledgeruby.so`, `libSDL3.so`, `liblog.so`, `libm.so`, `libdl.so`, and `libc.so`, and `libSDL3.so` needed only the system's (`libOpenSLES.so`, `libandroid.so`, `libGLESv1_CM.so`, `libGLESv2.so`, and the C libraries).

Two runs before 41541037904 failed on what they were built to find: the first on the `extconf.rb` passing `sdl3.pc`'s `-L${libdir}` unexpanded, the third on Ruby on SDLThread with 16 KB pages, which the driver then reported instead of failing on.

Running the spike found three faults in ADR 022's linking, since fixed (tests in `test/mobile_extensions_test.rb`): `-framework NAME` was kept as two words and merged with `uniq`, so `-framework UIKit -framework Metal` became `-framework UIKit Metal`; a static library an `extconf.rb` named went into `OTHER_LDFLAGS`, shared by every slice, so the Simulator's link took the device's `libSDL3.a`; and `libSDL3.so` stayed out of the APK.

### The `host` key in CI (2026-11-02)

From old ADR 025, section 6. Branch `experiment/phone-host`, runtimes of trunk's run 41548182485 (681c459), driver building the projects with `fledge build` alone: run 41580788898, every job green. The builds said `host/ios replaces Fledge's Host/Info.plist, Host/main.m, project.yml` and `host/android replaces Fledge's src/main/java/org/setdef/fledge/host/MainActivity.java`. The device build's `LC_MAIN` again asked for 67108864 bytes. iPhone 17 Pro: `touch down at 398, 865 in 1206x2622, frame 978`, `1069 frames`; iPad Pro 13-inch (M5): `touch down at 681, 908 in 2064x2752, frame 1238`, `1329 frames`; Android 4 KB pages: `frame 368`, `459 frames`; 16 KB pages: `frame 418`, `509 frames`; each with Ruby's stack and depth as before, and status 0. The run before, 41579700222, failed on the iOS UI test: the project's `-stack_size` reached the test bundle too, which ld refuses for anything but a main executable, so the host's `project.yml` gives the test target no linker flags of the project's.

Not verified then: an iPhone 12 mini (a later Ruby 4.1 spike ran `examples/native_phone` on one); audio, game controllers, and SDL's other subsystems; an app coming back from the background; SDL as an XCFramework or a dynamic library on iOS; SDL's satellite libraries (SDL_image, SDL_ttf, SDL_mixer); a C++ extension over SDL.

### A game on a real iPad (2026-11-05)

From old ADR 025, section 6. A game on a wrapper for 2D games, built by `fledge build ios` from Fledge v0.5.1 with its engine linked as ADRs 022 and 025 describe and its host named by `ios: host:`, ran on an iPad Pro 12.9-inch (6th generation, M2, iPad14,5) with iPadOS 26.7.1, signed with a free Personal Team and installed from a Mac with `xcodebuild` and `devicectl`. The maintainer played it and reported, in a results file: the game fills the screen with no status bar in both orientations; a tap pops where the finger is; an Xbox controller works; sound plays, mixes with another app's audio, and goes quiet in Silent Mode; rotating mid-round keeps every dot on screen; tilting at Game Over rolls the dots; no crash or freeze in several rounds. Not measured: whether the device granted the 64 MB main-thread stack, since nothing recursed deeply.

### A game and `examples/sdl_phone` on a real iPhone 13 mini (2026-11-05)

From old ADR 025, section 6, and old ADR 011 and 012, Consequences. The same game (v0.8.3), and `examples/sdl_phone` built for a device, ran on an iPhone 13 mini (iOS 18) signed with the same free Personal Team. The example logged `SdlDemo runs Ruby on the main thread with a stack of 65536 KB` and recursed 3970 levels deep: the device granted the 64 MB that `-stack_size` asks for. What the SDL build does at this phone's fractional native scale (2.880) is the framework's to explain.

### A game on a real Android phone (2026-11-05)

From old ADR 019, section 5, and old ADR 025, Consequences. A game built by Fledge v0.5.1 ran on a OnePlus Nord N30 5G (Android 14, arm64-v8a), the first run of the arm64-v8a runtime.

### CMake in an `extconf.rb`, before and after the toolchain file (2026-11-03)

From old ADR 027, Context and section 7. `examples/cmake_phone`: a path gem `tally` whose `extconf.rb` runs `cmake -S lib -B tally-build` and `cmake --build tally-build` to build `libtally.a` from `tally.cc`, then builds `tally.c`, a C extension over it, reporting the system CMake configured for and the processor and platform its compiler aimed at.

Before the fix, built with `fledge build` at 19efbfa with the runtimes of trunk's run 41764673083 and CMake 4.3.2:

- iOS: CMake found `/usr/bin/c++` (AppleClang 21) and built `libtally.a` for macOS for both slices; mkmf's `tally.a` was for iOS; `libtool -static` merged them, and `xcodebuild -create-xcframework` refused: `binaries with multiple platforms are not supported`.
- Android: the same macOS `libtally.a`; the NDK's `ld.lld` warned `archive member 'tally.cc.o' is neither ET_REL nor LLVM bitcode`, skipped it, and linked `libfledgeext.so` with `tally_sum` and `tally_built_for` undefined (`llvm-readelf --dyn-syms`). The build succeeded; the app would have failed when Android loaded the library. It also needed `libc++_shared.so`: the NDK's clang linked the `extconf.rb`'s `-lstdc++` as the shared C++ runtime, and its `-lc++` is no better (`sysroot/usr/lib/x86_64-linux-android/26/libc++.so` is the linker script `INPUT(-lc++_shared)`).

After, on the Mac (Xcode 27.2, CMake 4.3.2, NDK r30), with the same runtimes, in `test/mobile_extensions_test.rb`: the `tally.cc.o` CMake built was `platform IOS` in `ios-arm64` and `platform IOSSIMULATOR` in `ios-arm64-simulator` (`xcrun vtool -show-build`); each Android `libfledgeext.so` was for its machine (AArch64, x86-64), with no undefined `tally_` or C++ runtime symbol and no need of `libc++_shared.so`. Without `CMAKE_TOOLCHAIN_FILE` the tests failed on every target; without the C++ runtime rule on undefined C++ runtime symbols.

CI, branch `experiment/cmake-phone`, workflow running only the Mobile apps jobs for `examples/cmake_phone` and `examples/native_phone`, same runtimes: run 41779653817, every job green, with the runners' CMake (4.4.4 on macOS, 3.31.6 on Ubuntu), Xcode 26.5, and the pinned NDK r30. iOS Simulator, iPhone 17 Pro and iPad Pro 13-inch (M5), iOS 26.5: `CmakePhone totals 10 in C++ that CMake 4.4.4 built for iOS Simulator on arm64, on arm64-darwin`, status 0; the unsigned Release build for devices linked (`minos 15.0, sdk 26.5`) with no warning. Android x86_64 emulator, API 36, 4 KB and 16 KB pages: `CmakePhone totals 10 in C++ that CMake 3.31.6 built for Android on x86_64, on x86_64-linux-android`, status 0; both APKs passed the 16 KB and target-API checks for both ABIs. `NativePhone` printed its line on all four.

Not verified: the device slice and arm64-v8a running; a CMake build that uses `find_package` or `find_library`; the Xcode generator (`CMAKE_GENERATOR=Xcode`); an Android APK built on a Mac (the Mac compiled and linked both ABIs in the tests; CI built the APKs on Linux).

### `OS_ACTIVITY_DT_MODE` makes forwarded output loop (2026-11-05)

From old ADR 011, section 5. The device playtest found it in the Simulator: the first line 42 times in 30 seconds, and no frame drawn (`doc/contributors/device-test.md`, section 6). What counts is the variable's presence, not its value: on macOS 27.0.1 and in the iOS 26.1 Simulator (`simctl spawn` and `simctl launch`), `os_log` copied an entry to standard error with the variable set to `YES`, `1`, `true`, `NO`, `0`, `false`, `foo`, or nothing, and did not with it unset. A program of `output.c` and `apple.c` alone, launched as an app in that Simulator, logged its first line 40 times and never its last with the variable set to `YES` or `NO`, and once each without it.

CI, branch `experiment/ios-output`, whose Mobile apps (iOS) job ran each app also with `OS_ACTIVITY_DT_MODE=YES` and read its streams with `simctl launch --console`: with the runtime from before the fix, `examples/hello` logged 1,135 entries in a tenth of a second, its line inside 17 of them, and its streams carried nothing of it (run 41981582665); with the fixed runtime, `examples/hello`, `examples/mobile_app`, and `test/fixtures/mobile_hello` each printed its line once on its streams and exited 0, on an iPhone and an iPad (run 41985507137). Without the variable every app logged as before in both runs.

Background read then: Xcode before 15 set the variable for the program it ran, and "the existence and behaviour of this environment variable is an implementation detail" (Quinn, Apple DTS, developer.apple.com/forums/thread/705868); Xcode 15 and newer read the log itself unless a scheme asks for `IDELogRedirectionPolicy=oslogToStdio` (Xcode 15 release notes, 109380695). CPython's iOS support, which Briefcase's iOS template turns on (`config.use_system_logger = 1`, `main.m` line 68 at fe1bcaf), replaces only `sys.stdout` and `sys.stderr` (`Lib/_apple_support.py` lines 5 to 10; `Python/pylifecycle.c`, `init_apple_streams`, lines 3376 to 3411 at 7c5231e), so it never meets the loop. Briefcase's macOS template skips its own forwarding when Xcode sets `IDE_DISABLED_OS_ACTIVITY_DT_MODE` (`main.m` lines 484 to 489 at c0ee4ea); Fledge forwards then, since nothing loops.

### A phone app's lines arrive as printed (2026-11-05)

From old ADR 011, section 5. Through 0.5.0 a game's lines reached the iOS log only when it ended, in a framework's CI in the iPad Simulator, until the game set `$stdout.sync = true` itself. Branch `experiment/phone-stdout`: an app that printed a line, slept 5 seconds, and printed another (`test/fixtures/mobile_prompt` there) logged the first 5.0 seconds before the second, by the log's own timestamps, on an iPhone and an iPad in the iOS 26.5 Simulator and on Android emulators of API 36 with 4 KB and 16 KB pages; with 0.5.0's runtimes both arrived at the same instant, when Ruby ended (run 42023858857). The parity probe there reported `$stdout.sync` true with the fix and false without it.

Prior art read then: Briefcase's iOS host, "We want output to appears in the log immediately" (`config.buffered_stdio = 0`, `main.m` lines 57 and 58 at fe1bcaf); CPython's iOS stream is line-buffered (`Lib/_apple_support.py` line 16 at v3.14.0); its Android support flushes at each newline ("Since this is a line-based logging system, line buffering cannot be turned off", `Lib/_android_support.py` lines 82 to 106 at v3.14.0), as Chaquopy's does (`product/runtime/src/main/python/java/android/stream.py` line 103 at 71a373b); none claims to be a terminal.

### The Android App Bundle in CI (2026-11-07)

From old ADR 012, section 9. Each of the three conditions (asset made for a bundle, `fledge.zip` stored, native libraries stored and 16 KB-aligned) was checked on a built bundle before any CI ran. Branch `experiment/android-aab`, workflow running only these jobs with the runtimes of trunk's run 42428270566 (5f851d2): run 42435210013, every job green, with no change to how the template builds; only its comments changed, to name the bundle tasks and `jarsigner`. All six apps, run from their bundles' APKs on both emulators, printed the same lines as from their APKs and exited 0, and the probe found 16 differences, all justified, either way. The release bundles were 22.9 to 23.9 MB, and their largest downloads 16.3 MB (`examples/hello`) to 17.3 MB (`examples/mobile_app`); `examples/native_phone`'s and `examples/cmake_phone`'s `libfledgeext.so` was stored at 16 KB in every split. The emulator jobs took about ten minutes, four more than before. `examples/sdl_phone`'s host is not in the check: it needs SDL built by its `sdl3/build.sh`, which no CI job on trunk runs.

Sizes: `examples/mobile_app`'s release bundle is 23.9 MB, and bundletool's `get-size total` measures its largest download, the base and one ABI's split for API 29 to 31 on arm64-v8a, as 17.3 MB, with the master APK holding the 30.3 MB `fledge.zip` stored.

Sources read on 2026-11-07: "From August 2021, new apps are required to publish with the Android App Bundle on Google Play" (developer.android.com/guide/app-bundle); Briefcase's `briefcase package android` makes an AAB by default; Flutter's `flutter build appbundle` writes `build/app/outputs/bundle/release/app.aab` (docs.flutter.dev/deployment/android); "you can also specify which file types to leave uncompressed when packaging APKs using glob patterns" (developer.android.com/build/building-cmdline); "If you see `PAGE_ALIGNMENT_16K` then you know your bundle requests 16 KB zip alignment", and the warning that with the plugin's 8.3 to 8.5 "`bundletool` does not zipalign APKs by default" (developer.android.com/guide/practices/page-sizes); "You cannot use `apksigner` to sign your app bundle" (developer.android.com/build/building-cmdline); Play's limits of 500 MB for a base module's compressed download and 4 GB for modules and install-time asset packs together (support.google.com/googleplay/android-developer/answer/9859372). Not proven: an upload to Play, Play's review, and an arm64-v8a device running the bundle's split.

### The iOS archive check in CI (2026-11-07)

From old ADR 012, section 10. `xcodebuild -exportArchive` on Fledge's unsigned archive, with an `ExportOptions.plist` whose `method` is `app-store-connect`, failed at once with `error: exportArchive No Team Found in Archive` (Xcode 27.2). `man xcodebuild` (Xcode 27.2): it "requires `-archivePath` and `-exportOptionsPlist`", and "an Apple ID account belonging to the archive's development team is required". `xcrun altool --validate-app` and `--upload-app` "require authorization" (`altool --help`, Xcode 27.2). Apple: an archive is "a build of your app, including debugging information, that Xcode stores in a bundle", and Xcode's Validate App performs only "a limited, automated initial validation" ("Distributing your app for beta testing and releases"). Flutter's `flutter build ipa` writes the same `.xcarchive` and stops where an account starts (docs.flutter.dev/deployment/ios).

What the check found: everything Xcode writes into the app's `Info.plist` was there, and the template needed no change. The one defect was `examples/mobile_app`'s 1024 pixel icon, RGBA with transparent, pre-rounded corners, which App Store Connect would have refused (ITMS-90717, as developers report it in Apple's forums, thread 86829); the example's icon is now a full-bleed square without alpha.

Branch `experiment/ios-archive`, workflow running only the Mobile apps (iOS) job with the runtimes of trunk's run 42440596461 (ec4b920): run 42444091357, green in 12 minutes 56 seconds, with Xcode 26.5. All six apps archived and passed, `examples/mobile_app` with its icon and the other five with the note that they have none, and each then ran on the iPhone and iPad Simulators as before, the probe finding 16 differences from `ruby main.rb`, all justified.

### Export compliance and version 0.0.0, as Apple's and Google's pages read (2026-11-07)

From old ADR 012, section 10. Read through developer.apple.com's `tutorials/data` JSON on 2026-11-07:

- `ITSAppUsesNonExemptEncryption` is for an app "including any third-party libraries you link against" that "either uses no encryption, or only uses encryption that's exempt"; "Overview of export compliance" asks for a determination when an app "uses, accesses, contains, implements, or incorporates encryption". Every Fledge iOS app then contained OpenSSL 3.6.5.
- Exempt by name: "encryption that's built into the operating system—for example, when your app makes HTTPS connections using `URLSession`" ("Complying with encryption export regulations"). Apple's table for "an industry standard algorithm, not provided within the Apple operating system" asks only for a French declaration, for distribution in France ("Export compliance documentation for encryption"), and says nothing of whether the key is `false`.
- "you're responsible for all liabilities associated with misinterpretation of export regulations or claiming exemption inaccurately", and "you might alternatively be required to submit a year-end self-classification report" to BIS. BIS's text (EAR 740.17, 742.15) could not be read from bis.gov's pages.
- `CFBundleVersion` is "one to three period-separated integers ... 0 specifies 0.0.0"; `CFBundleShortVersionString` "three period-separated integers", with no word on zero. No App Store Connect page read (the upload statuses, the version information reference) refuses 0.0.0; an older Apple wording that the first integer be above zero, which a blog quoted, is not in the current reference. Google Play: `versionCode` is "a positive integer" up to 2,100,000,000. Flutter: "Each upload needs a unique build number".

## Releases

### What running CI again on the tag cost (2026-11-03)

From old ADR 014, section 4. Through 0.2.1, `release.yml` ran all of CI on the tagged commit before publishing. That run tested the commit the pin commit's push had tested minutes earlier, and threw its runtimes away. It cost each release about 28 minutes, and drew every flaky download a second time. 0.2.0 was never published: that run, and its re-run, failed on `musl.libc.org` resetting the connection, in a job that builds nothing a release publishes (`doc/contributors/research/2026-11-03-ci-speed.md`, sections 1 and 3). Commit 74e0864 replaced the second run with a lookup of the push's run.

### What a pin commit's full CI run cost (2026-11-03)

From old ADR 014, section 5. Before the short CI, a pin commit's run built every runtime again, delivered every app again, and threw it all away, about 30 minutes per release (commit d0de4a4). Two of the three releases through 0.2.0 needed that run re-run for a flake.

### GitHub's API and 100 jobs a page (2026-11-03)

From commit 74e0864, which old ADR 014, section 4, recorded. GitHub's REST API answered 502 to every request for 100 jobs of a run that had been run again, and to 50 at once. `tasks/ci_runs.rb` reads 50 jobs a page and asks again after a 5xx.

### Release downloads that fail for a moment (2026-11-07)

From old ADR 014, section 6. GitHub's release downloads answered a 502 or 504 now and then, and passed a minute later. CI's own downloads failed that way for days, until `tasks/download_cache.rb` tried them again (commit 46ab775). `fledge build` met the same hosts with one try, so a developer's build, or a release's `installed.yml`, failed on a moment's outage of GitHub or of a gem server. Commit 4a815c3 added `Fledge::Download`'s retries.

### Rooibos, the first framework wrapper proven (2026-11-01)

From old ADR 019, sections 1 and 4. Rooibos 0.8.0 was the wrapper closest to shipping: pure Ruby on `ratatui_ruby`, a Rust gem published precompiled for `arm64-darwin`, `x86_64-linux`, and `x64-mingw-ucrt`. Tokra 0.0.1.pre.2 compiled a Rust extension everywhere and needed WebKitGTK on Linux; Lota was 0.0.0, unpublished, with no examples. The proof's app was Rooibos's `examples/verify_website_hello_mvu` (MIT-0) as `main.rb`, with a Gemfile that locked `rooibos` 0.8.0 and put Fledge, from the tag `v0.0.1.pre.16`, in the `development` group, locked for `arm64-darwin`, `x86_64-linux`, `aarch64-linux`, and `x64-mingw-ucrt` with checksums.

Run 41360640888 on `experiment/wrapper` did what Rooibos's own CI would: on a runner of each platform it wrote that project from Rooibos's `v0.8.0` tag, installed Fledge from the tag with Bundler, and built with the release's runtime. On a fresh runner it ran the program in an 80 by 24 pseudo-terminal (macOS and Linux, `python3`'s `pty`) or a console of its own (Windows, read with `ReadConsoleOutputCharacterW`, typed into with `WriteConsoleInputW`), with no Ruby on `PATH` and `RUBYOPT`, `RUBYLIB`, and `GEM_HOME` set. The app showed `Current count: 0.`, showed `1` after an `a` was typed, restored the terminal, and exited 0 on Ctrl-C. It passed on `arm64-darwin`, `x86_64-linux`, `aarch64-linux` (where `ratatui_ruby` compiled with cargo), and `x64-mingw-ucrt`. `aarch64-mingw-ucrt` and the musl platforms were not proven: `ratatui_ruby` published no ARM64 Windows build.

Building Rooibos's own repository, rather than such a project, found the RubyGems plugin-loader bug that old ADR 019, section 3, records (now in `doc/contributors/design/gems.md`).
