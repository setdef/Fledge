<!--
  SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
  SPDX-License-Identifier: CC-BY-SA-4.0
-->
# iPhone, iPad, and Android

For a phone, [Fledge](../README.md) writes a project that holds your program and a Ruby, and you build, sign, and submit that project as you would any other phone app.

- **iOS:** `fledge build ios` writes an [Xcode](https://developer.apple.com/xcode/) project for iOS 15 and newer. Run it on a Mac with Xcode and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).
- **Android:** `fledge build android` writes a [Gradle](https://gradle.org/) project for Android 8.0 (API 26) and newer. Run it on a Mac, x86-64 Linux, or Windows. To build the project, you need a JDK and the Android SDK.

Lock `ruby` as a platform first (`bundle lock --add-platform ruby`). To build a folder named `ios` or `android`, write `./ios` or `./android`. [`examples/mobile_app`](../examples/mobile_app) is a complete example.

A phone's Ruby has the standard library and gems of a desktop's, `fiddle` among them. A phone also forbids some things a desktop lets your code do, such as starting a program. [What a phone forbids](#what-a-phone-forbids) lists them, with what to do instead.

## Gems with extensions

Fledge compiles a gem's C, C++, or Rust extension for the phone and links it into the app: with Xcode on iOS, and with the [Android NDK](https://developer.android.com/ndk) on Android. Set `ANDROID_NDK_ROOT`, or install the NDK in the SDK's `ndk/` folder.

- Load the extension with `require "name/name"`, not `require_relative`.
- When an `extconf.rb` runs CMake, Fledge passes a toolchain file for each target in `CMAKE_TOOLCHAIN_FILE`, so CMake builds the library for the phone.
- A Rust extension built with [rb-sys](https://github.com/oxidize-rb/rb-sys) needs Rust and Cargo, with Rust's standard library for each of the phone's targets: `rustup target add aarch64-apple-ios aarch64-apple-ios-sim` for iOS, and `rustup target add aarch64-linux-android x86_64-linux-android` for Android. Cargo builds it as a static library for each target. An app has been tested with one Rust extension; two can't share a name.
- The ffi gem works, with the libffi it bundles, and so does Ruby's `fiddle`. Each calls a C function by its name, such as one of the phone's C library or a system framework, and turns a Ruby block into a C callback.
- Fledge refuses, and names the gem, an extension built by CMake, configure, or Cargo with no `extconf.rb` or Rakefile, and a shared library a Rakefile builds for ffi to load.

For each case, see [`examples/native_phone`](../examples/native_phone), [`examples/cmake_phone`](../examples/cmake_phone), [`examples/rake_phone`](../examples/rake_phone), [`examples/rust_phone`](../examples/rust_phone), and [`examples/ffi_phone`](../examples/ffi_phone).

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
- **Export compliance.** App Store Connect asks about your app's encryption on every upload. [Below](#export-compliance) says what Apple's pages say, and what Fledge leaves to you.
- **A version, and a new one for each upload.** Put `version` in `fledge.yml`: without one the app is 0.0.0 (build number 0.0.0 on iOS, `versionCode` 1 on Android). Apple's reference for [`CFBundleVersion`](https://developer.apple.com/documentation/bundleresources/information-property-list/cfbundleversion) allows one to three integers and says "0 specifies 0.0.0", and Google Play wants a `versionCode` that is a positive integer, so `fledge build` builds such an app, but a store listing wants a version people can read. The build number is `version`'s first three numbers, and each store wants a new one each time you upload (Play: "You can't upload an APK to the Play Store with a `versionCode` you have already used").

- **The privacy manifest** (see above) must describe your app, not only Fledge's Ruby.

CI archives every example app with no team or certificate, as `xcodebuild archive` does with `CODE_SIGNING_ALLOWED=NO`, and checks with Apple's tools what App Store Connect reads in that archive: the app's `Info.plist` keys, arm64 and iOS 15 in the executable and no Simulator slice, bitcode, or library outside the system's, no other Mach-O file, the `.dSYM`, the privacy manifest, and an app icon with a 1024 pixel image and no alpha. That is everything Apple's tools check without an account. What only an upload proves is your team's signature and profile, App Store Connect's own validation, and App Review; no Fledge app has been through them.

### Export compliance

*This is what Apple's pages say, as of 2026-11-07, not legal advice. Whether your app is exempt is your claim and your responsibility: Apple says "you're responsible for all liabilities associated with misinterpretation of export regulations or claiming exemption inaccurately." If you are unsure, ask a lawyer who knows U.S. export rules.*

Every Fledge iOS app contains OpenSSL, which Ruby uses for HTTPS and the `openssl` library. The same is true of an Android app, and of a desktop app, but only App Store Connect asks about it, so it matters on iOS first.

- **Apple asks about what the app contains, not only what it does.** The overview says to determine your requirements "if your app uses, accesses, contains, implements, or incorporates encryption" ([Overview of export compliance](https://developer.apple.com/help/app-store-connect/manage-app-information/overview-of-export-compliance/)), and the `ITSAppUsesNonExemptEncryption` key counts "any third-party libraries you link against" ([key reference](https://developer.apple.com/documentation/bundleresources/information-property-list/itsappusesnonexemptencryption)). So a library that has encryption counts, whether or not your program calls it, and an app that never touches the network should not assume it answers "no encryption": it still contains OpenSSL. The questions themselves are in App Store Connect, which asks them when you upload; Apple's pages do not print them.
- **An app that only uses HTTPS.** Apple says that "the use of encryption that's built into the operating system—for example, when your app makes HTTPS connections using `URLSession`—is exempt from export documentation upload requirements" ([Complying with encryption export regulations](https://developer.apple.com/documentation/security/complying-with-encryption-export-regulations)). Ruby's HTTPS does not use the operating system's: it uses the OpenSSL in the app. By Apple's text that sentence does not cover it.
- **"Standard encryption other than Apple's".** That is where OpenSSL falls: "an industry standard algorithm, not provided within the Apple operating system". Apple's table asks for one document for it, your French encryption declaration, and only if you distribute the app in France; a proprietary algorithm that no standards body accepted adds a U.S. classification (CCATS) ([Export compliance documentation for encryption](https://developer.apple.com/help/app-store-connect/reference/app-information/export-compliance-documentation-for-encryption/)). Only encryption "limited to that within the Apple operating system" needs no document at all. Whether OpenSSL's use in your app is "exempt" under the U.S. rules is what the `ITSAppUsesNonExemptEncryption` value says, and Apple's pages do not decide it for an app like yours.
- **A report to the U.S. government.** Apple adds that "if your app uses exempt forms of encryption, you might alternatively be required to submit a year-end self-classification report" to the Bureau of Industry and Security, and that it is your responsibility to review the Export Administration Regulations to find out whether the app needs a formal classification. BIS's [encryption controls page](https://www.bis.gov/learn-support/encryption-controls) points to sections 740.17 and 742.15 of the regulations, its mass-market and publicly-available provisions among them. Fledge could not read their text here, so it says nothing of when they apply to you.

Fledge's template writes no `ITSAppUsesNonExemptEncryption`, so App Store Connect asks every time. When you know your answer, add the key to `Host/Info.plist`, `false` for exempt or no encryption, `true` with the `ITSEncryptionExportComplianceCode` Apple gives you once it approves your documents, and Apple says the questions stop: "Including the key streamlines the app submission process."

## What a phone forbids

Your code runs on a phone as under `ruby main.rb`, with the exceptions here. Most are calls a phone's operating system refuses that a desktop answers, and each item says why. A gap in Fledge's own Ruby, when there is one, is marked **Temporary**: a defect Fledge means to fix, so read the item again after you update Fledge. Everything not listed here ran the same as on a desktop in Fledge's tests; [What has run where](#what-has-run-where) says on which phones.

The Simulator and the Android emulators are looser than a phone. Test what this page names on a device.

### On iOS

What follows holds on an iPhone 12 mini with iOS 27.0 and a development-signed build. A development build is the least restricted kind, so no iOS app does better.

- **Starting a program.** No app can start one, and Apple's sandbox is the reason. On that iPhone, `system("/bin/echo", "hi")` returned `nil`, and backticks, `Process.spawn`, and `IO.popen` raised `Errno::EPERM: Operation not permitted - /bin/echo`. Do the work in your own process: call a Ruby library where you would call a command, or a gem with a C extension that Fledge links into the app ([Gems with extensions](#gems-with-extensions)).
- **`fork`.** `fork` raised `Errno::EPERM - fork(2)`. The Simulator allows it, so a program that forks can pass there and fail on an iPhone. The sandbox is the reason. Use a `Thread` for work in the background, or a `Ractor` for work that shares nothing.
- **`RbConfig.ruby`.** It names where `bin/ruby` would be, and nothing is there: a phone's Ruby is a library inside the app. Starting it raises `Errno::EPERM`. Anything that restarts your app with `exec RbConfig.ruby, ...` or runs a script with `system(RbConfig.ruby, ...)` fails. Call `load` or `require` in the same process instead.
- **`mkmf`.** `require "mkmf"` aborts. The app carries no C headers, and a phone has no toolchain. An extension compiles on your computer, when you run `fledge build ios`.
- **Set-user-ID, set-group-ID, and sticky bits.** The sandbox keeps an app from setting these bits on its own files, so `File.setuid?`, `File.setgid?`, and `File.sticky?` do not report a bit you set with `chmod` (the Simulator's runs of ruby/spec show this). Keep that information in your own data, not in a file's mode.
- **User and group names.** An iOS app has no user or group database. `Etc` finds no user or group for the app's own IDs (the Simulator's runs of ruby/spec show this). `ENV["USER"]` and `ENV["LOGNAME"]` both read `mobile`, whoever owns the phone. Name a person from what your app asks them, or from an account service, not from `Etc`.
- **User and group IDs.** Setting your own IDs works: `Process.uid=`, `Process.euid=`, `Process.gid=`, and `Process.egid=` raised nothing when given the current value on the iPhone.
- **Groups.** An iOS app gets no list of the groups it belongs to: `Process.groups` raises `Errno::EINVAL`. So `File.grpowned?` (and the same method of `File::Stat` and `FileTest`) is true only for a file of the app's own primary group, and `File.readable?`, `File.writable?`, and `File.executable?` answer as on a desktop.

### On Android

What follows holds on a OnePlus Nord with Android 14 (API 34).

- **Starting a program.** Programs the system holds start. On that phone `system`, backticks, `Process.spawn`, and `IO.popen` all ran `/bin/echo` and `/system/bin/echo`, and each exited 0. A program or script your app writes at run time does not: an app that targets API 29 or later may not run a file from its own writable folders. On that phone, a shell script written to `Dir.tmpdir` and made executable gave `nil` from `system(path)` and raised `Errno::EACCES` from `Process.spawn(path)`. Hand such a script to the program that reads it: `system("sh", path)` and `system(RbConfig.ruby, path)` both ran there. Programs the installer unpacked from the app's native libraries do, and Fledge's `ruby` is one (next item). For a program of your own, link the code into the app as a gem extension ([Gems with extensions](#gems-with-extensions)), or call the system's own tools.
- **`RbConfig.ruby`.** It names a `ruby` program the app carries, so `system(RbConfig.ruby, "worker.rb")`, `IO.popen`, backticks, and `Gem.ruby` start Ruby as on a desktop, with your app's gems, and your app's own program started that way runs as your app first ran it. It runs in a process of its own, with no Java, and Android may stop it with your app; `exec RbConfig.ruby, ...` replaces your app's process, so use `system` or `spawn`. Android runs only the native libraries its installer unpacks, so the project packs them compressed (`useLegacyPackaging = true` in `build.gradle`), and the app takes more space once installed. If your code never starts Ruby, set it to `false`; then `RbConfig.ruby` names a file that is not there, and starting it raises `Errno::ENOENT`. On that phone, `system(RbConfig.ruby, "-e", "p 1")` printed `1` and returned `true`, and `IO.popen([RbConfig.ruby, "-v"], &:read)` read Ruby's version.
- **Group IDs.** `Process.egid=` and `Process.gid=` raise `NotImplementedError` (`egid=() function is unimplemented on this machine`). Android's seccomp filter stops an app that calls `setgid`, `setregid`, `setresgid`, or `setgroups`, so Fledge builds Ruby without them. The same holds for `Process::GID`'s changes, `Process.initgroups`, `Process.groups=`, and `Process.maxgroups=`. Setting your own user ID works: `Process.uid=` and `Process.euid=` raised nothing with the current value. No workaround exists.
- **`mkmf`.** `require "mkmf"` aborts, as on iOS: the app carries no C headers, and a phone has no toolchain. An extension compiles on your computer, when you run `fledge build android`.
- **The process title.** `$0 = "name"` and `Process.setproctitle("name")` set what `ps` and `/proc/PID/cmdline` show for your app's process, as on Linux, in the room Android gave its command line: your app's identifier and one byte more. A longer title is cut there, where Linux's Ruby can also write into the space of the environment. A Ruby your app starts with `RbConfig.ruby` has its own command line, and its room.
- **Files the system keeps back.** SELinux forbids an app to read `/dev`, so listing it, as `Dir.scan("/dev")` does, raises `Errno::EACCES`. Android's `fdsan` ends the process, not only the call, when `Dir.for_fd` opens a descriptor that another `Dir` owns. Keep one `Dir` to a descriptor.
- **Set-ID bits and `Etc`.** Fledge's tests list no difference from Linux for these on Android, so treat them as Linux's.

### On both

- **No terminal.** An app's standard output goes to the system log. Fledge puts `$stdout` in sync mode so each line appears as it prints, where a desktop program writing to a pipe buffers. Standard input is at its end, and the working directory is `/`.
- **A read-only bundle.** On a device the app's own folder cannot be written to (it can in the Simulator). Write under `Dir.home` or `Dir.tmpdir`.
- **No JIT.** `RubyVM::YJIT` is not defined. Guard its use with `defined?(RubyVM::YJIT)`.
- **Stopped in the background.** The system may stop an app that is not in front without running `at_exit`. Save what matters as you go.
- **Native code in the app.** A phone's Ruby links each extension in, and holds no `archdir` of them; `RbConfig::CONFIG["archdir"]` names a folder with no extensions in it.

## What has run where

CI runs phone apps in the iOS Simulator, on an iPhone and an iPad, and archives them for devices unsigned, and on x86-64 Android emulators. On Android, each app runs from its APK, and again from the APKs bundletool makes from its signed release bundle, as Play would install them. A game built with `fledge build ios` has run on a physical iPad Pro and a physical iPhone 13 mini, signed with a free Personal Team. Apple's membership page says a free team's profiles expire after 7 days, but the profiles Xcode made for that team last a year, so read the `ExpirationDate` in your own (`security cms -D -i FILE.mobileprovision`). No app has been through App Review or Google Play's review yet. For `arm64-v8a`, which most Android phones use, CI builds the library and checks the APK, but no free CI runner can start an arm64 emulator. A game that `fledge build android` built has run on a physical OnePlus Nord N30 5G with Android 14, which loaded the APK's `arm64-v8a` library, and on that phone Fledge's `ruby` program has started child Rubies, and the parity probe found no difference it does not justify.
