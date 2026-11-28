# Sign and notarize an app

macOS and Windows warn before they open an app from the internet that nobody signed, and macOS refuses one Apple has not notarized. `fledge build` signs the app's code, and on macOS has Apple notarize it, when you give it the identity to sign with. A Linux app carries no signature for its system to check, so there is nothing to sign there.

Signing needs a certificate from Apple or a certificate authority, which you get and keep; Fledge never holds your keys.

## macOS: sign

With no identity, fledge signs a windowed app's bundle ad hoc, which lets it run on the Mac that built it, and on no one else's without a warning. To sign with your Developer ID:

1. Get a Developer ID Application certificate from your Apple Developer account, and install it in your keychain.
2. Find its name:

   <!-- SPDX-SnippetBegin -->
   <!--
     SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
     SPDX-License-Identifier: MIT-0
   -->
   ```console
   $ security find-identity -v -p codesigning
   ```
   <!-- SPDX-SnippetEnd -->

3. Build with it:

   <!-- SPDX-SnippetBegin -->
   <!--
     SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
     SPDX-License-Identifier: MIT-0
   -->
   ```console
   $ bundle exec fledge build --sign "Developer ID Application: Example, Inc. (ABCDE12345)"
   ```
   <!-- SPDX-SnippetEnd -->

fledge signs every file of code in the app with the hardened runtime, a secure timestamp, and Fledge's entitlements, then the app's bundle, then its disk image. When Apple's timestamp service doesn't answer, fledge asks it again, waiting 5, 10, 20, and 40 seconds, before it fails the build with `codesign`'s words.

## macOS: notarize

Notarizing sends the app to Apple, which checks it and issues a ticket that fledge staples to the app, so that macOS opens it without a warning, even offline.

1. Store your notary credentials in your keychain once, under a name of your choosing:

   <!-- SPDX-SnippetBegin -->
   <!--
     SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
     SPDX-License-Identifier: MIT-0
   -->
   ```console
   $ xcrun notarytool store-credentials notary
   ```
   <!-- SPDX-SnippetEnd -->

   `notarytool` asks for your Apple ID, your team, and an app-specific password, or an App Store Connect API key.

2. Build with your Developer ID and that name:

   <!-- SPDX-SnippetBegin -->
   <!--
     SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
     SPDX-License-Identifier: MIT-0
   -->
   ```console
   $ bundle exec fledge build --sign "Developer ID Application: Example, Inc. (ABCDE12345)" --notarize notary
   ```
   <!-- SPDX-SnippetEnd -->

fledge submits the disk image, or the bundle when the app has no disk image, or the folder of a console app, waits for Apple's answer, which takes minutes, and staples the ticket to the disk image and the bundle before it packs the archive. A console app has nothing to staple a ticket to. When Apple refuses, fledge prints each issue Apple's log lists, and the command that shows the whole log. Your credentials stay in the keychain: fledge passes only the profile's name to `notarytool`.

To check the result:

<!-- SPDX-SnippetBegin -->
<!--
  SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
  SPDX-License-Identifier: MIT-0
-->
```console
$ spctl --assess --type execute --verbose "dist/Cool App-arm64-darwin/Cool App.app"
```
<!-- SPDX-SnippetEnd -->

## Windows: sign with a certificate in your store

1. Install your code-signing certificate in your certificate store, and find its thumbprint, its SHA-1 hash:

   <!-- SPDX-SnippetBegin -->
   <!--
     SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
     SPDX-License-Identifier: MIT-0
   -->
   ```powershell
   (Get-ChildItem Cert:\CurrentUser\My -CodeSigningCert).Thumbprint
   ```
   <!-- SPDX-SnippetEnd -->

2. Build with it:

   <!-- SPDX-SnippetBegin -->
   <!--
     SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
     SPDX-License-Identifier: MIT-0
   -->
   ```console
   > bundle exec fledge build --sign 0123456789ABCDEF0123456789ABCDEF01234567
   ```
   <!-- SPDX-SnippetEnd -->

fledge signs with `signtool` from the Windows SDK, with SHA-256 and DigiCert's timestamp server. It finds `signtool` on `PATH`, or in the newest Windows SDK installed. Install one with `winget install Microsoft.WindowsSDK.10.0.26100`, or put Microsoft's SDK build-tools package's folder for your processor on `PATH`.

## Windows: sign with your own command

For a signing service, a hardware token, or a cloud key that `signtool` alone cannot reach, give fledge the command that signs one file:

<!-- SPDX-SnippetBegin -->
<!--
  SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
  SPDX-License-Identifier: MIT-0
-->
```console
> bundle exec fledge build --sign-command "C:\signing\sign.cmd %1"
```
<!-- SPDX-SnippetEnd -->

fledge runs the command once for each file, with the file's path, in quotes, in place of `%1`, or after the command when it has no `%1`. A command that holds all three of `'`, `"`, and `` ` `` can't be quoted for the setup program's compiler; put it in a `.cmd` file, as here. To sign every build on a computer without typing it, set `FLEDGE_SIGN_COMMAND` to the command instead.

## What gets signed, and in what order

On Windows, fledge signs each `.exe`, `.dll`, and `.so` in the app first. Then each installer is signed as fledge writes it: the setup program's compiler signs its uninstaller, then the setup program, and fledge signs the MSIX package. So the files inside each installer are signed before the installer seals them.

On macOS, fledge signs the code inside the bundle, then any console programs the bundle holds beside the app, then the bundle, then the disk image.

## What signing doesn't do

- An MSIX package for the Microsoft Store is signed by the Store; build it unsigned, with `msix_allow_unsigned: false` under `windows` in `fledge.yml`, so that its publisher stays the one Partner Center gave you.
- A phone's app is signed by Xcode or Gradle, when you build its project.
