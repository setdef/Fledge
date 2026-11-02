<!--
SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>

SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Questions for the Maintainer

This file holds only what agents cannot decide (AGENTS.md, Questions): an apparent conflict with, or ambiguity in, the maintainer's decisions in `decisions.md`, and direction only the maintainer can give. Everything agents invented is theirs to decide, by prior art, in an ADR. None of these blocks work: each names the default the work proceeds on and how to reverse it. When the maintainer answers, quote the answer in `decisions.md`, apply it, and remove the entry.

## A. An Apple Developer account, for iOS on a real device and App Store review

**Context.** The maintainer said on 2026-10-28: "We should eventually get an Apple Developer account, but I'd like to wait until the last responsible moment." Plan 002's story "Mobile apps from fledge build" reaches that moment for two of its proofs. `fledge build ios` writes an Xcode project that builds unsigned for devices and runs in the iOS Simulator on an iPhone and an iPad in CI (ADR 012). What remains needs a development team to sign with, which only an Apple Developer account gives: running a built app on a real iPhone and iPad, where Apple's sandbox differs from the Simulator's (no `fork`, a read-only bundle; ADR 011, section 6), and submitting one to App Review, which judges Fledge's runtime, its privacy manifest, and its interpreter (guidelines 2.5.2 and 4.2.6). Each developer signs and submits their own app; the account would be setdef's, for Fledge's own proof.

**Default.** Work proceeds without one: iOS is proven in the Simulator and by an unsigned device build in CI, and ADR 012 and Plan 002 list the device run and App Review as not yet proven. Nothing else in Plan 002 waits on it but notarization (entry B).

**To reverse.** Get the account (and, for CI, a device or a device cloud); then a story adds a signed device run and a TestFlight submission of `examples/hello` and `examples/mobile_app`.

## B. Accounts and certificates for signing Fledge's own proof: Apple's Developer ID and notarization, and Windows' code signing

**Context.** Decision 17 asks that developers who have done Apple's and Microsoft's ceremony be able to sign so that neither system blocks their app, and that those who have not still get an app that works. `fledge build --sign` now signs with the developer's own identity (ADR 016): codesign with the hardened runtime and a timestamp on macOS, signtool with SHA-256 and a timestamp on Windows. CI proves it with a self-signed certificate it makes in each run, verified by codesign and signtool on fresh runners. What a self-signed certificate cannot prove needs accounts only the maintainer can open, and the story "Signing and notarization" reaches the last responsible moment for them (decisions, 2026-10-28): notarization (`xcrun notarytool` and `stapler`), which needs an Apple Developer account, the same one entry A asks about; Gatekeeper's and SmartScreen's verdicts on a real trust chain, which need a Developer ID Application certificate from that account and a code signing certificate from a certificate authority (or an Azure Trusted Signing account, which signs through signtool with Microsoft's plug-in); and whether YJIT still needs `com.apple.security.cs.allow-unsigned-executable-memory` under a Developer ID's stricter checks.

**Default.** Unsigned builds stay the default, and `--sign` takes a developer's own identity, which Fledge never stores. Fledge does not notarize, and does not sign with Azure Trusted Signing; the README tells developers the two `xcrun` commands that notarize a signed disk image themselves, and tells the people they send an unsigned app how to open it on each system. ADR 016 and Plan 002 list notarization, the real trust chains, and Trusted Signing as not yet proven.

**To reverse.** Open the Apple Developer account (and, for Windows, buy a code signing certificate or open an Azure Trusted Signing account) and give CI its credentials as repository secrets; then a story adds `--notarize` (notarytool with an App Store Connect API key, then stapler on the disk image), Trusted Signing's signtool options, and Delivery jobs that check Gatekeeper's verdict (`spctl --assess`) and SmartScreen's on a downloaded copy.

## C. A device cloud account, to run Android's arm64-v8a build in CI

**Context.** Plan 003's story "Android on arm64" asks that every push run the Mobile apps checks (the parity probe and the HTTPS script) on an arm64-v8a emulator or device. No free GitHub-hosted runner can (ADR 011, Consequences, "Android on arm64, tried 2026-11-02"): Linux ARM64 runners have no `/dev/kvm` ("kvm: HYP mode not available"), every macOS runner is a virtual M1 on which the emulator's Hypervisor.framework fails with `HV_UNSUPPORTED`, Windows ARM64 runners have the Windows Hypervisor Platform off and report no hypervisor to guests, and Google publishes the Android emulator for Linux x86-64, macOS, and Windows x86-64 hosts only. The options that remain cost money or an account that only the maintainer can open: Firebase Test Lab (a Google Cloud project; the Spark plan has no cost and gives 60 virtual-device minutes and 30 physical-device minutes a day, then Blaze at $1 per virtual and $5 per physical device-hour, per firebase.google.com/pricing, read 2026-11-02); AWS Device Farm (real arm64 phones at $0.17 per device-minute, a 1,000-minute trial, or from $250 a month per device slot, per aws.amazon.com/device-farm/pricing); or a larger paid GitHub runner or a self-hosted Apple-silicon Mac with an M3 or later chip, which an emulator could use through Hypervisor.framework, at the price of the machine and of keeping it. Unverified: whether Test Lab's virtual devices are arm64-v8a, and whether a Test Lab or Device Farm run can drive Fledge's host app and read its results as `tasks/mobile_parity.rb` does through adb.

**Default.** Work proceeds without one: CI builds the arm64-v8a library and checks its APK, runs the same checks on x86_64 emulators, and the maintainer's one manual run on an Apple-silicon Mac stands as the only arm64-v8a evidence. The story stays open, and ADR 011 and ADR 012 say so.

**To reverse.** Decide which option, open the account, and give CI its credentials as repository secrets (never in the repository); then a story adds a job that uploads the host APK and runs the parity probe and the HTTPS script on an arm64-v8a device, and this entry is removed.
