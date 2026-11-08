<!--
  SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
  SPDX-License-Identifier: CC-BY-SA-4.0
-->
# Desktop apps: names, windows, installers, and signing

Use this guide to give an app that [Fledge](../README.md) builds the name, icon, and installers people expect on macOS, Windows, and Linux, and how to sign it. You describe the app in `fledge.yml`, an optional YAML file at the top of your project, beside your `Gemfile`. `bundle exec fledge --help` prints every key.

## Name and describe your app

Without `fledge.yml`, an app is a console app named after your gemspec or your project's folder, at your gemspec's version or `0.0.0`. With these keys, you give it the name, version, and description each system shows:

<!-- SPDX-SnippetBegin -->
<!--
  SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
  SPDX-License-Identifier: MIT-0
-->
```yaml
name: My Cool App
version: "1.0.0"
publisher: Example, Inc.
copyright: © 2026 Example, Inc.
description: Keeps your notes
homepage: https://example.com/my-cool-app
```
<!-- SPDX-SnippetEnd -->

On Windows, every program carries these, console programs too: Explorer shows them in the program's properties, with the description as its comments. Read on for what each key does on the other systems.

## Make a windowed app

An app that opens its own windows, through a GUI library such as [SDL](https://www.libsdl.org/), sets `kind: windowed`, with an identifier and an icon:

<!-- SPDX-SnippetBegin -->
<!--
  SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
  SPDX-License-Identifier: MIT-0
-->
```yaml
name: My Cool App
kind: windowed
identifier: com.example.MyCoolApp   # reverse-DNS; macOS and Windows know the app by it
version: "1.0.0"
icon: icons/app                     # icons/app.icns, icons/app.ico, icons/app-16.png to -512.png
description: Keeps your notes
long_description: |
  My Cool App keeps your notes in plain files.
homepage: https://example.com/my-cool-app
license_file: LICENSE.txt
installers: [dmg, nsis, appimage, deb]
linux:
  deb_changelog: CHANGES.txt
macos:
  build: "1.0.417"
```
<!-- SPDX-SnippetEnd -->

Fledge then builds:

| macOS | Windows | Linux |
| --- | --- | --- |
| a `.tar.gz` holding `NAME.app`, and a `.dmg` | a `.zip` holding `NAME.exe`, which opens no console, and a `-setup.exe` that installs without an administrator | a `.tar.gz` holding the program, a desktop entry, and icons; an AppImage; and a `.deb` if you ask for one |

Each system shows the app's name, icon, and version in its usual places. If you change `identifier` later, each system sees a new app, and Windows and `apt` install it beside the old one. [`examples/windowed_app`](../examples/windowed_app) is a complete example.

What each key does:

- **`icon`** names the icon's files without their extension. Make one `.icns` for macOS, one `.ico` for Windows, and for Linux a PNG of each size you have, of 16, 32, 64, 128, 256, and 512 pixels. Linux needs at least one. `fledge build` warns about each size you lack, and the desktop scales the nearest one.
- In **`installers`**, list which of `dmg`, `nsis`, `appimage`, and `deb` to build. The default is the first three. A `.deb` needs `dpkg-deb` on your computer, and an AppImage needs `mksquashfs` from squashfs-tools 4.4 or newer.
- **`description`** is the tooltip that Linux menus show, and the summary line of a `.deb`. **`long_description`**, in paragraphs, follows it in the `.deb`, for `apt show` and software centers.
- **`homepage`** is the `.deb`'s homepage, and the link that Windows' Settings shows for the installed app.
- **`license_file`**, a UTF-8 file in your project, is a page that the Windows setup program shows before it installs, and the `.deb`'s copyright file.
- With **`linux: deb_changelog`**, Fledge adds your changelog to the `.deb`.
- **`macos: build`** is the Mac app's build number, which the App Store and updaters compare. Without it, the build number is the version's first three numbers.

A `.deb` depends on `libc6`, and on the packages of any libraries you list under `linux: system_libraries` (see [Gems](gems.md)), so `apt` installs it on a computer without a desktop too. A library that a gem opens while your app runs, such as the X11, Wayland, or OpenGL libraries SDL opens, comes from the desktop, and Fledge cannot check that it is there.

## Open files and folders with your app

A windowed app can list the files and folders it opens, so that each system offers the app for them:

<!-- SPDX-SnippetBegin -->
<!--
  SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
  SPDX-License-Identifier: MIT-0
-->
```yaml
file_associations:
  - name: Project folder
    folders: true
  - name: Project archive
    role: editor                    # viewer, the default, or editor
    extensions: [zip]
    mime_types: [application/zip]
```
<!-- SPDX-SnippetEnd -->

- **macOS** lists the app under "Open With" for them, and never makes it their default unless your users do. Add `content_types` for macOS's types, such as `public.zip-archive`, where you know them.
- **Windows:** the setup program adds the app to each extension's "Open with" list and to every folder's menu, and its uninstaller removes them. Windows registers nothing for an app your users unpack from the `.zip`.
- **Linux** desktops know a file by its MIME type, so list `mime_types` for Linux.

On Windows and Linux, your program receives the path of a file or folder opened with it, or dropped on it, in `ARGV`. On macOS, the system sends the path as an Apple event instead, and your GUI library's event loop receives it, as SDL3 does with `SDL_EVENT_DROP_FILE`. `ARGV` stays empty there, as it does under `ruby main.rb`.

## Ship several programs in one app

If your app has more than one way in, such as a window, a terminal interface, and a command line that all open the same save file, list them under `programs`. Fledge builds them into one folder that shares one Ruby, one copy of your project, and one set of gems:

<!-- SPDX-SnippetBegin -->
<!--
  SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
  SPDX-License-Identifier: MIT-0
-->
```yaml
name: Shared Save
programs:
  - path: window.rb
    kind: windowed
    identifier: com.example.SharedSave
  - path: bin/shared-save
    kind: console
```
<!-- SPDX-SnippetEnd -->

`fledge build` with no argument builds all of them, and `fledge build bin/shared-save` builds that program alone. At most one program is windowed. Fledge gives it the app's name unless you give it a `name`, builds the installers for it, and on macOS puts the console programs inside its `.app` bundle. Fledge names each console program after its file, such as `shared-save`, the command your users type. [`examples/programs`](../examples/programs) is a complete example.

## Sign your app

An app is unsigned unless you sign it. Without a signature, macOS's [Gatekeeper](https://support.apple.com/guide/security/gatekeeper-and-runtime-protection-sec5599b66df/web) and Windows' [SmartScreen](https://learn.microsoft.com/windows/security/operating-system-security/virus-and-threat-protection/microsoft-defender-smartscreen/) warn the people who download your app. On a Mac, Gatekeeper opens a downloaded app without a warning only once Apple has also notarized it. Your credentials stay on your computer: none of them goes in `fledge.yml`, which other people build too.

### On macOS

Pass `--sign` with a code signing identity from your keychain, and `--notarize` with the name of a notarytool profile:

<!-- SPDX-SnippetBegin -->
<!--
  SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
  SPDX-License-Identifier: MIT-0
-->
```console
$ bundle exec fledge build --sign "Developer ID Application: Example, Inc. (ABCDE12345)" --notarize example-notary
```
<!-- SPDX-SnippetEnd -->

Fledge signs every program and library with the hardened runtime and a timestamp from Apple's server, then the app bundle, then the disk image. When the timestamp server does not answer, Fledge signs again after 5, 10, 20, and 40 seconds before it gives up.

With `--notarize`, Fledge sends the signed disk image to Apple's notary service and waits for Apple's answer, which most apps get within 15 minutes. It then staples Apple's ticket to the disk image and to the app bundle, so that Gatekeeper finds it even on a Mac with no network, and only then packs the archive, which holds the stapled bundle. A console app has no bundle to staple to: Fledge sends its folder in a zip archive, and Gatekeeper looks up its ticket online. When Apple refuses the app, the build fails and lists each problem from Apple's log.

The profile keeps your Apple credentials in your keychain, where notarytool reads them. Store them once, with an [App Store Connect API key](https://developer.apple.com/documentation/appstoreconnectapi/creating-api-keys-for-app-store-connect-api), or with your Apple ID and an [app-specific password](https://support.apple.com/102654):

<!-- SPDX-SnippetBegin -->
<!--
  SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
  SPDX-License-Identifier: MIT-0
-->
```console
$ xcrun notarytool store-credentials example-notary --key ~/private_keys/AuthKey_ABC123DEFG.p8 --key-id ABC123DEFG --issuer 69a6de70-0000-0000-0000-000000000000
$ xcrun notarytool store-credentials example-notary --apple-id you@example.com --team-id ABCDE12345
```
<!-- SPDX-SnippetEnd -->

A Developer ID Application certificate and an App Store Connect key come with the [Apple Developer Program](https://developer.apple.com/programs/). Apple notarizes no ad hoc signature, so `--sign -` and `--notarize` together fail.

### On Windows

Pass `--sign` with the SHA-1 thumbprint of a code signing certificate in your certificate store, and Fledge signs with `signtool` from the Windows SDK, with SHA-256 and a timestamp from DigiCert's server.

A certificate kept in a cloud or a hardware service, such as [Azure Artifact Signing](https://learn.microsoft.com/azure/artifact-signing/), DigiCert KeyLocker, or SSL.com eSigner, signs with that service's own tool. Pass `--sign-command` with the command that signs one file, and `%1` where the file's path goes:

<!-- SPDX-SnippetBegin -->
<!--
  SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
  SPDX-License-Identifier: MIT-0
-->
```console
> bundle exec fledge build --sign-command "signtool sign /fd sha256 /tr http://timestamp.acs.microsoft.com /td sha256 /dlib C:\ArtifactSigning\bin\x64\Azure.CodeSigning.Dlib.dll /dmdf C:\ArtifactSigning\metadata.json %1"
```
<!-- SPDX-SnippetEnd -->

Fledge runs the command through `cmd.exe` once for each program and library, then for the uninstaller and the setup program as it writes them, with the path in quotes. Without `%1`, the path goes at the end, so a `.cmd` file of your own works too. A command that exits with anything but 0 stops the build and names the file. Fledge never prints the command, which may hold a password. To keep the command out of your build scripts, set `FLEDGE_SIGN_COMMAND` instead, as a CI secret can.

### What is proven

Fledge's CI signs with a self-signed certificate, on macOS and on Windows, and runs `signtool` through `--sign-command` too. It notarizes against a stand-in for Apple's service that answers as Apple documents. How Gatekeeper and SmartScreen treat an app signed and notarized with real credentials is untested. Fledge does not sign Linux apps, and Xcode and Gradle sign a phone's app.

## Publish to a store

No Fledge app has been through any store's review. This section says what each store's own documents ask for, as they read on 2026-11-04, against what Fledge writes. A store can still refuse an app for a reason its documents leave out, and only a submission settles that. For phones, see [Google Play and the App Store](phones.md#google-play).

### The Microsoft Store

The Store's [policy 10.2.9](https://learn.microsoft.com/windows/apps/publish/store-policies) takes a desktop program as an `.exe` installer at a link you give it, and the setup program Fledge writes fits what it lists:

- It holds the whole app, and is no downloader stub.
- `/S` installs it silently, which the policy asks for. Fledge's CI installs it this way, runs the app from the Start menu, and uninstalls it.
- It installs for one person, with no administrator, and adds a Start menu entry and an uninstaller.

What the setup program lacks, you bring:

- **A certificate.** The setup program, and every program and library in it, must chain to a certificate authority in Microsoft's Trusted Root Program. The Store does not sign this route for you, and a self-signed certificate will not pass. `--sign` signs them all, and `--sign-command` does the same through a cloud or hardware service. [Microsoft's table](https://learn.microsoft.com/windows/msix/package/signing-package-overview) lists Azure Artifact Signing at about US$10 a month and an OV certificate at US$300 to 500 a year.
- **A versioned HTTPS address**, whose file never changes. A GitHub Release's address redirects to a download host, and whether the Store's check takes that is unknown.
- **A Partner Center account.** Microsoft's [new onboarding flow](https://learn.microsoft.com/windows/apps/publish/partner-center/open-a-developer-account) charges no registration fee.

No one has tried this. Fledge's CI signs the setup program with a self-signed certificate only, so the Store's certification, and its malware scan of a Ruby runtime, are unknown.

The Store's other route takes an MSIX package, which it signs and hosts for free. Fledge writes no MSIX.

### The Mac App Store

Fledge does not build for the Mac App Store. Its `.app` is signed for Developer ID, for people who download it from you. The Store takes a different program: an [App Sandbox](https://developer.apple.com/documentation/xcode/configuring-the-macos-app-sandbox) on every executable, a provisioning profile, Apple Distribution and Mac Installer Distribution certificates, and a `.pkg`. Inside the sandbox, your Ruby code reads only its own container and the files a person picks, so it no longer runs as it does under `ruby main.rb`. Ship a Mac app outside the Store, signed and notarized, as [Sign your app](#sign-your-app) says.

### Linux

Flathub, the Debian and Ubuntu archives, and Launchpad PPAs take only what they build from source, so none of them takes a Fledge app. [Flathub says](https://docs.flathub.org/docs/for-app-authors/requirements) "Binary or precompiled files must not be present in the submission pull request". Fedora's rules were out of reach when this was written. Three routes take prebuilt apps, and no one has tried any of them with a Fledge app:

- **Your own apt repository.** Serve the `.deb` Fledge builds from a repository you make with [`reprepro` or `aptly`](https://wiki.debian.org/DebianRepository/Setup) and sign, and your users [add your key and a `.sources` file](https://wiki.debian.org/DebianRepository/UseThirdParty). Fledge's CI installs the `.deb` with `apt`, from the file. It has not served one from a repository.
- **The Snap Store.** Its documents ask for no source build in what was read, and [Tauri's guide](https://v2.tauri.app/distribute/snapcraft/) makes a strict snap with snapcraft's `dump` plugin from a built `.deb`. Fledge writes no `snapcraft.yaml`, so you would write one. A strict snap sees only what its interfaces open, so the app's files and network reach differ from `ruby main.rb`. Whether the launcher runs from a snap's read-only mount is unknown.
- **Your own Flatpak repository.** [Flatpak's guide](https://docs.flatpak.org/en/latest/hosting-a-repository.html) says how to host one, on a web server or GitLab Pages. Fledge writes no Flatpak, so you would write its manifest, and the default sandbox gives an app no host files or network until you open them.
