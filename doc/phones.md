<!--
  SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
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

## Google Play

Google Play takes an [Android App Bundle](https://developer.android.com/guide/app-bundle) (`.aab`) from a new app, not an APK. Build one in the project Fledge wrote:

```sh
./gradlew bundleRelease
```

The bundle is `build/outputs/bundle/release/NAME-release.aab`, and it is unsigned. Fledge holds no key of yours. Sign the bundle with your upload key, and Play signs the APKs it makes from it with your app's signing key ([Play App Signing](https://support.google.com/googleplay/android-developer/answer/9842756)). Make an upload key once with the JDK's `keytool`, and keep it out of your repository:

```sh
keytool -genkeypair -v -keystore ~/upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

Then sign each bundle with `jarsigner`, as [Android's documentation](https://developer.android.com/build/building-cmdline#sign_cmdline) does. `apksigner` signs APKs, not bundles.

```sh
jarsigner -keystore ~/upload-keystore.jks "build/outputs/bundle/release/NAME-release.aab" upload
```

Or name the key in a `signingConfigs` block in `build.gradle`, and `bundleRelease` signs the bundle as it builds it. `./gradlew assembleDebug` still builds an APK you can install on a phone or an emulator with `adb install`.

To see the APKs Play would make from your bundle, and install them, use Google's [bundletool](https://developer.android.com/tools/bundletool): `build-apks` with your key, then `install-apks`. Play limits the base module, which holds all of a Fledge app, to a 500 MB download ([size limits](https://support.google.com/googleplay/android-developer/answer/9859372)). `bundletool get-size total --apks=app.apks` prints yours. Ruby and the example apps download as about 17 MB.

## The App Store

The App Store takes an archive that your team signed, which Fledge cannot make: it holds no certificate or profile of yours, and uploading needs an [Apple Developer Program](https://developer.apple.com/programs/) account. Open the project's `NAME.xcodeproj`, choose your team under Signing & Capabilities, and use Xcode's Product > Archive, then Window > Organizer, where Validate App and Distribute App take it to App Store Connect. Or from a terminal, with your team's ID:

```sh
xcodebuild archive -project NAME.xcodeproj -scheme NAME -configuration Release -sdk iphoneos \
  -archivePath NAME.xcarchive -allowProvisioningUpdates DEVELOPMENT_TEAM=YOURTEAMID
xcodebuild -exportArchive -archivePath NAME.xcarchive -exportPath export -exportOptionsPlist ExportOptions.plist -allowProvisioningUpdates
```

`ExportOptions.plist` holds `method` `app-store-connect`, and `destination` `upload` to send the build to App Store Connect, or `export` to write an `.ipa` for Transporter. Xcode must have your Apple ID in its Accounts settings.

Before you do, know what is yours to settle:

- **An icon.** Give `fledge.yml` an `icon`, and for iOS a `-1024.png` that has no alpha channel and no rounded corners: App Store Connect refuses an icon with transparency, even an opaque one. `sips -g hasAlpha ICON.png` says whether yours has it.
- **Export compliance.** Every app carries OpenSSL, so Fledge does not say for you whether your app's encryption is exempt from U.S. export rules. Answer App Store Connect's questions once, then add `ITSAppUsesNonExemptEncryption` to `Host/Info.plist`, `false` if Apple's [export compliance overview](https://developer.apple.com/documentation/security/complying-with-encryption-export-regulations) says yours is exempt, so it stops asking.
- **A new version for each upload.** The build number is `version`'s first three numbers, and App Store Connect wants a new one each time you upload.
- **The privacy manifest** (see above) must describe your app, not only Fledge's Ruby.

CI archives every example app with no team or certificate, as `xcodebuild archive` does with `CODE_SIGNING_ALLOWED=NO`, and checks with Apple's tools what App Store Connect reads in that archive: the app's `Info.plist` keys, arm64 and iOS 15 in the executable and no Simulator slice, bitcode, or library outside the system's, no other Mach-O file, the `.dSYM`, the privacy manifest, and an app icon with a 1024 pixel image and no alpha. That is everything Apple's tools check without an account. What only an upload proves is your team's signature and profile, App Store Connect's own validation, and App Review; no Fledge app has been through them.

## What has run where

CI runs phone apps in the iOS Simulator, on an iPhone and an iPad, and archives them for devices unsigned, and on x86-64 Android emulators. On Android, each app runs from its APK, and again from the APKs bundletool makes from its signed release bundle, as Play would install them. A game built with `fledge build ios` has run on a physical iPad Pro and a physical iPhone 13 mini, signed with a free Personal Team. Apple's membership page says a free team's profiles expire after 7 days, but the profiles Xcode made for that team last a year, so read the `ExpirationDate` in your own (`security cms -D -i FILE.mobileprovision`). No app has been through App Review or Google Play's review yet. For `arm64-v8a`, which most Android phones use, CI builds the library and checks the APK, but no free CI runner can start an arm64 emulator. A game that `fledge build android` built has run on a physical OnePlus Nord N30 5G with Android 14, which loaded the APK's `arm64-v8a` library.
