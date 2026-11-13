<!--
SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>

SPDX-License-Identifier: CC-BY-SA-4.0
-->

> Requested: written by an agent and not reviewed line by line. An adversarial audit of what the ruby/spec comparison accepts, made on 2026-11-12 at trunk 173ddc1a. It changes no code, no justification, and no ADR; it says what each entry rests on, and what to do about the ones that rest on less than they claim.

# Audit of ruby/spec's justifications and exclusions

The ruby/spec comparison (`doc/contributors/design/parity.md`, "ruby/spec") fails CI on any example that fails in a built app and passes in stock Ruby, or the other way round, unless `RubySpec::JUSTIFIED` (`tasks/ruby_spec.rb`) explains it. Two other lists keep examples from running at all: `RubySpec::EXCLUDED`, on the desktop, and `RubySpec::Phone::EXCLUDED` (`tasks/ruby_spec/phone.rb`), on the phones. An exclusion is worse than a justification. A justification names a difference CI sees on every run; an exclusion keeps CI from looking.

On 2026-11-12 two justifications fell to one question each: Android's process title, called impossible, took about 25 lines to fix, and `fiddle` on iOS rested on a claim borrowed from another project that was false. This audit asks the same question of every other entry: is the difference really there for stock Ruby too, does an operating system really forbid it, and does the entry still match what CI sees?

Each entry gets one class:

- **A, inherent**: stock Ruby from the same place, or the build itself, shows it too.
- **B, forbidden**: the operating system forbids what the spec does, by a primary source.
- **C, closable**: Fledge could make the app pass.
- **D, stale or wrong**: the entry no longer matches what CI sees, or its stated reason is not the cause.

`fiddle`'s entry is left out: another agent is bringing ffi and `fiddle` to the phones.

## The evidence

Sources, all at their pinned commits: ruby/spec 47b10f1d7b1c29bda01d6903cceddd5b0b4c857d and MSpec 521207f313abfaffd56dca274475c56012f90221 (`RubySpec::SOURCES`); Ruby 4.1.0-preview1, revision 2d08b5f42f; ruby/ruby's master at 0e25874222 for what has changed since.

CI runs read, with their output files where CI kept them:

| Run | Commit | What it ran |
|---|---|---|
| 43221077433 (ruby-spec.yml, nightly) | 0096dc7f | all seven desktops |
| 43313316095 (CI, trunk) | 0811346f | `x86_64-linux`, `arm64-darwin`, iOS, both Android emulators; artifacts `ruby-spec-ios`, `ruby-spec-android-*` |
| 43279374531 (CI, `experiment/android-ruby-followups`) | e1fc3c80 | iOS and Android with Android running the process files (`2d6527d7`'s change) |
| 43315555155 (CI, `experiment/android-proctitle`) | 962d5783 | Android with the process title fixed; artifact `ruby-spec-android-google_apis` |

No trunk run since 2d6527d7 reached the ruby/spec jobs: every one was cancelled or failed earlier. The Android entries are judged from the two experiment runs, which between them cover today's lists.

Totals the comparison does not compare, from those runs:

| Run | Stock examples | App examples | App errors |
|---|---|---|---|
| iOS Simulator, iPhone (43313316095) | 32681 | 32648 | 8 |
| Android, 4 KB pages (43279374531) | 33123 | 33043 | 9 |
| Android, 4 KB pages (43315555155) | 32722 | 32645 | 8 |

## Two holes in the comparison itself

These are not entries of either list, but they hide differences the way an exclusion does, and one of them hides differences today.

**H1. An error outside an example is never compared.** MSpec describes an error in a `before :all` hook, or in a `describe` block's own body, as `An exception occurred during: before :all` with nothing after it, since such an error has no example (`lib/mspec/runner/exception.rb`, lines 7 to 20 at MSpec 521207f). The phones' formatter prints that one line with `ERROR` after it (`tasks/ruby_spec/phone_config.rb`, line 73), and the desktop's formatter does the same. `Results.read` (`tasks/ruby_spec/results.rb`, lines 61 and 62) sees `An exception occurred during:`, steps to the next line, which is the exception's message, finds no `FAILED` or `ERROR` at its end, and skips the failure. In the iOS run of 43313316095 the app has three such errors that stock Ruby does not, and CI passed without a word about them:

- `library/etc/getpwuid_spec.rb`, line 17: `before :all` runs `` `id -u` ``, `Errno::ENOENT`;
- `library/etc/struct_group_spec.rb`, line 6: the `describe` body runs `IO.popen` of `id`, `Errno::ENOENT`;
- `library/etc/struct_passwd_spec.rb`, line 7: `before :all` runs `` `id -u` ``, `Errno::ENOENT`.

Their 17 examples (4, 5, and 8) never ran in the app. They start a program of the system's, as the iOS exclusion of that kind (P-X5, below) says iOS cannot, but they are in no list: they slipped through. The app's 8 errors are these 3, the 3 `grpowned?` errors, `Process.euid=`, and `fiddle`'s one file; only 5 of the 8 are compared.

**H2. Examples that run on one side only are never compared.** The comparison reads failures, not the examples that ran. The app runs 33 fewer examples than stock Ruby on iOS and 77 to 80 fewer on Android, and nothing says which. Part of it is H1's 17 and `fiddle`'s file on iOS. Much of Android's is ruby/spec's own guards: `platform_is_not :android` skips examples in 23 places (`core/process/groups_spec.rb`, `core/process/initgroups_spec.rb`, `core/dir/chroot_spec.rb`, `library/etc/group_spec.rb`, `library/syslog/`, `shared/file/readable.rb`, and more), which upstream accepts as Android's. The rest is unaccounted for: guards such as `Process.respond_to?(:fork)`, `with_block_device` (which runs `find /dev`), and every method Ruby defines as not implemented, which `respond_to?` reports false. Until a run lists each side's examples, nobody knows whether those 80 hide a bug.

**H3. Nothing finds a justification that matches nothing.** `Results.compare` asks only whether some justification explains each difference. A justification that no difference uses, or half of whose pattern never matches, passes every run. That is how P-J5's `Process.egid=` half (below) went unnoticed.

**H4. Patterns wider than the failures.** P-J4's pattern, `(?:File|File::Stat|FileTest)[.#](?:setuid|setgid|sticky)\? `, explains any failure of any example of six predicates on iOS, including ones that fail today in neither run. A new bug there would be called justified.

## Every entry

Examples hidden counts the `it` blocks in the files at ruby/spec 47b10f1, with each shared group counted where it is used; guards make the number a run sees a little different.

### The desktop

| Entry | Class | Evidence | Examples hidden |
|---|---|---|---|
| **D-X1.** `EXCLUDED`, `x86_64-linux-musl` and `aarch64-linux-musl`: `Thread#to_s returns a description including a thread name if given any` | **C** | Stock Ruby on musl is the musl runtime itself (`Parity#unpack_reference`, `tasks/parity.rb`, lines 350 and 351), so both sides crash alike, and the crash is real: `rb_thread_setname` names the native thread of a thread that has ended (`thread.c`, lines 3977 to 3979 at 2d08b5f42f), and musl's `pthread_setname_np` reads a `pthread_t` that `join` has freed. ruby/ruby 6fdd452087 (Yusuke Endoh, 2026-10-25) fixed it on master, and Fledge already carries it as the `thread_c` edit for Android, where bionic aborts on the same call (`doc/contributors/design/phone-runtimes.md`, "Scripted edits to Ruby's source"). Making the musl build take `thread_c` would let the example run and pass, and stop the crash for any app on musl that names a finished thread. The comment's "CRuby 4.0.9" is stale: the musl runtimes are 4.1.0-preview1 (`runtime/sources.yml`, `musl-ruby`). | 1, which would pass with the edit |
| **D-J1.** `arm64-darwin`, stock only: `Dir.chdir`, `File.readlink`, `File.realpath` accept a path in a non-UTF-8 encoding | **A** | All four fail in stock Ruby in the nightly run and pass in the app. Both sides run with no locale, as a desktop starts an app; stock Ruby takes US-ASCII for paths, and the launcher takes UTF-8 in place of a bare C locale (the former ADR 041, now ADR 087). Each example encodes a path in Windows-31J and compares `Dir.pwd` with the UTF-8 one (`core/dir/chdir_spec.rb`, lines 69 to 83). The difference is in the app's favor, and in a terminal with a UTF-8 locale both sides pass. | none |
| **D-J2.** `x64-mingw-ucrt`, `aarch64-mingw-ucrt`, stock only: `Refinement#import_methods ... from C extension` | **A** | Seen in the nightly run on both. RubyInstaller's head build ships `zlib.so` without `libz-1.dll`, which a developer's Ruby finds through MSYS2; the clean environment has none. It expires with Ruby 4.1.0's RubyInstaller (ADR 066). | none |
| **D-J3.** `x64-mingw-ucrt`, `aarch64-mingw-ucrt`, stock only: `library: loading library/zlib/` | **A** | As D-J2: 42 spec files fail to load in stock Ruby on each, and stock runs 148 fewer library examples (5535 against 5683). Expires with D-J2. | none |

### The phones' justifications

| Entry | Class | Evidence | Examples hidden |
|---|---|---|---|
| P-J1. iOS, `library: loading library/fiddle/` | not audited | Another agent's work. One file, one example. | |
| **P-J2.** iOS and Android: `IO#sync is false by default for STDOUT` | **C** | Seen on both phones. The embedding API sets `$stdout.sync = true` when descriptor 1 is not a terminal (`runtime/mobile/fledge_ruby.c`, line 195), so each line reaches the log as it is printed (the former the former ADR 059, now ADR 078). A terminal gets the same timing without sync mode: Ruby flushes every write to an IO marked `FMODE_TTY` (`io.c`, `io_binwrite_requires_flush_write`, lines 1941 to 1954), and `IO#sync` reads only `FMODE_SYNC` (lines 2805 to 2812) while `IO#tty?` asks `isatty` (lines 5542 to 5548). the former ADR 059 weighed setting `FMODE_TTY` and set it aside because Ruby's header says "You cannot change this" (`include/ruby/io.h`, lines 188 to 192), which is the public API's rule, not the operating system's. Fledge already edits Ruby's source for the phones; an edit to `io.c` that flushes standard output after every write when it is the log's pipe would keep `$stdout.sync` false, `tty?` false, and the timing the former ADR 059 wants. CPython's own choice, line buffering (`Lib/_apple_support.py`, `Lib/_android_support.py`), also leaves its flag apart from its timing. Cost: one scripted edit for both phones, its test, and the former ADR 059, `Parity::MOBILE_JUSTIFIED`'s `$stdout.sync` (`tasks/parity/mobile.rb`, line 63), and `doc/differences_from_ruby.md`. | none |
| **P-J3.** iOS and Android: `RbConfig::CONFIG ['archdir'] returns the directory containing standard libraries C extensions` | **C**, at a high cost | Seen on both phones: the example looks for `archdir/etc.bundle` or `etc.so` (`library/rbconfig/rbconfig_spec.rb`, line 30), and a phone runtime links every extension in. No rule forbids the files: CPython's iOS build keeps each extension module as a framework of its own with a `.fwork` file in `lib-dynload` (PEP 730), and Android loads any `lib*.so` its installer extracts. Closing it means shipping the standard library's extensions as dynamic libraries, against ADR 058 and ADR 067, for one RbConfig example. Not worth it now; recorded so the reason is "Fledge chose static linking", not "a phone cannot". | none |
| **P-J4.** iOS: `(?:File\|File::Stat\|FileTest)[.#](?:setuid\|setgid\|sticky)\? ` | **D**, reason wrong | Seen in the Simulator: 8 examples fail. The reason says the sandbox keeps an app from setting these bits. The examples never ask it: each sets the bit with `system "chmod u+s #{@name}"` or `system "chmod +t #{filename}"` (`core/file/setuid_spec.rb`, line 29; `core/file/sticky_spec.rb`, line 29; `shared/file/setuid.rb`, line 10; `shared/file/sticky.rb`, line 32), and the app cannot start `chmod`. Nobody has tried `File.chmod(04644, path)` in an iOS app. The cause that holds is that iOS gives an app no way to start a program: Apple's SDK marks `system` `__IOS_PROHIBITED` with "On iOS, process spawning is unavailable" (`iPhoneOS.sdk/usr/include/_stdlib.h`, lines 205 to 208, Xcode with the iOS 27.2 SDK). So these belong with P-X5, under that reason, and the pattern is wider than the failures (H4). Before that, one probe in the Simulator would settle whether the sandbox claim is also true: `File.chmod(04644, f); File.setuid?(f)`. | none |
| **P-J5.** iOS: `grpowned? takes non primary groups into account` and `Process.(?:egid\|euid)= sets the effective ... id to its own ... if given the username` | **D**, scope wrong and half matching nothing | Seen: the three `grpowned?` examples and `Process.euid=`. Not seen in either iOS run: `Process.egid=`, which passes, since `Etc.getgrgid` finds the group (`core/process/egid_spec.rb`, lines 25 to 32); that half of the pattern explains nothing (H3). The mechanism is confirmed: Ruby builds with `-D_DARWIN_C_SOURCE` (`configure.ac`, line 1154), which selects Darwin's `getgroups$DARWIN_EXTSN` (`usr/include/unistd.h`, lines 465 to 469 of the iOS Simulator 27.2 SDK), and that `getgroups` fails with EINVAL when `getpwuid(getuid())` finds no user (Libc, `sys/getgroups.c`, lines 35 to 58 at Libc-1752.120.2). But the user it cannot find is 501, the Mac's user, whom the Simulator's directory has no entry for ("can't find user for 501"). On a device apps run as `mobile`, user 501, whom the device's own directory names; these examples may pass there. "An iOS app's C library finds no user" claims all of iOS from the Simulator. In the Simulator it is inherent (A), and any Ruby there would show it; the reason should say so, and say a device is unchecked. CPython takes `getgroups` out on iOS altogether (`configure.ac`, lines 5253 to 5259 at v3.14.0), and its `pwd` and `grp` modules are stubs there. | none |
| **P-J6.** iOS: `Etc.getlogin returns the name associated with the current login activity` | **B** | Seen. The example's only expectation compares `Etc.getlogin` with what `logname` or `id -un` prints, and skips it if neither runs (`library/etc/getlogin_spec.rb`, lines 32 to 38); with neither, MSpec reports no expectation. The SDK's "On iOS, process spawning is unavailable" (as P-J4) is the primary source. In the Simulator the programs are missing (ENOENT) rather than denied. | none |
| **P-J7.** Android: `RbConfig::CONFIG ['(?:AR\|STRIP)'] exists and can be executed` | **A** | Seen. RbConfig names the NDK's `llvm-ar` on the computer that built the runtime, and `strip`; a stock Ruby copied off the computer that built it shows the same, and a phone has no toolchain to point at. | none |
| **P-J8.** Android: `Process.maxgroups sets the maximum number of gids allowed` | **C**, cheap | Seen. Android's filter does stop `setgroups` (bionic, `libc/SECCOMP_BLOCKLIST_APP.TXT`, as Fledge's design cites, confirmed in the AOSP mirror's current file). But `Process.maxgroups=` calls nothing: it stores a number in a static variable (`process.c`, `proc_setmaxgroups`, lines 6845 to 6862 at 2d08b5f42f), and exists only `#ifdef HAVE_SETGROUPS` (line 6835). Telling configure there is no `setgroups` took the setter away with the call. An edit that defines `proc_setmaxgroups` without `HAVE_SETGROUPS`, or P-J9's way, closes it. | none |
| **P-J9.** Android: four examples of `Process.egid=` | **C** | Seen. The filter forbids the calls: `setgid`, `setregid`, `setresgid`, and `setgroups` are in `SECCOMP_BLOCKLIST_APP.TXT` (lines 9 to 30), and CPython's Android build tells configure the same functions are missing, "When these functions are used in an unprivileged process, they crash rather than returning an error" (`configure.ac`, lines 5190 to 5211 at v3.14.0). So Ruby's `NotImplementedError` is what CPython does too. But the kernel's answer to an unprivileged process is fully known, and an app is always one: an app's real, effective, and saved group IDs are equal, and without CAP_SETGID Linux lets `setresgid` set each only to one of them and refuses everything else with EPERM, and refuses every `setgroups`. A shim of a few lines that answers as that kernel would, in place of the call the filter stops, makes `Process.egid=` behave as on a desktop for a user: the TypeError, the EPERM for root, and setting its own group by name would all pass, and `Process.gid=`, `Process.groups=`, and `Process.initgroups` would raise EPERM as a desktop user's do, not `NotImplementedError`. Cost: the shim, its test, and `RuntimeBuilder::Android::CONFIGURE` and the design text that explains it. Risk: an app with group privileges, which no installed app has. | none |
| **P-J10.** Android: `Dir.scan handles character devices` | **B** | Seen: `Errno::EACCES ... /dev`. The example lists the folder of `/dev/null` (`core/dir/scan_spec.rb`, lines 23 to 25). AOSP's policy gives every domain only `search` on `/dev`'s folder, not `read`: `allow domain device:dir search;` (`system/sepolicy`, `public/domain.te`, line 66 at android14-release). | none |
| **P-J11.** Android: `mkmf can be required with --enable-frozen-string-literal` | **A** | Seen. mkmf aborts when Ruby's headers are missing, and a phone app does not carry them; a stock Ruby installed without its headers, as Debian's `ruby` without `ruby-dev`, shows the same. Shipping the headers in every app would close it at the cost of their size, for a library that cannot compile anything on a phone. | none |
| **P-J12.** Android: `Process.spawn uses the passed env['PATH']` and `Kernel#system executes with sh if ... there is no shebang` | **B** | Seen in run 43279374531. Each writes a script into a temporary folder and runs it; Android forbids an app that targets API 29 or later to `execve` a file in its home folder ("Untrusted apps that target Android 10 cannot invoke execve() directly on files within the app's home directory", developer.android.com, Android 10 behavior changes). Termux keeps targeting API 28 for this reason; Play requires a newer target. | none |

### The phones' exclusions

| Entry | Class | Evidence | Examples hidden |
|---|---|---|---|
| **P-X1.** iOS: `command_line` | **B** | Every one of the 32 files starts Ruby through `ruby_exe`, including the two with no `ruby_exe` of their own, which share `command_line/shared/change_directory.rb`. iOS has no ruby program and spawns no process (as P-J4). CPython's `subprocess` refuses on iOS (`_can_fork_exec`, `Lib/subprocess.py`, line 78 at v3.14.0). None would pass. Excluding rather than letting `ruby_exe` skip only keeps 177 skips out of the run. | 176 to 177 (stock's count) |
| **P-X2.** iOS: `core/process/kill_spec.rb` | **C**, cheap | The reason fits 13 of the file's 19 examples, which signal a Ruby they start through `Signalizer` or `Process.spawn`. Six start nothing: the three `ArgumentError` examples, `Process.kill(0, Process.pid)` (lines 11 to 37), and the two that send SIGTERM to the app's own process and check that Ruby's handler runs on the main thread (lines 42 to 75). Those two test something a phone app can meet, a signal to itself while Ruby runs on a thread of the host's, and Android, which runs this file, passes them. Exclude the 13 by name, or let MSpec skip them as `ruby_exe` already skips, and run the 6. | 19, of which 6 would likely pass |
| **P-X3.** iOS: 13 files of Ruby's ways to start a program, and `IO#close on an IO.popen stream sets $?` | **B** for most, **C** for the rest | `spawn_spec.rb`, `kernel/spawn_spec.rb`, `system_spec.rb`, `backtick_spec.rb`, `popen_spec.rb`, `language/execution_spec.rb`, `library/open3`, `wait_spec.rb`, `wait2_spec.rb`, `waitall_spec.rb`, `status/wait_spec.rb`, `io/pid_spec.rb`, `io/tty_spec.rb`. Most examples start the Ruby under test with `ruby_cmd` or `RUBY_EXE`, which `phone_config.rb` does not wrap as it wraps `ruby_exe`. At least 15 start nothing: `Kernel#system` and `Kernel#spawn` are private and `Kernel.system` and `Kernel.spawn` public (4); `Process.wait` and `Process.wait2` raise ECHILD with no children, `Process.waitall` returns `[]` and takes no arguments, and `Process::Status.wait` returns pid -1 (5); `IO#pid` is nil for a file (1); three of `io/tty_spec.rb`'s four, `File.open(__FILE__).tty?` false, a closed IO raising, and `/dev/tty`, which skips on ENXIO (3); and the spawn and popen examples that raise `ArgumentError` or `TypeError` before any child exists (at least 2 more). Whether a missing child "has ended when an example looks" is a race, as the reason says, only for the examples that start one. Wrapping `ruby_cmd` in `phone_config.rb` as `ruby_exe` is wrapped, or excluding by example, would run the rest. Why `io/tty_spec.rb` is listed at all is not said; its fourth example skips unless standard output is a terminal. | about 222 (`it` blocks), of which at least 15 would likely pass |
| **P-X4.** iOS: `Process.setproctitle should set the process title`, `Global variable $0 actually sets the program name` | **B** for the check | Both check through `ProcessSpecs.command_line_include?`, which reads `/proc/PID/cmdline` or runs `ps` (`core/process/fixtures/common.rb`, lines 18 to 25); iOS has no `/proc` and spawns nothing. The exclusion is right that the check cannot run. It hides a question Android's fix answered: an iOS app's Ruby also starts with an argv `fledge_ruby_run` allocates, so Ruby's `setproctitle` likely writes where `KERN_PROCARGS2`, which `ps` reads, never looks, as it did on Android before `setproctitle_c`. Nothing on a device shows a process title to a person, so this ranks low. | 2 |
| **P-X5.** iOS: 4 files and 7 examples that start a program of the system's | **B**, incomplete | `close_read_spec.rb`, `close_write_spec.rb`, and `stat_spec.rb` open `IO.popen("cat")` in `before :each`; `getgrgid_spec.rb` runs `id -gn` as it loads and `id -g` in `before :all`; the 7 examples run `cat`, `id`, or `whoami`. As P-J4, the SDK says process spawning is unavailable. Incomplete: `getpwuid_spec.rb`, `struct_group_spec.rb`, and `struct_passwd_spec.rb` start `id` the same way and are in no list, hidden by H1 instead. | 30 |
| **P-X6.** iOS: 7 files and 6 patterns that fork a child that runs Ruby | **B** on a device, weakly sourced | `kernel/fork_spec.rb` and `process/fork_spec.rb` (the shared `:process_fork`, 10 examples each), `_fork_spec.rb`, `daemon_spec.rb`, `setpgid_spec.rb`, `setpgrp_spec.rb`, `thread/fork_spec.rb`, and 7 examples elsewhere. No primary source is cited. The iOS SDK does not mark `fork` prohibited on iOS, only on watchOS and tvOS (`usr/include/unistd.h`, line 459), and `doc/contributors/design/phone-projects.md` (line 254) says the Simulator, where CI runs, allows it, so these would run there and likely pass. That a device's sandbox denies `fork` is widely reported (OWASP MASTG's jailbreak checks rely on it) and is what CPython assumes (`_can_fork_exec`; "subprocess and multiprocessing are not supported (no fork syscall)", `configure.ac`, line 7732 at v3.14.0), but it is not Apple's word; it is the same kind of borrowed claim that sank `fiddle`'s. A device test would settle it, and needs the maintainer's Apple account. If a device does deny it, there is a better answer than excluding: tell configure iOS has no `fork`, so `Process.respond_to?(:fork)` is false and `fork` raises `NotImplementedError`, as on Windows. Libraries choose their path by `respond_to?(:fork)`, and ruby/spec's own guards would then run the examples written for a Ruby without fork (`_fork_spec.rb`, lines 10 to 14; `daemon_spec.rb`, line 121). Today a device app's Ruby claims a `fork` it cannot use. | about 56 |
| **P-X7.** Android: `Dir#close raises an error if the file descriptor is closed with another Dir instance` | **C**, with a cost | The citation holds: bionic's fdsan aborts when a descriptor tagged for one `DIR` is closed as another's. But fdsan's level is the app's to choose: bionic's public `android_fdsan_set_error_level` (API 29) sets it to warn once or to nothing, and then the second close fails with EBADF and Ruby raises, as on glibc, which is what the example expects. The cost is real: the level is process-wide and also guards the host's Java and native code, so lowering it trades a crash Google wants for parity in one example. The honest reason is "Fledge keeps Android's fdsan at the level Android sets", not that Android forbids it. | 1, which would pass with fdsan lowered |

## Counts

Of the 23 entries, 22 audited:

| Class | Entries |
|---|---|
| A, inherent | 5: D-J1, D-J2, D-J3, P-J7, P-J11 |
| B, forbidden | 7: P-J6, P-J10, P-J12, P-X1, P-X4, P-X5, P-X6 (P-X6 on a device only, without a primary source) |
| C, closable | 8: D-X1, P-J2, P-J3, P-J8, P-J9, P-X2, P-X3, P-X7 |
| D, stale or wrong | 2: P-J4, P-J5 |

Plus the comparison's own four holes, H1 to H4, of which H1 hides three app-only errors and 17 examples on iOS today.

## What to close, ranked

By how much each hides, then by cost.

1. **H1, the reader.** Have `Results.read` take an `An exception occurred during: ACTION ERROR` line as a failure named by its spec file, as it names a file that fails to load. Then add the three `library/etc` files to P-X5, or let them be compared. Cheap; it is a reader that drops differences today.
2. **P-X3 and P-X2, iOS's process files.** Wrap `ruby_cmd` and the `Signalizer` fixture in `phone_config.rb` as `ruby_exe` is wrapped, or exclude by example, and run at least 21 examples that start nothing, among them a signal to the app's own process. Cheap: the harness only.
3. **D-X1, musl's thread name.** Apply the `thread_c` edit to the musl runtimes, as Android has it, until Ruby 4.1.0 brings ruby/ruby 6fdd452087. Cheap; it is a crash any musl app can meet. To confirm the crash on 4.1.0-preview1 first, from the orchestrator (Docker on the Linux machine):

   ```
   ~/bin/machines run linux -- bash -c 'set -e; d=$(mktemp -d); cd "$d"; curl -fsSLO https://github.com/setdef/Fledge/releases/download/v0.12.0/fledge-runtime-0.12.0-x86_64-linux-musl.tar.gz; mkdir r; tar -xzf fledge-runtime-0.12.0-x86_64-linux-musl.tar.gz -C r; docker run --rm -v "$d/r:/r" alpine:3.24 sh -c "R=\$(find /r -path \"*/bin/ruby\" | head -n1); \$R -e \"t = Thread.new { 1 }.join; t.name = %q(x); puts t\"; echo exit=\$?"'
   ```

   A segmentation fault, exit 139, confirms it; the thread's description, exit 0, makes the exclusion stale.
4. **P-J8, `Process.maxgroups=`.** A few lines in Android's `process.c` edits, or P-J9's shim, which closes it too.
5. **P-J9, Android's group calls.** A shim that answers as Linux answers an unprivileged process, in place of the calls the seccomp filter stops. Small; changes `NotImplementedError` to a desktop's EPERM or success across `Process.egid=`, `gid=`, `groups=`, and `initgroups`.
6. **P-J2, `$stdout.sync` on phones.** An `io.c` edit that flushes standard output after each write while it is the log's pipe, keeping `IO#sync` false. Moderate: it reopens the former ADR 059 and touches the mobile parity check.
7. **P-X7, fdsan.** One call, but a process-wide safety trade the maintainer may prefer not to make.
8. **P-X6, iOS's fork.** First a device test (maintainer's Apple account; `doc/contributors/account-tests.md`); if a device denies `fork`, configure iOS without it.
9. **P-J3, archdir.** Dynamic extensions on phones; not worth it for one example.

## What is stale or wrong, ranked

1. **P-J4.** Its reason names the sandbox; the examples fail because they run `chmod`. Rewrite it on the SDK's "process spawning is unavailable", narrow its pattern to the 8 failures, and probe `File.chmod` in the Simulator to learn whether the sandbox claim holds at all.
2. **P-J5.** Its reason claims every iOS app from what the Simulator shows; its `Process.egid=` half matches no failure. Say "in the Simulator", drop `egid`, and list a device check.
3. **D-X1's comment.** "CRuby 4.0.9" is now 4.1.0-preview1.
4. **D-J2 and D-J3.** Due to go when Windows' runtimes leave RubyInstaller's head build for Ruby 4.1.0 (ADR 066); H3's check would catch them then.
5. **`doc/contributors/design/phone-projects.md`, line 254**, "Apple's sandbox denies `fork` on a device", which P-X6 rests on, cites nothing primary.

## Not measured

- Which examples make up H2's gaps. A run with MSpec's specdoc formatter on both sides, compared by name, would list them; on Android that needs the emulator, on iOS the Simulator in the hidden session.
- Whether `File.chmod` sets the set-user-ID and sticky bits in an iOS app (P-J4), and whether `getpwuid(501)` and `fork` work on a device (P-J5, P-X6).
- Whether the six kill examples and the 15 process examples pass in the Simulator (P-X2, P-X3); Android passing the same file suggests so.
