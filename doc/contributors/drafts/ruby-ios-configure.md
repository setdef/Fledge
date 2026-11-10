<!--
SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>

SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Draft: a Ruby bug report, for the maintainer to file

Not filed. For the maintainer to file, if he chooses, at https://bugs.ruby-lang.org/projects/ruby-master/issues/new as a **Bug**, with the subject and the Ruby version below, and everything after the line as the description (the tracker takes Markdown).

Ruby's contributing guide (`doc/contributing/reporting_issues.md` at ruby/ruby master 6214ace537) asks a reporter to search for an existing ticket first, to show the bug on master, to give `ruby -v`, and to keep any reproduction small; it says nothing about AI-assisted reports either way. Before filing: search the tracker for "Unsupported OS X version" and for 3e96f16643, since someone may have reported it after 2026-11-10; and read the description start to finish as your own words, since you are the one filing it. Found in Fledge's Ruby 4.1 spike (`doc/contributors/research/2026-11-09-ruby-4.1-spike.md`).

- **Tracker:** Bug
- **Subject:** configure refuses iOS targets: "Unsupported OS X version is required" since 3e96f16643
- **Ruby version:** ruby 4.1.0preview1 (2026-10-11 master 2d08b5f42f); still present at master 6214ace537
- **Backport:** none needed; 4.0 and older are not affected.

---

Since 3e96f16643 ("Require Mac OS X 10.6 or later"), `configure` stops when Ruby is cross-compiled for iOS (or any other Apple platform that is not macOS):

```
checking if minimum required OS X version is supported... no
configure: error: Unsupported OS X version is required
```

## Cause

The check in `configure.ac` (lines 439 to 451 at master) runs for every `darwin*` target, and an iOS cross build is one (for example `--host=aarch64-apple-darwin` with clang's `-target arm64-apple-ios15.0`):

```c
#include <AvailabilityMacros.h>
#if MAC_OS_X_VERSION_MIN_REQUIRED < __MAC_10_6
#error pre OS X 10.6
#endif
```

When clang targets iOS it defines no `__ENVIRONMENT_MAC_OS_X_VERSION_MIN_REQUIRED__`, so `AvailabilityMacros.h` falls back to a default, `MAC_OS_X_VERSION_10_5` on arm64. Apple publishes the header under the APSL 2.0 ([xnu-12377.121.6, `EXTERNAL_HEADERS/AvailabilityMacros.h`, lines 118 to 133](https://github.com/apple-oss-distributions/xnu/blob/xnu-12377.121.6/EXTERNAL_HEADERS/AvailabilityMacros.h#L118-L133)), and the iPhoneOS 27.2 SDK's copy (lines 96 to 111) has the same code:

```c
#ifndef MAC_OS_X_VERSION_MIN_REQUIRED
    #ifdef __ENVIRONMENT_MAC_OS_X_VERSION_MIN_REQUIRED__
        ...
        #define MAC_OS_X_VERSION_MIN_REQUIRED __ENVIRONMENT_MAC_OS_X_VERSION_MIN_REQUIRED__
    #else
        #if __i386__ || __x86_64__
            #define MAC_OS_X_VERSION_MIN_REQUIRED MAC_OS_X_VERSION_10_4
        #elif __arm__ || __arm64__
            #define MAC_OS_X_VERSION_MIN_REQUIRED MAC_OS_X_VERSION_10_5
        ...
```

So an iOS target always reads as macOS 10.5 and is refused, though it says nothing about macOS at all. Before 3e96f16643, Ruby cross-compiled for iOS with this configure (as xord/cruby does, and as Fledge does for Ruby 4.0.9).

## Reproduction

With Xcode's command line tools, save the check above as `check.c` and preprocess it for each target:

```
$ xcrun --sdk iphoneos clang -target arm64-apple-ios15.0 -E check.c -o /dev/null
check.c:3:2: error: pre OS X 10.6
$ xcrun --sdk iphonesimulator clang -target arm64-apple-ios15.0-simulator -E check.c -o /dev/null
check.c:3:2: error: pre OS X 10.6
$ xcrun --sdk macosx clang -target arm64-apple-macos14.0 -E check.c -o /dev/null
$ xcrun --sdk macosx clang -target x86_64-apple-macos10.5 -E check.c -o /dev/null
check.c:3:2: error: pre OS X 10.6
```

(Apple clang 21.0.0, iPhoneOS and iPhoneSimulator SDKs 27.2; clang's source-context lines are left out.)

## Suggested fix

Apply the check only to macOS, as `TargetConditionals.h` tells it apart:

```diff
     AC_MSG_CHECKING(if minimum required OS X version is supported)
-    AC_PREPROC_IFELSE([AC_LANG_SOURCE([[@%:@include <AvailabilityMacros.h>
-	@%:@if MAC_OS_X_VERSION_MIN_REQUIRED < __MAC_10_6
+    AC_PREPROC_IFELSE([AC_LANG_SOURCE([[@%:@include <TargetConditionals.h>
+	@%:@include <AvailabilityMacros.h>
+	@%:@if TARGET_OS_OSX && MAC_OS_X_VERSION_MIN_REQUIRED < __MAC_10_6
 	@%:@error pre OS X 10.6
```

With that condition, the four targets above give: iOS device passes, iOS Simulator passes, macOS 14.0 passes, and macOS 10.5 is still refused. Checking `defined(__ENVIRONMENT_MAC_OS_X_VERSION_MIN_REQUIRED__)` instead works as well.

---

This report was produced entirely by Claude (Anthropic) via Claude Code. [https://declare-ai.org/1.0.0/total.html](https://declare-ai.org/1.0.0/total.html)
