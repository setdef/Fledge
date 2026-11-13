<!--
SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>

SPDX-License-Identifier: CC-BY-SA-4.0
-->

> Findings of 2026-11-12 on whether iOS or App Review forbids Ruby's fiddle and the ffi gem. Requested: written by an agent and not reviewed line by line. ADRs cite these findings by this file.

# ffi and fiddle on phones: what the sources say

Fledge leaves fiddle out of its iOS runtime, and refuses gems that build a library for Ruby's ffi on both phones. The only reason on record for iOS is one comment in xord/cruby. The maintainer asked why (decisions, 2026-11-12): "Why can't we have it on both? And why does Fledge leave Ruby's `fiddle` out?" These findings check that reason, and four claims the orchestrating agent made from memory, against their sources. Every page below was read on 2026-11-12.

## Verdict

Nothing in Apple's text forbids fiddle or ffi on iOS. App Review's rules on code concern what an app does, not what a library could call. Python's own iOS build, and BeeWare's, ship `ctypes`, Python's counterpart of fiddle, and Pythonista ships on the App Store with it. libffi makes callbacks on iOS without writable and executable memory. The one thing iOS does require is where a dynamic library sits: inside a framework in the app's `Frameworks` folder, never loose.

So fiddle can return to the iOS runtime, and an ffi gem's library can ship on iOS, packed as a framework.

## The reason Fledge gave

xord/cruby's Rakefile, at commit 11d62c4, line 577:

```ruby
withouts << 'fiddle' if ios # to pass the App Store review
```

The comment cites nothing: no guideline, no rejection. Fledge copied it into ADR 058 (line 45), `doc/contributors/design/phone-runtimes.md` (lines 65 and 113), `doc/phones.md` (lines 14 and 106), `tasks/runtime_builder/ios.rb` (lines 38 to 42), `tasks/parity/mobile.rb` (lines 68 to 71), and `tasks/ruby_spec.rb` (lines 108 to 110).

## Claim 1: CPython's official iOS build ships ctypes

**True, with one correction.** PEP 730's text never mentions ctypes or libffi; CPython's build files do.

- PEP 730 (https://peps.python.org/pep-0730/, Final, Python 3.13, last modified 2025-02-01) says iOS apps "can use dynamically loaded libraries", which "must be packaged in the app bundle as Frameworks", one dynamic library per framework, in the app's `Frameworks` folder. It names Pythonista and Pyto as apps already in the App Store.
- CPython's `iOS/README.rst` at tag v3.13.0, lines 179 to 188: a full iOS build needs "XZ, BZip2, LibFFI and OpenSSL", and "LibFFI is especially important, as many parts of the standard library (including the `platform`, `sysconfig` and `webbrowser` modules) require the use of the `ctypes` module at runtime."
- CPython's `configure.ac` at v3.13.0, lines 7701 to 7703, builds `_ctypes` whenever libffi is found; the iOS case (lines 3997 to 3999) adds only `malloc_closure.c`, whose `Py_ffi_closure_alloc` calls libffi's `ffi_closure_alloc` when libffi has it (`Modules/_ctypes/malloc_closure.c`, lines 119 to 133).
- `Lib/ctypes/util.py` at v3.13.0, line 70, looks for libraries the same way on `darwin`, `ios`, `tvos`, and `watchos`, including `NAME.framework/NAME`.
- How CPython makes a loose binary module into a framework: the iOS testbed's build phase (`iOS/testbed/iOSTestbed.xcodeproj/project.pbxproj` at v3.13.0, shell function `install_dylib`) moves each `.so` into `Frameworks/MODULE.framework/`, leaves a `.fwork` file where the module was, and signs each framework. `Lib/importlib/_bootstrap_external.py` at v3.13.0, lines 1724 to 1745 (`AppleFrameworkLoader`), reads the `.fwork` file to find the framework's binary.

## Claim 2: BeeWare ships ctypes on iOS, and App Store apps carry it

**True for BeeWare and Pythonista; Pyto was not checked.**

- BeeWare's Python-Apple-support, tag 3.15-b3 (commit 23dc218d87a69e8b2f39921efa550b476c728de2), `Makefile`: line 31 pins `LIBFFI_VERSION=3.4.7-2`; lines 257 to 279 download BeeWare's iOS build of libffi and keep only its static library (`--exclude="*.dylib"`); lines 333 and 334 hand it to CPython's configure as `LIBFFI_CFLAGS` and `LIBFFI_LIBS`. So `_ctypes` is in every Briefcase iOS app.
- Pythonista 3 is on the App Store (https://apps.apple.com/us/app/pythonista-3/id1085978097). Its `objc_util` module is "Based on ctypes and the Objective-C runtime library" (https://omz-software.com/pythonista/docs/ios/objc_util.html, line 10 of its text).
- Pyto is named in PEP 730 as an App Store app; whether it carries ctypes was not checked.

## Claim 3: App Review Guidelines 2.5.1 and 2.5.2 concern conduct

**True.** App Review Guidelines (https://developer.apple.com/app-store/review/guidelines/, "Last Updated: October 16, 2026"):

- 2.5.1: "Apps may only use public APIs and must run on the currently shipping OS." This is a rule on which functions an app calls. `dlopen` and `dlsym` are public: the iPhoneOS 27.2 SDK documents both in `usr/include/dlfcn.h`. A fiddle or ffi call into a private framework would break 2.5.1, as the same call written in C would; the library does not.
- 2.5.2: apps "may not download, install, or execute code which introduces or changes features or functionality of the app". fiddle and ffi call code that is already in the app or in iOS. Neither downloads anything.
- 4.7.2: "Your app may not extend or expose native platform APIs or technologies to the software without prior permission from Apple." This binds only "software that is not embedded in the binary" (4.7: mini apps, mini games, streaming games, chatbots, plug-ins). A Fledge app's Ruby is embedded in the app.
- No guideline names interpreters, foreign function interfaces, ctypes, libffi, or fiddle.

So an app built with fiddle or ffi meets App Review exactly as well as the same app written in C does. What it calls is the developer's choice and responsibility, as it is for the gems themselves (ADR 007).

## Claim 4: libffi supports static trampolines on iOS

**False as worded, true in substance.** libffi's "static trampolines" (`FFI_EXEC_STATIC_TRAMP`) are for Linux and Cygwin only: libffi's `configure.ac` at v3.4.7, lines 372 to 390. On Apple's ARM targets libffi uses a different mechanism to the same end, its trampoline table:

- `configure.ac` at v3.4.7, lines 224 to 231, and at v3.5.2, lines 233 to 240: for `*arm*-apple-*` and `aarch64-apple-*` it defines `FFI_EXEC_TRAMPOLINE_TABLE`, "Cannot use PROT_EXEC on this target, so, we revert to alternative means".
- `src/closures.c` at v3.4.7, lines 161 to 245: `ffi_trampoline_table_alloc` maps a page of trampolines that was compiled into the signed binary (`ffi_closure_trampoline_table_page`) next to a writable data page with `vm_remap`. No page is ever both writable and executable, and no code is made at run time, so iOS's code signing accepts it.

Both bindings use it when they ask libffi for closures:

- Ruby's fiddle 1.1.8 (Ruby 4.1.0-preview1's), `ext/fiddle/closure.c`, lines 21 to 26, uses `ffi_closure_alloc` whenever `extconf.rb` (line 175) finds it.
- The ffi gem v1.17.4, `ext/ffi_c/ClosurePool.c`, line 219, calls `ffi_closure_alloc` when built with `USE_FFI_ALLOC`; without it, lines 292 to 322 `mmap` a writable page and `mprotect` it executable, which iOS refuses. `ext/ffi_c/extconf.rb` turns `USE_FFI_ALLOC` on by default when `RbConfig::CONFIG["host_os"]` matches `darwin` and `host` matches `arm` or `aarch64`, which Fledge's iOS runtime, configured for `aarch64-apple-darwin`, does. The gem's bundled libffi (submodule at 2263d6037f8ef6b8d5bef14117ad1a17c32a20b9, 2025-12-26) is built for `--host=aarch64-apple-darwin`, which takes the trampoline table.

## What iOS does require: frameworks

Apple's "Placing content in a bundle" (https://developer.apple.com/documentation/bundleresources/placing-content-in-a-bundle): on iOS a framework or dynamic library goes in `Frameworks/`, and "iOS, watchOS, and tvOS support third-party frameworks but don't support third-party standalone dynamic libraries, which are those outside a framework bundle, typically with the .dylib filename extension." Only the app itself may hold frameworks: "a nested bundle, like an app extension, can't include a framework." So a library an ffi gem builds ships on iOS as a signed framework in the app's `Frameworks` folder, as CPython packs its modules (claim 1), and not at the path inside the gem where the gem's `ffi_lib` looks for it.
