<!--
SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>

SPDX-License-Identifier: CC-BY-SA-4.0
-->

> Findings of 2026-11-25 on what an app's Ruby reaches on Android with Fiddle alone, for issue #131: the Java VM, a Context and an Activity, calls from Java into Ruby, and Android's main loop. Requested: written by an agent and not reviewed line by line. They change no design document and no ADR; those change with the code.

# Android's views from pure Ruby: what the sources and a probe say

Fledge's Android runtime carries a bridge of its own between Ruby and Java: `Fledge::JNI`, `org.setdef.fledge.RubyProxy`, `fledge_ruby_java_vm` in `runtime/mobile/android.c`, `FledgeRuby.activity()`, and R8 rules for them. A program that uses them runs only under Fledge. Issue #131 asks whether an app's Ruby, with what Ruby gives every program (its standard library and bundled gems, Fiddle among them), can do what that bridge does: reach the Java VM, reach a Context or an Activity, receive calls from Java, and run Android's main loop. These findings answer each question from Android's sources and from a probe run on a phone and on emulators.

## Verdict

- **The Java VM: yes on API 26 and 28 and from API 31, with nothing of Fledge's; on API 29 and 30 only around the linker.** `Fiddle.dlopen("libnativehelper.so")` finds `JNI_GetCreatedJavaVMs` on API 34 and 36, as it should from API 31, where Android made the library public, and `Fiddle::Handle.new(nil)`, the program's handle, finds it on API 26, 28, 34, and 36. On API 29 and 30, where the library lives in the ART module, neither does, and Ruby finds it only by reading `/proc/self/maps` and the library's own symbol table, which found it on both. `libart.so` and `libandroid_runtime.so` are hidden from an app's native code on every release, and `Fiddle::Handle::DEFAULT` does not see the symbol.
- **A Context or an Activity: not through Android's SDK.** No public API gives a program its Application or its Activity; Android hands a Context only to the components it creates. Ruby reaches both through non-SDK members of `android.app.ActivityThread`, all on Android's "unsupported" list, which every target SDK may use today. Once Ruby has the Application, the public `Application.registerActivityLifecycleCallbacks` gives it each Activity that changes state from then on.
- **Calls from Java into Ruby: yes, with no Java class in the APK.** ART does not implement JNI's `DefineClass`, and the SDK has no public class that turns an interface call into a native call. Ruby writes a dex file of one class in memory (112 lines, with `zlib` and `digest`), loads it with `dalvik.system.InMemoryDexClassLoader` (API 26), binds the class's native method to a `Fiddle::Closure` with `RegisterNatives`, and makes listeners with `java.lang.reflect.Proxy`. A `Runnable`, a `View.OnClickListener` tapped on the screen, and `Application.ActivityLifecycleCallbacks` all reached Ruby.
- **The main loop: Ruby calls `Looper.loop()` itself,** nested inside the message that started it, and every later message, tap, and lifecycle call arrives from that loop on Ruby's main thread. `Thread.main` is then the process's main thread, as it is under `ruby main.rb`; when Fledge's host runs Ruby on a thread of its own, as it does today for `kind: console`, it is not.

So Basket can drive Android's views from its own Ruby, and the runtime needs none of the pieces #131 removes. Basket leaves what Android documents for apps in two places, the first Context on every release and the VM on API 29 and 30, and each is a decision (see "Decisions the implementation needs").

## The probe

The probe is a Ruby program of 270 lines and the dex writer of 112 in "Appendix: the dex writer", which require only `fiddle`, `zlib`, and `digest/sha1`. It does not load `fledge/jni`. `fledge build android` built it, as two apps, from Fledge 0.17.0's released Android runtime, which has none of the pieces above: no `JNI_OnLoad`, no `fledge_ruby_java_vm`, no `RubyProxy`, no `FledgeRuby.activity()`. The probe looked `fledge_ruby_java_vm` up only to show it absent, and Fiddle answered `unknown symbol "fledge_ruby_java_vm"` everywhere.

- **`org.example.probe.windowed`** has a host `MainActivity` that posts one message to the main looper in `onCreate` and calls 0.17.0's `FledgeRuby.runApp` from it, as trunk's `FledgeRuby.startAppOnMainThread` does. The host hands Ruby nothing.
- **`org.example.probe.console`** has a host that calls `FledgeRuby.startApp`, which runs Ruby on a thread of its own with a 64 MB stack, as trunk's template does for `kind: console`.

Each was installed, launched with `adb shell monkey`, tapped in the middle of the screen with `adb shell input tap`, sent home with `keyevent 3`, and launched again; the probe printed each finding to logcat. They ran on:

| Device | Android | API | ABI |
|---|---|---|---|
| An arm64 Android phone | 14 | 34 | arm64-v8a |
| The emulator `mise.android.toml` pins, `google_apis` image 36-r07 | 16 | 36 | x86_64 |
| An emulator, Google's `google_apis` image `x86_64-30_r16.zip` | 11 | 30 | x86_64 |
| An emulator, Google's `google_apis` image `x86_64-29_r13.zip` | 10 | 29 | x86_64 |
| An emulator, Google's `google_apis` image `x86_64-28_r11.zip` | 9 | 28 | x86_64 |
| An emulator, Google's `google_apis` image `x86_64-26_r16.zip` | 8.0 | 26 | x86_64 |

The four older images are not among the project's pins: the run downloaded each from `dl.google.com` and checked it against the SHA-1 that Google's repository index, `sys-img/google_apis/sys-img2-3.xml`, lists for it. The probe gained its `/proc/self/maps` route and its `dladdr` report after its run on API 26, so that column of section 1 has no answer for them.

## Sources

Every source was read at a tag, from a clone made for this note:

- AOSP's `platform/bionic` at `android-8.0.0_r1` and `android-16.0.0_r1` (the dynamic linker), `platform/libnativehelper` at `android-8.0.0_r1`, `android-11.0.0_r1`, `android-12.0.0_r1`, and `android-16.0.0_r1`, `platform/system/core` at the same four tags (`rootdir/etc/public.libraries.android.txt`), `platform/art` at `android-8.1.0_r1`, `android-9.0.0_r1`, and `android-16.0.0_r1`, and `platform/libcore` at `android-16.0.0_r1`, all from `android.googlesource.com`, since github.com/aosp-mirror holds no `libnativehelper`, `art`, or `system/core`.
- aosp-mirror's `platform_frameworks_base` at `android-9.0.0_r1` (the hidden API lists of Android 9), `android-11.0.0_r1`, and `android-16.0.0_r1`, AOSP's `platform/frameworks/base` at `android-8.0.0_r1`, and AOSP's `platform/frameworks/native` at `android-16.0.0_r1`.
- The Android SDK's own list of when each public class and method arrived, `platforms/android-36/data/api-versions.xml` (platform 36-r02, the one `mise.android.toml` pins).
- fiddle 1.1.8, the version Ruby 4.1.0-preview1 bundles, as installed with that Ruby.
- Google Play's Device and Network Abuse policy, as `2026-10-27-mobile.md` (section 4) and `2026-11-04-app-stores.md` quote it. This note's author could not fetch Google's pages, so no policy text here is newer than those notes.

## 1. The Java VM

### What the probe found

| Route | API 26 | API 28 | API 29 | API 30 | API 34 (phone) | API 36 |
|---|---|---|---|---|---|---|
| `Fiddle.dlopen("libnativehelper.so")` | not found | not found | not found | not found | one VM | one VM |
| `Fiddle::Handle.new(nil)` | one VM | one VM, from `/system/lib64/libnativehelper.so` | `unknown symbol` | `unknown symbol` | one VM, from `/system/lib64/libandroid_runtime.so` | one VM, from `/system/lib64/libandroid_runtime.so` |
| `libnativehelper.so` as `/proc/self/maps` and its `.dynsym` place it | not run | one VM, from `/system/lib64/libnativehelper.so` | one VM, from `/apex/com.android.runtime/lib64/libnativehelper.so` | one VM, from `/apex/com.android.art/lib64/libnativehelper.so` | one VM, from `/apex/com.android.art/lib64/libnativehelper.so` | one VM, from `/apex/com.android.art/lib64/libnativehelper.so` |
| `Fiddle::Handle::DEFAULT` | `unknown symbol` | `unknown symbol` | `unknown symbol` | `unknown symbol` | `unknown symbol` | `unknown symbol` |
| `Fiddle.dlopen("libart.so")`, `Fiddle.dlopen("libandroid_runtime.so")` | not found | not found | not found | not found | not found | not found |

"Not found" is Fiddle's `dlopen failed: library "libnativehelper.so" not found` (or the library named), and `unknown symbol` its `unknown symbol "JNI_GetCreatedJavaVMs"`. Each route that found a VM found the same pointer, and the library named after it is the one `dladdr` named for the function the route found. `GetEnv` with JNI 1.6 then gave the calling thread's `JNIEnv` (status 0) on Android's main thread and on the thread `FledgeRuby.startApp` makes, which Java started and so had attached.

The whole of the route through the program's handle, in Ruby, which from API 31 works with `Fiddle.dlopen("libnativehelper.so")` in place of `Fiddle::Handle.new(nil)`:

```ruby
require "fiddle"

process = Fiddle::Handle.new(nil) # dlopen(NULL): the program and what it loaded globally
created = Fiddle::Function.new(process["JNI_GetCreatedJavaVMs"],
  [Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT, Fiddle::TYPE_VOIDP], Fiddle::TYPE_INT)
vms = Fiddle::Pointer.malloc(Fiddle::SIZEOF_VOIDP, Fiddle::RUBY_FREE)
count = Fiddle::Pointer.malloc(Fiddle::SIZEOF_INT, Fiddle::RUBY_FREE)
created.call(vms, 1, count) # => 0, and count holds 1
java_vm = vms[0, Fiddle::SIZEOF_VOIDP].unpack1("J")
```

### Why, from the sources

- **The program's handle.** fiddle 1.1.8 passes `nil` to `dlopen` as `NULL` (`ext/fiddle/handle.c`, lines 145 to 157 and 183). bionic answers `dlopen(NULL)` with the main executable's `soinfo` (`linker/linker.cpp`, lines 1686 and 1687 at `android-8.0.0_r1`, lines 1860 and 1861 at `android-16.0.0_r1`), and looks a symbol up through that handle in every `RTLD_GLOBAL` library of the default namespace: "Since RTLD_GLOBAL is always set for the main executable and all dt_needed shared libraries ... we can just execute dlsym(RTLD_DEFAULT, ...)" (`linker.cpp`, lines 780 to 793 at `android-8.0.0_r1`, lines 836 to 849 at `android-16.0.0_r1`). The libraries an executable needs are loaded with `RTLD_GLOBAL` (`linker_main.cpp`, line 368 at `android-8.0.0_r1`, lines 448 to 459 at `android-16.0.0_r1`). An app's process is zygote's, `app_process`, which at `android-8.0.0_r1` needs `libandroid_runtime` (`cmds/app_process/Android.mk`, line 4), which needs `libnativehelper` (`core/jni/Android.mk`, line 246), both in `/system` and so in the default namespace; `libnativehelper.so` exports `JNI_GetCreatedJavaVMs` at every tag read (`JniInvocation.cpp`, lines 184 and 185 at `android-8.0.0_r1`; `libnativehelper.map.txt`, line 8 at `android-11.0.0_r1` and line 11 at `android-12.0.0_r1` and `android-16.0.0_r1`). bionic's comment there gives the reason, "According to man dlopen(3) and posix docs in the case when si is handle of the main executable we need to search not only in the executable and its dependencies but also in all libraries loaded with RTLD_GLOBAL", so the probe's lookup means on Android what it means under `ruby main.rb` on Linux: a symbol of a library the process has loaded.
- **`libnativehelper.so` by name, from API 31.** At `android-12.0.0_r1` the library's map puts `JNI_GetCreatedJavaVMs` in the version `LIBNATIVEHELPER_S { # introduced=S`, under "JNI Invocation methods available to platform and apps" (`libnativehelper.map.txt`, lines 1 to 11), and `public.libraries.android.txt` lists `libnativehelper.so` (line 20; line 21 at `android-16.0.0_r1`). At `android-8.0.0_r1` and `android-11.0.0_r1` the list does not name it. ART's native loader gives an app's code a namespace in which "only the public native libraries that is listed in `/system/etc/public.libraries.txt` are available from the platform", and "it is prohibited for a device manufacturer to expose an AOSP-defined private library, e.g. libgui.so, libart.so, etc., to APKs" (`libnativeloader/README.md`, lines 25 to 31 and 53 to 55 at `android-16.0.0_r1`). That is why `libart.so` and `libandroid_runtime.so` are "not found".
- **`RTLD_DEFAULT`.** bionic searches the caller's namespace, skipping every library not loaded `RTLD_GLOBAL`, and then the caller's own dependencies (`linker.cpp`, lines 797 to 825 at `android-16.0.0_r1`). An app's namespace, which is not shared, starts with only its parent's shared group (lines 2527 to 2529; `linker_namespaces.cpp`, lines 120 to 150), which holds the executable but not its libraries, and the caller here is `fiddle.so`, none of whose dependencies defines `JNI_GetCreatedJavaVMs`, as `unknown symbol` shows.
- **API 29 and 30: the ART module.** At `android-11.0.0_r1` libnativehelper is built for the ART module's APEXes, `com.android.art.release` and `com.android.art.debug` (its `Android.bp`, lines 67, 68, and 97 to 99), and `libandroid_runtime` links it as a shared library (frameworks/base `core/jni/Android.bp`, lines 46 to 53). The probe found the function there mapped from `/apex/com.android.runtime/lib64/libnativehelper.so` on API 29 and from `/apex/com.android.art/lib64/libnativehelper.so` on API 30, and `dlopen(NULL)`, which searches the default namespace's list, did not find it. At `android-16.0.0_r1` `libandroid_runtime` links `libnativehelper_lazy` statically instead (`core/jni/Android.bp`, lines 284 to 292), the "Lazy loading version of libnativehelper that can be used by code that is running before the ART APEX is mounted" (libnativehelper's `Android.bp`, lines 164 to 168), whose `JNI_GetCreatedJavaVMs` calls libnativehelper's once it is loaded (`libnativehelper_lazy.c`, lines 210 to 220 at `android-12.0.0_r1`). That copy, in a library of the default namespace, is the one `dladdr` named on API 34 and 36.
- **The mapped route.** `/proc/self/maps` lists every file the process has mapped, and the library's file is readable, so Ruby reads its section headers, finds `.dynsym` and its strings, and adds the symbol's value to the address where the file starts. It finds a function in a library that the native loader keeps out of the app's namespace on purpose (the README, above). The probe used it only to learn whether the VM is reachable at all where no `dlopen` route reaches it.

### What it implies

- **For the runtime:** nothing in Fledge's Ruby has to change for an app to reach the VM. `JNI_OnLoad`, `fledge_ruby_java_vm`, and the embedding API's row for it can go.
- **For Basket:** the lines above, with `libnativehelper.so` by name from API 31, the NDK's documented way, the program's handle on API 26 to 28 (27 not run), and the mapped route, 22 lines of the probe's, on API 29 and 30.

## 2. A Context or an Activity

A view needs a Context, and `setContentView` an Activity. Android gives a Context to the components it creates (an Activity, a Service, an Application, a ContentProvider) and to nothing else.

### What the probe found

| Call, through JNI from Ruby | Result | Android's list |
|---|---|---|
| `ActivityThread.currentApplication()` | the app's `android.app.Application` | unsupported |
| `AppGlobals.getInitialApplication()` | the same object | unsupported |
| `ActivityThread.currentActivityThread().mActivities`, then `ActivityClientRecord.activity` | the host's `MainActivity`, one of one | unsupported, both fields |
| `Thread.currentThread().getContextClassLoader()` (public) | the app's `PathClassLoader`, which is no Context | SDK |
| `Application.registerActivityLifecycleCallbacks` with a Ruby proxy (public) | every later lifecycle call, each with its Activity | SDK |

On the main thread the probe then made a `TextView` on that Activity, gave it a click listener written in Ruby, and put it on the screen with `Activity.setContentView`; the tap reached Ruby as `onClick` with the `TextView`, laid out at the phone's full width. Sending the app home and back reached Ruby as `onActivityPaused` and `onActivityResumed` (and on API 36 the `Pre` and `Post` calls around each), each with the same `MainActivity`.

ART logged each field it gave Ruby: `hiddenapi: Accessing hidden field Landroid/app/ActivityThread;->mActivities:Landroid/util/ArrayMap; (runtime_flags=0, domain=platform, api=unsupported) from Lorg/setdef/fledge/FledgeRuby; (domain=app, TargetSdkVersion=36) using JNI: allowed` (the phone's wording), and the same for `ActivityClientRecord.activity`. It logged no line for the two methods, since ART's JNI logs a method only when it denies it (`runtime/jni/jni_internal.cc`, lines 496 to 510 at `android-16.0.0_r1`).

### Why, from the sources

- **No public accessor.** `android.app.ActivityThread` is `{@hide}` (`core/java/android/app/ActivityThread.java`, lines 304 to 306 at `android-16.0.0_r1`), and the SDK's `api-versions.xml` lists no such class. Its `currentActivityThread()`, `currentApplication()`, `mActivities`, and `ActivityClientRecord.activity` are each `@UnsupportedAppUsage` (lines 2911 to 2914, 2946 to 2950, 414 and 415, and 621 and 622), with no `maxTargetSdk`, and so is `AppGlobals.getInitialApplication()`, of another `@hide` class (`core/java/android/app/AppGlobals.java`, lines 25, 32, and 33).
- **What "unsupported" allows.** ART files a member annotated so as `kUnsupported`, "Values independent of target SDK version of app", whose highest target SDK is `SdkVersion::kMax`, against the `max-target-*` lists, which stop at a release (`libartbase/base/hiddenapi_flags.h`, lines 92 to 111 and 175 to 184 at `android-16.0.0_r1`). So an app that targets API 36, as Play requires of new apps, may use all four. Android 9, the first release with these checks, put all four on its light greylist (`config/hiddenapi-light-greylist.txt`, lines 176, 226, 227, and 249 at `android-9.0.0_r1`); ART at `android-8.1.0_r1` has no `runtime/hidden_api.cc` at all, so API 26 and 27 check nothing.
- **A loophole not to use.** ART takes the class of the first Java frame on the stack as the caller of a JNI lookup, and "If the calling class cannot be determined, e.g. unattached threads, we conservatively assume the caller is trusted" (`jni_internal.cc`, lines 249 to 257). A thread Ruby made and attached has no Java frame, so on it even blocked members would answer. This note relies on nothing that needs that.
- **The first Activity.** Ruby starts in a message posted after `onCreate`, when the Activity has already started and resumed, so lifecycle callbacks registered then report only later changes, as the probe saw. A public route to the first Activity would need Ruby running before the Activity starts; this note did not try one (see "What stays unproven").

### What it implies

- **For the runtime:** `FledgeRuby.activity()` can go. Whatever Basket uses instead is Basket's own code.
- **For Basket:** the Application through `ActivityThread.currentApplication()`, the first Activity through `mActivities`, and each later one through `Application.ActivityLifecycleCallbacks`, which Basket already implements for the Activity Android makes when the phone turns. Four non-SDK members, two methods and two fields, which a future Android may restrict.

## 3. Calls from Java into Ruby

A listener is an object of a Java interface, and Java calls its methods. Something on the Java side has to turn that call into a call of native code.

### What the probe found

- `DefineClass` through JNI returned `NULL`, and ART logged `JNI DefineClass is not supported`, on every device: ART's `DefineClass` is only that log line and `return nullptr` (`runtime/jni/jni_internal.cc`, lines 668 to 671 at `android-16.0.0_r1`).
- The probe's dex writer made a dex file, version 035, of one class, `basket.Handler`, that implements `java.lang.reflect.InvocationHandler`, with a public constructor and one method, `invoke`, declared `native`. Android's `dexdump` read it back as that class.
- `new InMemoryDexClassLoader(ByteBuffer.wrap(bytes), ClassLoader.getSystemClassLoader())` loaded it, `loadClass("basket.Handler")` returned the class, `RegisterNatives` bound `invoke` to a `Fiddle::Closure::BlockCaller` of five pointers (status 0), and `Proxy.newProxyInstance` made one object of `Runnable`, `View.OnClickListener`, and `Application.ActivityLifecycleCallbacks` with an instance of the class as its handler.
- Java then called Ruby: `toString` as Ruby logged the proxy, `run` when Ruby called it through JNI, `run` again when the main looper ran it from `Handler.post`, `onClick` for a tap, and the lifecycle calls for leaving and returning. Each call came on the thread Ruby had run on, and in it `Thread.current == Thread.main` held: Android's main thread for the windowed probe, and the thread `FledgeRuby.startApp` makes for the console probe, which ran only the calls Ruby made itself.

### Why, from the sources

- **No simpler public route.** `java.lang.reflect.Proxy` needs an `InvocationHandler`, which is an interface itself. The SDK's `api-versions.xml` has no `java.lang.invoke.MethodHandleProxies`, Java's other way to make an interface's object from a function. `InMemoryDexClassLoader(ByteBuffer, ClassLoader)` is public "since 26" (`api-versions.xml`, lines 81279 to 81281), the runtime's floor, and "can be used to execute code that has not been written to the local file system" (`dalvik/src/main/java/dalvik/system/InMemoryDexClassLoader.java`, lines 22 to 27 at libcore's `android-16.0.0_r1`). `Proxy.newProxyInstance` makes its class at run time with ART's native `generateProxy` (`ojluni/src/main/java/java/lang/reflect/Proxy.java`, lines 802 and 854), so nothing about a proxy is in the APK either.
- **Threads.** A Fiddle closure takes Ruby's lock with `rb_thread_call_with_gvl` when the calling thread does not hold it (`ext/fiddle/closure.c`, lines 229 to 232), and a Fiddle call lets the lock go unless the function asks for it (`ext/fiddle/function.c`, lines 381 to 385). So a callback works on any thread Ruby made, and ends the process on any other, as `doc/contributors/design/phone-widgets.md`, "Threads", cites from `thread.c`. The probe gave Java no other thread to call from.

### What it implies

- **For the runtime:** `RubyProxy`, its R8 rule, and `FledgeRuby`'s calls of `RubyProxy.rubyEnded()` can go. No R8 rule is needed for the class Ruby writes, since it is not in the APK.
- **For Basket:** the dex writer, about 120 lines, and the dispatch from `invoke` to its Ruby objects. `RubyProxy.rubyEnded` exists because Android's main thread went on delivering clicks after Ruby's closures were gone (`phone-widgets.md`, "The Android bridge"); with the closures Basket's own, keeping them alive, or answering after Ruby ends, is Basket's to do, and under the nested loop of section 4 Ruby does not end while the app runs.

## 4. The main loop and the thread

### What the probe found

| | `Process.pid` | `Thread.main.native_thread_id` | Same? |
|---|---|---|---|
| `ruby -e` on glibc Linux (Ruby 4.1.0-preview1, x86_64) | 1804764 | 1804764 | yes |
| Windowed probe, Ruby on Android's main thread, API 34 phone | 16507 | 16507 | yes |
| Console probe, Ruby on `FledgeRuby.startApp`'s thread, API 34 phone | 16942 | 17017 | no |
| Windowed probe, API 36 | 2234 | 2234 | yes |
| Console probe, API 36 | 4288 | 4308 | no |
| Windowed probe, API 26 | 4260 | 4260 | yes |
| Console probe, API 26 | 5067 | 5084 | no |
| Windowed probe, API 28 | 3624 | 3624 | yes |
| Console probe, API 28 | 5562 | 5580 | no |
| Windowed probe, API 29 | 3780 | 3780 | yes |
| Console probe, API 29 | 6275 | 6299 | no |
| Windowed probe, API 30 | 3315 | 3315 | yes |

The windowed probe called `Looper.loop()` through JNI as its last line. On API 30, 34, and 36 Android logged `Loop again would have the queued messages be executed before this one completed.` once, and on API 26, 28, and 29 nothing; on each the loop never returned, and every later message (a posted `Runnable`, the tap, the lifecycle calls) reached Ruby from it, on Ruby's main thread.

### Why, from the sources

- **Every Android program starts inside a loop it does not own.** `ActivityThread.main` prepares the main looper and loops, and throws if the loop ever ends: "Main thread loop unexpectedly exited" (`ActivityThread.java`, lines 9038, 9067, and 9069 at `android-16.0.0_r1`). Every component's code, and so every host's call into Ruby, runs inside one of that loop's messages. Ruby cannot return to that loop and keep running, so a program that stays on the main thread loops itself: `Looper.loop()`, public since API 1 (`api-versions.xml`, lines 49596 and 49603), which Android allows a second time and only warns of (`core/java/android/os/Looper.java`, lines 314 to 324 at `android-16.0.0_r1`); at `android-9.0.0_r1` `Looper.loop` has no such check, which is why API 26 and 28 logged nothing (the probe logged none on API 29 either, and on API 30 the warning; Looper at `android-10.0.0_r1` and `android-11.0.0_r1` was not read).
- **What blocking the main thread costs.** While Ruby runs on the main thread and has not entered the loop, no message of the main looper runs, and so no frame is drawn and no input event is handled. Android's input dispatcher gives an app `UNMULTIPLIED_DEFAULT_DISPATCHING_TIMEOUT_MILLIS = 5000` to take an event, multiplied by the device's `ro.hw_timeout_multiplier` (`libs/input/android/os/IInputConstants.aidl`, lines 22 to 26 in frameworks/native at `android-16.0.0_r1`), and past it reports the app as not responding; the probe did not block the main thread to see that.

### What it implies

- **The truer Ruby, for every kind,** is Ruby on Android's main thread: only there is `Thread.main` the process's main thread, as under `ruby main.rb`. Fledge's host already does that for `kind: windowed` (`FledgeRuby.startAppOnMainThread`); for `kind: console` it does not, and the probe shows the difference a program can read.
- **How a program's own Ruby enters the loop:** `Looper.loop()` through JNI, which is `Fledge::JNI.loop`'s one line made Basket's own. Nothing of Fledge's is needed for it.

## Decisions the implementation needs

Each is listed with its options, the evidence, and a recommendation. The first, the floor in the second, and the fourth change what Fledge offers, supports, or does, and are the maintainer's to make; the rest are the implementation's.

1. **Where Basket gets its first Context.**
   - *Non-SDK `ActivityThread` members from Basket's own Ruby* (recommended): `currentApplication()` for the Application, `mActivities` for the first Activity, public lifecycle callbacks afterwards. Proven on API 26, 28, 29, 30, 34, and 36; all "unsupported", allowed for every target SDK today and logged for the fields. The risk is a future Android that moves them to a blocked list, which would break Basket and not Fledge.
   - *A public route that starts Ruby before the Activity starts*, so that public lifecycle callbacks report the first Activity too, from a host that runs Ruby earlier (from `Application.onCreate`, say). It still needs the Application, which only `currentApplication()` or a handover gives, so it leaves one non-SDK member of the four; untried.
   - *A handover from Fledge's host* (today's `FledgeRuby.activity()`, or a static field of the template's `MainActivity` read by name): no non-SDK member, but it is a Fledge API by another name, which #131 removes.
2. **How Basket finds the Java VM, and Android 10 and 11.** No `dlopen` route reaches the VM on API 29 and 30.
   - *Three routes in Basket's Ruby* (recommended): `Fiddle.dlopen("libnativehelper.so")` from API 31, the NDK's documented library; the program's handle on API 26 to 28; and on API 29 and 30 the mapped route, 22 lines, which found the VM on both, and with it every other part of the probe ran on API 29 and 30 as on the other releases. It reads around the linker namespace on two releases, which is Basket's choice and nothing of Fledge's.
   - *A floor of API 31 for an app whose Ruby calls Java*, or for every app: one documented route, and Android 8.0 to 11 left out. It changes what Fledge supports, so it is the maintainer's.
   - *`libfledgeruby.so` exporting JNI's own `JNI_GetCreatedJavaVMs`*, from the VM `JNI_OnLoad` is given: `Fiddle::Handle::DEFAULT` would then find it on every release, through the caller's dependencies (`linker.cpp`, lines 814 to 825), so an app would call only JNI's name. Untried, and it keeps a piece of C that exists only for the app to call, which #131 removes.
3. **How Java calls Basket.** Ruby's in-memory dex with `RegisterNatives` and `Proxy` (recommended, proven), or a Java class in Basket's tree, which would put a language other than Ruby in the example, against AGENTS.md's "no example asks for one".
4. **Which thread runs Ruby for `kind: console`.**
   - *Android's main thread, for every kind* (recommended, as the truer Ruby): `Thread.main` is the process's main thread everywhere. A program that runs long and never enters the loop leaves the host's screen frozen and is reported as not responding after an input event waits 5 seconds, as a native app that blocks its main thread is; a program whose screen must answer enters the loop or works on threads of its own, as an Android app must.
   - *A thread of its own for `kind: console`* (today): the screen never freezes, and `Thread.main.native_thread_id != Process.pid`, a difference `Parity::MOBILE_JUSTIFIED` would have to justify.
   - Whichever is chosen for Android, iOS (#130) faces the same question with UIKit's main thread.

## What Basket's own bridging would cost

From the probe's size, and the pieces Basket needs that the probe already has:

| Piece | Lines, about |
|---|---|
| The VM by the three routes of section 1, each thread's `JNIEnv`, and attaching a thread Ruby made | 45 |
| JNI's function table: classes, method IDs, calls by return type, strings as UTF-16, exceptions as Ruby exceptions | 80 |
| The dex writer | 120 |
| A listener's dispatch from `invoke` to a Ruby object, with Java's arguments unboxed and its result boxed | 60 |
| The Application and the first Activity | 20 |

About 325 lines in Basket's `lib/`, where `Fledge::JNI` is 762 lines and `RubyProxy` 82. The difference is mostly `Fledge::JNI`'s overload resolution by reflection, which a program that spells out each method's JNI signature, from the types Android's reference lists, does without. These counts are estimates; the probe's code is 270 and 112 lines, and does less than Basket needs.

## Google Play

- **The in-memory dex.** The Device and Network Abuse policy, as `2026-10-27-mobile.md` quotes it: "an app may not download executable code (such as dex, JAR, .so files) from a source other than Google Play." The dex Basket writes is made by code in its APK, from bytes in its APK, and nothing is downloaded. The same note quotes the policy's rule on interpreted code "loaded at run time (for example, not packaged with the app)", which Basket's Ruby, packaged with the app, is not.
- **Non-SDK interfaces, and the mapped route.** The policy text on record says nothing of either: of members on Android's non-SDK lists, or of reading a platform library's symbols from `/proc/self/maps`. Android's documentation page on restrictions on non-SDK interfaces, and whatever Play's pre-launch report says of them, were not read for this note.
- **The target SDK.** "Starting August 31 2026: New apps and app updates must target Android 16 (API level 36) or higher" (`2026-11-04-app-stores.md`, quoting Google's target-SDK page); the "unsupported" list is open to that target, as section 2 shows.

## What stays unproven

- **An app on Google Play.** No app has been submitted with an in-memory dex or with these non-SDK members; that needs an account (`doc/contributors/account-tests.md`).
- **The policy and documentation text.** The quotes above are those earlier notes took; this note's author could not fetch Google's pages, so a change since then is unseen.
- **A future Android.** Whether a later release restricts `currentApplication()`, `mActivities`, or `ActivityClientRecord.activity`.
- **Android 8.1, 12, 12L, 13, and 15** (API 27, 31 to 33, and 35). Not run; what this note says of API 31 to 33 rests on the sources at `android-12.0.0_r1` and the runs on API 34 and 36.
- **Other builds of Android.** API 26 to 30 ran only on Google's x86_64 images, and API 34 on one arm64 phone. The program's handle finds the VM only through what zygote's `app_process` loaded globally, which a device's maker can change, and the mapped route depends on the library's file being readable where it is mapped.
- **A release build with R8, and 16 KB pages.** The probe ran from debug APKs, on 4 KB pages only.
- **A public route to the first Activity,** and starting Ruby before the Activity starts; not tried.
- **Callbacks on a thread Ruby made, and threads Ruby attaches and detaches,** which `Fledge::JNI` does today; not run.
- **Speed.** Nothing was timed; every call crosses Fiddle, as it does today.

## Appendix: the dex writer

The probe's dex writer, as it ran on every device above. It writes the header, the string, type, prototype, and method ids, one class definition, and then the data: the constructor's code, two type lists, the strings, the class's data, and the map of sections. ART's `DexFileVerifier` refuses ids out of order (`libdexfile/dex/dex_file_verifier.cc`, line 283 at `android-16.0.0_r1`) and a map whose items are out of order (line 763), and checks the header's Adler-32 checksum (from line 660), so the writer sorts each list and fills in the SHA-1 signature and the checksum last. `dexdump` from build-tools 36.0.0 reads its output as `basket.Handler`, with `<init>` calling `Object.<init>` and `invoke` marked `PUBLIC NATIVE`.

```ruby
# frozen_string_literal: true

require "zlib"
require "digest/sha1"

# A dex file of one class, written in Ruby: a public class NAME that
# implements java.lang.reflect.InvocationHandler, with a public
# constructor that calls Object's, and the interface's one method,
# invoke, declared native, so that RegisterNatives can give it code.
# Version 035, its ids sorted, as ART's DexFileVerifier requires.
module Dex
  OBJECT = "Ljava/lang/Object;"
  HANDLER = "Ljava/lang/reflect/InvocationHandler;"
  METHOD = "Ljava/lang/reflect/Method;"
  OBJECTS = "[Ljava/lang/Object;"
  NO_INDEX = 0xffffffff

  def self.uleb(value)
    bytes = +"".b
    loop do
      byte = value & 0x7f
      value >>= 7
      bytes << (value.zero? ? byte : byte | 0x80)
      return bytes if value.zero?
    end
  end

  def self.handler_class(name)
    descriptor = "L#{name.tr('.', '/')};"
    strings = ["<init>", "LLLL", descriptor, OBJECT, HANDLER, METHOD, "V", OBJECTS, "invoke"].sort
    s = ->(text) { strings.index(text) }
    types = [descriptor, OBJECT, HANDLER, METHOD, "V", OBJECTS].sort_by { |t| s[t] }
    t = ->(text) { types.index(text) }
    # proto 0: (Object, Method, Object[]) Object; proto 1: ()V
    protos = [[s["LLLL"], t[OBJECT], [t[OBJECT], t[METHOD], t[OBJECTS]]], [s["V"], t["V"], []]]
    protos.sort_by! { |shorty, ret, params| [ret, params] }
    invoke_proto = protos.index { |p| p[1] == t[OBJECT] }
    init_proto = protos.index { |p| p[1] == t["V"] }
    methods = [[t[descriptor], init_proto, s["<init>"]], [t[descriptor], invoke_proto, s["invoke"]], [t[OBJECT], init_proto, s["<init>"]]]
    methods.sort_by! { |klass, proto, name_idx| [klass, name_idx, proto] }
    m_init = methods.index([t[descriptor], init_proto, s["<init>"]])
    m_invoke = methods.index([t[descriptor], invoke_proto, s["invoke"]])
    m_object_init = methods.index([t[OBJECT], init_proto, s["<init>"]])

    header_size = 0x70
    string_ids_off = header_size
    type_ids_off = string_ids_off + strings.size * 4
    proto_ids_off = type_ids_off + types.size * 4
    method_ids_off = proto_ids_off + protos.size * 12
    class_defs_off = method_ids_off + methods.size * 8
    data_off = class_defs_off + 32

    data = +"".b
    align = ->(n) { data << "\0" * ((-(data_off + data.bytesize)) % n) }
    here = -> { data_off + data.bytesize }

    # code_item of <init>: invoke-direct {v0}, Object.<init>; return-void
    align[4]
    code_off = here[]
    data << [1, 1, 1, 0, 0, 4].pack("vvvvVV")
    data << [0x1070, m_object_init, 0x0000, 0x000e].pack("vvvv")

    # type_lists: the interfaces, and invoke's parameters
    align[4]
    interfaces_off = here[]
    data << [1, t[HANDLER]].pack("Vv")
    align[4]
    params_off = here[]
    data << [3, t[OBJECT], t[METHOD], t[OBJECTS]].pack("Vvvv")

    string_data_offs = strings.map do |text|
      off = here[]
      data << uleb(text.size) << text.b << "\0"
      off
    end

    class_data_off = here[]
    data << uleb(0) << uleb(0) << uleb(1) << uleb(1)
    data << uleb(m_init) << uleb(0x10001) << uleb(code_off)
    data << uleb(m_invoke) << uleb(0x0101) << uleb(0)

    align[4]
    map_off = here[]
    map = [
      [0x0000, 1, 0], [0x0001, strings.size, string_ids_off], [0x0002, types.size, type_ids_off],
      [0x0003, protos.size, proto_ids_off], [0x0005, methods.size, method_ids_off], [0x0006, 1, class_defs_off],
      [0x2001, 1, code_off], [0x1001, 2, interfaces_off], [0x2002, strings.size, string_data_offs.first],
      [0x2000, 1, class_data_off], [0x1000, 1, map_off],
    ]
    data << [map.size].pack("V")
    map.each { |type, size, off| data << [type, 0, size, off].pack("vvVV") }

    body = +"".b
    body << string_data_offs.pack("V*")
    body << types.map { |text| s[text] }.pack("V*")
    protos.each { |shorty, ret, params| body << [shorty, ret, params.empty? ? 0 : params_off].pack("VVV") }
    methods.each { |klass, proto, name_idx| body << [klass, proto, name_idx].pack("vvV") }
    body << [t[descriptor], 1, t[OBJECT], interfaces_off, NO_INDEX, 0, class_data_off, 0].pack("V8")
    body << data
    file_size = header_size + body.bytesize

    header = +"dex\n035\0".b
    header << [0].pack("V") << "\0" * 20
    header << [file_size, header_size, 0x12345678, 0, 0, map_off,
      strings.size, string_ids_off, types.size, type_ids_off, protos.size, proto_ids_off,
      0, 0, methods.size, method_ids_off, 1, class_defs_off, file_size - data_off, data_off].pack("V*")
    dex = header + body
    dex[12, 20] = Digest::SHA1.digest(dex[32..])
    dex[8, 4] = [Zlib.adler32(dex[12..])].pack("V")
    dex
  end
end
```
