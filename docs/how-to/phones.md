# Build for iPhone and Android

A phone runs no program but the app its store installed, so a phone's app can't be a folder with Ruby beside it, as a desktop's is. fledge writes a project instead: an Xcode project for iOS and iPadOS, a Gradle project for Android, each holding Fledge's Ruby, your project, and its gems. You build, sign, and ship it with Xcode or Gradle, as any phone app is shipped. [Ruby on a phone](../explanation/phones.md) explains how the app's Ruby runs there.

## Before you start

The app needs an `identifier` in `fledge.yml`: iOS's bundle identifier and Android's `applicationId`. For Android, each part of it begins with a letter and holds only letters, digits, and underscores.

<!-- SPDX-SnippetBegin -->
<!--
  SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
  SPDX-License-Identifier: MIT-0
-->
```yaml
name: Basket
version: "1.0.0"
identifier: com.example.Basket
icon: icons/basket
```
<!-- SPDX-SnippetEnd -->

A phone's app takes each gem's source build, so `Gemfile.lock` must lock the `ruby` platform:

<!-- SPDX-SnippetBegin -->
<!--
  SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
  SPDX-License-Identifier: MIT-0
-->
```console
$ bundle lock --add-platform ruby
```
<!-- SPDX-SnippetEnd -->

Each phone's project is written on a computer whose tools build it:

| Phone | Write the project on | And have |
| - | - | - |
| iOS and iPadOS | a Mac with Apple silicon | Xcode, and [XcodeGen](https://github.com/yonaskolb/XcodeGen) on `PATH` |
| Android | a Mac with Apple silicon, x86-64 Linux, or x64 Windows | the Android SDK and a Java 17 or newer to build the project; the Android NDK to compile a gem's extension, on the Mac or Linux only |

## Write the project

<!-- SPDX-SnippetBegin -->
<!--
  SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
  SPDX-License-Identifier: MIT-0
-->
```console
$ bundle exec fledge build ios
dist/Basket-ios
```
<!-- SPDX-SnippetEnd -->

<!-- SPDX-SnippetBegin -->
<!--
  SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
  SPDX-License-Identifier: MIT-0
-->
```console
$ bundle exec fledge build android
dist/Basket-android
```
<!-- SPDX-SnippetEnd -->

Each prints the project's folder. From there, it's the platform's workflow:

- **iOS:** open `dist/Basket-ios/Basket.xcodeproj` in Xcode, choose your team under Signing & Capabilities, and run or archive the app. The app runs on iOS and iPadOS 15.0 and later, on iPhone and iPad.
- **Android:** build with the project's Gradle wrapper, `./gradlew assembleDebug` or `./gradlew bundleRelease` in `dist/Basket-android`, or open the folder in Android Studio. The app runs on Android 8.0 (API 26) and later.

> [!WARNING]
> fledge replaces the project folder each time it writes it. Don't edit the project in `dist`: put your changes in a host folder (see [Change the host](#change-the-host)), so that each build carries them.

For the icon, iOS takes one 1024-pixel PNG (`icons/basket-1024.png`) and Android five (`-48`, `-72`, `-96`, `-144`, and `-192`); see [Icon files](../reference/fledge-yml.md#icon-files).

## Run a program on the Simulator or an emulator

`test` writes the project, builds a debug app, installs it, launches it, and prints what the program prints. It exits with the program's exit status, so it can run a test suite in CI:

<!-- SPDX-SnippetBegin -->
<!--
  SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
  SPDX-License-Identifier: MIT-0
-->
```console
$ bundle exec fledge test ios test/phone.rb
```
<!-- SPDX-SnippetEnd -->

<!-- SPDX-SnippetBegin -->
<!--
  SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
  SPDX-License-Identifier: MIT-0
-->
```console
$ bundle exec fledge test android test/phone.rb
```
<!-- SPDX-SnippetEnd -->

The program you name takes the place of the app's main program, in a project under `dist/test`.

- **iOS:** boot one Simulator first, such as with `open -a Simulator`. With several booted, name the one to use with `--device UDID`, as `xcrun simctl list devices booted` lists them.
- **Android:** fledge runs `platform-tools/adb` from the SDK at the path in `ANDROID_HOME`, or in `ANDROID_SDK_ROOT` when `ANDROID_HOME` is unset. When neither is set, or that SDK has no `adb`, fledge runs the `adb` on `PATH`. It runs the program on the one device or emulator `adb devices` lists; with several, name one with `--device SERIAL`.

On a phone, what the program prints goes to the system's log. fledge reads it from there: on iOS, from the log entries of the app's subsystem, its identifier; on Android, from logcat lines tagged with the identifier.

## Gems with extensions

fledge compiles each gem's extension for the phone's processors (an iPhone and the Simulator; Android's `arm64-v8a` and `x86_64`), and links it into the app. It compiles what an `extconf.rb` builds (including an `extconf.rb` that runs CMake), what a Rakefile builds, and Rust extensions that build through `rb_sys`. A gem whose extension builds any other way is refused, with the gem named.

- **iOS:** Xcode's compilers do it, on the Mac.
- **Android:** the NDK's do, on a Mac or Linux. fledge takes the NDK at the path in `ANDROID_NDK_ROOT` or `ANDROID_NDK_HOME`, and stops with an error when that folder has no toolchain for this computer. With neither set, it takes the newest NDK in the `ndk` folders of the SDKs at the paths in `ANDROID_HOME` and `ANDROID_SDK_ROOT`, `~/Library/Android/sdk`, and `~/Android/Sdk`. Fledge's Android runtime is built with NDK r30.
- **Rust:** install Rust's standard library for each target with `rustup target add aarch64-apple-ios aarch64-apple-ios-sim` or `rustup target add aarch64-linux-android x86_64-linux-android`.

A compiled library a gem carries for a desktop, such as a Linux `.so` or a macOS `.bundle`, cannot load on a phone, and fledge refuses the gem.

## The main thread

On a phone, the app's Ruby runs on the process's main thread, as `ruby main.rb` runs on a desktop, whatever `kind` says. That is the thread UIKit and Android's views call back on, so a program that drives the platform's widgets can answer them. It also means a program that holds the main thread freezes its screen, as a native app does:

- iOS ends an app that has not started its interface, by calling `UIApplicationMain`, within 20 seconds of launch. A program that runs long, such as a test suite on an iPhone, starts the interface first and does its work on a Ruby thread.
- Android reports an app as not responding once an input event has waited 5 seconds.

The Simulator ends no program that holds the main thread, so `fledge test ios` runs a test suite of any length there.

## Draw the platform's widgets

Fledge gives your Ruby no bridge to Objective-C or Java: on a phone, as on a desktop, your Ruby is a Ruby program like any other. It reaches UIKit through the Objective-C runtime, and Android's views through JNI, with [Fiddle](https://github.com/ruby/fiddle), the gem Ruby bundles for calling C, or with a gem that does that for you. Add `fiddle` to the `Gemfile`, as for any program under `bundle exec` that uses it:

<!-- SPDX-SnippetBegin -->
<!--
  SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
  SPDX-License-Identifier: MIT-0
-->
```ruby
gem "fiddle"
```
<!-- SPDX-SnippetEnd -->

## Change the host

The host is the native program in each project that starts Ruby: `Host/main.m` for iOS, and `MainActivity.java` for Android. To change it, or anything else in the project, such as `Info.plist`, the Android manifest, or a Gradle file, put your version in a folder of the project and name it in `fledge.yml`:

<!-- SPDX-SnippetBegin -->
<!--
  SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
  SPDX-License-Identifier: MIT-0
-->
```yaml
ios:
  host: host/ios
android:
  host: host/android
```
<!-- SPDX-SnippetEnd -->

fledge copies the folder's files over the project it writes: each replaces fledge's file at the same path, or joins the project, and fledge prints which of its files each replaced. It fills its `@@NAME@@` marks in your copies of the files it fills in its template. The host folder stays out of the app's files.

When a host adds native libraries through its Gradle dependencies, list them in `host_libraries`, so that fledge accepts a gem's library that needs one; see [android](../reference/fledge-yml.md#android).

> [!WARNING]
> An Android host's `build.gradle` must keep `useLegacyPackaging = true` in its `packaging { jniLibs { } }` block, as fledge's does. Without it, Android installs none of the app's native libraries as files, and Ruby can't load its extensions. fledge refuses a host `build.gradle` that drops it.
