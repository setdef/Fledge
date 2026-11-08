<!--
  SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
  SPDX-License-Identifier: CC-BY-SA-4.0
-->
# Desktop apps: names, windows, installers, and signing

Use this guide to give an app that [Fledge](../README.md) builds the name, icon, and installers people expect on macOS, Windows, and Linux, and how to sign it. You describe the app in `fledge.yml`, an optional YAML file at the top of your project, beside your `Gemfile`. `bundle exec fledge --help` prints every key.

## Name and describe your app

Without `fledge.yml`, an app is a console app named after your gemspec or your project's folder, at your gemspec's version or `0.0.0`. With these keys, you give it the name, version, and description each system shows:

<!-- SPDX-SnippetBegin -->
<!--
  SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
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
  SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
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
  SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
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
  SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
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

An app is unsigned unless you sign it. Without a signature, macOS's [Gatekeeper](https://support.apple.com/guide/security/gatekeeper-and-runtime-protection-sec5599b66df/web) and Windows' [SmartScreen](https://learn.microsoft.com/windows/security/operating-system-security/virus-and-threat-protection/microsoft-defender-smartscreen/) warn the people who download your app.

To sign with your identity, pass `--sign` to `fledge build`:

- **macOS:** a code signing identity from your keychain, such as `"Developer ID Application: NAME (TEAM)"`.
- **Windows:** the SHA-1 thumbprint of a code signing certificate in your certificate store.

Fledge signs every program and library, the app bundle, and the installer. A macOS signature carries a timestamp from Apple's server; when that server does not answer, Fledge signs again after 5, 10, 20, and 40 seconds before it gives up. Fledge does not sign Linux apps, and does not notarize Mac apps: `xcrun notarytool` notarizes a signed disk image. Xcode and Gradle sign a phone's app. Fledge's CI signs with a self-signed certificate only, so how Gatekeeper and SmartScreen treat an app signed with a certificate from Apple or a certificate authority is untested.
