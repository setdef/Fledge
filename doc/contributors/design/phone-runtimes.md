<!--
SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>

SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Phone Runtimes

This document says how Fledge's phone runtimes are built and what they hold, how the embedding API starts an app's Ruby, and what a phone runtime's licenses are. The decisions are ADR 011 (Ruby as a static library built from source), ADR 057 (target names), ADR 058 (bundled gems stay gems), ADR 059 (output to the system log), and ADR 061 (`fledge_ruby_run_app`). The projects `fledge build` writes around a runtime, and what CI checks before a store would, are `doc/contributors/design/phone-projects.md`. What a developer does with the project is in `doc/phones.md`; this document adds the internals.

## Targets

A phone runtime has two targets, named in RubyGems' grammar so that no desktop gem fits them (ADR 057). `RuntimeBuilder::Mobile::PLATFORMS` (`tasks/runtime_builder/mobile.rb`) holds them.

| Runtime | Target | What | Its Ruby's `RUBY_PLATFORM` | Compiler triple |
|---|---|---|---|---|
| `ios` | `arm64-ios` | iPhones and iPads | `arm64-darwin` | `arm64-apple-ios15.0` |
| `ios` | `arm64-ios-simulator` | the iOS Simulator on Apple silicon | `arm64-darwin` | `arm64-apple-ios15.0-simulator` |
| `android` | `aarch64-linux-android` | arm64-v8a phones and tablets | `aarch64-linux-android` | `aarch64-linux-android` (API 26) |
| `android` | `x86_64-linux-android` | x86_64 emulators and Chromebooks | `x86_64-linux-android` | `x86_64-linux-android` (API 26) |

Gem::Platform reads `arm64-ios` as `arm64-unknown`, which matches no desktop gem, and reads the Android names as Linux with Android's C library, which no `-linux`, `-gnu`, or `-musl` gem matches. The floors are iOS 15.0 (xord/cruby's and the spike's) and API 26, Android 8.0, the first whose C library has `nl_langinfo`, which Ruby's `localeinit.c` calls.

The iOS runtime is built on a Mac (`arm64-darwin`), since only Xcode builds for iOS. The Android runtime is built on x86-64 Linux in CI, and a Mac may build it too, with Google's NDK. Neither is built on the other's runner.

## What a phone runtime holds

Each runtime is a release asset of its own, `fledge-runtime-VERSION-ios.tar.gz` and `fledge-runtime-VERSION-android.tar.gz`, with its SBOM and NOTICES beside it as every runtime has (`doc/contributors/design/license-audit.md`). It has no build-only companion: its headers are in it.

**iOS** is `FledgeRuby.xcframework`, made by Apple's `xcodebuild -create-xcframework` from one static library per target, in the slices `ios-arm64` and `ios-arm64-simulator`. Each slice holds:

- `libfledgeruby.a`: Ruby, its extensions and encodings, OpenSSL, libyaml, and the embedding API, merged by Apple's `libtool -static`, with debug information stripped;
- `Headers/`: Ruby's headers, with the slice's `ruby/config.h` moved beside the rest so one folder serves `#include <ruby.h>`, and the embedding API's `fledge_ruby.h` with a Clang module map (`runtime/mobile/module.modulemap`), so Swift imports it as `FledgeRuby` and linking it adds libz and the Security and CoreFoundation frameworks;
- `lib/ruby` and `libexec/cert.pem`: the Ruby the slice runs, which the app copies into its bundle for the slice it builds, as CPython's iOS XCFramework carries its standard library per slice.

The two slices' Rubies differ only in the compiler their `rbconfig.rb` records. One binary runs on iPhone and iPad.

**Android** is `FledgeRuby.aar`, packed by the pinned Gradle and Android Gradle plugin from `runtime/mobile/android/`, holding `libfledgeruby.so` for arm64-v8a and x86_64 and the Java class `org.setdef.fledge.FledgeRuby`. Beside it are one `lib/ruby` for both ABIs (Ruby names each ABI's folder of platform-specific files for its platform, so both fit one tree, and the build fails if any other file differs between them), `libexec/cert.pem`, and `include/`.

`libfledgeruby.so` holds all of Ruby, so native code that links it finds Ruby's whole C API. It keeps OpenSSL's, libyaml's, and libffi's symbols to itself (`--exclude-libs`), so an app's own copies cannot clash with them. The build fails unless it needs only Android's `libc`, `libm`, `libdl`, `liblog`, and `libz`, and unless every LOAD segment is aligned to 16 KB, which Google Play requires of 64-bit apps from 2027-02-01.

Neither runtime has a `bin/ruby` or the gems' executables: nothing on a phone could run them.

## Ruby's C headers on a phone

Both phone runtimes ship Ruby's C headers, for the computer that builds the app: each iOS slice in `Headers/`, and the Android runtime in `include/` (both ABIs' `include/ruby-VERSION/` merged, with each ABI's configuration folder, and `fledge_ruby.h`). mkmf compiles a gem's extension against them (see `doc/contributors/design/phone-projects.md`, "Gems with extensions"), and native code that links the runtime includes them.

The app on the phone carries no headers. The iOS project's build phase copies the slice's `lib/` and `libexec/` into the bundle, and the Android project puts the runtime's `lib/` and `libexec/` in `fledge/`, so the Ruby root an app runs from has no `include/`. `require "mkmf"` on a phone therefore aborts as it does where Ruby's headers are missing. A desktop runtime keeps its headers for that reason (`doc/contributors/design/runtimes.md`); on a phone an app starts no programs, so mkmf's `find_executable` could find nothing it may run, and the mobile parity check does not test it.

## Building Ruby for a phone

`RuntimeBuilder::IOS` and `RuntimeBuilder::Android` (`tasks/runtime_builder/ios.rb` and `android.rb`, over `mobile.rb`) build the pinned Ruby from its release tarball with Ruby's own `configure` and `make`, after xord/cruby's Rakefile on iOS and Termux's `packages/ruby/build.sh` on Android. Every input is pinned by version and SHA-256 under `mobile:` in `runtime/sources.yml`: Ruby's tarball, OpenSSL, libyaml, libffi, the NDK for each computer that runs it, Gradle and the Android Gradle plugin, Mozilla's CA certificates as curl publishes them, XcodeGen, and bundletool. Xcode is chosen by version on the runner, since Apple publishes no download to pin.

For each target the build:

1. builds libyaml and, on Android, libffi with their own `configure` (`--enable-static --disable-shared --with-pic`), and OpenSSL with its own `Configure` target for the platform (`ios64-xcrun`, `iossimulator-arm64-xcrun`, `android-arm64`, `android-x86_64`), with no shared library, programs, tests, documents, or modules;
2. configures Ruby with `--enable-load-relative --disable-shared --with-static-linked-ext --disable-yjit --disable-zjit --without-gmp`, the dependencies' folders, `--with-out-ext` for Windows' extensions and the bundled gems' own builds (see "Bundled gems' extensions"), and `PKG_CONFIG=false`, so nothing of the build machine's leaks in;
3. writes the builtin binary (see "The builtin binary"), runs `make`, marks the bundled gems' extensions built, and runs `make install-nodoc`;
4. checks the bundled gems were installed, prunes the tree as a desktop runtime is pruned, and installs Fledge's RubyGems defaults (`doc/contributors/design/runtimes.md`).

What each system adds:

- **iOS** builds with Xcode's clang (`xcrun --sdk iphoneos|iphonesimulator`), aimed at the target's triple and the SDK's sysroot, configured for the host `aarch64-apple-darwin` so that Ruby's `configure.ac` does what it does for Darwin. After xord/cruby it passes `--disable-dln`, tells configure that iOS has no `system`, `syscall`, `__syscall`, `backtrace`, `getentropy`, `dup3`, or `pipe2` (`RuntimeBuilder::IOS::MISSING`), adds a stub `sys/vnode.h` the SDK lacks (xord/cruby's, with its MIT notice as an SPDX snippet in `ruby_source.rb`; it is a header Ruby compiles against, and nothing of it ships), and builds with `-Os -fvisibility=hidden` and `-framework Security`. OpenSSL's Simulator build takes `-mios-simulator-version-min`, since with `-mios-version-min` its assembly is tagged for devices and the Simulator's link fails. fiddle is left out (ADR 058).
- **Android** builds with the NDK's `TRIPLE26-clang`, `llvm-ar`, and `llvm-ranlib`, and tells configure what Termux tells it about bionic (`RuntimeBuilder::Android::TERMUX`): no `setgroups`, `setresuid`, `setreuid`, or libcrypt, so `String#crypt` is Ruby's own `missing/crypt.c`. The NDK is unpacked from its pinned download and checked to be the revision `runtime/sources.yml` names.

Then each system packs what it built. iOS merges every archive Ruby's build made (libruby, each extension's, the encodings' and transcoders'), `extinit.o` and `encinit.o`, the libraries, and the embedding API's objects into `libfledgeruby.a` per slice. Android links the same into `libfledgeruby.so` per ABI with `-Wl,--whole-archive`, `--exclude-libs` for the libraries, `--wrap=X509_get_default_cert_file` (see "Certificates"), and `-z max-page-size=16384`, then strips it. Both leave out libruby's `dmyext.o` and `dmyenc.o`, the empty `Init_ext` and `Init_enc` of a Ruby without static extensions: the linker would take them before `extinit.o`'s and `encinit.o`'s, and `require "json"` would fail. The embedding API's C is compiled with the launcher's warnings as errors and checked by clang's static analyzer.

## Scripted edits to Ruby's source

`RuntimeBuilder::RubySource` (`tasks/runtime_builder/ruby_source.rb`) makes a few edits to Ruby's source before it builds. Each fails the build when the lines it replaces are gone, so a new Ruby shows which to look at again.

| Edit | System | What it does | From |
|---|---|---|---|
| `psych_extconf` | both | psych's `extconf.rb` stops preferring pkg-config's libyaml | xord/cruby |
| `vm_dump` | iOS | `vm_dump.c` stops calling `system()` | xord/cruby |
| `configure` | Android | the generated `configure` stops appending `-android` twice, so the platform is `aarch64-linux-android`, not `aarch64-linux-android-android` | Termux's guard |
| `ruby_c` | both | `ruby.c` gains `ruby_embed_libruby_path`, through which an embedder names the file Ruby would otherwise find with `dladdr` and derive its prefix from (`runtime_libruby_path`, lines 591 to 664 at Ruby 4.0.9) | Fledge |

The last exists because on Android Ruby's library sits in a folder of native libraries alone, and an iOS app may keep Ruby anywhere in its bundle, so neither prefix is where `dladdr` would point.

## The builtin binary

A cross build cannot run its own miniruby, so `configure.ac` (lines 1584 to 1588 at Ruby 4.0.9) leaves out the builtin binary, and Ruby falls back to `mini_builtin.c`, which never loads `gem_prelude.rb`: such a Ruby boots with no RubyGems. An iseq binary depends only on Ruby's version, endianness, and word size (`compile.c`, `ibf_load_setup_bytes`), so the build makes a miniruby for the build machine from the same source, once per runtime, and has it write `builtin_binary.rbbin` from Ruby's own template into each target's build folder. It then sets the Makefile's `BUILTIN_BINARY` to `yes` and adds a rule to `GNUmakefile` that keeps `make` from replacing the file with the empty stub a cross build writes. It fails when the binary or the Makefile line is not what it expects.

## Bundled gems' extensions

Ruby's build links its standard library's extensions in and registers each in `extinit.c`, but not a bundled gem's: `template/configure-ext.mk.tmpl` builds `.bundle/gems` with `--no-extstatic`, and `ext/extmk.rb` (line 656 at Ruby 4.0.9) leaves a gem's extension out of `extinit.c`. `RuntimeBuilder::BundledExtensions` keeps those gems gems (ADR 058):

1. It copies each bundled gem's extension sources (its `ext/`, and the `lib/`, `include/`, and `src/` its `extconf.rb` reads beside it) among Ruby's own, to `ext/gems/NAME`, where extmk links them in and registers each under the feature the gem requires (`bigdecimal.so`, `racc/cparse.so`, `rbs_extension.so`).
2. `configure --with-out-ext` leaves out the gem's own build, by the names extmk matches a gem by (`NAME` and `NAME-*`, `ext/extmk.rb` lines 519 to 523 at Ruby 4.0.9).
3. Once Ruby is built, it writes each gem's `gem.build_complete` where its own build would (`.bundle/extensions/PLATFORM/ABI-static/NAME-VERSION/`), so `tool/rbinstall.rb` installs the gem, specification and all, and RubyGems loads it rather than ignoring it because its extensions are not built.
4. After install it checks that every such gem has its specification and its mark.

When the gem's Ruby requires its extension, `load.c`'s `search_required` finds no file and looks among the statically linked extensions, which have it. On iOS fiddle is left out, as xord/cruby leaves it out "to pass the App Store review", since it calls any C function by name. win32ole and win32 are Windows' alone. Every other bundled and default gem is as a desktop runtime has it, but one.

On Ruby 4.1 the phones' runtimes also leave out the bundled prism gem (`RuntimeBuilder::Mobile#omitted_gems`), which breaks ADR 058. Its extension compiles its own copy of libprism, and libruby holds Ruby's own, so linking both into one library defines the same symbols twice. Without it, `require "prism"` fails on a phone, and so does activating irb, minitest, rbs, rdoc, repl_type_completor, or typeprof, which depend on it. `Parity::MOBILE_JUSTIFIED` records the difference as temporary. This is a defect to fix, not a decision: the fix links prism's extension beside libruby's prism, and removes this paragraph and those entries.

## The embedding API

`runtime/mobile/fledge_ruby.h` is the embedding API, in C, compiled into both runtimes with `fledge_ruby.c`, `output.c`, `apple.c` or `android.c`, and the launcher's `locale.c`, `config.c`, and `bundler.c`. Its header comments are the reference for each function.

| Function | What it does |
|---|---|
| `fledge_ruby_forward_output(tag)` | Sends standard output and standard error to the system log (see "Output to the system log"). |
| `fledge_ruby_run(root, script, argc, argv)` | Runs a Ruby file on the calling thread, as `ruby SCRIPT ARGS` would, and returns its status. |
| `fledge_ruby_run_app(root, argc, argv)` | Runs the app `fledge build` put in `root`, as the desktop launcher runs one (ADR 061). |
| `fledge_ruby_add_extension(feature, init)` | Tells Ruby that an extension is linked in (see `doc/contributors/design/phone-projects.md`, "Registering extensions"). |

`fledge_ruby_run` starts Ruby as the desktop launcher does, after Ruby's own `main.c` (`doc/contributors/design/launcher.md`): the locale, `ruby_sysinit`, then `ruby_start_main`, whose callback runs `RUBY_INIT_STACK`, `ruby_init`, and `ruby_run_node(ruby_options(...))`, with `ruby --disable=rubyopt -- SCRIPT ARGS`. Between `ruby_options` and `ruby_run_node` it registers the extensions added so far and puts `$stdout` in sync mode when descriptor 1 is not a terminal (ADR 059). Ruby's prefix is `root`, through `ruby_embed_libruby_path`, so the load path and `Gem.path` are `root/lib/ruby`, which Fledge's RubyGems defaults keep `Gem.path` to. A bare C locale becomes a UTF-8 one, with the launcher's own `fledge_coerce_locale` (ADR 041). Ruby boots once per process, so a second call returns 70 (`FLEDGE_RUBY_SOFTWARE`).

`fledge_ruby_run_app` reads `root/fledge.cfg` with the launcher's reader and runs `root/app/ENTRY`. For an app with a Gemfile it sets `BUNDLE_GEMFILE` to the app's Gemfile, whose `.bundle/config` Bundler then reads as the app's settings, and requires `bundler/setup` from Ruby's own library, or from the gem of the Bundler `fledge.cfg` names, as the desktop launcher does (`doc/contributors/design/launcher.md`, "The Bundler environment"), which sets `ENV` as `bundle exec` would (`Bundler::Runtime#setup`, `set_bundle_environment`). It returns 66 (`FLEDGE_RUBY_NO_APP`) when `fledge.cfg` or the program is missing, and 70 when the configuration is damaged or Bundler cannot set up the gems.

Unlike the desktop launcher, neither function sets anything of the environment aside: iOS and Android start an app with an environment of their own, which no person sets. Ruby needs a deep stack: Fledge's hosts run it on a thread with 64 MB.

Swift needs no shim: the module map imports the C functions.

## Output to the system log

iOS and Android discard an app's standard streams unless a debugger holds them. `fledge_ruby_forward_output` (`runtime/mobile/output.c`) makes standard output and standard error each the write end of a pipe, which a thread of its own reads line by line into the system log (ADR 059):

- on Apple's systems, os_log with the tag as subsystem (`apple.c`);
- on Android, logcat with the tag as tag, standard error's lines as warnings, as CPython's Android support logs them (`android.c`).

A line longer than an entry holds (logcat cuts one at about 4,000 bytes) goes as several entries in a row of at most 1,000 bytes (`FLEDGE_LOG_ENTRY_MAX`, `mobile.h`). The cut falls between UTF-8 characters and before whitespace, never after it, since the unified log drops an entry's trailing whitespace (`log show` prints `a ` as `a`), which would take a space out of the line the entries make (`fledge_log_chunk`).

**`OS_ACTIVITY_DT_MODE`.** When the process's environment holds this variable, the unified log copies each entry to standard error, for a developer tool that reads the app's streams. Then `fledge_ruby_forward_output` leaves the streams alone and returns 0 (`fledge_log_echoes` in `apple.c`), since forwarding standard error would send each copy back to the log, which would copy it again, until the pipe filled and Ruby's `puts` blocked. What counts is that the variable is present, not its value: `NO`, `0`, and an empty value turn the copy on as `YES` does. Android's `fledge_log_echoes` is always false, since logcat copies nothing to an app's streams. Xcode 15 and newer read the log itself and set the variable only when a scheme asks for the old way (`IDELogRedirectionPolicy=oslogToStdio`). With the variable set, a developer tool shows each of the app's lines once, from its streams, and the log holds none of Ruby's.

**Line timing.** Ruby writes through to a terminal but buffers standard output to a pipe until its buffer fills or the program ends (`io.c`, `io_binwrite_requires_flush_write`, lines 1966 to 1979 at Ruby 4.0.9: only `FMODE_SYNC` or `FMODE_TTY` writes at once); standard error is in sync mode already (`rb_io_prep_stderr`). So `fledge_ruby_run` sets `$stdout.sync = true` after `ruby_options`, before Bundler's setup and the program, whenever descriptor 1 is not a terminal (`write_lines_as_printed`, `fledge_ruby.c`). That holds under `OS_ACTIVITY_DT_MODE` too: the streams then go to the developer tool, which reads them as the log is read (`simctl launch --console` gives the app pipes). On a terminal (`simctl launch --console-pty`) Ruby already writes through, and `$stdout.sync` stays false, as under `ruby main.rb` in one.

## Certificates

OpenSSL's compiled-in certificate folder is the build machine's, so the runtime carries Mozilla's CA certificates as `libexec/cert.pem` and points OpenSSL at them.

- **iOS:** `fledge_ruby_run` sets `SSL_CERT_FILE` to `root/libexec/cert.pem` unless the environment names another, and OpenSSL reads it.
- **Android:** OpenSSL reads no environment variable in an app. `ossl_safe_getenv` refuses them where `AT_SECURE` is set (`crypto/uid.c`, `OPENSSL_issetugid`), and every app inherits `AT_SECURE` from zygote, which Android starts in an SELinux domain of its own; setting `SSL_CERT_FILE` alone fails on an emulator. So `libfledgeruby.so` is linked with the linker's `--wrap=X509_get_default_cert_file`, which sends OpenSSL's every call of that function to `android.c`, which answers with the runtime's file. `OpenSSL::X509::DEFAULT_CERT_FILE` names it too. The linker's option needs no edit to OpenSSL's or Ruby's source, and reaches every caller, not only Ruby's default store. Apple's linker has no such option and needs none.

## The Java class

Android needs Java for what C cannot do, in `org.setdef.fledge.FledgeRuby` (`runtime/mobile/android/src/main/java/org/setdef/fledge/FledgeRuby.java`):

- **Unpack the asset.** An app carries `lib/`, `libexec/`, and its own code as one stored zip asset, which the class unpacks into the app's files folder on the first launch of each installed version, and leaves on later launches.
- **Set `HOME`** to the app's files folder when Android sets none, as iOS gives every app one, so `Dir.home` is writable.
- **Pass strings as UTF-8 bytes,** not through JNI's `GetStringUTFChars`, which writes modified UTF-8 that differs past Unicode's first plane, and paths canonical: an app's files folder is `/data/user/0/PACKAGE/files`, through a link to `/data/data`, which Ruby resolves `__dir__` through, as the desktop launcher resolves its own folder.
- **Start Ruby on its own thread** with a 64 MB stack (`STACK_SIZE`), never the UI thread, which Android stops an app for blocking: `start` and `startApp`, with `run` and `runApp` for a caller that has its own thread.

It is Java, not Kotlin, so an app need not depend on Kotlin's standard library; Kotlin calls it as it is.

## Licenses of a phone runtime

Each phone runtime passes the license audit before it is archived (ADR 004; `doc/contributors/design/license-audit.md`), and ships only what decision 8 allows, with no LGPL library. Its components are recorded in `runtime/licenses.yml`: Ruby, OpenSSL, libyaml, libffi on Android, the NDK's compiler-rt builtins and libunwind on Android (`compiler-rt-ndk`), Mozilla's CA certificates as a file, and Fledge's own embedding API (`fledge-embedding`, MIT). GMP is configured out, iOS's `crypt` is its libSystem's, and Android's `String#crypt` is Ruby's own `missing/crypt.c`, so neither runtime carries libxcrypt.

Two things in the audit exist for phones. An iOS runtime has a Ruby per slice, so a platform's map entry names several prefixes (`runtime/licenses.yml`, `prefixes`), and each gem in them is one component. An AAR is a zip whose entries the app ships, so the audit reads each entry with `unzip`, as `FledgeRuby.aar!ENTRY`, and a copyleft library's code in one fails as it would in a file. The audit's readers for the Android runtime are the NDK's own LLVM tools (`RuntimeBuilder::Android#readers`).

The templates and the embedding API are Fledge's own code, MIT, and the host's compiled code ships in every phone app, which `doc/licensing.md` says. Gradle's wrapper, which no app holds, is Gradle's, under Apache-2.0.
