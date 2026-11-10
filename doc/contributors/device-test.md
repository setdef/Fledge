<!--
SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>

SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Playtesting `examples/sdl_phone` on an iPad and an Android phone

Plan 003's story "A game plays on a tablet and a phone" ends with a playtest on two devices: an M1 iPad Pro running iPadOS 27 and a OnePlus Nord N30 5G running Android 13 (decisions, 2026-11-02). No agent can hold those devices. Everything an agent can check without them is checked below, so that what you find on a device is about the device, and the time you spend is an hour, not a day. The iPad that ran it was an iPad Pro 12.9-inch (6th generation, M2, iPad14,5) with iPadOS 26.7.1, which Xcode's device list names, not the M1 with iPadOS 27 first planned.

This runbook takes `examples/sdl_phone` to both devices. It is the game of `doc/contributors/design/phones.md`, "A host that owns the main loop": a gem's C extension over SDL3 that owns the screen and the frame loop, with Ruby choosing each frame's color and following your finger. It is not Lota, but it starts the way a Lota game will, so a pass here leaves only Lota's own code to try. Nothing in it costs money: a free Apple ID signs the iPad's build, and the Android SDK's debug key signs the phone's.

Agents wrote this page from a checkout of `trunk` at `c20a629` (Fledge 0.4.0's runtimes) on 2026-11-04, and ran every step before "On the iPad" and "On the phone" on this Mac (section 6).

## 1. What you set up once, on the Mac

- **Xcode 27.2 or newer**, from the App Store. Xcode runs an app only on a device whose OS it knows: if the iPad reports a newer iPadOS than Xcode offers, Xcode offers to download its support (Apple, "Running your app on simulated or physical devices": "To install platform support, click the Get button that appears next to the run destination").
- **XcodeGen 2.46.0**, which `fledge build ios` runs (`mint install yonaskolb/XcodeGen@2.46.0`, or `brew install xcodegen`).
- **CMake**, which builds SDL3. With mise: `mise use -g cmake@4.3.2`. Any CMake 3.24 or newer builds SDL 3.4.18.
- **A JDK 17 or newer**, which the Android Gradle plugin 9.4.1 runs on (`java -version`).
- **The Android SDK and NDK r30.** Android Studio installs them under `~/Library/Android/sdk`. Without Android Studio, take Google's command-line tools (`commandlinetools-mac-15641748_latest.zip` from developer.android.com/studio, SHA-1 `b62a5d8cf63ded173b47be867be4ee058ceda6df`, unpacked as `~/Library/Android/sdk/cmdline-tools/latest`) and run:

  ```sh
  export ANDROID_HOME=~/Library/Android/sdk
  $ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager --licenses
  $ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager "platform-tools" "platforms;android-36" "build-tools;36.0.0" "ndk;30.0.16248370"
  ```

  `platform-tools` holds `adb`; `build-tools` holds `zipalign` and `apksigner`. NDK r30 is the one Fledge's Android runtime is built with (`runtime/sources.yml`, `mobile.ndk`).
- **Fledge's gems**: `bundle install` in the checkout.
- **Optional, for logs from the Terminal**: `brew install libimobiledevice`, for `idevicesyslog` and `idevicecrashreport`. Console.app and Xcode do the same without it.

Set these in each Terminal you build from:

```sh
export ANDROID_HOME=~/Library/Android/sdk
export ANDROID_NDK_ROOT=$ANDROID_HOME/ndk/30.0.16248370
export PATH="$ANDROID_HOME/platform-tools:$ANDROID_HOME/build-tools/36.0.0:$PATH"
export PLAYTEST=~/fledge-playtest
```

## 2. Build both apps

From the root of the checkout. The first command downloads SDL 3.4.18's release tarball, checks its SHA-256, and builds it for each target (`doc/contributors/design/phones.md`, "A host that owns the main loop"). The second puts SDL's Java classes into the example's Android host, where git ignores them.

```sh
examples/sdl_phone/sdl3/build.sh ios "$PLAYTEST/sdl3"
examples/sdl_phone/sdl3/build.sh android "$PLAYTEST/sdl3"

export BUNDLE_BUILD__SDL_DEMO="--with-sdl3-builds=$PLAYTEST/sdl3"
bundle exec fledge build ios -o "$PLAYTEST" examples/sdl_phone
bundle exec fledge build android -o "$PLAYTEST" examples/sdl_phone

(cd "$PLAYTEST/SdlPhone-android" && ./gradlew assembleDebug)
```

Each `fledge build` prints one line on standard output, the project it wrote: `$PLAYTEST/SdlPhone-ios` and `$PLAYTEST/SdlPhone-android`. On standard error it says `host/ios replaces Fledge's Host/Info.plist, Host/main.m, project.yml` and `host/android replaces Fledge's src/main/java/org/setdef/fledge/host/MainActivity.java`. Those lines are expected: SDL owns the app's startup, and the example's host files say so (ADR 025; `doc/contributors/design/phones.md`, "Host files"). Gradle writes `$PLAYTEST/SdlPhone-android/build/outputs/apk/debug/SdlPhone-debug.apk`.

A rebuild starts again at `fledge build`, which writes each project afresh. Anything you change inside `$PLAYTEST/SdlPhone-ios` or `SdlPhone-android`, the signing team included, lasts until then.

## 3. On the iPad

### What Apple gives a free Apple ID

Apple's "Choosing a membership" page (developer.apple.com/support/compare-memberships, fetched 2026-11-04) says of an Apple Account with no paid membership, which Xcode calls a Personal Team:

> To install and test your apps on a personal device, you'll need to sign in to your Apple Account in Xcode. If your account is not associated with a developer program membership, Xcode will indicate it's a Personal Team. Your account's App IDs, devices, certificates, and provisioning profiles are managed directly in Xcode, and you'll be required to reprovision your apps to a device periodically.
>
> - You can register up to 10 App IDs, which expire after 7 days.
> - You can register up to 3 devices, which expire after 7 days.
> - You can install up to 3 apps per device. Provisioning profiles that enable apps to be installed on a device will expire 7 days from issuance. You'll need to rebuild and reinstall your app to your device after expiration.

Apple's page still says that, and it does not match what was observed. The builds that ran on the iPad and the iPhone were signed by a free Personal Team (the maintainer confirmed the team "Kerrick Long" is not enrolled in the paid program). The profiles Xcode made for that team on 2026-11-05 and 2026-11-06 (`~/Library/Developer/Xcode/UserData/Provisioning Profiles/`) each have `TimeToLive` 365 and an `ExpirationDate` exactly one year after `CreationDate` (for `com.setdef.DotPopper`, created 2026-11-06T21:43:24Z, expiring 2027-11-06T21:43:24Z), and that one lists four `ProvisionedDevices` where the page says 3. So the observation contradicts the page; why is not known. Do not count on either number. Read the `ExpirationDate` in your own profile: `security cms -D -i "FILE.mobileprovision" | plutil -p - | grep -E "CreationDate|ExpirationDate|TimeToLive"`. If it has passed, the build stops launching; run `fledge build ios` and install again. The app uses one App ID, `com.setdef.fledge.SdlPhone`, and one of the iPad's 3 app slots. Do not run the project's UI test on the iPad: its runner is a second app with a second App ID (`com.setdef.fledge.SdlPhoneUITests`).

Apple's "Enabling Developer Mode on a device" (developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device, fetched 2026-11-04) covers the iPad's side: "Developer Mode only appears in Settings if you initiate pairing or if you previously paired the device to a Mac", and then "In the Privacy & Security settings on the device, turn on the Developer Mode switch under Security", restart, and after the restart "swipe up, tap Enable in the dialog, and enter your device passcode".

### Steps

1. **Sign in.** Xcode > Settings > Apple Accounts, add your Apple ID. Xcode lists it with a team named "YOUR NAME (Personal Team)".
2. **Pair the iPad.** Connect it with a cable, unlock it, and tap Trust. In Xcode choose Manage Devices from the run destination menu, which opens Device Hub (Apple, "Managing your simulated and physical devices in Device Hub"), select the iPad, and click Pair. Then turn on Developer Mode as Apple describes above. An iPad can also pair over Wi-Fi (Pair Nearby Device), but a cable is the simpler first time.
3. **Choose the team.** `open "$PLAYTEST/SdlPhone-ios/SdlPhone.xcodeproj"`. Select the project, the SdlPhone target, and Signing & Capabilities. Turn on "Automatically manage signing" and choose your Personal Team. Xcode registers the iPad and makes a profile. Leave the Bundle Identifier as it is unless Xcode says it is unavailable; then see the table, row I1.
4. **Keep `OS_ACTIVITY_DT_MODE` out of the scheme.** Product > Scheme > Edit Scheme, Run, Arguments: under Environment Variables there should be no `OS_ACTIVITY_DT_MODE`, with any value, `NO` included. The unified log copies each entry to standard error whenever that variable is there, whatever its value, and the runtimes of Fledge 0.4.0 and earlier send standard error back to the log, so the game freezes in a loop of its own output (section 6). Runtimes with the fix leave the streams to the tool instead, and Ruby's lines then reach Xcode's console from the app's streams rather than from the log.
5. **Run.** Choose the iPad as the run destination and press Run (Product > Run). Xcode builds the Debug configuration, installs, and launches.
6. **Trust the developer, the first time.** If the iPad says "Untrusted Developer", open Settings > General > VPN & Device Management, tap your Apple ID under Developer App, tap Trust, and press Run again.

The same from the Terminal, with your team's ten-character ID. Once you have chosen the team in Xcode, `xcodebuild -project SdlPhone.xcodeproj -target SdlPhone -showBuildSettings | grep DEVELOPMENT_TEAM` prints it. A setting on `xcodebuild`'s command line overrides the project's, so nothing Fledge wrote is edited:

```sh
cd "$PLAYTEST/SdlPhone-ios"
xcodebuild -project SdlPhone.xcodeproj -scheme SdlPhone -configuration Debug \
  -destination 'platform=iOS,name=YOUR IPAD NAME' -derivedDataPath build \
  -allowProvisioningUpdates -allowProvisioningDeviceRegistration \
  DEVELOPMENT_TEAM=YOURTEAMID CODE_SIGN_STYLE=Automatic build
xcrun devicectl list devices
xcrun devicectl device install app --device 'YOUR IPAD NAME' build/Build/Products/Debug-iphoneos/SdlPhone.app
xcrun devicectl device process launch --device 'YOUR IPAD NAME' com.setdef.fledge.SdlPhone
```

### What you should see

The screen fills with a color that cycles through the rainbow once every four seconds, with a white square in the middle. Touch the screen: the square jumps to your finger and follows it. About a second and a half after your first touch the game ends. The app stays open on its last frame, because SDL keeps UIKit's run loop going after the program returns (Lota's CI measured this in the Simulator: the process outlives the log line `exited with status 0`, and `simctl launch` only brings it forward); press the Home button to leave it. That is the program ending, not a crash. A device has not been checked, so if the app returns to the Home Screen by itself, note that in the results table. Untouched, it ends after a minute.

### What to capture

- **The log.** Ruby's output goes to the unified log under the subsystem `com.setdef.fledge.SdlPhone` (category `ruby`), and the host's exit line under category `app`. With Xcode's Run, Xcode's console shows them. Otherwise open Console.app, select the iPad, press Start, and search `subsystem:com.setdef.fledge.SdlPhone`; or, after the run, from the Terminal:

  ```sh
  sudo log collect --device-name 'YOUR IPAD NAME' --last 5m --output "$PLAYTEST/ipad.logarchive"
  log show "$PLAYTEST/ipad.logarchive" --info --predicate 'subsystem == "com.setdef.fledge.SdlPhone"'
  ```

  `idevicesyslog --match SdlDemo` streams the same lines live. Expect, with your own numbers:

  ```
  SdlDemo runs Ruby on the main thread with a stack of 65536 KB, on arm64-darwin with SDL 3.4.18
  SdlDemo recurses 3970 levels deep
  SdlDemo drew 60 frames
  SdlDemo touch down at X, Y in 2048x2732, frame N
  SdlDemo drew M frames in all, after a touch
  SdlPhone exited with status 0
  ```

  An error line from SDL, `You need UIApplicationSupportsIndirectInputEvents in your Info.plist for mouse support`, comes too; it matters only to a mouse or trackpad. The size is the iPad's screen in pixels as SDL reports it, in the orientation you hold it: `2048x2732` on a 12.9-inch iPad Pro held upright, `1668x2388` on an 11-inch. The Simulator's 13-inch iPad Pro (M5) says `2064x2752`.
- **The stack.** The first two lines are the evidence `doc/contributors/design/phones.md`, "A host that owns the main loop" asks for. `65536 KB` and `3970` mean iPadOS grants the 64 MB main-thread stack the app asks for. `1024 KB` and a depth near `800` mean it does not (Apple documents 1 MB for an iOS main thread), and the app still runs, with a fifth of the depth (`doc/contributors/design/phones.md`, "A host that owns the main loop"). Copy both lines into the results table.
- **A screenshot** while the color cycles and after a touch: the iPad's top and volume-up buttons together, or `xcrun devicectl device capture screenshot --device 'YOUR IPAD NAME' --destination "$PLAYTEST/ipad.png"`.
- **A crash report**, if it crashes: Device Hub, select the iPad, the device's logs; on the iPad, Settings > Privacy & Security > Analytics & Improvements > Analytics Data, the newest `SdlPhone-*.ips`; or `idevicecrashreport -e "$PLAYTEST/crashes"`.
- **The device's facts**: `xcrun devicectl device info details --device 'YOUR IPAD NAME'`, for the model and the iPadOS build.

## 4. On the phone

### What the phone takes

The Nord N30 5G is an arm64-v8a phone on Android 13 (API 33). The APK's lowest Android is API 26 and it holds both `lib/arm64-v8a/` and `lib/x86_64/`, so Android installs the arm64-v8a libraries. Android 13 uses 4 KB pages: 16 KB pages begin with Android 15 (developer.android.com/guide/practices/page-sizes, fetched 2026-11-04: "Beginning with Android 15, AOSP supports devices that are configured to use a page size of 16 KB"). The APK is aligned for 16 KB anyway, as Google Play will refuse updates that are not from 2027-02-01, and a 16 KB alignment loads on a 4 KB phone. The debug APK is signed with the SDK's debug key (APK Signature Scheme v2), which `adb install` takes with no account and no Play Console.

### Steps

1. **Developer options.** Google's "Configure on-device developer options" (developer.android.com/studio/debug/dev-options, fetched 2026-11-04) gives the path for "OnePlus 5T and later": Settings > About phone > Build number, tapped seven times "until you see the message `You are now a developer!`". For Android 9 and later it puts the switch at "Settings > System > Advanced > Developer Options > USB debugging". OxygenOS may file both elsewhere; the search box in Settings finds "Build number" and "USB debugging" by name.
2. **Connect.** Plug the phone in with a cable that carries data. Tap Allow on the phone's "Allow USB debugging?" dialog, with "Always allow from this computer" if you like. `adb devices` lists it as `device`, not `unauthorized`.
3. **Check the phone.**

   ```sh
   adb shell getprop ro.product.model
   adb shell getprop ro.build.version.release
   adb shell getprop ro.product.cpu.abilist
   adb shell getconf PAGE_SIZE
   ```

   Expect a Nord N30 5G model name, `13`, a list that starts with `arm64-v8a`, and `4096`.
4. **Install and start.**

   ```sh
   adb install -r "$PLAYTEST/SdlPhone-android/build/outputs/apk/debug/SdlPhone-debug.apk"
   adb logcat -c
   adb shell am start -W -n com.setdef.fledge.SdlPhone/org.setdef.fledge.host.MainActivity
   ```

   The app is also on the phone's home screen as SdlPhone.

### What you should see

The same game as on the iPad, full screen. The first time, Android may show a "Viewing full screen" notice; your first tap may land on it (`doc/contributors/research/2026-11-10-findings-from-the-adrs.md`, "SDL3 owning the main loop, on phones"), so tap again once it goes. The app closes itself about a second and a half after the touch that reaches the game.

### What to capture

- **The log.** Ruby's output goes to logcat under the tag `com.setdef.fledge.SdlPhone`:

  ```sh
  adb logcat -d -v threadtime -s com.setdef.fledge.SdlPhone:V SDL:V AndroidRuntime:E DEBUG:V libc:V > "$PLAYTEST/phone-logcat.txt"
  adb logcat -d -b crash > "$PLAYTEST/phone-crash.txt"
  ```

  Expect:

  ```
  SdlDemo runs Ruby on a thread of its own with a stack of 66593 KB, on aarch64-linux-android with SDL 3.4.18
  SdlDemo recurses 3970 levels deep
  SdlDemo touch down at X, Y in WIDTHxHEIGHT, frame N
  SdlDemo drew M frames in all, after a touch
  SdlPhone exited with status 0
  ```

  The emulators reported 66593 KB; a size near 65536 KB is the same 64 MB thread (`FledgeRuby.STACK_SIZE`).
- **The stack on SDL's own thread**, a second measurement made on emulators only (`doc/contributors/research/2026-11-10-findings-from-the-adrs.md`, "SDL3 owning the main loop, on phones"). It runs Ruby on SDLThread, whose stack is Android's default for a thread, and shows how much Fledge's 64 MB thread matters on this phone:

  ```sh
  adb logcat -c
  adb shell am start -W -n com.setdef.fledge.SdlPhone/org.setdef.fledge.host.MainActivity --ez fledge.sdlthread true
  adb logcat -d -v raw -s com.setdef.fledge.SdlPhone:V
  ```

  On emulators SDLThread had about 1057 KB and recursed 867 levels with 4 KB pages.
- **A screenshot**: `adb exec-out screencap -p > "$PLAYTEST/phone.png"` while the color cycles.
- **A crash**, if it crashes: the `DEBUG` lines of logcat hold the native backtrace, `phone-crash.txt` holds Java's, and `adb bugreport "$PLAYTEST/phone-bugreport.zip"` holds the tombstones.

## 5. Results

Fill in "Seen" as you go. "Owner" says whose code a failure points at: Fledge (the runtimes, `fledge build`, the generated projects), the example's host (`examples/sdl_phone/host`, Fledge's own example of what Lota will ship), Lota (its engine and host, when it ships them), or the device and its account.

| # | Check | Expected | Seen | If not, it means | Owner |
|---|---|---|---|---|---|
| I1 | Xcode makes a profile for the Personal Team | Signing shows the team and a profile | | "Failed to register bundle identifier": another team holds `com.setdef.fledge.SdlPhone`. Change `identifier` in `examples/sdl_phone/fledge.yml` (your copy), rebuild, and read the log under the new subsystem. | Device and account |
| I2 | The iPad pairs, with Developer Mode on | Device Hub lists it as available | | Xcode does not know this iPadOS: install its platform support or a newer Xcode | Device |
| I3 | Xcode builds and installs | "Build Succeeded", the app on the Home Screen | | A link or signing error names the cause. Section 6 shows the device build links unsigned and signs cleanly ad hoc, so a failure here is new | Fledge |
| I4 | The app launches | The color cycles | | "Untrusted Developer": trust it in Settings. A crash before any `SdlDemo` line: read the crash report; a refusal of the main thread's stack (`LC_MAIN` asks for 64 MB) would show here, before `main` | Device, or Fledge |
| I4b | Each log line appears once | One `SdlDemo runs Ruby` line | | The same line again and again, each copy inside the next, and the color frozen: the console loop of section 6: `OS_ACTIVITY_DT_MODE` reached the app, on runtimes without the fix. Take it out of the scheme (step 4), or launch with `devicectl`, and note which Xcode set it | Fledge |
| I5 | The stack line | `the main thread with a stack of 65536 KB` | | `1024 KB`: iPadOS ignores `-Wl,-stack_size`. Ruby runs, shallower; whether a game may live with a fifth of the depth, or Ruby moves to a thread of its own with SDL's calls sent to the main thread, is Lota's and Fledge's to decide (`doc/contributors/design/phones.md`, "A host that owns the main loop") | Fledge and Lota |
| I6 | The depth line | `recurses 3970 levels deep` | | Near 800: as I5. A crash instead of a number: the stack is smaller than Ruby thinks | Fledge |
| I7 | A touch moves the square, and is logged | `touch down at ...` | | No touch logged: SDL's UIKit events, through SDL's scene delegate | Example's host, then Lota |
| I8 | The game ends by itself | `exited with status 0` | | A `LoadError` names a feature Fledge's registration missed; another status names Ruby's error just above it | Fledge |
| A1 | `adb install` | `Success` | | `INSTALL_FAILED_NO_MATCHING_ABIS`: the APK lacks arm64-v8a (section 6 shows it has it). `INSTALL_FAILED_USER_RESTRICTED`: the phone refused the install itself; look on its screen for a prompt, and in Developer options for a switch for installs over USB. `INSTALL_FAILED_UPDATE_INCOMPATIBLE`: `adb uninstall com.setdef.fledge.SdlPhone` first | Fledge, or device |
| A2 | The app launches | The color cycles | | `UnsatisfiedLinkError` or `dlopen failed` names a library the APK lacks or a symbol it cannot find | Fledge |
| A3 | The stack line | `a thread of its own with a stack of` about `65536 KB` | | Smaller: ART did not grant `FledgeRuby.STACK_SIZE` | Fledge |
| A4 | The depth line | `recurses 3970 levels deep` | | Lower: as A3 | Fledge |
| A5 | A touch moves the square, and is logged | `touch down at ...` | | No touch: SDL's Java side (`SDLActivity`, `SDLSurface`) | Example's host, then Lota |
| A6 | The game ends by itself | `exited with status 0` | | As I8 | Fledge |
| A7 | SDLThread, with `fledge.sdlthread` | A smaller stack and depth, or `SystemStackError` | | Only a record: it says how much the 64 MB thread buys on this phone | Nobody |
| B1 | A black screen with log lines that go on | Colors | | SDL's renderer on the device's GPU (Metal on the iPad, OpenGL ES on the phone's Adreno), not Ruby | Example's host, then Lota |

Send the filled table, the screenshots, and the logs to the session that takes Plan 003's story next; `doc/contributors/design/phones.md`, "A host that owns the main loop" gains a paragraph of what ran on which device.

## 6. What agents checked without a device

On this Mac (macOS 27.0.1, Xcode 27.2, XcodeGen 2.46.0, CMake 4.3.2, the pinned NDK r30, Android build-tools 36.0.0), with Fledge 0.4.0's released runtimes, which `fledge build` downloaded and checked against `lib/fledge/SHA256SUMS`:

- **SDL3** built for `ios-arm64`, `ios-arm64-simulator`, `arm64-v8a`, and `x86_64` with `sdl3/build.sh`, from the tarball its SHA-256 pins.
- **The iOS device build.** `xcodebuild -project SdlPhone.xcodeproj -scheme SdlPhone -configuration Debug -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build` succeeded with no warnings. The executable is `Mach-O 64-bit executable arm64`; `otool -l` gives `LC_BUILD_VERSION` `platform 2` (iOS) `minos 15.0` `sdk 27.2`, and `LC_MAIN` `stacksize 67108864`, the 64 MB stack, in the Debug configuration Xcode's Run builds. It links only Apple's frameworks and `libSystem`, `libobjc`, and `libz`, with no `SdlPhone.debug.dylib`. A copy signed ad hoc (`codesign --force --sign -`) passes `codesign --verify --deep --strict`, so nothing in the bundle, the `fledge/` folder of Ruby and the app included, stops a signature.
- **The settings a free team overrides.** `xcodebuild -showBuildSettings DEVELOPMENT_TEAM=ABCDE12345 CODE_SIGN_STYLE=Automatic` shows both on the app target, with `PRODUCT_BUNDLE_IDENTIFIER = com.setdef.fledge.SdlPhone`, `IPHONEOS_DEPLOYMENT_TARGET = 15.0`, `TARGETED_DEVICE_FAMILY = 1,2`, `ARCHS = arm64`, `ENABLE_DEBUG_DYLIB = NO`, and `OTHER_LDFLAGS` starting `-Wl,-stack_size,0x4000000`. A free team needs nothing from Fledge: Xcode's team menu, or the command line, sets it.
- **The 64 MB stacks, where they come from.** iOS: `examples/sdl_phone/host/ios/project.yml`, the project's `settings: base:` with `OTHER_LDFLAGS: -Wl,-stack_size,0x4000000` and `ENABLE_DEBUG_DYLIB: NO` (lines 33 to 36), which the app target's `OTHER_LDFLAGS: @@LDFLAGS@@` (line 90) inherits, since Fledge fills that mark with a value that begins `$(inherited)` (line 91 of the generated `project.yml`), and which the UI test target clears (`OTHER_LDFLAGS: ""`, line 51). Android: `FledgeRuby.STACK_SIZE = 64L * 1024 * 1024` (`runtime/mobile/android/src/main/java/org/setdef/fledge/FledgeRuby.java`, line 42), the stack of the thread `onRubyThread` makes (lines 154 to 166), which the example's `MainActivity.main()` starts with `FledgeRuby.startApp`; `javap -constants` on the `FledgeRuby.aar` in the generated project prints `STACK_SIZE = 67108864l`.
- **The Android APK.** `./gradlew assembleDebug assembleRelease` succeeded. `aapt2 dump badging` gives `package: name='com.setdef.fledge.SdlPhone'`, `minSdkVersion:'26'`, `targetSdkVersion:'36'`, `native-code: 'arm64-v8a' 'x86_64'`, and the launchable activity `org.setdef.fledge.host.MainActivity`. `zipalign -c -P 16 -v 4` says `Verification successful`, with `lib/arm64-v8a/libSDL3.so`, `libfledgeext.so`, and `libfledgeruby.so` stored uncompressed and `(OK)`. `apksigner verify --verbose` says `Verifies`, v2 scheme, one signer, `CN=Android Debug`; the release APK is unsigned, as Fledge leaves it. Each arm64-v8a library is `ELF 64-bit LSB shared object, ARM aarch64`, every `LOAD` segment aligned `0x4000`, and each `GNU_RELRO` fills its own `LOAD` segment, which Google's page lists as 16 KB compliant. `libfledgeruby.so`'s Android note names API 26 and NDK r30. `libfledgeext.so` needs `libfledgeruby.so`, `libSDL3.so`, `liblog.so`, `libm.so`, `libdl.so`, and `libc.so`; `libSDL3.so` needs only Android's own libraries, so the APK carries every library that is not the system's.
- **The Simulator**, in the hidden test session (AGENTS.md, Commands), on an iPad Pro 13-inch (M5) with iOS 26.1, the build of this project for `iphonesimulator`, installed and launched with `simctl`: `SdlDemo runs Ruby on the main thread with a stack of 65536 KB, on arm64-darwin with SDL 3.4.18`, `SdlDemo recurses 3970 levels deep`, a line a second of frames drawn, then `SdlDemo drew 7460 frames in all, with no touch` and `SdlPhone exited with status 0` after the minute. It also logs SDL's own `You need UIApplicationSupportsIndirectInputEvents in your Info.plist for mouse support` as an error, which is harmless for a touch screen. `xcodebuild test`, which taps the screen, stalled in that session before its runner started, with the Mac's load average near 900; CI's run 41580788898 ran the same test on an iPhone and an iPad (`doc/contributors/research/2026-11-10-findings-from-the-adrs.md`, "SDL3 owning the main loop, on phones").
- **Xcode's console mode.** The same app, launched with `OS_ACTIVITY_DT_MODE=YES`, the variable that makes the unified log copy each entry to standard error for a developer tool, logged its first line 42 times over in 30 seconds, each copy nested in the last, and drew no frame: Fledge's forwarding sends standard error to the log, the log copies the entry back to standard error, and the pipe fills until Ruby's `puts` blocks. The log copies whenever the variable is there, whatever its value: on macOS 27.0.1 and in the iOS 26.1 Simulator, `NO`, `0`, and an empty value turned the copy on as `YES` did, so `NO` is no cure (ADR 059; `doc/contributors/design/phones.md`, "Output to the system log"). The runtimes since that finding leave the streams alone when the variable is there (`runtime/mobile/output.c`, `fledge_log_echoes`): on the `experiment/ios-output` branch, `examples/hello` launched with `OS_ACTIVITY_DT_MODE=YES` logged 1,135 entries in a tenth of a second, its line inside 17 of them and on its streams not at all, with the runtime from before the fix (run 41981582665), and with the fixed one it, `examples/mobile_app`, and `test/fixtures/mobile_hello` each printed its line once on its streams, on an iPhone and an iPad (run 41985507137). The example's UI test still sets `NO` (`host/ios/UITests/TapTest.m`, line 18), and its runs in CI drew frames and logged the touch, so XCTest seems not to hand that value to the app; why was not established. Whether Xcode 27's Run sets the variable for an app on a device was not established either (the string is in no file of Xcode.app); Xcode 15 and newer read the log itself by default, so section 3 has you check the scheme holds none.
- **What a Run builds.** `xcodebuild build` of the SdlPhone scheme builds the SdlPhone target alone, not the UI test target, so a device Run asks the Personal Team for one App ID.

## 7. What only a device can prove

- That the iPad's kernel grants a 64 MB main-thread stack from `LC_MAIN` (I5, I6). Nothing on a Mac answers it: the Simulator is a macOS process.
- That the iPad's sandbox, which forbids `fork` and `exec` and keeps the bundle read-only, leaves Ruby's boot, Bundler's setup, and the program alone. The Simulator allows both (`doc/contributors/research/2026-10-27-mobile-spike.md`).
- Whether Xcode's Run sets `OS_ACTIVITY_DT_MODE` for an app on a device, and so whether Ruby's lines reach Xcode's console from the log or, with runtimes that have the fix, from the app's streams; with 0.4.0's runtimes, whether a developer who presses Run meets the console loop (I4b).
- That a Personal Team's profile installs and launches this app, and how long it lasts; only Apple's servers and the iPad sign off on it. The profiles seen so far last a year, which Apple's page does not say of a free team.
- That the arm64-v8a build runs at all. No free runner boots an arm64-v8a emulator (`doc/contributors/design/phones.md`, "What a framework provides"), so `libfledgeruby.so`, `libfledgeext.so`, and `libSDL3.so` for arm64-v8a have been linked and checked, never loaded.
- That ART on Android 13 grants the 64 MB thread, which emulators of API 36 did.
- That SDL draws through the iPad's Metal and the phone's Adreno GPU, and takes their touches.
- How fast it starts. The Android app unpacks `fledge.zip` (28 MB) on its first launch; the emulators said nothing of a real phone's storage.

When all of section 5 passes, the Fledge side of the story is proven, and what remains is Lota's game in place of `sdl_demo`, through the same steps.
