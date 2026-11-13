<!--
SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>

SPDX-License-Identifier: CC-BY-SA-4.0
-->

> Findings of 2026-11-13 on whether a phone's Ruby could load each C extension from a file, as a desktop's does. Requested: written by an agent and not reviewed line by line. It changes no code and no ADR; the orchestrator decides and writes any ADR.

# Phone Extensions as Files

On a phone, Fledge compiles every C extension into a static archive, links it into the app, and registers it with Ruby (ADRs 022, 058, 068, 079, 080). Three differences from `ruby main.rb` follow. `$LOADED_FEATURES` holds a linked extension's feature, `json/ext/parser.so`, where a desktop holds the file it loaded (`doc/contributors/research/2026-11-12-phone-parity-audit.md`, row 12). `RbConfig::CONFIG["archdir"]` names a folder with no extensions in it (row 42). A path that names an extension's `.so` or `.bundle` fails, which ADR 080's stub `.rb` files leave open (ADR 080, line 48).

Every one of those ADRs rests on one sentence: "A phone's Ruby loads no extension from a file" (ADR 058, line 18; ADR 022, line 20). These findings check that sentence against Apple's, Google's, and AOSP's own text, read what CPython, BeeWare's Briefcase, Chaquopy, python-for-android, kivy-ios, Flutter, and React Native do, and weigh what loading extensions from files would cost Fledge and what it would close.

## Verdict

The sentence describes Fledge's build, not the phones.

- **iOS** lets an app load a dynamic library that sits in a framework in the app's `Frameworks` folder, and forbids only a loose one. CPython's official iOS build loads every binary module that way, and Briefcase apps ship it. Fledge's iOS Ruby cannot load a file because Fledge configures it with `--disable-dln`, after xord/cruby.
- **Android** lets an app `dlopen` a library from its own data folder. It forbids only `execve` of a file there. CPython's official Android build, Chaquopy, and python-for-android all load extension modules from the app's files.

So the linked-in design is a choice, and a difference that follows from a choice is one the maintainer calls a bug to fix (`decisions.md`, 2026-11-12: "Every difference, every lack of parity, is a knife in Fledge's back"). Extensions as files would close rows 12 and 42 and the rest of ADR 080's gap. They would also delete most of the machinery of ADRs 058, 067, 068, and 080. On Android the cost is medium. On iOS it is large: Ruby itself becomes a dynamic framework, each extension becomes a signed framework, and whether the App Store takes the result needs a developer account to prove.

The recommendation, at the end, is to load extensions from files on both phones: Android first, then iOS once a spike proves it on a device and through App Store Connect.

## What was read

Every page below was read on 2026-11-13.

- **Ruby** 4.1.0-preview1, the pinned tarball (SHA-256 `fb530bb8...b88ef`, as `runtime/sources.yml` line 343 pins it): `configure.ac`, `dln.c`, `dmydln.c`, `load.c`, `box.c`.
- **Apple:** "Placing content in a bundle", "Reducing your app's launch time", and "Configuring your project to use mergeable libraries" (developer.apple.com/documentation, read as the JSON their pages render from); App Review Guidelines (developer.apple.com/app-store/review/guidelines, "Last Updated: October 16, 2026"); Xcode 27.2's linker on this Mac.
- **Google:** "Behavior changes: apps targeting Android 10" and "... Android 14"; "Support 16 KB page sizes"; Google Play's "Device and Network Abuse" policy (support.google.com/googleplay/android-developer/answer/9888379).
- **AOSP** at `refs/heads/main`: `frameworks/base` `libs/androidfw/ApkParsing.cpp`, `core/jni/com_android_internal_content_NativeLibraryHelper.cpp`, and `core/java/android/app/LoadedApk.java`; `system/sepolicy` `private/untrusted_app_all.te` and `private/app_neverallows.te`; bionic's `android-changes-for-ndk-developers.md`.
- **CPython** v3.14.0 (commit ebf955df7a): `Lib/importlib/_bootstrap_external.py`, `configure.ac`, `Apple/testbed/Python.xcframework/build/utils.sh` and its `iOS-dylib-Info-template.plist`, `Android/testbed/app/build.gradle.kts`, `Doc/using/ios.rst`; PEP 730 (last modified 2025-02-01) and PEP 738 (last modified 2024-10-07); docs.python.org's "Using Python on Android".
- **Briefcase:** briefcase-iOS-Xcode-template at b3133d32b3 and briefcase-android-gradle-template at 06e840f96e.
- **Chaquopy** at 502ad46fe8; **python-for-android** at 1c9a4b4f81; **kivy-ios** at fd363d49ed.
- **Flutter** at bd400446b7 (main): `packages/flutter_tools/lib/src/isolated/native_assets/ios/native_assets.dart`, `android/native_assets.dart`, `macos/native_assets_host.dart`.
- **React Native:** "React Native 0.76" (reactnative.dev/blog/2024/10/23/release-0.76-new-architecture).

No app ran on a device, Simulator, or emulator for these findings. Two things were measured on this Mac: what Xcode 27.2's linker says about iOS links, and how `codesign` treats a link inside an app bundle.

## Is it true that a phone's Ruby loads no extension from a file?

### iOS

Apple's "Placing content in a bundle" lists the place for a "framework, dynamic library" on "iOS, tvOS, visionOS" as `Frameworks/`, and says: "iOS, watchOS, and tvOS support third-party frameworks but don't support third-party standalone dynamic libraries, which are those outside a framework bundle, typically with the `.dylib` filename extension." A framework's binary is a dynamic library, and `dlopen` is a public function of the iPhoneOS SDK (`doc/contributors/research/2026-11-12-ffi-and-fiddle-on-phones.md`, claim 3).

App Review Guideline 2.5.2 says apps "may not download, install, or execute code which introduces or changes features or functionality of the app". A framework the app ships in its bundle is not downloaded. No guideline names extensions, plug-ins of an interpreter, or `dlopen`.

PEP 730 says the same, from experience: "iOS apps can use dynamically loaded libraries; however, there are very strict requirements on how dynamically loaded content is packaged" (lines 87 to 92 of the page's text). They must be dynamic libraries, "not shared objects or binary bundles", in a framework, one library per framework, in the app's `Frameworks` folder, with no other content.

So iOS forbids a loose library, which is what a desktop Ruby's `json/ext/parser.bundle` is. It does not forbid loading one. Fledge's iOS Ruby cannot load any file because Fledge passes `--disable-dln` (`tasks/runtime_builder/ios.rb`, line 93), which swaps `dln.o` for `dmydln.o` (`configure.ac`, lines 4136 to 4139). `dmydln.c`'s `dln_load` only raises "this executable file can't load extension libraries" (lines 6 to 13). The flag came from xord/cruby's recipe (`doc/contributors/research/2026-10-27-mobile-spike.md`, line 132). The spike itself noted the other way: "iOS may dlopen a signed framework embedded in the app. That is how CPython's iOS support (PEP 730) ships binary modules" (lines 419 to 422).

### Android

Android 10 forbids running a written file, not loading one. "Untrusted apps that target Android 10 cannot invoke `execve()` directly on files within the app's home directory" ("Behavior changes: apps targeting Android 10", "Removed execute permission for app home directory"). The same section says "Apps should load only the binary code that's embedded within an app's APK file", a recommendation, and forbids only text relocations in what `dlopen` maps.

AOSP's policy draws the same line:

- `private/app_neverallows.te`, lines 64 to 73, forbids `execute_no_trans` (that is, `execve`) on `app_data_file` for apps that target API 29 and later.
- `private/untrusted_app_all.te`, lines 24 to 28, allows `execute` (mapping a file as code, which `dlopen` does) on `app_data_file`: "Some apps ship with shared libraries and binaries that they write out to their sandbox directory and then execute." Line 28 audits each such load.
- `private/app_neverallows.te`, lines 75 to 81, shows where Google would like to go: "execute cannot be blocked on all of app_data_file without causing backwards compatibility issues (see b/237289679)". For now it blocks `execute` only on a new kind of storage area, behind a flag.
- `LoadedApk.java`, lines 925 to 935, gives an app's linker namespace its data folder as a permitted path, and notes that for an app not bundled with the system "entire /data is already set to the permitted paths".

PEP 738 says it plainly: "Unlike iOS, Android allows dynamic libraries to be loaded from any location, so a directory tree containing co-located .py, .pyc and .so files can be handled by Python's standard importer" (line 109 of the page's text). Android 14's rule that "all dynamically-loaded files must be marked as read-only" names DEX, JAR, and APK files, and its examples are Java class loaders ("Behavior changes: apps targeting Android 14", "Safer dynamic code loading"). Google Play forbids downloading ".so files from a source other than Google Play" ("Device and Network Abuse", line 48 of the page's text), which a library inside the app's own package is not.

The installer extracts only a package's `lib/ABI/lib*.so` entries, with no subfolders: `ValidLibraryPathLastSlash` (`ApkParsing.cpp`, lines 36 to 84) refuses an entry unless the next slash after `lib/` is its last and, for an app that is not debuggable, its name starts with `lib` and ends with `.so`. That limits where the installer puts a library, not where an app may load one from.

## What the prior art does

| Tool | iOS | Android |
|---|---|---|
| CPython (official) | A framework per binary module, loaded by `dlopen`, with a `.fwork` file where the `.so` was | `.so` files in the standard library's tree, extracted from the app's assets and loaded from the app's files |
| Briefcase | CPython's way, through CPython's own script | Chaquopy |
| Chaquopy | none | `.so` files extracted from the app's assets when imported, then loaded |
| python-for-android | none | `.so` files in a tar packed as `libpybundle.so`, extracted into the app's files and loaded |
| kivy-ios | Linked in: an empty file where each `.so` was, and the loader looks the init function up in the executable | none |
| Flutter (native assets) | A framework per dynamic library | A `.so` per library in `jniLibs` |
| React Native | Static libraries, or frameworks through CocoaPods | `.so` files in `jniLibs`; 0.76 merged most into one |

**CPython.** On iOS, configure refuses to build without `--enable-framework` (`configure.ac`, lines 570 and 680), so libpython is `Python.framework`, a dynamic library, and binary modules link against it: `LDSHARED='$(CC) -dynamiclib -F . -framework $(PYTHONFRAMEWORK)'` (lines 3472 to 3475). PEP 730 explains why: linking a module to a static libpython needs `-undefined dynamic_lookup`, which "raises a deprecation warning" on iOS, so "a static libpython3.x.a iOS library will not be supported" (lines 94 and 130 of the page's text). The Xcode build phase `install_dylib` (`Apple/testbed/Python.xcframework/build/utils.sh`, lines 63 to 112) moves each `.so` to `Frameworks/FULL.MODULE.NAME.framework/FULL.MODULE.NAME`, writes an `Info.plist` from a template, writes a `.fwork` file holding the framework's path where the `.so` was and a `.origin` file in the framework pointing back, copies the module's `.xcprivacy` into the framework, and signs it with `codesign` (line 111). `AppleFrameworkLoader` (`Lib/importlib/_bootstrap_external.py`, lines 1464 to 1502) reads the `.fwork` file, loads the framework's binary, and sets the module's `__file__` to the `.fwork` path, so a module's file is where a desktop's would be. `Doc/using/ios.rst`, lines 72 to 115, documents it.

On Android, the testbed copies `libpython*.*.so` and the external libraries into `jniLibs` (`Android/testbed/app/build.gradle.kts`, lines 234 to 242), and the whole of `prefix/lib/python3.x`, `lib-dynload`'s `.so` files included, into the assets (lines 186 to 220), which `MainActivity.kt` extracts into the app's files (lines 43 to 79). Python then imports binary modules from there with its ordinary importer. PEP 738 adds that "Android does not implicitly use a dlopened library to resolve relocations in subsequently-loaded libraries, even if RTLD_GLOBAL is used", so every module links against `libpython3.x.so` (line 106).

**Briefcase.** The iOS template's build phase sources CPython's `utils.sh` and calls its `install_python` (`{{ cookiecutter.format }}/{{ cookiecutter.formal_name }}.xcodeproj/project.pbxproj`, line 214). The Android template applies Chaquopy's Gradle plugin (`app/build.gradle`, line 2).

**Chaquopy.** `ExtensionAssetLoader.create_module` extracts a module's `.so` from the app's asset zip when it is imported, loads the libraries it needs, and hands it to Python's own `ExtensionFileLoader` (`product/runtime/src/main/python/java/android/importer.py`, lines 729 to 733). Its comment on lines 741 to 756 records how bionic's `RTLD_GLOBAL` differs from Linux's.

**python-for-android.** The build copies every compiled module into the bundle's `modules` folder (`pythonforandroid/recipes/python3/__init__.py`, lines 440 to 449), packs the bundle as a tar named `libpybundle.so` in each ABI's `libs` folder (`pythonforandroid/bootstraps/common/build/build.py`, lines 382 to 390), so that the installer extracts it, and the app untars it into its files on first run (`PythonUtil.java`, lines 204 to 244).

**kivy-ios.** The one tool that links modules in. Its `liblink` stands in for the linker of a shared module: it collects the objects, writes an empty file at the path the build asked for, and links the objects into one relocatable object (`kivy_ios/tools/liblink`, lines 73 to 110). Its patch to `Python/dynload_shlib.c` skips `dlopen` and looks the module's init function up in the running program, `dlsym(RTLD_SELF, funcname)` (`kivy_ios/recipes/python3/dynload_shlib.patch`, lines 8 to 14; applied by `recipes/python3/__init__.py`, line 31). Python's importer finds a module's file before it calls that loader, so the empty file stands where the module was. Whether every empty file reaches the app was not checked.

**Flutter.** For Dart's native assets, `copyNativeCodeAssetsIOS` puts each dynamic library in a framework of its own, sets its install name to `@rpath/...`, writes an `Info.plist` with the minimum iOS version, makes a dSYM, and signs it (`ios/native_assets.dart`, lines 51 to 129; `frameworkInstallName`, `macos/native_assets_host.dart`, line 316). On Android it copies each library into `jniLibs/lib/ABI/` (`android/native_assets.dart`, lines 26 to 46).

**React Native.** 0.76 "merged a lot of our native code into a single library called libreactnative.so", which cut an Android app by "~3.8MB (20% of the total)" and median startup by "~15ms (~8%)" ("React Native 0.76", "Android Apps are ~3.8Mb smaller thanks to Native Library merging"). Those are libraries loaded when the app starts; it is the one measurement found of what many shared libraries cost.

So among Python's tools only kivy-ios links modules in, and every official or maintained tool loads them from files on Android. On iOS, CPython, Briefcase, and Flutter wrap each library in its own framework.

## What it would take in Fledge

### Android

1. **Ruby as a shared library.** Configure Ruby with `--enable-shared`, named so that the package carries it as `libfledgeruby.so`, and without `--with-static-linked-ext`, so that Ruby's build makes each extension a `.so` file under `archdir`, as a desktop's does. Each extension links against `libfledgeruby.so`, as PEP 738 requires of Python's (line 106), and each is linked with `-z max-page-size=16384`, the flag Fledge already passes for its own libraries.
2. **Where the files live.** Two places work:
   - **In the Ruby tree**, inside `fledge.zip`, at the paths a desktop has, extracted with the rest of Ruby into the app's files (`FledgeRuby.java`, lines 64 to 73). This is what CPython, Chaquopy, and python-for-android do. It needs no renaming and no links, and it works whether or not the native libraries are compressed. It leans on the policy line Google says it keeps for compatibility (`app_neverallows.te`, lines 75 to 81), and goes against the "should" of Android 10's page.
   - **In the native library folder**, flattened to `lib*.so` names the installer extracts (`ApkParsing.cpp`, lines 64 to 74), with a link from each desktop path made at boot, as ADR 083 links `bin/ruby`. The installer writes these files and the app cannot change them, which is what Google recommends. It needs a name scheme, a link per extension each time the folder moves, and `useLegacyPackaging = true` always: with stored libraries there is no file to link to, so every extension, `json`'s included, would fail, where today that setting only loses `RbConfig.ruby` (ADR 082).
3. **What goes away.** `libfledgeext.so`, the registration unit, the `Init_fledge_N` renaming, and the ruby program's loading of `libfledgeext.so` (`phone-runtimes.md`, "The ruby program on Android"). Ruby's `dln.c` loads each extension with `dlopen` and calls its `Init_` function by its own name (lines 482 to 535).
4. **16 KB pages.** Each extension's LOAD segments must be aligned to 16 KB, which the build checks today for `libfledgeext.so` (`phone-projects.md`, "The Android App Bundle check"). A library in `fledge.zip` is extracted, so its alignment inside the zip does not matter; but Play's own check of an app's libraries may not look inside an asset, so Fledge's check would carry that alone. CI already runs on 16 KB emulators (ADR 079, Confirmation).

### iOS

1. **Ruby as a dynamic framework.** An extension linked to a static Ruby needs `-undefined dynamic_lookup`, and Xcode 27.2's linker warns for it: linking a one-function library with `xcrun --sdk iphoneos clang -target arm64-apple-ios15.0 -dynamiclib -undefined dynamic_lookup` printed "ld: warning: -undefined dynamic_lookup is deprecated on iOS", and `-flat_namespace` drew "-flat_namespace is deprecated on iOS". The App Store archive check fails on any warning (`phone-projects.md`, "The App Store archive check"). So, as CPython did, Ruby becomes `FledgeRuby.framework`, a dynamic library the app embeds and signs, and every extension links against it with `-dynamiclib -framework FledgeRuby`, not with Ruby's Darwin default of `-bundle` (PEP 730: "not shared objects or binary bundles"). This reverses the static half of ADR 079 on iOS. It also removes one of ADR 079's costs: a dynamic library can keep OpenSSL's symbols to itself, which a static one cannot (ADR 079, line 49).
2. **dln.** Drop `--disable-dln`, so `dln.c` loads extensions with `dlopen` (lines 362 to 381) and `dlsym` (lines 419 to 426).
3. **One framework per extension.** Each `.bundle` becomes `Frameworks/NAME.framework/NAME` with an `Info.plist` naming its executable, identifier, and minimum iOS version, as CPython's template (`iOS-dylib-Info-template.plist`) and Flutter's `createInfoPlist` write one, and is signed. CPython signs in its build phase; Flutter signs in its tool. Xcode's own "Embed Frameworks" phase could sign them if each were an XCFramework the project embeds without linking; that was not tried.
4. **How `require` finds one.** Ruby looks for `json/ext/parser.bundle` on `$LOAD_PATH` and loads the path it finds (`load.c`, `search_required`, lines 1179 to 1190; `load_ext`, lines 1253 to 1262). Two ways put the framework there:
   - **A link** at the desktop path, `fledge/lib/ruby/4.1.0/arm64-darwin/json/ext/parser.bundle`, to `../../../../../../../Frameworks/json.ext.parser.framework/json.ext.parser`. Ruby needs no edit, and `$LOADED_FEATURES` records the link's path (`load.c` keeps the path it found, line 1410, and resolves real paths only to find a second load of the same file, lines 1396 to 1397). On this Mac, `codesign --verify --deep --strict` passed an ad-hoc signed app bundle holding such a link. Whether App Store Connect accepts a link to a binary outside `Frameworks` is unknown, and only an upload can show it (`doc/contributors/account-tests.md`, IOS-1 to IOS-3).
   - **A marker file**, as CPython's `.fwork`, with a scripted edit to `dln.c` that reads the framework's path from a file that is not Mach-O. One more edit of Ruby's source, and the same `$LOADED_FEATURES` as the link.
5. **Names.** A framework's name must be unique in `Frameworks`. CPython uses the module's dotted path. Ruby can hold a default gem's extension and a newer locked copy of the same gem, two `json/ext/parser`s, so an app gem's framework would carry its gem's name too. Whether today's linked design handles an app that locks a newer default gem with an extension was not checked.
6. **The checks.** `tasks/mobile_parity/ios_archive.rb` fails an app with a `Frameworks` folder or any Mach-O file besides its executable (lines 261 to 269); it would check each framework instead, and the privacy manifest check, which reads the executable's imports, would read every framework's. CPython copies a module's `.xcprivacy` into its framework (`utils.sh`, lines 100 to 108). Each framework needs its dSYM for App Store Connect, as Flutter makes one (`ios/native_assets.dart`, lines 92 to 98).
7. **Mergeable libraries do not help.** Xcode 15's mergeable libraries make launch "similar to static linking", but a merged library's embedded copy holds no binary ("Xcode does not include the binaries from the libraries in the embedded copy", "Configuring your project to use mergeable libraries"), so an extension that links `FledgeRuby.framework` by its install name would find nothing to load.

### Size and startup

- **iOS, per framework.** A one-function iOS dynamic library linked by Xcode 27.2 is 65,752 bytes, nearly all of it padding: four segments rounded to 16 KB pages. It compresses to 1,181 bytes, so the download barely grows and the installed size does. As a measure of the whole: the macOS Ruby 4.1.0-preview1 that mise built on this Mac (not Fledge's runtime) has 180 `.bundle` files in its library, 14.1 MB; 122 are encodings and transcoders, 6.6 MB; 142 of the 180 are under 70 KB. So the standard library as frameworks would add on the order of 10 MB installed, and 180 or more frameworks to sign at each build. Decision 20 sets the weight: "Tiny filesize is not a priority".
- **Encodings.** Ruby can keep encodings linked while every other extension is a file: `--with-static-linked-ext=enc` (`configure.ac`, lines 3141 to 3147). That cuts the frameworks to about 60 for the standard library, and leaves `enc/encdb` and `enc/trans/transdb`, which a desktop records as files at boot, recorded as features.
- **Launch.** Apple: "Each additional third-party framework that your app loads adds to the launch time" ("Reducing your app's launch time", "Reduce dependencies on external frameworks and dynamic libraries"). An extension loads when it is required, not at launch, so launch gains one framework, `FledgeRuby.framework`, which PEP 730 counts as "a very slightly reduced app startup time" for static linking (line 193). Each `require` of an extension pays a `dlopen`, as on a desktop. Nothing was measured on a phone.
- **Android.** No measurement. React Native's 3.8 MB and 15 ms came from libraries loaded at startup; Fledge's would load at `require`.

### ADR 067's symbol isolation

ADR 067 makes every symbol of a bundled gem's linked extension local but its `Init_` function, so that prism's libprism and libruby's do not collide, with `cc -r`, Apple's `nmedit`, the NDK's `llvm-objcopy`, and `-fno-common`. Loaded from a file, each extension is an image of its own, as on a desktop: prism's `extconf.rb` hides libprism with `-fvisibility=hidden` (ADR 067, line 20), and `dln.c` looks `Init_prism` up in the extension's own handle (line 425), where libruby's `Init_prism` does not meet it. The relocation step, the `-DInit_NAME=Init_fledge_N` renaming, and the build failure for two extensions with one `Init_` name would go; so would the limit on two Rust extensions, which today each carry Rust's standard library into one link (`phone-projects.md`, "Rust extensions"). What stays is what a desktop has: on Android `dln.c` opens with `RTLD_GLOBAL` (line 376), as on Linux.

### What stays different

- **Ruby::Box** loads an extension into a box by copying it to a temporary folder first (`load.c`, lines 1258 to 1259; `rb_box_local_extension` and `copy_ext_file`, `box.c`, lines 877 to 892 and 699). On iOS a copy outside the bundle is not part of the signed app. Box is experimental and off by default; it was not tried.
- **Encodings,** if they stay linked (above).
- **Android's native library setting,** if extensions live in the native library folder (above).

## What it would close

| Difference or cost today | Where it is recorded | With files |
|---|---|---|
| `$LOADED_FEATURES` holds features, not files | Parity audit row 12; `Parity::MOBILE_JUSTIFIED` (`tasks/parity/mobile.rb`, lines 61 to 65) | Closed; encodings stay features if linked |
| `archdir` holds no extensions | Audit row 42; `RubySpec::JUSTIFIED` (`tasks/ruby_spec.rb`, lines 136 to 143); `doc/phones.md`, line 132 | Closed |
| A path naming `name.so` or `name.bundle` fails | ADR 080, line 48 | Closed |
| `require_relative` of an extension, and `require "racc/cparse"` before racc is active | ADR 080's stub files | Closed by the files themselves; the stubs go |
| The `load_c` gate on linked gems' extensions | ADR 068 | Goes: RubyGems puts a gem's extension folder on `$LOAD_PATH` as it activates the gem |
| Bundled gems' extensions copied among Ruby's own, with marks | ADR 058 | Mostly goes: Ruby's build makes them as a desktop's does, though the cross-build trick of `phone-runtimes.md`, "Building Ruby for a phone", step 3, stays |
| Each extension relocated and stripped of globals | ADR 067 | Goes |
| `Init_fledge_N` renaming, the registration unit, `libfledgeext.so`, `FledgeExtensions.xcframework` | ADR 022; `phone-projects.md`, "Registering extensions" | Goes; `fledge_ruby_add_extension` stays for a host's own linked code |
| A Rakefile's extensions get no stub; a Rakefile's other shared libraries are refused | ADR 080, line 48; ADR 072; `phone-projects.md`, "Rakefiles", step 5 | Its `.so` files ship where RubyGems installs them; an ffi library still needs framework wrapping on iOS |
| Two Rust extensions in one app untried; two cannot share a name | `doc/phones.md`, line 22 | Each is its own library, as on a desktop |
| An iOS app's own OpenSSL clashes with the runtime's | ADR 079, line 49 | Closed by a dynamic `FledgeRuby.framework` |

## Lines these findings make untrue

These lines say a phone forbids loading a file. Each proposed text holds whatever the orchestrator decides.

- **ADR 022, line 20:** "A phone's Ruby loads no extension from a file. iOS forbids it, so its Ruby is built with `--disable-dln`. Android runs native code only from the libraries its package carries (`lib/ABI/libNAME.so`), not from files an app writes." Proposed: "Fledge links every extension into a phone app. iOS loads a library only from a framework in the app's `Frameworks` folder, and Fledge builds its iOS Ruby with `--disable-dln`, after xord/cruby; Android loads one from the app's files too, and runs a program only from what its installer extracts (`doc/contributors/research/2026-11-13-phone-extensions-as-files.md`)."
- **ADR 022, line 39:** "`dlopen` works on Android but not on iOS". Proposed: "`dlopen` on iOS works only for a framework in the app's `Frameworks` folder, which needs Ruby itself as a dynamic framework".
- **ADR 058, line 18:** "A phone's Ruby loads no extension from a file, so every extension is linked in (ADR 079)." Proposed: "Fledge links every extension into a phone app (ADR 022)."
- **ADR 073, line 40:** "since iOS loads no library from a file". Proposed: "since iOS loads a library only from a framework, which ADR 022's static design does not make".
- **ADR 072, line 41,** rejects option 4 because it "reverses ADR 022's static design and the iOS runtime's `--disable-dln`". True, but it is the only reason given; these findings are the weighing it lacked.
- **`doc/contributors/design/phone-projects.md`, line 129:** "since a phone app opens no library at run time". This is already untrue: ffi and fiddle open libraries on both phones (ADR 074). Proposed: "since Fledge links every extension in and wraps no other library for a phone".
- **`phone-projects.md`, line 145:** "iOS Ruby has `--disable-dln`, and App Store Review Guideline 2.5.2 leaves an app no code it did not ship, so extensions link into the app's executable." Guideline 2.5.2 forbids downloaded code, not a shipped framework. Proposed: "iOS Ruby has `--disable-dln` (ADR 022), so extensions link into the app's executable."
- **`phone-projects.md`, line 151:** "Android carries native code only as shared libraries in the package". Proposed: "Fledge carries an Android app's extensions as one more shared library in the package".
- **`tasks/parity/mobile.rb`, line 63,** the reason "since iOS loads no code from files", and **`tasks/ruby_spec.rb`, lines 141 and 142,** "where Android and iOS load native code from": both name a platform rule that is a Fledge choice. Under the maintainer's rule of 2026-11-12, such a justification does not hold.
- **`doc/phones.md`, lines 20 and 132,** and the comments in `lib/fledge/mobile_extensions.rb` (line 30) and `lib/fledge/mobile_extensions/rake_build.rb` (lines 35, 105, and 182) say the same and would follow the decision.

## Options

**A. Keep linking every extension in, and correct the reasons.** Costs nothing now. Closes nothing: rows 12 and 42 and ADR 080's gap stay, and with the reasons corrected they are differences Fledge chose, which the maintainer's words of 2026-11-12 call bugs. ADRs 058, 067, 068, and 080 stay, with their checks on each new Ruby.

**B. Files on Android, linked on iOS.** Costs: an Android runtime built shared with its extensions as files, the extension build switched from `make static` to `make` and a link against `libfledgeruby.so`, a 16 KB check per extension, and one of the two placements above. Closes every row of the table on Android. iOS keeps today's design, so Fledge carries both mechanisms, against ADR 022's driver of "one mechanism for both phones where one serves", which no longer serves parity.

**C. Files on both phones.** Costs B's, plus on iOS: Ruby as `FledgeRuby.framework`; `--disable-dln` dropped; extensions linked `-dynamiclib` against it; a framework, `Info.plist`, signature, and dSYM per extension; a link or a `dln.c` edit at each desktop path; the archive and privacy checks rewritten for frameworks; about 10 MB more installed for the standard library, or about 60 frameworks with encodings linked; and an App Store Connect upload to prove that a link, or about 180 frameworks, pass review. Closes every row of the table on both phones, and deletes most of ADRs 058, 067, 068, and 080, and ADR 022's registration. It follows CPython, Briefcase, and Flutter on iOS, and CPython, Chaquopy, and python-for-android on Android.

**D. kivy-ios's way: a file at each desktop path, answered by the linked extension.** A file, empty or naming its feature, at each extension's desktop path, and a `dln` of Fledge's own, put where `--disable-dln` puts `dmydln.o`, that looks the linked extension up instead of opening the file. Costs: one C file in Ruby's build, and the files. Closes rows 12 and 42 and ADR 080's gap on both phones, and lets ADR 068's gate and ADR 080's stubs go. Keeps ADRs 058, 067, and 022's registration. The files are not what their names say: `File.size` reads 0, and `Fiddle.dlopen` of one fails. ADR 068 rejected this shape, as files "that pretend to be code" (line 40).

## Recommendation

**C, in two steps.**

1. **Android first,** with the files in the Ruby tree inside `fledge.zip`. Every Python tool that ships to Android does it so, PEP 738 states it as Android's rule, AOSP's policy permits it, and it needs no renaming, no links, and no tie to `useLegacyPackaging`. If Google ever stops apps of a new target API from mapping their own files as code, which `app_neverallows.te` lines 75 to 81 show it would like to, the native library folder with links (above) is the fallback.
2. **iOS after a spike** on an `experiment/*` branch that proves three things: an app with `FledgeRuby.framework` and extension frameworks found through links runs in the Simulator and on a device; the archive passes `xcodebuild archive` with no warning; and an upload to App Store Connect accepts it. The last is an account test, so it goes in `doc/contributors/account-tests.md` and to the maintainer. If App Store Connect refuses the links, use a marker file and a `dln.c` edit, after CPython's `.fwork`.

The reasons, in Fledge's order of precedence: the differences are not forced by either phone, and the maintainer accepts none that is not (`decisions.md`, 2026-11-12). Ruby's own way of loading an extension is `dln` from a file. The prior art loads binary modules from files on Android everywhere, and from per-module frameworks on iOS in CPython's official build, Briefcase, and Flutter. And it deletes more of Fledge's code than it adds: ADR 067's relocation, ADR 068's edit of `load.c`, ADR 080's stubs, most of ADR 058's copy, and ADR 022's renaming and registration, each of which "a new Ruby means checking" again.

D is cheaper, but keeps the linked design and its machinery, and ships files that lie about what they are. A gives up parity the platforms do not take away.
