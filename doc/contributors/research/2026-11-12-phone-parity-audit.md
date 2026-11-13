<!--
SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>

SPDX-License-Identifier: CC-BY-SA-4.0
-->

> Requested: written by an agent and not reviewed line by line. An adversarial audit, 2026-11-12, of every difference Fledge accepts between a phone app and `ruby main.rb`. It changes no code, justification, or ADR; it says which justifications hold and which do not.

# An Audit of the Phone Parity

Two phone justifications fell today, each to one question: Android's `$0 =`, called impossible and fixed through `/proc/self/stat`, and `fiddle` on iOS, left out "for App Review" on a sentence nobody checked. This note asks the same question of every other one. It covers each entry of `Parity::MOBILE_JUSTIFIED` (`tasks/parity/mobile.rb`) and its rows in `test/parity_justified.yml`, `doc/phones.md`'s "What a phone forbids", and each place `doc/contributors/design/phone-runtimes.md` and `phone-projects.md` say something is left out or differs. The ruby/spec lists for phones (`RubySpec::JUSTIFIED` in `tasks/ruby_spec.rb`, `RubySpec::Phone::EXCLUDED` in `tasks/ruby_spec/phone.rb`) back the same items, and are mapped to them at the end.

Each difference gets one class:

- **A, inherent:** the place the app runs, which a `ruby main.rb` run from the same place would show too.
- **B, forbidden:** iOS or Android forbids it, by Apple's or Google's own text, their SDK headers, AOSP source, or a measurement on a device.
- **C, closable:** Fledge could remove it. The fix is given in outline with its cost.

`fiddle` is being added to iOS by another agent, so it is marked C and not worked out again here.

## What was read, and where the evidence is from

- Apple: the iPhoneOS 27.2 SDK's headers in this Mac's Xcode (`/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.2.sdk/usr/include`); "Placing content in a bundle" (developer.apple.com/documentation/bundleresources/placing-content-in-a-bundle); "Protecting code compiled just in time" (developer.apple.com/documentation/browserenginekit/protecting-code-compiled-just-in-time); the `com.apple.security.cs.allow-jit` entitlement's page (developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.cs.allow-jit). Read through each page's JSON on 2026-11-12.
- Google: "Behavior changes: apps targeting Android 10" (developer.android.com/about/versions/10/behavior-changes-10, "Removed execute permission for app home directory"); "Processes and app lifecycle" (developer.android.com/guide/components/activities/process-lifecycle).
- AOSP, at `refs/heads/main` on 2026-11-12: bionic `libc/SECCOMP_BLOCKLIST_APP.TXT` and `libc/include/android/fdsan.h`; system/sepolicy `private/app.te` and `private/untrusted_app_all.te`.
- Ruby 4.1.0-preview1's tarball, the pinned one: `configure.ac`, `missing/setproctitle.c`.
- Other embedders, as practice, not as proof: CPython's "Using Python on iOS" (docs.python.org/3/using/ios.html) and PEP 730; Chaquopy's FAQ and issue 284 (github.com/chaquo/chaquopy/issues/284).

No device, Simulator, or emulator was run for this note.

## Parity::MOBILE_JUSTIFIED

| # | Fact, platforms | Class | Evidence | Fix and cost (C) |
|---|---|---|---|---|
| 1 | `ENV`, both: the system's own variables (`HOME` and `TMPDIR` in the container, the Simulator's, no shell's) | A | The OS builds the environment of an app's process; a `ruby main.rb` in that process would read the same. | |
| 2 | `ENV`, both: `SSL_CERT_FILE`, which `fledge_ruby_run` sets | **C** | `runtime/mobile/fledge_ruby.c`, `prepare`, line 254, sets it on both phones. On Android OpenSSL never reads it: `android.c`, lines 19 to 29, says `ossl_safe_getenv` refuses it under `AT_SECURE`, and `__wrap_X509_get_default_cert_file` (lines 66 to 72) answers instead. So on Android it is a variable `ruby main.rb` lacks, set for nothing. On iOS, the desktop's reference Ruby, rv-ruby, does not set `SSL_CERT_FILE` at boot: its `openssl.rb` sets `PORTABLE_RUBY_SSL_CERT_FILE` as `openssl` loads (`doc/contributors/design/runtimes.md`, line 128). | Android: stop calling `setenv` there; the wrap already serves. A few lines in `fledge_ruby.c`. iOS: take the desktop's two scripted edits from rv-ruby (rename the variable in OpenSSL's source, set it in `openssl.rb`), so `ENV` at boot is the system's and changes at `require "openssl"` exactly as under rv-ruby's `ruby main.rb`. Small, reuses existing edits. Touches `ruby_source.rb`, the iOS builder, and `phone-runtimes.md`, "Certificates". |
| 3 | `ENV`, Android: `HOME`, set by `FledgeRuby.java` (line 182) when Android sets none | A, kept | Every desktop reference has a `HOME`, so setting it brings the app closer to `ruby main.rb`, not further. Chaquopy sets `HOME` to the files folder too (issue 284; its FAQ). Removing it would leave `Dir.home` at whatever bionic answers for the app's user. | |
| 4 | `ENV`, both: the justification's patterns are `[/./]` on both sides | **C** (the gate) | It accepts any element of `ENV` on either side, so row 2 passed, and any variable Fledge adds tomorrow will pass. The rule (AGENTS.md, Design precedence 2) needs a gate that sees Fledge's own additions. | Have the test hosts record `environ` as the OS gave it, before `FledgeRuby.prepare` and `fledge_ruby_run`, into the probe's report, and compare the probe's `ENV` with that, not with the desktop's. Then the justification shrinks to "the system's environment differs from the desktop's", and an added variable fails. Small: the test host and `tasks/mobile_parity.rb`. |
| 5 | `child ENV`, iOS: `Errno::` | B | Apple's SDK: `system` is `__IOS_PROHIBITED`, and `popen` and `system` carry "On iOS, process spawning is unavailable." (`_stdlib.h`, lines 205 to 208; `_stdio.h`, lines 335 to 339). `fork` and `execve` are not marked so (`unistd.h`, lines 456 to 459), so the header alone does not forbid `posix_spawn`; the device measurement does: on an iPhone 12 mini, `Process.spawn` and `IO.popen` raised `Errno::EPERM` (`doc/phones.md`, line 104). CPython's PEP 730 reports the same. | |
| 6 | `child ENV`, Android | A | As row 1, for a child; it inherits row 2's variable until row 2 is fixed. | |
| 7 | `RbConfig.ruby is a program`, iOS | B | As row 5: nothing on iOS could run it. A file there would only change which error a caller meets. | |
| 8 | `RbConfig.ruby runs`, iOS | B | As row 5. The documents disagree on the error: `phone-projects.md`, line 254, says ENOENT; `phones.md`, line 106, says EPERM. The pattern accepts any `Errno::`. | |
| 9 | `RUBY_PLATFORM` | A | Ruby names the platform it was built for; any Ruby on that phone would. Note for developers: iOS reports `arm64-darwin`, so a gem that tests `/darwin/` for macOS takes the iPhone for a Mac. CPython reports `sys.platform == "ios"` there. That is a naming choice of ADR 057's configure host, not a parity difference. | |
| 10 | `RUBY_DESCRIPTION` | A | As row 9. | |
| 11 | `$LOAD_PATH`'s folders of platform-specific files | A | As row 9. | |
| 12 | `$LOADED_FEATURES`: linked extensions recorded as features (`json/ext/parser.so`), not files | **C** | The reason says "iOS loads no code from files", and the former ADR 011, now ADR 079, line 20, says "it may load no code from files". Apple's own page says otherwise: "iOS, watchOS, and tvOS support third-party frameworks but don't support third-party standalone dynamic libraries", with frameworks in the app's `Frameworks/` ("Placing content in a bundle"). CPython's iOS build ships each binary module as a framework there and loads it with `dlopen`, through a `.fwork` file at the module's old path ("Using Python on iOS", "Binary extension modules"). On Android, loading `.so` files is ordinary: Google tells apps to "load only the binary code that's embedded within an app's APK file", and forbids `execve` of written files, not `dlopen` (Android 10 behavior changes); AOSP's sepolicy even grants `execute` on `app_data_file` to untrusted apps (`private/untrusted_app_all.te`, lines 24 to 28). Termux's Ruby loads its extensions from files. | Android: build Ruby's and the gems' extensions as shared objects in each ABI's `lib/` folder (the installer extracts them, as it already extracts `libfledgerubyexe.so`), and let `dln` load them; `$LOADED_FEATURES`, `archdir`, `require_relative` of an extension, and `require "racc/cparse"` before racc is active then all match a desktop, and the `load_c` gate goes. Medium: reverses part of the former ADR 011, now ADR 079 and ADR 067 on Android, changes `phone-projects.md`'s "Linking extensions on Android", and costs some size and load time. iOS: CPython's way, one framework per extension, and a `load.c` or `dln` hook that maps a path to its framework. Large: a build phase per extension, signing, and an ADR. |
| 13 | `RubyVM::YJIT`, iOS | B | Apple grants writable then executable memory only to a browser's web content extension, with BrowserEngineKit's entitlements ("Protecting code compiled just in time"); `com.apple.security.cs.allow-jit` lists macOS alone. | |
| 14 | `RubyVM::YJIT`, Android | **C** | The reason cites `configure.ac`, and the lines say less than it claims: lines 3895 to 3910 turn the JIT off for `*android*` only in the default, when not cross-compiling, and `--enable-yjit` (line 3917) overrides it. Fledge passes `--disable-yjit` itself (`phone-runtimes.md`, line 57). Android allows a JIT: AOSP's `private/app.te`, lines 188 to 189, "WebView and other application-specific JIT compilers", `allow appdomain self:process execmem;`. | Build YJIT for both Android targets: Rust and its `aarch64-linux-android` and `x86_64-linux-android` targets in the Android runtime's job, `--enable-yjit` with the cross `rustc`, then the parity and ruby/spec runs. Medium, and unproven until it runs on a 16 KB-page emulator and a device. `RubyVM::YJIT.enabled?` would then be `false`, as on the desktop. |
| 15 | `$stdout.sync`, both: `true` | **C**, with a cost | Nothing forbids a buffered `$stdout`: `ruby main.rb \| logger` buffers exactly so. It is Fledge's choice (the former the former ADR 059, now ADR 078), for a developer watching the log, as Briefcase's host unbuffers Python's. The desktop launcher does not make it. | Leave `$stdout` as Ruby leaves it, which is exact parity, and lines reach the log when the buffer fills or the program ends. A pseudo-terminal in place of the pipe would make Ruby write through with `sync` false, but makes `$stdout.tty?` true, another difference. Trivial to do; the cost is the developer's view of the log. This is the maintainer's trade to weigh, not a rule of the phone. |
| 16 | `gems`, iOS: no `fiddle` | **C** | Being fixed elsewhere. The only evidence was xord/cruby's comment (`tasks/runtime_builder/ios.rb`, lines 38 to 41). CPython's iOS build ships `ctypes`, which does what `fiddle` does. | In progress. |
| 17 | `requireable`, iOS: no `fiddle` | **C** | As row 16. | In progress. |
| 18 | `gems`, both: `win32-registry` present | **C** | Nothing about a phone puts it there; Ruby's install of a source build does, and rv-ruby's builds, the reference, leave it out. The phone runtimes already leave out `win32ole` and `win32` (`tasks/runtime_builder/mobile.rb`, line 109). | Prune the gem from the phone runtimes, as rv-ruby's builds lack it. One line in the pruning, and two justifications fewer. No developer meets this one, but the list shrinks. |
| 19 | `requireable`, both: `win32-registry` | **C** | As row 18. | As row 18. |

`test/parity_justified.yml` also applies its rows without platforms to the phones: the program's path as typed, the `:bundle` check's rows, `$VERBOSE` under the person's `RUBYOPT=-W0`, `Gem.path` and `Gem.dir`, bootsnap and msgpack, and Fledge's `operating_system.rb`. Those are the desktop's differences, shared by the phones, and are outside this audit.

## doc/phones.md, "What a phone forbids"

| # | Item | Class | Evidence | Fix and cost (C) |
|---|---|---|---|---|
| 20 | iOS: starting a program | B | Row 5. | |
| 21 | iOS: `fork` | B | `EPERM` on the iPhone 12 mini (`phones.md`, line 105). The SDK does not mark `fork` prohibited on iOS (`unistd.h`, line 459), so the device measurement is the evidence, and PEP 730 agrees ("`os.fork` and `os.spawn` calls will raise an `OSError`"). | |
| 22 | iOS: `RbConfig.ruby` | B | Row 7; row 8's disagreement on the error. | |
| 23 | iOS: `fiddle` | **C** | Row 16. Line 14's "other iOS Rubies leave out for App Review" and line 107 rest on the one comment. | In progress. |
| 24 | iOS: `mkmf` aborts | **C** | Not forbidden: headers are files, and an app may carry files. The desktop runtime carries them for this reason, so `require "mkmf"` and `find_executable` work (`doc/differences_from_ruby.md`, line 49). The phone's reason, no compiler, holds for most desktops too. | Copy the runtime's headers into the app's Ruby root (`include/`), as the desktop does. A few megabytes per app, and the gate's check that the archive holds only what App Store Connect accepts must allow headers. Then `require "mkmf"` loads; compiling still fails, as on a desktop with no compiler. On Android `find_executable` is useful, since system programs run. |
| 25 | iOS: set-ID and sticky bits | B, unproven | The evidence named is the Simulator's ruby/spec runs (`phones.md`, line 109; `RubySpec::JUSTIFIED`). The cause, "the sandbox", is asserted, not cited. The section's heading says what follows held on an iPhone 12 mini, but this item does not say it was measured there. | Measure on a device: `File.chmod(04755, f); File.setuid?(f)`. |
| 26 | iOS: user and group names (`Etc`) | A | Darwin's C library answers so in the app; any Ruby there would. `ENV["USER"]` reading `mobile` was measured on the device; `Etc` finding no user is from the Simulator's runs only. | Measure `Etc.getpwuid` on a device. |
| 27 | iOS: user and group IDs | none | Not a difference. | |
| 28 | iOS: groups (`Process.groups` raises `EINVAL`) | A | Darwin's `getgroups` looks the user up and fails (Libc, `sys/getgroups.c`, lines 35 to 58 at Libc-1752.120.2, cited in `phone-runtimes.md`, line 93); a `ruby main.rb` in the app would raise the same. Fledge's `file_c` edit already mends the bug it caused. | |
| 29 | Android: starting a program written at run time | B | Google: "Untrusted apps that target Android 10 cannot invoke `execve()` directly on files within the app's home directory" (Android 10 behavior changes). | |
| 30 | Android: `RbConfig.ruby`, and `exec RbConfig.ruby` | A for `system` and `spawn`; unproven for `exec` | `system` and `spawn` run as on a desktop. The advice not to `exec` rests on no measurement: nobody has seen what Android does with an app whose process image is replaced, and after `exec` the threads that forward the log are gone, so the new Ruby's output goes to pipes no one reads. | Measure `exec RbConfig.ruby, "-e", "puts 1; sleep 5"` on the emulator. If Android keeps the process, the ruby program could forward the log again when it replaces the app (small, `android.c`). |
| 31 | Android: group IDs | **C** | The seccomp filter is real: bionic's `libc/SECCOMP_BLOCKLIST_APP.TXT` blocks `setgid`, `setuid`, `setregid`, `setreuid`, `setresgid`, and `setgroups`, with "setresuid is explicitly allowed". But "No workaround exists" does not follow. An app's process has no `CAP_SETGID` and its real, effective, and saved group IDs are one ID, so Linux's answer is already settled without the call: setting the group ID it already has succeeds, any other raises `EPERM`, and `setgroups` and `initgroups` raise `EPERM`. Ruby answers `NotImplementedError` instead, which no Linux gives. | Give the Android runtime's Ruby its own `setgid`, `setegid`, `setregid`, `setresgid`, `setgroups`, and `initgroups`, which make no system call and answer as Linux would for an unprivileged process: 0 when every ID asked for is the current one, otherwise -1 with `EPERM`. Tell `configure` they exist. Then `Process.gid=`, `Process.egid=`, `Process::GID`, `Process.groups=`, `Process.initgroups`, and `Process.maxgroups=` behave as on Linux, and three ruby/spec justifications go. Small: about 40 lines of C, a scripted edit or `-D` names, `RuntimeBuilder::Android::CONFIGURE`. |
| 32 | Android: `mkmf` | **C** | Row 24. ruby/spec's "mkmf can be required with --enable-frozen-string-literal" justification goes with it. | Row 24. |
| 33 | Android: process title cut at the identifier's length | **C**, moderate risk | Linux's Ruby writes past `argv` into the environment's area, after copying `environ` to the heap (`missing/setproctitle.c`, `compat_init_setproctitle`, lines 117 to 175 at 4.1.0-preview1). The kernel gives that area's bounds in `/proc/self/stat` too (`env_start` and `env_end`, fields 50 and 51), beside the fields 48 and 49 the `setproctitle_c` edit already reads. | Extend the edit to the environment's area, as Linux's Ruby does. Small in code; the risk is Java's threads, which may read `environ` while Ruby moves it. Few developers will ever look. |
| 34 | Android: `/dev` unreadable | B | Measured (`EACCES`) on the emulator by ruby/spec; the SELinux rule is not cited by line. | |
| 35 | Android: `fdsan` ends the process for two `Dir`s on one descriptor | **C**, with a cost | bionic's own API lets an app lower it: `android_fdsan_set_error_level` (`libc/include/android/fdsan.h`, line 212, API 29, weak), down to `ANDROID_FDSAN_ERROR_LEVEL_WARN_ONCE`. | Lower it to warn-once in `fledge_ruby_run`, where the API exists. One call; the cost is the whole process, Java's side too, losing a crash that finds real bugs. Few developers meet it; the case is a bug on Linux too. |
| 36 | Android: set-ID bits and `Etc` | none | No difference claimed. | |
| 37 | Both: no terminal, standard input at its end, working folder `/` | A | How each OS starts an app, as the Finder starts a macOS app. | |
| 38 | Both: `$stdout` in sync mode | **C** | Row 15. | Row 15. |
| 39 | Both: a read-only bundle | A on an iOS device; **wrong** for Android | iOS signs the bundle and a device keeps it read-only. On Android the app's Ruby root is `getFilesDir()/fledge` (`FledgeRuby.java`, line 64), which is writable, so "On both" is untrue there. | Correct the item: say iOS. |
| 40 | Both: no JIT | B on iOS; **C** on Android | Rows 13 and 14. | Row 14. |
| 41 | Both: stopped in the background without `at_exit` | B | Google: "the system can kill the process at any time to reclaim memory", and "`onDestroy()` is not guaranteed to be called" ("Processes and app lifecycle"). A `ruby main.rb` killed with SIGKILL runs no `at_exit` either. | |
| 42 | Both: native code in the app, `archdir` empty | **C** | Row 12. | Row 12. |

## Elsewhere in the phone documents

| # | Claim | Class | Evidence | Fix and cost (C) |
|---|---|---|---|---|
| 43 | `require_relative` cannot load a gem's extension; write `require "name/name"` (`phones.md`, line 20; `phone-projects.md`, line 137) | **C** | Not a phone's rule: the linked extensions are in a table keyed by feature, and an absolute path is not in it. A developer meets this with real gems whose Ruby loads its extension by `require_relative`, and cannot change a locked gem's code. | Android: row 12's shared objects remove it. Both, short of that: in the `load_c` edit, when an absolute path finds no file, strip the `$LOAD_PATH` entry it lies under and look the rest up in the table. Small to medium, in `ruby_source.rb`. |
| 44 | `require "racc/cparse"` raises `LoadError` until racc is active (`phone-runtimes.md`, line 111, "One difference stays") | **C** | Not in `MOBILE_JUSTIFIED`: the probe requires only each gem's main feature, so the gate never sees it. It follows from linking, not from a phone. | Android: row 12. Both: in the `load_c` gate, when a table feature's gem is not active, raise the `LoadError` RubyGems expects with a path RubyGems can find, or have the gate activate the gem through `Gem::Specification`. Small. Add the case to the probe first. |
| 45 | iOS's `MISSING` functions (`ios.rb`, line 28): `system`, `syscall`, `__syscall`, `backtrace`, `getentropy`, `dup3`, `pipe2` | Mostly A; one borrowed claim | `system` is `__IOS_PROHIBITED` (row 5). `syscall` is deprecated on iOS (`unistd.h`, line 750), and Ruby turns it off on macOS too (`configure.ac`, lines 1155 to 1165), so no difference. `getentropy` is not in the iOS SDK's headers. `dup3` and `pipe2` are iOS 27 only (`sys/unistd.h`, lines 216 to 219), past the iOS 15 floor. `backtrace` is in the SDK since iPhone OS 2.0 (`execinfo.h`, line 39): xord/cruby's list is wrong there. It only takes the C frames out of a `[BUG]` report, which an app's code never sees. | Drop `backtrace` from `MISSING`. Trivial; gives crash reports their C frames. |
| 46 | iOS's `$0 =` and `Process.setproctitle` | **C**, suspected | Ruby uses `SPT_REUSEARGV` on Darwin (`configure.ac`, line 2144), which writes over the `argv` Ruby was given, and on iOS that is the array `fledge_ruby_run` allocates, not the process's arguments, which Darwin's `KERN_PROCARGS2` reads. That is the Android bug fixed today. ruby/spec's two examples are excluded on iOS (`RubySpec::Phone::EXCLUDED`, the `/proc` one), so nothing has looked. | Measure in the Simulator (`ps -o command -p PID` on the Mac after `$0 = "x"`). If it is so, point the edit at `*_NSGetArgv()` (`crt_externs.h`, in the iOS SDK), as `setproctitle_c` points Android's at `arg_start`. Small. |
| 47 | `fiddle` on iOS (`phone-runtimes.md`, lines 65 and 113; ADR 058, line 45; `RubySpec::JUSTIFIED`'s fiddle entry) | **C** | Row 16. | In progress. |

## The ruby/spec lists for phones, mapped

- `RubySpec::JUSTIFIED`: `library/fiddle` (row 16); `IO#sync` (row 15); `archdir` (row 12); set-ID bits (row 25); `grpowned?` and `egid=` by name on iOS (rows 26 and 28); `Etc.getlogin` on iOS (row 5: the example starts `logname`); `AR` and `STRIP` on Android (A: a phone has no toolchain, and a desktop without one fails the same way); `Process.maxgroups=` and `Process.egid=` on Android (row 31); `Dir.scan` of `/dev` (row 34); `mkmf` with frozen string literals (row 32); the two examples that run a script they wrote (row 29).
- `RubySpec::Phone::EXCLUDED`: `command_line`, `Process.kill`, the spawning files, the system-program examples on iOS (row 5); the `/proc` title examples on iOS (row 46, unexamined); the forking files on iOS (row 21); `Dir#close` with two `Dir`s on Android (row 35).

## Counts

Of the 47 rows, 19 are `Parity::MOBILE_JUSTIFIED`'s rows (with `ENV` split into its parts), 23 are `phones.md`'s items, and 5 are other claims. Several rows are the same difference seen from two documents. Counted once each, the distinct differences are:

- **A, inherent: 11.** The system's `ENV`, Android's `HOME`, a child's `ENV` on Android, `RUBY_PLATFORM`, `RUBY_DESCRIPTION`, the `$LOAD_PATH` folders, `Etc` on iOS, `Process.groups` on iOS, no terminal and `/` as the working folder, the read-only bundle on an iOS device, and `RbConfig`'s `AR` and `STRIP` on Android.
- **B, forbidden: 8.** Starting a program on iOS, with `RbConfig.ruby` and a child's `ENV`; `fork` on iOS; a JIT on iOS; running a written file on Android; Android's `/dev`; being killed in the background; set-ID bits on iOS (unproven on a device); and `exec RbConfig.ruby` on Android (unproven).
- **C, closable: 15.** Ranked below, with row 30's possible fix beside them.
- Not a difference: 2 (rows 27 and 36). One document error (row 39), and one documents' disagreement (row 8).

## The closable ones, by what a developer meets first

1. **A gem's extension loaded by `require_relative`, or by its own feature before its gem is active** (rows 43 and 44). A real gem breaks at `require`, and the developer cannot edit a locked gem. Small fix in `load_c` for both; on Android, row 12's fix removes it.
2. **`fiddle` on iOS** (rows 16, 17, 23, 47). In progress elsewhere.
3. **`RubyVM::YJIT` on Android** (row 14). Code that calls `RubyVM::YJIT.enable` unguarded raises `NameError`, and every app runs slower than it could. AOSP allows application JITs. Medium cost.
4. **`mkmf` on both** (rows 24 and 32). Gems that `require "mkmf"` at run time for `find_executable` abort. Copy the headers; a few megabytes.
5. **`$stdout.sync`** (rows 15 and 38). Every app has it, few read it. Trivial to close; the cost is a delayed log, so it is the maintainer's trade.
6. **`SSL_CERT_FILE` in `ENV`, and the `ENV` gate that let it pass** (rows 2 and 4). Visible to code that lists or copies `ENV`; the gate matters more, since it hides the next addition too. Small.
7. **Group IDs on Android** (row 31). `NotImplementedError` where Linux gives success or `EPERM`; met by servers and libraries that drop privileges. About 40 lines of C.
8. **`$LOADED_FEATURES` and `archdir`** (rows 12 and 42). Met by code that reads `$LOADED_FEATURES` or `RbConfig::CONFIG["archdir"]`, such as loaders and boot caches. Medium on Android, large on iOS.
9. **`$0 =` on iOS** (row 46). Suspected, unmeasured; seen only by tools that read the process's arguments. Small.
10. **`exec RbConfig.ruby` on Android loses the log** (row 30). Counted under B as unproven; if a measurement shows Android keeps the process, forwarding the log again is small.
11. **The process title's length on Android** (row 33). Seen only in `ps`.
12. **`fdsan` and two `Dir`s on one descriptor** (row 35). A bug on Linux too.
13. **`backtrace` in iOS's `MISSING`** (row 45). Only `[BUG]` reports.
14. **`win32-registry` on phones** (rows 18 and 19). No developer meets it; the list shrinks by two.

## Lines this makes untrue

For the orchestrator, who keeps the ADRs:

- the former ADR 011, now ADR 079, line 20: "An iOS app is one signed binary in a bundle, and it may load no code from files." Apple's "Placing content in a bundle" supports third-party frameworks in `Frameworks/`, and CPython loads its binary modules from them. Proposed: "An iOS app may load code only from frameworks signed into its bundle, and an Android app only from the native libraries its package carries."
- ADR 058, line 18: "A phone's Ruby loads no extension from a file". Proposed: "A phone's Ruby links every extension in (the former ADR 011, now ADR 079)", without the reason, or with the former ADR 011, now ADR 079's corrected one.
- `tasks/parity/mobile.rb`, the `$LOADED_FEATURES` reason, "since iOS loads no code from files", and the YJIT reason, "Ruby builds no JIT for Android (configure.ac at 4.1.0-preview1)": both overstate their sources (rows 12 and 14).
- `doc/phones.md`, line 120, "No workaround exists" (row 31), and line 129, which says "On both" of a bundle that is read-only on iOS only (row 39).
- `doc/contributors/design/phone-projects.md`, line 254, ENOENT, against `phones.md`'s EPERM (row 8).
