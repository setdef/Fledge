<!--
SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>

SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Phones

This document says how Fledge's phone runtimes are built and what they hold, how the embedding API starts an app's Ruby, what `fledge build ios` and `fledge build android` write, how a gem's extension is compiled and linked into a phone app, how a framework's own startup files enter the project, and what CI checks before a store would. The decisions are ADR 011 (Ruby as a static library built from source), ADR 012 (a project the developer builds and signs), ADR 022 (extensions through mkmf), ADR 025 (host files), ADR 027 (CMake toolchain files), ADR 057 (target names), ADR 058 (bundled gems stay gems), ADR 059 (output to the system log), ADR 060 (the phone as the first operand), ADR 061 (`fledge_ruby_run_app`), and ADR 062 (export compliance). What a developer does with the project is in `doc/phones.md`; this document adds the internals.

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

Both phone runtimes ship Ruby's C headers, for the computer that builds the app: each iOS slice in `Headers/`, and the Android runtime in `include/` (both ABIs' `include/ruby-VERSION/` merged, with each ABI's configuration folder, and `fledge_ruby.h`). mkmf compiles a gem's extension against them (see "Gems with extensions"), and native code that links the runtime includes them.

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

When the gem's Ruby requires its extension, `load.c`'s `search_required` finds no file and looks among the statically linked extensions, which have it. On iOS fiddle is left out, as xord/cruby leaves it out "to pass the App Store review", since it calls any C function by name. win32ole and win32 are Windows' alone. Every other bundled and default gem is as a desktop runtime has it.

## The embedding API

`runtime/mobile/fledge_ruby.h` is the embedding API, in C, compiled into both runtimes with `fledge_ruby.c`, `output.c`, `apple.c` or `android.c`, and the launcher's `locale.c`, `config.c`, and `bundler.c`. Its header comments are the reference for each function.

| Function | What it does |
|---|---|
| `fledge_ruby_forward_output(tag)` | Sends standard output and standard error to the system log (see "Output to the system log"). |
| `fledge_ruby_run(root, script, argc, argv)` | Runs a Ruby file on the calling thread, as `ruby SCRIPT ARGS` would, and returns its status. |
| `fledge_ruby_run_app(root, argc, argv)` | Runs the app `fledge build` put in `root`, as the desktop launcher runs one (ADR 061). |
| `fledge_ruby_add_extension(feature, init)` | Tells Ruby that an extension is linked in (see "Registering extensions"). |

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

## The projects

`fledge build ios [PATH]` and `fledge build android [PATH]` (ADR 060) write `OUT/NAME-ios/` or `OUT/NAME-android/`, named as a desktop's folder is, replacing an earlier one, and print its path. `Fledge::MobileProject` (`lib/fledge/mobile_project.rb`) does what both share:

1. checks the app has an identifier, and that a host folder `fledge.yml` names is a folder in the project;
2. unpacks the phone's runtime, found and checked against the pins as every runtime is (`Fledge::Runtimes`; ADR 014);
3. copies the system's template from `lib/fledge/templates/`;
4. compiles the gems' extensions, when the app has any, and places the runtime and the extensions as the system needs;
5. writes the folder `fledge/`: `fledge.cfg`, the project in `app/` (but the output folder and any host folder), the app's gems in Ruby's gem folder, and the runtime's `notices/`, refusing a file that would replace one of the runtime's Ruby;
6. copies the host's files over the project (see "Host files");
7. fills the template's marks (`@@NAME@@` and the rest) with the app's values;
8. copies the icons, and finishes the project as the system needs.

It writes in a temporary folder inside `OUT` and moves the project into place, and removes what it wrote if the build fails. On the phone, Ruby's root is `fledge/` merged with the runtime's `lib/` and `libexec/`.

Each phone's project is built where its tools run (`Fledge::MobilePlatform::HOSTS`): iOS on `arm64-darwin`; Android on `arm64-darwin`, `x86_64-linux`, and `x64-mingw-ucrt`. `aarch64-linux` is left out, since Google publishes no Android SDK build tools for it. Elsewhere the build says where to build it and exits 1.

Nothing configures signing. `xcodebuild` builds for the Simulator, and for a device with `CODE_SIGNING_ALLOWED=NO`; the developer chooses a team in Xcode to run on a device. `./gradlew assembleDebug` and `bundleDebug` sign with the Android SDK's debug key, and `assembleRelease` and `bundleRelease` leave the app unsigned, for the developer's own key. Fledge holds no key and never submits an app.

## The Xcode project

`Fledge::MobileProject::IOS` writes XcodeGen's `project.yml` from its template (`lib/fledge/templates/ios/project.yml`), and `xcodegen generate` writes `NAME.xcodeproj`, so Fledge writes no Xcode project file. `project.yml` stays, for the developer to change and generate again. XcodeGen is a tool the developer installs; without it the build names it and how to get it (`MobileProject::IOS::INSTALL`).

- `FledgeRuby.xcframework` is linked, not embedded, being a static library, and so is `FledgeExtensions.xcframework` for an app whose gems have extensions.
- The build phase "Copy Ruby and the app" copies the slice's `lib/` and `libexec/` for the SDK the build is for, then `fledge/`, into the bundle's `fledge/` folder with `ditto`, as CPython's "Process Python libraries" copies its slice's standard library. User script sandboxing is off for it (`ENABLE_USER_SCRIPT_SANDBOXING: NO`), as CPython's documentation sets it.
- `Host/` holds `main.m`, the app's `Info.plist`, its privacy manifest, and its asset catalog.
- The target builds for `arm64` alone, the only architecture the runtime has, for iOS 15.0 and later, with `TARGETED_DEVICE_FAMILY` `1,2` for iPhone and iPad.
- The marks are JSON strings, which YAML reads as quoted ones: the name, identifier, version, icon name, and the extensions' linker flags in `OTHER_LDFLAGS` (after `$(inherited)`).

## The Gradle project

`Fledge::MobileProject::Android` writes a Gradle project of one app module (`lib/fledge/templates/android/`):

- **Gradle's wrapper,** the very `gradle-wrapper.jar`, `gradlew`, and `gradlew.bat` that the pinned Gradle writes, pinned to the distribution and SHA-256 Fledge's runtime builds with. `runtime/sources.yml` pins the jar's SHA-256 too, and CI validates it with Gradle's own wrapper-validation action. The Android Gradle plugin is the version the runtime builds with (`MobileProject::Android::AGP`).
- **`libs/FledgeRuby.aar`** is its dependency, and `fledge/` holds the runtime's `lib/` and `libexec/`, since one Ruby serves both ABIs.
- **The task `fledgeAsset`** stores `fledge/` uncompressed as the asset `fledge.zip`, with the Ant that Gradle carries (`ant.zip`), into a folder its task declares as output, which the plugin takes as generated assets on every variant (`addGeneratedSourceDirectory`). The folder must be the task's declared output: Gradle's own `Zip` task writes into a folder that is not one of its outputs, so the plugin never ran it and the asset was missing.
- **`androidResources.noCompress += ['zip']`** keeps `fledge.zip` stored in the APK and in every APK made from the app bundle, and `useLegacyPackaging = false` stores native libraries uncompressed and aligned for 16 KB pages.
- It targets and compiles against API 36, as Google Play requires of new apps and updates, and runs on API 26 and later, as the runtime does.
- Its manifest asks for `android.permission.INTERNET`, since a Ruby program may reach the network on a desktop (decision 20).
- The host's Java package is Fledge's own, `org.setdef.fledge.host`, the plugin's `namespace`, apart from the `applicationId`, so no identifier collides with Java's keywords.
- The marks are written as each file reads them: Groovy's single-quoted strings in the Gradle files, and an escaped Android string resource in `strings.xml`.

## Identity on a phone

The app's identity is `fledge.yml`'s (ADR 008), where each system shows it:

- **identifier:** the bundle identifier on iOS and the `applicationId` on Android. A phone's app has to have one, so a phone's build without it fails, suggesting one. Android takes only parts that begin with a letter and hold letters, digits, and underscores (`MobileProject::Android::APPLICATION_ID`), so an identifier with a hyphen, or a part that begins with a digit, fails for Android with one it would take.
- **name:** `PRODUCT_NAME` and `CFBundleDisplayName` on iOS, and the label on Android.
- **version:** `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION`, its first three numbers (`Fledge::MacBundle.bundle_version`), on iOS. On Android, `versionName` as it is, and `versionCode` made of its first three numbers, three digits each (1.2.3 is 1002003), as Briefcase pads a version's parts, so each later version has a greater code; 0.0.0 gets 1, Android's lowest, and a version whose code would pass Play's 2,100,000,000 is refused (`MobileProject::Android.version_code`). An app with no `version` is 0.0.0 (see "Export compliance and the build number").
- **icon:** the files `fledge.yml`'s `icon` names, as the desktop's are named: `ICON-1024.png` for iOS, the one size an asset catalog's app icon needs, from which Xcode makes the rest, in `Host/Assets.xcassets`; and `ICON-48.png`, `-72`, `-96`, `-144`, and `-192` for Android, each density's launcher icon in `mipmap-mdpi` to `mipmap-xxxhdpi`. Fledge copies them and reads no image (ADR 048). Without an icon, each system shows its own, and the iOS project drops its asset catalog.

## Gems on a phone

No gem publishes a build for a phone, so a phone's app ships each gem's `ruby` build, with Bundler's own `force_ruby_platform` in the app's `.bundle/config` (ADR 057; `Fledge::MobilePlatform#force_ruby_platform?`). A gem that also publishes builds for desktops ships its `ruby` build, and an iOS Ruby, which reports `arm64-darwin`, never resolves a macOS gem. Since the app's Bundler runs with it, the lockfile must lock `ruby`, and a build that finds it unlocked says so, naming `bundle lock --add-platform ruby`. A gem the lockfile locks no `ruby` build of fails as a desktop build fails for a gem with no build for it. A gem with a C or C++ extension is compiled and linked in (see "Gems with extensions"). Gems' licenses stay the developer's business (ADR 007).

## The host app

Each template's host is as small as the embedding API allows, and the developer's to change (`lib/fledge/templates/ios/Host/main.m`; `lib/fledge/templates/android/src/main/java/org/setdef/fledge/host/MainActivity.java`):

- it shows the app's name on one screen: in the one UIKit scene that apps built with the iOS 26 SDK must use, and in one Android `Activity`;
- it sends standard output and standard error to the system log under the identifier;
- it runs the app with `fledge_ruby_run_app` on a thread of its own with a 64 MB stack, as `FledgeRuby.startApp` does on Android, so the interface never waits for Ruby and iOS's watchdog never stops an app whose program runs long;
- it passes no arguments, since a phone has no command line, and logs `NAME exited with status N` when the program ends;
- on Android, it starts Ruby once per process, so an Activity Android creates again does not start it again, and it loads `libfledgeext.so` after `libfledgeruby.so` when the app has extensions.

The app stays open when the program ends: iOS's guidelines and Android's leave quitting to the person. A framework replaces the host with its own files (see "Host files"), keeping the two calls.

## The privacy manifest

`Host/PrivacyInfo.xcprivacy` declares the APIs Apple requires a reason for ("Describing use of required reason API", developer.apple.com) that Fledge's Ruby calls, as `nm -u` lists the imports of a built app's executable:

- `stat`, `fstat`, `fstatat`, `lstat`, `getattrlist`, and `fgetattrlist`, among Apple's file timestamp APIs, with reason C617.1 (files inside the app's container);
- `mach_absolute_time`, among the system boot time APIs, with reason 35F9.1 (time elapsed between events in the app).

It also says that the app tracks no one and collects nothing, which the developer changes for their own app. Ruby calls no disk space API (`statfs`, `statvfs`), so none is declared.

CI checks each built app's imports against its manifest (`MobileParity::IOS#check_privacy`, `tasks/mobile_parity/ios.rb`), so a Ruby that starts calling another such API fails there. The check also compares reasons: each category the manifest declares that Fledge's template gives a reason must still name it. `getattrlist`, `fgetattrlist`, and `getattrlistat` are not in the check's disk space row, though Apple lists them there too, because Ruby's `dir.c` calls them for the filesystem's type and the check matches by function name only.

## Gems with extensions

`Fledge::MobileExtensions` (`lib/fledge/mobile_extensions.rb`) compiles an app's gems' C and C++ extensions for every target of the phone, one after the other (ADR 022): `ios-arm64` and `ios-arm64-simulator` with Xcode on a Mac; `aarch64-linux-android` and `x86_64-linux-android` with the NDK on a Mac or x86-64 Linux. Windows is refused for gems with extensions.

For each target and each gem with an extension, it:

1. unpacks the gem's source afresh into a folder of the target's own, from where Fledge already has it: a server's `.gem` with `Gem::Package#extract_files`, a path gem with `PathPackage#copy_to`, a git gem from its checkout;
2. runs `bin/ruby --disable-gems -I ARCHDIR -r SHIM extconf.rb ARGS` with **this computer's desktop runtime's Ruby**, where ARCHDIR is the folder of the phone runtime's `rbconfig.rb` for the target (iOS: the slice's `lib/ruby/VERSION/arm64-darwin`; Android: `lib/ruby/VERSION/ABI-linux-android`), and ARGS are Bundler's `build.NAME` options for the gem; `rbconfig.rb` finds its prefix from its own path, so mkmf reads the phone Ruby's configuration, `CROSS_COMPILING` included;
3. runs `make static`, which makes `NAME.a`;
4. reads the report the shim wrote: the feature, the archive, and the libraries the `extconf.rb` added.

**The shim** (`MobileExtensions::SHIM`) is loaded before the `extconf.rb`. It puts this computer's tools in place of the ones `rbconfig.rb` records, which are the CI machine's paths: Xcode's `clang` and `clang++` aimed at the recorded `-target` triple and the SDK's sysroot, or on Android the NDK's clang of the very name recorded (`aarch64-linux-android26-clang`), `llvm-ar`, and `llvm-ranlib`. It points `rubyhdrdir` at the runtime's headers, and `LIBRUBYARG` at `libfledgeruby` (`-L SLICE -lfledgeruby -lz ...` on iOS), so mkmf's link tests answer as they would in Ruby's own build: `have_func("rb_str_new", "ruby.h")` links. It sets mkmf's `$static`, as `ext/extmk.rb` does for an extension it links in (line 651 at Ruby 4.0.9), and wraps `create_makefile` to add `-DInit_NAME=Init_fledge_N`, N counting the app's extensions from 0, as `extmk.rb` renames `Init_cparse` to `Init_racc_cparse`, so two gems' extensions cannot clash in one binary.

**The NDK** is the developer's own, found as Gradle's Android plugin and Android Studio find it (`MobileExtensions::NDK.find`): `ANDROID_NDK_ROOT`, then `ANDROID_NDK_HOME`, then the newest in `ndk/` of `ANDROID_HOME`, `ANDROID_SDK_ROOT`, or the SDK Manager's default folder. Fledge downloads no toolchain onto a developer's computer, and says how to install the recommended one with `sdkmanager` when there is none. CI pins the NDK it uses by SHA-256, as the runtime build does.

**RubyGems' marks.** RubyGems and Bundler ignore a gem with extensions unless `gem.build_complete` is in its extension folder (`Gem::BasicSpecification#missing_extensions?`). So `fledge build` writes the empty mark where RubyGems looks (`extensions/PLATFORM/ABI-static/NAME-VERSION`) and where Bundler looks for a git gem (`bundler/gems/extensions/PLATFORM/ABI-static/SCOPE`), with `Gem.extension_api_version`'s `-static` suffix for a Ruby with no shared libruby. A path gem needs no mark, as on a desktop.

## Registering extensions

A statically linked extension is found by `require` when its name is in Ruby's table: `load.c`'s `search_required` finds no file and looks the name, with `.so` appended, up in `vm->static_ext_inits`, and `run_static_ext_init` calls the registered function; `ruby_init_ext(name, init)` fills the table (`load.c`, lines 1126 to 1145, 1200 to 1212, and 1480 to 1498 at Ruby 4.0.9).

`fledge_ruby_add_extension(feature, init)` keeps each registration until Ruby has booted, and `fledge_ruby_run` then calls `ruby_init_ext(feature ".so", init)` for each, after `ruby_options` and before Bundler's setup and the program, when the main namespace exists. A call after Ruby has started returns -1 with `EALREADY`, since the extension would never be registered. `feature` is what the `extconf.rb` gave `create_makefile` (`"adder/adder"`). `require "adder/adder"` and `require "adder/adder.so"` find it; `require_relative "adder/adder"` does not, since it asks for an absolute path, which is not in the table.

Fledge writes the **registration unit**, a C file with a `__attribute__((constructor))` that calls `fledge_ruby_add_extension` for each extension and declares each renamed `Init_fledge_N` (`MobileExtensions.registration_source`). A constructor needs no call from the host, so a framework that replaces Fledge's host keeps its own entry point and the extensions still register.

Ruby's weak `Init_extra_exts` (`ruby.c`, lines 1805 to 1812 at Ruby 4.0.9), "to be replaced with the actual strong symbol by the linker", is not used: on Android the call is inside `libfledgeruby.so`, whose objects are built `-fvisibility=hidden`, so a strong definition in another library is never bound to it.

## Linking extensions on iOS

iOS Ruby has `--disable-dln`, and App Store Review Guideline 2.5.2 leaves an app no code it did not ship, so extensions link into the app's executable. Each slice's archives, with each static library an `extconf.rb` named for that slice, are merged by Apple's `libtool -static` into `libFledgeExtensions.a`, and the two slices are packed by `xcodebuild -create-xcframework -library ... -library ...` into `FledgeExtensions.xcframework`, which `project.yml` links beside `FledgeRuby.xcframework`. The registration unit is `Host/fledge_extensions.c`, compiled with the host, so its constructor and its `Init_fledge_N` references pull the archives in. `OTHER_LDFLAGS` carries the extensions' other libraries and frameworks, and `-lc++` when any extension has C++.

A static library goes with its own slice's archives, not into `OTHER_LDFLAGS`, which every slice shares; otherwise the Simulator's link would take the device's library too. A framework is one flag, `-Wl,-framework,NAME`, the form SDL3's `sdl3.pc` writes, so that merging the flags never splits a name from its `-framework` (`MobileExtensions::Linking.link_flags`).

## Linking extensions on Android

Android carries native code only as shared libraries in the package, so the extensions link into **one more shared library per ABI, `libfledgeext.so`** (`MobileExtensions#shared_library`): the registration unit and the archives, compiled `-fPIC` as the runtime is, against `-lfledgeruby` from the runtime's AAR, with the extensions' flags, `-llog -lm`, `-Wl,-z,max-page-size=16384`, and `-Wl,--exclude-libs,ALL`, then stripped. When an extension has C++ it links with `clang++ -static-libstdc++`, so the NDK's `libc++` is linked in and the package needs no `libc++_shared.so`. It goes to `src/main/jniLibs/ABI/`, where the plugin packs it as `lib/ABI/libfledgeext.so`, stored and aligned. The host loads it after `libfledgeruby.so` (`System.loadLibrary`), and its constructor registers the extensions. The registration unit stays in the project's `extensions/` folder for whoever reads it.

A shared library an extension links (`-lNAME` found as `libNAME.so` in one of the extension's `-L` folders) is copied into `jniLibs/ABI/` beside `libfledgeext.so` (`Linking.carry_shared_libraries`), since Android loads native code only from the libraries the package holds. A name found in none of them is the system's, as `-llog` is.

## CMake toolchain files

An `extconf.rb` may run CMake to build a library before mkmf builds the extension over it (ADR 027). For each target, Fledge writes a toolchain file into its build folder, `toolchains/TARGET.cmake`, and puts its path in `CMAKE_TOOLCHAIN_FILE` in the environment it runs that target's `extconf.rb` in (`MobileExtensions::CMake`). CMake 3.21 and later read that variable when a build folder is new, which it is, since each gem is unpacked afresh for each target. The files never enter the app. Each sets only CMake's own documented variables:

- **An iOS slice** (`CMake.ios`) uses CMake's own iOS support (cmake-toolchains(7), "Cross Compiling for iOS, tvOS, visionOS, or watchOS"): `CMAKE_SYSTEM_NAME` `iOS`; `CMAKE_OSX_SYSROOT`, the slice's SDK as `xcrun --show-sdk-path` gives it, which selects device or Simulator; `CMAKE_OSX_ARCHITECTURES` and `CMAKE_OSX_DEPLOYMENT_TARGET` from the triple the slice's `rbconfig.rb` records; and `CMAKE_C_COMPILER`, `CMAKE_CXX_COMPILER`, `CMAKE_OBJC_COMPILER`, and `CMAKE_OBJCXX_COMPILER`, the very clang and clang++ mkmf is given. The Objective-C compilers serve a library that enables CMake's `OBJC` or `OBJCXX` language; one that compiles `.m` files as C, as SDL3's does, gets the same clang.
- **An Android ABI** (`CMake.android`) sets `ANDROID_ABI` (`arm64-v8a`, `x86_64`) and `ANDROID_PLATFORM` (`android-26`, the API level in the name of the compiler the runtime was built with), then `include()`s the NDK's own `build/cmake/android.toolchain.cmake`, the file Google's documentation and Gradle give CMake. That file reads the two variables, defaults to the static C++ runtime (`c++_static`), and makes code position-independent. Setting them in a file that includes the NDK's, rather than as `-D` options, holds in CMake's `try_compile` projects too, which read the toolchain file again.

With the Makefile and Ninja generators a project handles "target CPU selection and code signing" itself (cmake-toolchains(7)): the architecture is set here, and a static library is not signed. An `extconf.rb` that passes its own `-DCMAKE_TOOLCHAIN_FILE` or `--toolchain` overrides Fledge's, as CMake documents. Fledge's files add no search paths: the NDK's and CMake's iOS platform files decide where `find_package` and `find_library` look.

## The environment kept out

A phone's build runs each `extconf.rb` in an environment with the developer's own toolchain variables removed (`MobileExtensions::FOREIGN`), since they would aim mkmf, make, or CMake at the developer's computer or give them the developer's flags: `CC`, `CXX`, `CPP`, `CFLAGS`, `CXXFLAGS`, `CPPFLAGS`, `LDFLAGS`, `SDKROOT`, `IPHONEOS_DEPLOYMENT_TARGET`, `MACOSX_DEPLOYMENT_TARGET`, `MAKEFLAGS`, `CMAKE_OSX_ARCHITECTURES`, `OBJC`, `OBJCXX`, `OBJCFLAGS`, and `OBJCXXFLAGS`, with the variables a desktop's native build removes (`NativeBuild::SCRUBBED`). The developer's `CMAKE_TOOLCHAIN_FILE` is replaced by the target's. `CMAKE_GENERATOR`, `CMAKE_BUILD_TYPE`, `CMAKE_BUILD_PARALLEL_LEVEL`, and the rest pass through: they choose how CMake builds, not what it builds for, and the gem's `extconf.rb` decides them as on a desktop.

## The C++ runtime rule

An extension whose Makefile lists a C++ source (`.cc`, `.cpp`, `.cxx`, `.C` in mkmf's `ORIG_SRCS`) has C++. So does a C extension whose `extconf.rb` names the C++ runtime (`-lc++` or `-lstdc++`, `Linking::CXX_RUNTIMES`), as a C extension over a C++ library must on a desktop (`Linking.cxx_runtime?`). The name itself is left out of the flags the app links (`Linking.link_flags`), and each phone links its own C++ runtime: `-lc++` once in the iOS app's `OTHER_LDFLAGS`, and `clang++ -static-libstdc++` for Android's `libfledgeext.so`. On Android neither desktop name is right: the NDK's clang links `-lstdc++` as the shared C++ runtime, and its `-lc++` is a linker script for `-lc++_shared`, a library the package does not carry.

## Refusals

`MobileExtensions.problems` refuses, naming the gem, what to do, and the Gemfile's `platforms:` that leaves the gem out of the phone's build:

- an extension the gemspec says something other than an `extconf.rb` builds (a `CMakeLists.txt`, `Rakefile`, `configure`, or `Cargo.toml` in `extensions`), since RubyGems' own builders for those would each need their own cross-compiling, and none makes the static archive and renamed `Init_` function that mkmf's `$static` does; the message says an `extconf.rb` may run CMake;
- a Rust extension (`rb_sys` among its runtime dependencies), which would need `cargo` aimed at each phone's Rust target, a `staticlib`, and rb-sys reading the phone Ruby's `RbConfig`, none of which was tried;
- for Android, a Windows computer.

The build also fails when an `extconf.rb` calls `create_makefile` more than once, since Fledge links one extension for each, and when `make static` makes no archive.

## Host files

`ios: host: DIR` and `android: host: DIR` in `fledge.yml` name a folder of the project's own files for that phone (ADR 025; `Fledge::Config::Phone`). The shape, one mapping for each phone with one key in it, leaves room for a phone's next setting beside `host`.

1. **It copies every file in the folder over the project,** at the same path relative to the folder, once Fledge has written its template, the runtime, the extensions, and `fledge/`, and before Fledge fills its marks and XcodeGen reads `project.yml` (`MobileProject#place_host`). A host file replaces Fledge's at its path, whole, or joins the project. Fledge merges nothing.
2. **Fledge fills its marks in a host's copy of a marked template:** `project.yml` on iOS; `settings.gradle`, `build.gradle`, `src/main/AndroidManifest.xml`, `src/main/res/values/strings.xml`, and `MainActivity.java` on Android. So a copied `project.yml` still takes the app's name, identifier, version, and the extensions' link flags. The templates' paths and marks are part of the public interface (`test/mobile_template_contract_test.rb`; `doc/contributors/design/public-interface.md`).
3. **The host wins.** The build says, in one line on standard error, where progress goes, which of Fledge's files the host replaced: `host/ios replaces Fledge's Host/Info.plist, Host/main.m, project.yml`. Files the host adds go unmentioned.
4. **It refuses a host it cannot copy.** Reading `fledge.yml`, Fledge refuses a `host` that is not text naming a folder in the project, by the rule a program's path follows: relative, with `/` between folders, and no segment empty, `.`, or `..`, naming the file and the phone. Writing the phone's project, it refuses a host that is not a folder, or that a link leads out of the project, before it writes anything.
5. **The folder stays out of the app.** Its files are the project's, not the program's, so the build leaves the folder out of `fledge/app/`.
6. **Each key is its own phone's.** Desktop builds ignore both, `fledge build ios` ignores `android`, and `fledge build android` ignores `ios`. Only that phone's build looks for the folder.

## A host that owns the main loop

Some frameworks start the app and run its main function themselves. SDL3 is the example `examples/sdl_phone` runs: a path gem, `sdl_demo`, whose `extconf.rb` links SDL3 and whose C extension opens a full-screen window and runs a frame loop that calls a Ruby block each frame. Fledge's API is the same for any such framework: the host forwards output and calls `fledge_ruby_run_app` wherever its framework runs the main function, and `fledge_ruby_run_app` runs Ruby on the calling thread.

**SDL3 itself** is built by `examples/sdl_phone/sdl3/build.sh` from SDL's release tarball, pinned by SHA-256, with SDL's own CMake build as SDL documents it, once per target:

- **iOS**, on a Mac: `-DCMAKE_SYSTEM_NAME=iOS`, the SDK, `arm64`, deployment target 15.0, static (`-DSDL_SHARED=OFF -DSDL_STATIC=ON`). A static library links into the app's executable as extensions do, so nothing is embedded; SDL's own `SDL3.xcframework`, which the app would embed, is not needed.
- **Android**, with the NDK: its `android.toolchain.cmake`, `ANDROID_ABI`, and `ANDROID_PLATFORM=26`, shared (`-DSDL_SHARED=ON -DSDL_STATIC=OFF`). It has to be shared: SDL registers its Java methods from `libSDL3.so`'s `JNI_OnLoad`, which `System.loadLibrary("SDL3")` calls, and `--exclude-libs,ALL` in `libfledgeext.so` would hide a static SDL's. The script also copies SDL's Java classes into the example's Android host, where git ignores them.

The gem finds SDL3 through Bundler's build options, as any gem finds a library: `bundle config build.sdl_demo --with-sdl3-builds=OUT`, which Fledge passes to the `extconf.rb` for every target. The `extconf.rb` tells the targets apart by the compiler Fledge gives mkmf, and links what SDL's `sdl3.pc` names. Libraries need no `fledge.yml` key: what an `extconf.rb` links, Fledge links per target and carries into the APK. SDL is Zlib, it is a dependency of the example's gem, and nothing of it goes into a Fledge runtime.

**On iOS, Ruby runs on the main thread, inside `SDL_RunApp`.** SDL's `SDL_RunApp` calls `UIApplicationMain` and, once the scene connects, runs the app's main function on the main thread inside the run loop. SDL's UIKit calls must be on the main thread ("On Apple platforms this is a requirement", SDL's `src/SDL.c`): Ruby on Fledge's own thread fails `SDL_Init`, and with `SDL_SetMainReady` it crashes on a UIKit threading violation. So the example's host (`examples/sdl_phone/host/ios/`) has:

- `Host/main.m`, whose `main` calls `SDL_RunApp(argc, argv, run_ruby, NULL)`, where `run_ruby` calls `fledge_ruby_run_app`; it declares the two SDL functions it calls, so it needs no SDL headers;
- `Host/Info.plist`, naming `SDLUIKitSceneDelegate` as the scene's delegate;
- `project.yml`, with `-Wl,-stack_size,0x4000000` in the project's `OTHER_LDFLAGS`, which asks for a 64 MB main-thread stack in `LC_MAIN`, and `ENABLE_DEBUG_DYLIB = NO`, since ld takes `-stack_size` only for a main executable and Xcode's Debug configuration otherwise links the app's code into `NAME.debug.dylib`; the UI test's target takes no linker flags of the project's, for the same reason.

kivy-ios runs Python under SDL the same way: its template's `main` becomes SDL's main function and runs Python on the main thread. Running Ruby on its own thread and sending each SDL call to the main thread (`SDL_RunOnMainThread`) would make every call the game's Ruby makes cross threads, and the engine, not Fledge, would carry that.

**On Android, an `SDLActivity` runs Ruby on a 64 MB thread.** SDL's Java side has to be the Activity: it makes the surface SDL draws on, and SDL's video calls back into its static methods. The example's host (`examples/sdl_phone/host/android/`) replaces Fledge's `MainActivity` with one of the same name and package, so the manifest needs no change. It extends `SDLActivity`, returns `{"SDL3", "fledgeruby", "fledgeext"}` from `getLibraries()`, SDL first so its `JNI_OnLoad` registers SDL's methods before Ruby's extensions load, and overrides `main()`, which SDL calls on its SDLThread, to run Ruby with `FledgeRuby.startApp` on a thread with a 64 MB stack and wait for it, so the game ends when Ruby does. Overriding `main()` replaces SDL's `nativeRunMain`, which would look for an `SDL_main` the app does not have. SDLThread itself is made with Java's default stack, about 1 MB, too shallow for Ruby. SDL's Java files enter the Gradle project as sources, as SDL's `android-project` holds them; python-for-android's `PythonActivity` extends `SDLActivity` the same way.

The measurements and device runs behind these choices are in `doc/contributors/research/2026-11-10-findings-from-the-adrs.md`. A real iPhone granted the 64 MB main-thread stack `-stack_size` asks for; Apple documents 1 MB for a device's main thread, and an iPad's grant is not measured.

## The Android App Bundle check

Google Play takes an Android App Bundle from a new app, not an APK. The project is a standard application module, so the plugin's `bundleRelease` and `bundleDebug` make one with no change to the template, and three things hold for it:

- **`fledgeAsset` runs for a bundle:** the asset is a generated source of every variant, and the bundle tasks merge the same assets as the APK tasks, so the bundle holds `base/assets/fledge.zip`.
- **`fledge.zip` stays stored:** the plugin writes `noCompress` into the bundle's `BundleConfig.pb`, whose `uncompressedGlob`s (`bundletool dump config`) include `**[zZ][iI][pP]`, so every APK bundletool or Play makes stores the asset.
- **Native libraries stay stored and 16 KB-aligned:** with `useLegacyPackaging = false`, the bundle's config asks for `uncompressNativeLibraries` with `PAGE_ALIGNMENT_16K`, the value Android's page-size guide tells a developer to look for.

`bundleDebug` signs with the SDK's debug key, and `bundleRelease` leaves the bundle unsigned. A developer signs it with their upload key, in a `signingConfigs` block or with `jarsigner`, since `apksigner` signs no bundle, and Play App Signing signs the APKs it serves (`doc/phones.md`, "Google Play"). A Fledge app is all base module: Ruby, its standard library, the app, and its gems are one asset. Play limits a base module to a 500 MB compressed download; an app with hundreds of megabytes of data would move the data into a Play Asset Delivery pack, which Fledge does not build.

CI's `mobile-apps-android` jobs build both bundles of every app beside its APKs (`tasks/mobile_parity/android.rb`). Each release bundle is signed with a throwaway upload key made in the job, verified with `jarsigner -verify`, validated with `bundletool validate`, checked for `PAGE_ALIGNMENT_16K`, and made into an APK set with `bundletool build-apks`, as Play would. Each split APK must pass `zipalign -c -P 16`; every native library and `fledge.zip` in it must be stored, which `zipalign` alone does not check; each of the base module's main APKs must hold `fledge.zip` and target API 36, the lowest from API 26; and the largest download must stay under the limit. Each app then runs a second time on the emulators, installed from its APK set with `bundletool install-apks`, which picks the device's splits as Play does, and must print the same line and exit 0. The `mobile-apps-android-hosts` jobs build `examples/mobile_app`'s release bundle on macOS and Windows and check it the same way. bundletool is pinned by SHA-256 in `runtime/sources.yml` as a tool only CI fetches.

## The App Store archive check

An iOS app reaches the App Store as an archive, which Xcode exports or uploads to App Store Connect. Exporting one for App Store Connect needs an Apple ID of the archive's development team (`man xcodebuild`); validating and uploading (`altool`, Transporter) need App Store Connect credentials. So everything on Apple's servers waits on an account (`doc/contributors/account-tests.md`, IOS-1 to IOS-3), and CI checks what Apple's own tools check without one.

The `mobile-apps-ios` job archives each app's Xcode project with `xcodebuild archive -sdk iphoneos -configuration Release CODE_SIGNING_ALLOWED=NO`, as Product > Archive does with no team, failing on any warning, and checks the archive and the app in it (`tasks/mobile_parity/ios_archive.rb`):

- **The archive:** its `Info.plist` names `Applications/NAME.app` and arm64 only, and it holds `dSYMs/NAME.app.dSYM`, which App Store Connect takes for symbolication.
- **The app's `Info.plist`,** read with `plutil -convert json`, holds the keys Apple's pages say the App Store needs: `CFBundleVersion` and `CFBundleShortVersionString`, `UIRequiredDeviceCapabilities` with `arm64`, the identifier, executable, name, and `APPL` package type, `MinimumOSVersion` 15.0, `UIDeviceFamily` `[1, 2]`, a launch screen, and the `DTXcode`, `DTSDKName`, and `DTPlatformName` keys only a build by Xcode for a device writes. The template writes none of the keys Xcode adds, and the check reads the built file, so a setting that stopped producing one fails it.
- **The executable** is arm64 alone (`lipo -archs`), built for the iOS platform with minimum 15.0 (`vtool -show-build`, so no Simulator slice), holds no bitcode segment (`otool -l`), and loads only `/usr/lib` and `/System/Library` libraries (`otool -L`). No other file in the app is Mach-O, found by its magic number, and there is no `Frameworks`, `PlugIns`, `Watch`, `SC_Info`, `embedded.mobileprovision`, or `_CodeSignature`, since a Fledge app embeds nothing and is unsigned here.
- **`PrivacyInfo.xcprivacy`** is in the app, passes `plutil -lint`, and holds the four keys of Apple's "Privacy manifest files" page; its reasons are checked against the executable's imports (see "The privacy manifest").
- **An app whose `fledge.yml` names an icon** has `CFBundleIconName` `AppIcon`, a 1024 pixel image named `AppIcon` in `Assets.car` (`assetutil --info`), and a source PNG with no alpha channel, read from its header (color type 4 or 6, or a `tRNS` chunk): App Store Connect refuses a large app icon with an alpha channel, even an opaque one (ITMS-90717). An app with no icon gets a note, since App Store Connect needs one and only the developer has one to give.
- **Export compliance and the version** are reported, not failed (see the next section).

## Export compliance and the build number

**Export compliance.** The template writes no `ITSAppUsesNonExemptEncryption`, and the archive check reports whether the key is declared (`IOSArchive.encryption`). App Store Connect's questionnaire is where a developer answers, and the developer adds the key to their host's `Info.plist` afterward (ADR 062). `doc/phones.md`, "Export compliance", says what Apple's pages say, marked as not legal advice.

**A version of 0.0.0.** An app with no `version` is 0.0.0, so its `CFBundleVersion` and `CFBundleShortVersionString` are 0.0.0 and its Android `versionCode` is 1. Apple's reference allows it (`CFBundleVersion` is "one to three period-separated integers ... 0 specifies 0.0.0"), no App Store Connect page read refuses it, and Google Play wants "a positive integer". So `fledge build` does not refuse it: refusing would stop every developer who runs an app on their own phone, for a rule no store states. The archive check notes it (`IOSArchive.version_note`), and `doc/phones.md` tells a developer to set a version before a store. Each store wants a new build number for each upload. If App Store Connect is found to refuse 0.0.0, `fledge build ios` should refuse it, citing that.

## Parity on a phone

The mobile parity check (`tasks/mobile_parity.rb`, in the Mobile apps jobs) runs the parity probe as a phone app, built by `fledge build`, in the iOS Simulator on an iPhone and an iPad and on Android emulators with 4 KB and 16 KB pages, and compares its report with `ruby main.rb` under the runner's desktop Ruby. The report reaches the check through the system log, as an app's output reaches its developer. Every difference must be justified in `Parity::MOBILE_JUSTIFIED` (`tasks/parity.rb`), which says why each is right; `doc/contributors/design/parity.md` describes the check. What the probe cannot show, and an app on a phone should expect:

- the working folder is `/`, as for a macOS app started from the Finder;
- standard input is at its end;
- the app's bundle is read-only on a device (writable in the Simulator), so an app writes under `Dir.home` or `Dir.tmpdir`;
- on iOS under Fledge's host, Ruby's thread has 64 MB; under a host that runs Ruby on the main thread, the main thread's stack is what the system grants;
- no program can run: iOS lets no app run one, and Android lets no app run a file of its own (W^X, from target API 29), so `RbConfig.ruby` names where `bin/ruby` would be, and starting it fails with ENOENT; Apple's sandbox denies `fork` on a device, though the Simulator allows it;
- the system may stop an app in the background without running `at_exit`.

## Licenses of a phone runtime

Each phone runtime passes the license audit before it is archived (ADR 004; `doc/contributors/design/license-audit.md`), and ships only what decision 8 allows, with no LGPL library. Its components are recorded in `runtime/licenses.yml`: Ruby, OpenSSL, libyaml, libffi on Android, the NDK's compiler-rt builtins and libunwind on Android (`compiler-rt-ndk`), Mozilla's CA certificates as a file, and Fledge's own embedding API (`fledge-embedding`, MIT). GMP is configured out, iOS's `crypt` is its libSystem's, and Android's `String#crypt` is Ruby's own `missing/crypt.c`, so neither runtime carries libxcrypt.

Two things in the audit exist for phones. An iOS runtime has a Ruby per slice, so a platform's map entry names several prefixes (`runtime/licenses.yml`, `prefixes`), and each gem in them is one component. An AAR is a zip whose entries the app ships, so the audit reads each entry with `unzip`, as `FledgeRuby.aar!ENTRY`, and a copyleft library's code in one fails as it would in a file. The audit's readers for the Android runtime are the NDK's own LLVM tools (`RuntimeBuilder::Android#readers`).

The templates and the embedding API are Fledge's own code, MIT, and the host's compiled code ships in every phone app, which `doc/licensing.md` says. Gradle's wrapper, which no app holds, is Gradle's, under Apache-2.0.

## What a framework provides

A framework that ships to an iPhone, an iPad, or an Android device through Fledge may rely on what follows from a Fledge release; it is part of Fledge's public interface (`doc/contributors/design/public-interface.md`), and changes only as that document says.

**Fledge provides:**

- `fledge build ios`, on a Mac with Xcode and XcodeGen, and `fledge build android`, on a Mac, x86-64 Linux, or Windows, which write an Xcode or Gradle project holding the project, its gems, and a runtime. The framework's team builds, signs, and submits that project with Xcode or Gradle.
- A gem with a C or C++ extension built by an `extconf.rb` is compiled for each of the phone's targets, linked into the app, and registered, so `require "name/name"` finds it. Static libraries an `extconf.rb` links are linked per iOS slice; shared ones are carried into the Android app.
- An `extconf.rb` that runs CMake finds each target's toolchain file in `CMAKE_TOOLCHAIN_FILE`.
- `ios: host: DIR` and `android: host: DIR` in `fledge.yml` name a folder of files that `fledge build` copies over the project it writes, so a framework that must own the app's startup supplies its own files and keeps them across builds (see "Host files"). The templates' file paths and marks stay, so a host's copy keeps working.
- The embedding API, `fledge_ruby_forward_output` and `fledge_ruby_run_app` (and on Android `FledgeRuby.startApp`), which a framework's host calls wherever its framework runs the main function.

**The framework provides:**

- A Ruby program that starts the app, and the gems it needs in the project's `Gemfile.lock`, locked for `ruby` (`bundle lock --add-platform ruby`). A phone runs no shell script, and the gems must be in the lockfile, not found on the build computer's paths.
- An extension that an `extconf.rb` builds with mkmf, calling `create_makefile` once, in C or C++, loaded with `require "name/name"` or `require "name/name.so"`, never `require_relative`, with its Init function named `Init_NAME` for the target's basename, as mkmf expects (Fledge renames it). The `extconf.rb` requires nothing but Ruby's standard library, since it runs with `--disable-gems`.
- No `dlopen` of a file it ships, no code that writes executable files, and no `fork` or `exec`.
- When the `extconf.rb` runs CMake first: run `cmake` with a new build folder each time, inside the folder the `extconf.rb` runs in, and let CMake find its toolchain in `CMAKE_TOOLCHAIN_FILE`; pass no `CMAKE_SYSTEM_NAME`, sysroot, or compiler of its own, but `CMAKE_BUILD_TYPE` and the project's options as on a desktop; link what CMake built through `$LOCAL_LIBS` by path; build static libraries position-independent (`POSITION_INDEPENDENT_CODE ON`); name the C++ runtime as on a desktop (`-lc++` or `-lstdc++`) when the extension is C over C++, and Fledge links the phone's; and have CMake 3.21 or later on the build computer's `PATH`.
- Its native libraries, built for the phone's targets: a static library per iOS slice (or an XCFramework), and a shared library per Android ABI, found by the `extconf.rb` through `dir_config` or Bundler's `build.NAME` options (`bundle config build.NAME --with-NAME-dir=...`), which Fledge passes as `extconf.rb` arguments for every target.
- Its host files, when its framework owns startup, in the `host:` folder: on iOS any of `Host/main.m`, `Host/Info.plist`, `Host/PrivacyInfo.xcprivacy`, the asset catalog, and `project.yml`; on Android `MainActivity.java` at its package's path, the manifest, the Gradle files, `strings.xml`, and any Java sources of its own.

Fledge refuses, naming the gem, an extension that the gemspec says Rake, CMake, configure, or Cargo builds with no `extconf.rb`, and a Rust extension.

**Known limits:**

- CI runs the apps in the iOS Simulator and on x86_64 Android emulators. It builds and checks the iOS device slice and the arm64-v8a library, but runs neither: no free GitHub-hosted runner boots an arm64-v8a emulator. Games built with `fledge build` have run on a physical iPad Pro, iPhone 13 mini, and OnePlus Nord N30 5G (arm64-v8a).
- An SDL host on iOS runs Ruby on the main thread and asks for a 64 MB main-thread stack in the project's linker flags. Apple documents 1 MB for a device's main thread. An iPhone 13 mini granted the 64 MB; an iPad's grant is not measured, so a deep recursion in Ruby could still fail there.
