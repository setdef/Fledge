<!--
SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>

SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Tests Blocked on Your Developer Accounts

This is your working checklist: every test that only your Apple, Microsoft, Google, or package-repository accounts, or a certificate you buy, can run. Agents keep it current (AGENTS.md, Releasing); you work through it.

## How to use this list

1. Pick a test. Its **Needs** line says what to have first, and **Steps** says where the instructions are. Where a walk-through already exists (`doc/contributors/signing-test.md`), this page links to its section and does not repeat it.
2. Run it. Compare what you see with **Passing**. When it differs, keep the output: it is the finding. Send agents that output, and never a key, password, or token (the walk-through's outputs hold none).
3. Tell an agent the result, or edit **Status** yourself. An agent then records it where the finding belongs (ADR 033, Plan 003, the README's line on what is untested) and updates this page in the same commit.

**You decide which of these block 1.0.0.** Every entry says "not decided", because you have said you may choose later (decisions, 2026-11-08), and until you do, no entry is a requirement. To decide, change an entry's "Blocks 1.0.0?" to yes or no; agents then change the "1.0" story in Plan 003 and `doc/contributors/releasing-1.0.md` to match, and answer question C in `questions.md`.

**Dot Popper and the stores.** Dot Popper should wait for Lota 0.3.0 before going to a store. That applies to IOS-2, IOS-3, AND-1, AND-2, and WIN-5 below if you submit Dot Popper itself. Fledge's own example apps can stand in for the tests that prove Fledge's part, since a store's review of the packaging does not depend on the game.

## The tests

### On a Mac, with an Apple Developer Program account

All of these use the Developer ID Application certificate and notarization profile that `signing-test.md`, Part 1, steps 1 and 2, have you make once.

#### MAC-1: A windowed Mac app is signed, notarized, and stapled

- **Proves:** Apple's notary service accepts what Fledge signs (hardened runtime, timestamps, entitlements), and stapling the app after notarizing its disk image finds a ticket.
- **Needs:** the Apple Developer Program (US$99 a year; enrollment is under way), Xcode, and a Developer ID Application certificate.
- **Steps:** `signing-test.md`, Part 1, steps 1 to 4 (`fledge build --sign ... --notarize ... examples/windowed_app`, then `stapler validate` and `spctl --assess`).
- **Passing:** the build prints "Apple accepted Hello Window-arm64-darwin.dmg" and two stapling lines; both `stapler validate` calls end `The validate action worked!`; both `spctl` calls say `source=Notarized Developer ID`.
- **Status:** not run.
- **Blocks 1.0.0?** not decided.

#### MAC-2: A console Mac app is notarized

- **Proves:** a lone program's folder notarizes as a zip, which Apple cannot staple, and Apple accepts it.
- **Needs:** as MAC-1.
- **Steps:** `signing-test.md`, Part 1, step 3, the second build (`examples/hello`).
- **Passing:** "Notarizing Hello-arm64-darwin.zip" then "Apple accepted Hello-arm64-darwin.zip", and no stapling line.
- **Status:** not run.
- **Blocks 1.0.0?** not decided.

#### MAC-3: Fledge's own contract test passes against Apple's real service

- **Proves:** the repeatable form of MAC-1, which agents can run again for a later release.
- **Needs:** as MAC-1.
- **Steps:** `signing-test.md`, Part 1, step 4, the `rake test:integration N=/gatekeepers_blessing/` command.
- **Passing:** `0 failures, 0 errors, 0 skips`. A skip means a variable was empty.
- **Status:** not run.
- **Blocks 1.0.0?** not decided.

#### MAC-4: Gatekeeper accepts a copy downloaded with a browser

- **Proves:** a person who downloads the notarized `.dmg` with Safari opens the app with one "Are you sure?" prompt, and without "Apple could not verify" or "developer cannot be verified"; offline, the stapled ticket is enough.
- **Needs:** MAC-1 passed, and a second Mac or another user account that has never run the app. A copy marked with `xattr` tests Gatekeeper but not a browser.
- **Steps:** `signing-test.md`, Part 1, step 5.
- **Passing:** the disk image opens with no warning; the app asks once and then opens a window.
- **Status:** not run.
- **Blocks 1.0.0?** not decided.

#### MAC-5: Does YJIT need its entitlement under a Developer ID? (optional)

- **Proves:** whether `com.apple.security.cs.allow-unsigned-executable-memory` can be dropped. CI's self-signed builds ran YJIT without it.
- **Needs:** as MAC-1.
- **Steps:** `signing-test.md`, Part 1, step 6.
- **Passing:** there is no pass or fail. `"yjit":true` with no entitlements means a later change may drop it; `"yjit":false` or a crash means it stays. An agent records either answer in ADR 050.
- **Status:** not run.
- **Blocks 1.0.0?** not decided.

### On Windows, with a code-signing certificate or service

Windows needs a trusted code-signing certificate or a signing service, bought separately. You need to pass only one route to prove Fledge's part, but each route below is a separate claim about a separate tool.

#### WIN-1: `--sign THUMBPRINT` with a certificate in the certificate store

- **Proves:** signtool, run by Fledge with SHA-256 and a DigiCert timestamp, signs every program, library, the uninstaller, and the setup program with a real certificate.
- **Needs:** an OV or EV code-signing certificate from a certificate authority (a `.pfx`, or a token whose driver puts it in the store), a Windows 10 or 11 computer, and the Windows SDK's signtool.
- **Steps:** `signing-test.md`, Part 2, "Before you start", 3a, and 4.
- **Passing:** `signtool verify /pa /v` on the setup program and on the program inside the archive ends `Successfully verified`, names your certificate, and says the signature is timestamped; the check of every `.exe`, `.dll`, and `.so` prints nothing; Explorer's Digital Signatures tab says "This digital signature is OK."
- **Status:** not run.
- **Blocks 1.0.0?** not decided.

#### WIN-2: `--sign-command` with Azure Artifact Signing

- **Proves:** a cloud signer works through `--sign-command`, with no code in Fledge for the service.
- **Needs:** an Azure account with an Artifact Signing account, a validated identity, and a certificate profile (about US$10 a month, per `doc/desktop_apps.md`), plus the Windows SDK's signtool.
- **Steps:** `signing-test.md`, Part 2, "Before you start", 3b, and 4.
- **Passing:** as WIN-1, with the cloud service's certificate under **Issued to**.
- **Status:** not run.
- **Blocks 1.0.0?** not decided.

#### WIN-3: `--sign-command` with another signer (optional, one is enough)

- **Proves:** the same, for the service you actually buy: DigiCert KeyLocker, SSL.com eSigner, or a key in a cloud vault through jsign.
- **Needs:** an account with that service. Skip it if WIN-1 or WIN-2 is the route you ship with.
- **Steps:** `signing-test.md`, Part 2, 3c, and 4.
- **Passing:** as WIN-1.
- **Status:** not run.
- **Blocks 1.0.0?** not decided.

#### WIN-4: SmartScreen's verdict on a downloaded setup program

- **Proves:** a person who downloads the signed setup program with Edge installs it, or sees "Windows protected your PC" with your name as the publisher, not "Unknown publisher".
- **Needs:** WIN-1, WIN-2, or WIN-3 passed, and a place a browser can download from. A new certificate has no reputation with SmartScreen yet, so a warning with the right publisher is not a failure on a first run.
- **Steps:** `signing-test.md`, Part 2, step 5.
- **Passing:** the setup program starts with no administrator prompt (or SmartScreen names setdef), installs, opens **Hello Window** from the Start menu, and uninstalls from Settings.
- **Status:** not run.
- **Blocks 1.0.0?** not decided.

#### WIN-5: The Microsoft Store takes the setup program

- **Proves:** the Store's certification, and its malware scan of a Ruby runtime, accept Fledge's NSIS setup program (policy 10.2.9), which no one has tried.
- **Needs:** a Partner Center account (Microsoft's new onboarding charges no registration fee, per `doc/desktop_apps.md`), a certificate that chains to Microsoft's Trusted Root Program (WIN-1 or WIN-2 passed), and a versioned HTTPS address for a file that never changes. Whether the Store's check follows a GitHub Release's redirect is unknown.
- **Steps:** `doc/desktop_apps.md`, "The Microsoft Store". No walk-through exists; an agent will write one when you want to run this.
- **Passing:** the Store certifies the submission and lists the app, and installing it from the Store runs the app.
- **Status:** not run.
- **Blocks 1.0.0?** not decided.

### On an iPhone or iPad, with an Apple Developer Program account

#### IOS-1: A Fledge iOS app passes App Store Connect's validation

- **Proves:** a team's signature and profile, `xcodebuild -exportArchive`, and App Store Connect's own checks accept an archive of a Fledge iOS project. CI checks everything Apple's tools check without an account (`doc/contributors/design/phone-projects.md`, "The App Store archive check").
- **Needs:** the Apple Developer Program, and an app record in App Store Connect.
- **Steps:** `doc/phones.md`, "The App Store" (Product > Archive, or the `xcodebuild archive` and `-exportArchive` commands there), and its "Export compliance", which is a legal claim of yours. Set a `version` in `fledge.yml` first.
- **Passing:** the upload is accepted and the build appears under TestFlight with no validation error. If App Store Connect refuses version 0.0.0, tell an agent: `fledge build ios` should then refuse it (ADR 012).
- **Status:** not run.
- **Blocks 1.0.0?** not decided.

#### IOS-2: TestFlight installs the build on a device

- **Proves:** a build that passed IOS-1 installs and runs on a phone or tablet through Apple's own channel, not Xcode's Run. Your iPad Pro and iPhone 13 mini already ran Fledge apps with a free Personal Team (proven, not in this list).
- **Needs:** IOS-1 passed, and a device signed in to TestFlight.
- **Steps:** App Store Connect's TestFlight page for the build; `doc/phones.md` has no steps for it.
- **Passing:** the app installs from TestFlight and runs as it did from Xcode.
- **Status:** not run.
- **Blocks 1.0.0?** not decided.

#### IOS-3: App Review approves a Fledge iOS app

- **Proves:** Apple's review accepts an app that carries a Ruby runtime, OpenSSL, and fiddle with libffi, with Fledge's privacy manifest. No Fledge app has been through it. Fledge left fiddle out of iOS for App Review until no guideline was found that forbids it (`doc/contributors/research/2026-11-12-ffi-and-fiddle-on-phones.md`); an app with the ffi gem, such as `examples/ffi_phone`, tests that claim most directly.
- **Needs:** IOS-1 passed, and an app worth submitting. The app is yours to choose.
- **Steps:** `doc/phones.md`, "The App Store", "Export compliance", and "The privacy manifest". Submit for review in App Store Connect.
- **Passing:** approved. A rejection is also a result: keep Apple's reason, which an agent then turns into a change or a note in `doc/phones.md`.
- **Status:** not run.
- **Blocks 1.0.0?** not decided.

### On Android, with a Google Play Console account

#### AND-1: Google Play takes a Fledge app bundle

- **Proves:** Play accepts the signed `.aab` that `./gradlew bundleRelease` makes, including the 16 KB alignment and the stored `fledge.zip` that CI checks with bundletool (`doc/contributors/design/phone-projects.md`, "The Android App Bundle check").
- **Needs:** a Google Play Console developer account, and an upload key made with `keytool`.
- **Steps:** `doc/phones.md`, "Google Play". Upload to an internal testing track.
- **Passing:** Play accepts the bundle with no error, and a device installs the app from the track and runs it. Your OnePlus Nord N30 5G is a device whose arm64-v8a library already ran Fledge's APK (proven, not in this list).
- **Status:** not run.
- **Blocks 1.0.0?** not decided.

#### AND-2: Google Play's review approves a Fledge Android app

- **Proves:** Play's review accepts an app that carries a Ruby runtime. No Fledge app has been through it.
- **Needs:** AND-1 passed, and an app worth publishing.
- **Steps:** `doc/phones.md`, "Google Play"; the review is in Play Console.
- **Passing:** the app is published on a track. A rejection is also a result: keep Google's reason.
- **Status:** not run.
- **Blocks 1.0.0?** not decided.

### Package managers' public routes

Every recipe in `doc/package_managers.md` is proven with the manager's own tool on fresh runners, against a local server (Plan 003, "A console app through a package manager"). Only a public repository adds an account and a review that no run has seen. These four are the routes the plan names as needing accounts: `winget-pkgs`, Chocolatey's repository, a tap on GitHub, and the AUR. Each needs a published GitHub Release of an app to point at.

#### PKG-1: winget-pkgs accepts a Fledge app's manifests

- **Proves:** Microsoft's review and virus scans of `winget-pkgs` accept a Ruby runtime in a portable package.
- **Needs:** the account the plan names for `winget-pkgs`, and a released console app.
- **Steps:** `doc/package_managers.md`, the winget section.
- **Passing:** the manifests merge, and `winget install` on a clean Windows computer installs the app and runs it by its command.
- **Status:** not run.
- **Blocks 1.0.0?** not decided.

#### PKG-2: Chocolatey's community repository accepts the package

- **Proves:** Chocolatey's moderation accepts the `.nupkg` with its `.ignore` files.
- **Needs:** a Chocolatey community repository account.
- **Steps:** `doc/package_managers.md`, the Chocolatey section.
- **Passing:** the package is approved, and `choco install` on a clean computer runs the app by its command.
- **Status:** not run.
- **Blocks 1.0.0?** not decided.

#### PKG-3: A Homebrew tap on GitHub installs on a clean Mac and Linux

- **Proves:** `brew tap` from GitHub and any trust step it asks for. Homebrew's official casks need notarization, which makes that route depend on MAC-1 and MAC-2 (question C in `questions.md`).
- **Needs:** a GitHub repository for the tap.
- **Steps:** `doc/package_managers.md`, the Homebrew section.
- **Passing:** `brew install` from the public tap installs the app and runs it by its command.
- **Status:** not run.
- **Blocks 1.0.0?** not decided.

#### PKG-4: The AUR accepts a `-bin` package

- **Proves:** the AUR's account and rules accept the `PKGBUILD`.
- **Needs:** an AUR account.
- **Steps:** `doc/package_managers.md`, the AUR section.
- **Passing:** the package is listed, and an AUR helper or `makepkg` installs it on Arch and runs the app.
- **Status:** not run.
- **Blocks 1.0.0?** not decided.

### Not testable yet

The Mac App Store needs a sandboxed mode and a `.pkg`, which Fledge does not build, and an MSIX for the Microsoft Store is after 1.0. They are not on this list until Fledge builds them.

## Not account-blocked, needs a person

These need no account, but they need a person at a real desktop. Agents do not do them, and they are not blocked on anything you buy. They are not on the list above, so none of them has a "Blocks 1.0.0?" line; decide for each whether it matters.

- **A drop on an app's icon in the Finder or the Dock.** Launch Services' offer and `open -a` are proved (ADR 052; `doc/contributors/design/desktop-apps.md`, "Files an app opens"), but not a real drop, nor a GUI library's drop event in a Fledge app. Agents do no SDL work, so the SDL3 app this test wants is yours to supply, or you can waive the test.
- **A Linux file manager's double-click.** The desktop entry's `MimeType=` and `Exec=... %F` are checked from the files; a real double-click in a file manager is not (ADR 052).
- **The Windows 10 floor on a real machine.** The README says Windows 10 and 11 on x64; the repository records no run of a built app on a real Windows 10 computer, only on GitHub's runners. Build or copy an app there and open it.

## Not in this list: already proven

A game on your iPad Pro and iPhone 13 mini with a free Personal Team, and on your OnePlus Nord N30 5G (`doc/contributors/device-test.md`, Plan 003). The playtest of `examples/sdl_phone` in `device-test.md` needs no paid account.
