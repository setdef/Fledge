<!--
SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>

SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Signing and Notarizing a Desktop App

This document says how `fledge build` signs a macOS or Windows app and has Apple notarize a macOS one: what each tool is given, in which order, how a tool is found, when a command runs again, and how CI proves it without the maintainer's accounts. It is for Fledge's contributors; an app's developer reads `doc/desktop_apps.md`, "Sign your app". Why things are so is in ADR 016 (`--sign` and each system's signer), ADR 050 (the hardened runtime and its entitlements), ADR 051 (`--sign-command`), and ADR 033 (`--notarize`). The unsigned ad hoc signature every macOS bundle gets is in `doc/contributors/design/desktop-apps.md`, "Identity on each system".

## Where signing comes in the build

A signature seals what it covers, so signing comes after Fledge has written everything into the app, and before the installers and the archive, which carry the signed files (`Fledge::Assembly`):

1. The project, its gems, and `fledge.cfg` are in place, and each program is placed last: on Windows with its resources from rcedit, on Linux after its desktop entry.
2. The app's code is signed (`Signing.for` chooses the signer from the build's platform and options).
3. `build_tools`, when set, is copied in, unsigned (`doc/contributors/design/desktop-apps.md`, "Building from a built app").
4. The installers are written; a disk image is signed once hdiutil writes it, and makensis signs the uninstaller and the setup program as it writes them.
5. With `--notarize`, Apple notarizes and the tickets are stapled.
6. The archive is packed, and then `fledge build` writes each file's checksum, so every checksum is of a signed, stapled file.

A Linux build with `--sign` or `--sign-command` fails, since a Linux app carries no signature for its system to check. On a phone, either option is a usage error: Xcode and Gradle sign a phone's app. `--sign` and `--sign-command` exclude each other, a usage error.

## Signing on macOS

`Fledge::MacSigning` runs codesign with these options on code (`MacSigning#code_options`):

```
codesign --force --sign IDENTITY --options runtime --timestamp --entitlements lib/fledge/templates/macos/entitlements.plist FILE...
```

The ad hoc identity, `-`, gets the same options but `--timestamp`, which needs a certificate to stamp. The entitlements are ADR 050's two. The order is inside out, as Apple asks of nested code:

1. Every Mach-O program and library of a console app's folder, or of a windowed app's `Contents/Resources`: the launcher, `bin/ruby`, Ruby's extensions, and the app's gems' compiled files. A file is code when its first bytes say Mach-O (`Fledge::Binary.format_of`); symbolic links are skipped, and so are object files (`MH_OBJECT`, a thin Mach-O whose file type is 1), which a gem's build can leave beside its extension and which nothing runs or loads. They go to codesign 100 at a time.
2. A windowed app's console programs in `Contents/MacOS` (ADR 024), in one run.
3. The bundle, with `--identifier IDENTIFIER`, which seals the rest, in place of the ad hoc signature an unsigned bundle gets.
4. The disk image, after `hdiutil` writes it: `codesign --force --sign IDENTITY --timestamp FILE.dmg`, with no hardened runtime or entitlements, as notarization asks of an image it staples a ticket to.

Every command has `--force`, so a run again replaces whatever a failed run signed.

## Signing on Windows

`Fledge::WindowsSigning` takes `--sign`'s value as a SHA-1 thumbprint, 40 hexadecimal digits, and refuses anything else, saying how `(Get-ChildItem Cert:\CurrentUser\My -CodeSigningCert).Thumbprint` shows one. It signs every PE file of the app's folder whose extension is `.exe`, `.dll`, or `.so` (Ruby's extensions), found by their first bytes, after rcedit has written each program's resources:

```
signtool sign /sha1 THUMBPRINT /fd sha256 /tr http://timestamp.digicert.com /td sha256 FILE...
```

These are Briefcase's defaults: SHA-256, and a timestamp from a server that stamps any certificate's signature, so the signature stays valid after the certificate expires. Files go 50 at a time. Ruby's own DLLs are signed too, which RubyInstaller ships unsigned, because Smart App Control checks every library a process loads.

**Finding signtool.** The Windows SDK puts signtool on no `PATH`. Fledge takes the first `signtool.exe` on `PATH`, or else the newest the SDK installed for the computer's architecture, `%ProgramFiles(x86)%\Windows Kits\10\bin\VERSION\x64\signtool.exe` (or `arm64` when `PROCESSOR_ARCHITECTURE` is `ARM64`), the newest VERSION by RubyGems' version order. With none, the build fails, naming the SDK's Signing Tools and `winget install Microsoft.WindowsSDK.10.0.26100`.

**The setup program.** A windowed app's NSIS script gets two lines with the same command line, signtool's above with `"%1"` in place of the files (`WindowsSigning#command_line`), or the developer's signing command:

```
!uninstfinalize 'COMMAND' = 0
!finalize 'COMMAND' = 0
```

NSIS 3.08 and later run `!uninstfinalize` on the uninstaller they write into the installer, before packing it, and `!finalize` on the installer, and fail unless the command exits 0. makensis replaces each `%1` with the file's path, verbatim, and runs the command through `%COMSPEC% /C IF 1==1 COMMAND`, the `IF 1==1` keeping `cmd.exe` from stripping the quotes off a command that begins with one (NSIS 3.13, `Source/build.cpp`, `run_postbuild_cmds`, lines 4195 to 4228; `Source/util.cpp`, `sane_system`, lines 1220 to 1245). makensis has no escape for a quote of the kind a string is quoted with, so the command goes in the first of `'`, `` ` ``, and `"` it does not hold; a command that holds all three fails the build, saying to put it in a `.cmd` file (`Nsis::Script#finalize`). A failed command makes makensis print "Finalize command returned N, aborting" or "UninstFinalize command returned N, aborting", which Fledge reads to name the setup program or its uninstaller and the exit status (`Nsis#signing_failure`).

## Timestamps

`--timestamp` asks Apple's timestamp server for a secure timestamp over each signature, so every signed macOS build depends on that server. When it does not answer, codesign stops with "A timestamp was expected but was not found." (the description of `errSecTimestampMissing`, -67882, in `<Security/SecBase.h>`) or "The timestamp service is not available." (`errSecTimestampServiceNotAvailable`, -67885). Every codesign Fledge runs goes through one method that, when codesign fails and its output holds either description (`MacSigning::TIMESTAMP_FAILURES`), waits and runs the same command again, after 5, 10, 20, and 40 seconds (`MacSigning::WAITS`), five runs in all, as Defold does. Any other failure, or a fifth of these, fails the build with codesign's own words. The prior art signs again on those words only: VS Code (`build/darwin/sign.ts`, lines 44 to 75, at microsoft/vscode b4bd9bd), Defold (`build_tools/codesigning.py`, lines 146 to 160, at defold/defold d4ca5d4), and Datadog's agent, through a generic retry.

Rules a reader might otherwise change:

- **Match the text, not the exit status**, which is 1 for every failure, so a real error does not cost 75 seconds. `Fledge::Dmg` does the same for hdiutil.
- **Do not retry the keychain.** VS Code also retries "The specified item could not be found in the keychain.", a short-lived problem on its own build agents, which sign with one known identity. On a developer's Mac, a keychain that cannot give up the identity named with `--sign` is the developer's to fix, as is an identity it lacks (`codesign --sign Nobody` says "Nobody: no identity found"), and waiting would only delay saying so.
- **The waits are longer than a download's** (`doc/contributors/design/releases.md`) because a signing build is a release, not a developer's every build, and an outage that cleared within seconds would not have failed. They are fixed, so a test can name them.

signtool's timestamp from DigiCert is not retried: no run has seen it fail, and makensis runs it through `!finalize`, where Fledge cannot run it again. notarytool is not retried either (see "Notarization").

The failure cannot be provoked on demand, so `test/mac_signing_test.rb` puts a `codesign` first on `PATH` that fails with each message as many times as a test asks and then runs the real `/usr/bin/codesign`, with the real `Fledge::Command`, `Fledge::Dmg`, and hdiutil around it.

## The signing command

`--sign-command COMMAND`, or `FLEDGE_SIGN_COMMAND` in a Windows build whose command line gives neither `--sign` nor `--sign-command` (an empty or blank value counts as none), signs a Windows app through the developer's own command (ADR 051; `Fledge::SignCommand`). A build for another system ignores the variable. An empty command is refused.

- **The files.** COMMAND runs once for each file `--sign` would sign (`WindowsSigning.files`: the programs, Ruby's DLLs, and its extensions), in the order of their paths, and then makensis runs it on the uninstaller and the setup program.
- **The path.** Fledge replaces each `%1`, bare or in double quotes, with the file's absolute path, with Windows' backslashes, in double quotes, since an app's name may hold spaces. A command with no `%1` gets the path at its end, so a `.cmd` file of the developer's own is a whole command. makensis gets the command with `"%1"` in the same places, and fills it in itself.
- **How it runs.** Fledge hands Ruby `IF 1==1 LINE`, which Ruby runs as `%COMSPEC% /c "IF 1==1 LINE"`, since a line that begins with a `cmd.exe` internal command runs through the shell (Ruby 4.0, `win32/win32.c`, `w32_spawn`, lines 1328 to 1335, and `is_internal_cmd`; `if` is one, line 977). That is the line NSIS's `sane_system` builds, so a command behaves the same for a program and for the setup program, environment variables and `.cmd` files included.
- **The failure.** Exit status 0 means signed. Anything else fails the build, naming the file, the exit status, and what the command printed, with anything not UTF-8 replaced. Fledge never prints the command, which may hold a secret (eSigner's CodeSignTool takes a password), and makensis, run at `-V2`, prints only its "returned N" line and the command's own output.

An Artifact Signing command, from Microsoft's "Set up signing integrations to use Artifact Signing", is signtool with Microsoft's plug-in and the account's metadata file:

```
signtool.exe sign /fd SHA256 /tr "http://timestamp.acs.microsoft.com" /td SHA256 /dlib "...\x64\Azure.CodeSigning.Dlib.dll" /dmdf "...\metadata.json" %1
```

## Notarization

`--notarize PROFILE` (ADR 033) needs `--sign IDENTITY`, a usage error without it, as with `--sign-command` or a phone. For Windows, and with the ad hoc identity `-`, which Apple does not notarize, the build fails. `Fledge::Notary` is the Gateway to notarytool and stapler, which come with Xcode and its Command Line Tools; Assembly calls it after the installers are written and before the archive is packed.

**What is sent.** Apple notarizes "the top-level file that you specify, as well as each nested file", and says to notarize only the outermost container:

- **A windowed app with a disk image** (the default): the signed `.dmg`, which holds the signed bundle, is the one submission, as Briefcase sends only the image.
- **A windowed app without one** (`installers: []`): the bundle, in a zip.
- **A console app:** its whole folder, in a zip, so every Mach-O file in it is notarized.

Every zip is `ditto -c -k --sequesterRsrc --keepParent PATH ZIP`, Apple's command with the `--sequesterRsrc` that Briefcase, Tauri, and @electron/notarize add, which keeps extended attributes in the archive's `__MACOSX` folder and out of the bundle. The zip goes in a temporary folder and is not kept.

**What is stapled, in which order.** The ticket is stapled to the disk image, then to the bundle in the app's folder, which the service issued a ticket for as a nested file, as Tauri staples its bundle. Then the archive is packed, so it holds the stapled bundle, as Apple asks of a zip ("run `stapler` against each item that you added to the archive"), and a `.tar.gz` is no different. The bundle inside the image is not stapled: stapling it would change a signed image, and "Code-signing a supported file format invalidates any stapled tickets" fixes the order as sign the image, notarize it, staple it. Gatekeeper reads the image's ticket when it opens the image, and the bundle's ticket online once it is copied out. A console app's zip is not stapled, since Apple cannot staple a lone program; Gatekeeper looks its ticket up online the first time someone runs it. After each staple, `xcrun stapler validate` checks it. stapler runs in the folder that holds the file, with the file's name, as @electron/notarize and Tauri run it. Each step's progress goes to standard error.

**Apple's answer.** Fledge runs

```
xcrun notarytool submit FILE --keychain-profile PROFILE --wait --output-format json
```

and reads the JSON whatever notarytool's exit status, since neither Apple's pages nor the prior art pins that status for an Invalid answer. Only `"status": "Accepted"` notarizes. Any other status (Invalid, Rejected, or In Progress, should the wait be cut short) fails the build with the submission's ID and status, then what `xcrun notarytool log ID --keychain-profile PROFILE` says, its `statusSummary` and each issue's severity, path, message, and documentation link, as Briefcase lists them, and the command that reads the whole log. When notarytool prints no submission, as when it cannot reach Apple, the build fails with notarytool's own words; for exit status 69, a profile the keychain lacks ("Error: No Keychain password item found for profile: NAME", notarytool 1.1.4), it adds how to store one under that name with `xcrun notarytool store-credentials`.

There is no `--timeout`, as neither Tauri nor @electron/notarize sets one: Apple says 98 percent of software finishes within 15 minutes, and a developer who stops waiting stops the build. A failed submission is not sent again: unlike a lost timestamp, it is a new request, and Apple limits them to 75 a day.

## What CI proves, and the stand-ins

No CI runner has a certificate macOS or Windows trusts, or an Apple account, so CI makes what it can and stands in for the rest:

- **A self-signed identity**, made fresh in each run (`.github/scripts/make-test-identity.sh` and `.ps1`): on macOS in a temporary keychain, trusted for code signing in the runner's system keychain, as `security add-trusted-cert` does; on Windows in the current user's store and its root store, so signtool can verify the chain. The Build jobs build `examples/hello` and `examples/windowed_app` with `--sign`, and on Windows again with `--sign-command` running the real signtool; the macOS and Windows Test jobs run `test/built_app_test.rb`'s signed builds with `FLEDGE_TEST_SIGN_IDENTITY` (`-` signs ad hoc on any Mac).
- **Delivery** verifies the signed builds on fresh runners: on macOS (`.github/scripts/deliver-signed.sh`) `codesign --verify --strict` on every Mach-O file, `--deep` on the bundle, the hardened runtime and a timestamp on each, the entitlements, the signed disk image, the apps running, and YJIT writing code; on Windows (`.github/scripts/deliver-signed.ps1`) `signtool verify /pa` on every PE file, the setup program, and the uninstaller it installed, refused before the test certificate is trusted and accepted after. Unsigned builds pass every Delivery job too.
- **The stand-in notary**, `test/support/stand_in_notary.rb`, puts an `xcrun` first on `PATH` that answers `notarytool submit` with notarytool's JSON (Accepted; Invalid with exit 1; an offline error; notarytool 1.1.4's message and exit 69 for a missing profile), `notarytool log` with Apple's own example log from "Customizing the notarization workflow", and `stapler` by writing a mark where stapler puts a bundle's ticket (`Contents/CodeResources`, which `codesign --verify --strict --deep` leaves alone) or on an image's end, and records each call and each file submitted. `test/notary_test.rb` checks every command and its order, an Invalid answer's issues, notarytool's words for a failure, the hint for a missing profile, and that no authenticating option reaches a command line. `test/built_app_test.rb` builds both examples with `--notarize` and the stand-in, and checks that the image went to Apple signed with the signed bundle in it, that the image and then the bundle were stapled, that the archive holds the stapled bundle and it still verifies, that the checksum is of the stapled image, and that the console app went as a zip of its folder.
- **The stand-in signer**, `test/support/stand_in_signer.rb`, a `.cmd` file on Windows and a shell script elsewhere, records each path and appends a mark to the file. `test/sign_command_test.rb` checks the path's place, makensis's form, one run per file in order, a failure that names the file and not the command, and, on Windows with a runtime, a whole build through `FLEDGE_SIGN_COMMAND`: every PE file, then the uninstaller, then the setup program; the marks on the archive's program and the setup program; the checksum of the signed setup program; and a failure on the setup program that names it.
- **The contract test**, `test/built_app_test.rb`'s `test_a_notarized_build_opens_with_gatekeepers_blessing`, runs only when `FLEDGE_TEST_NOTARY_PROFILE` is set: Apple's real service, then `stapler validate`, and `spctl --assess` saying "source=Notarized Developer ID" for the image and the bundle. The maintainer runs it (`doc/contributors/signing-test.md`). What waits on his accounts is listed in `doc/contributors/account-tests.md`.
