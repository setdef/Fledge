<!--
  SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
  SPDX-License-Identifier: CC-BY-SA-4.0
-->
# iPhone, iPad, and Android

For a phone, [Fledge](../README.md) writes a project that holds your program and a Ruby, and you build, sign, and submit that project as you would any other phone app.

- **iOS:** `fledge build ios` writes an [Xcode](https://developer.apple.com/xcode/) project for iOS 15 and newer. Run it on a Mac with Xcode and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).
- **Android:** `fledge build android` writes a [Gradle](https://gradle.org/) project for Android 8.0 (API 26) and newer. Run it on a Mac, x86-64 Linux, or Windows. To build the project, you need a JDK and the Android SDK.

Lock `ruby` as a platform first (`bundle lock --add-platform ruby`). To build a folder named `ios` or `android`, write `./ios` or `./android`. [`examples/mobile_app`](../examples/mobile_app) is a complete example.

## Gems with extensions

Fledge compiles a gem's C or C++ extension for the phone and links it into the app: with Xcode on iOS, and with the [Android NDK](https://developer.android.com/ndk) on Android. Set `ANDROID_NDK_ROOT`, or install the NDK in the SDK's `ndk/` folder.

- Load the extension with `require "name/name"`, not `require_relative`.
- When an `extconf.rb` runs CMake, Fledge passes a toolchain file for each target in `CMAKE_TOOLCHAIN_FILE`, so CMake builds the library for the phone.
- Fledge refuses, and names the gem, a Rust extension, and an extension built by Rake, CMake, or configure with no `extconf.rb`.

For each case, see [`examples/native_phone`](../examples/native_phone) and [`examples/cmake_phone`](../examples/cmake_phone).

## Frameworks that start the app themselves

Some frameworks, such as SDL3, need their startup files on each phone. Name a folder of them under `ios: host:` and `android: host:` in `fledge.yml`, and `fledge build` copies them over the project it writes. [`examples/sdl_phone`](../examples/sdl_phone) is a game loop that uses this.

## The privacy manifest

Apple asks for a reason each time an app uses certain system calls, and an app declares them in `PrivacyInfo.xcprivacy`. Fledge's manifest declares the file-timestamp and boot-time APIs that Ruby calls, for files in the app's container (C617.1) and for elapsed time (35F9.1). If your app shows a file's dates to the person (DDA9.1) or reads files the person picked (3B52.1), or if its gems call other required-reason APIs, add those to your own copy. Put it in your `ios: host:` folder as `Host/PrivacyInfo.xcprivacy`, which replaces Fledge's whole.

## What has run where

CI runs phone apps in the iOS Simulator, on an iPhone and an iPad, and on x86-64 Android emulators. A game built with `fledge build ios` has run on a physical iPad Pro and a physical iPhone 13 mini, signed with a free Personal Team. Apple's membership page says a free team's profiles expire after 7 days, but the profiles Xcode made for that team last a year, so read the `ExpirationDate` in your own (`security cms -D -i FILE.mobileprovision`). No app has been through App Review yet. For `arm64-v8a`, which most Android phones use, CI builds the library and checks the APK, but no free CI runner can start an arm64 emulator. A game that `fledge build android` built has run on a physical OnePlus Nord N30 5G with Android 14, which loaded the APK's `arm64-v8a` library.
