# Make a windowed app

A windowed app opens windows, through a gem that draws them, such as a GUI toolkit's or a game library's, and is started from a desktop rather than a terminal. Fledge gives it what each desktop expects of such an app: a macOS bundle and disk image, a Windows program that opens no console and a setup program, and a Linux desktop entry and AppImage. This guide makes the console app from [the tutorial](../tutorial.md) a windowed one; the program itself is yours to write with the gem you choose.

## Say that it's windowed

In `fledge.yml`, set `kind`, and give the app an identifier:

<!-- SPDX-SnippetBegin -->
<!--
  SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
  SPDX-License-Identifier: MIT-0
-->
```yaml
name: Cool App
version: "1.2.3"
kind: windowed
identifier: com.example.CoolApp
publisher: Example, Inc.
copyright: "© 2026 Example, Inc."
description: Keeps your notes
```
<!-- SPDX-SnippetEnd -->

The identifier is how each system tells your app from every other: macOS's bundle identifier, the ID Windows groups the app's windows and shortcuts by, and the name of its Linux desktop entry. Make it a domain you control, reversed, and keep it once people have installed the app. fledge refuses a windowed app without one, and suggests one.

`publisher`, `copyright`, and `description` are optional; [the fledge.yml reference](../reference/fledge-yml.md#identity) lists where each system shows them. The version is the one each system shows; quote it.

## Add an icon

Name the icon's files without an extension:

<!-- SPDX-SnippetBegin -->
<!--
  SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
  SPDX-License-Identifier: MIT-0
-->
```yaml
icon: icons/app
```
<!-- SPDX-SnippetEnd -->

and put each system's file beside it: `icons/app.icns` for macOS, `icons/app.ico` for Windows, and PNGs named for their size, such as `icons/app-256.png`, for Linux. A build reads only the file for its system, and fails, naming it, when it's missing. [Icon files](../reference/fledge-yml.md#icon-files) lists every size.

## Build on each desktop

`bundle exec fledge build` on each computer prints the archive, and then each installer. On a Mac:

<!-- SPDX-SnippetBegin -->
<!--
  SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
  SPDX-License-Identifier: MIT-0
-->
```console
$ bundle exec fledge build
Writing the gems' executables for arm64-darwin
dist/Cool App-arm64-darwin.tar.gz
dist/Cool App-arm64-darwin.dmg
```
<!-- SPDX-SnippetEnd -->

What each desktop gets:

| Desktop | The app | Installers, by default |
| - | - | - |
| macOS | `Cool App.app`, a bundle whose `Info.plist` holds the name, identifier, version, copyright, and icon, signed ad hoc unless you [sign it](signing.md) | `Cool App-arm64-darwin.dmg`, a disk image of the bundle beside a link to Applications |
| Windows | `Cool App.exe`, a Windows GUI program, so no console window opens with it, carrying the icon, version, publisher, copyright, and description as its file properties | `Cool App-x64-mingw-ucrt-setup.exe`, a setup program that installs for the person who runs it, with no administrator, adds a Start menu shortcut, offers a desktop shortcut, and registers an uninstaller in Settings |
| Linux | the program, with `com.example.CoolApp.desktop` and its icons beside it, in the folder | `Cool App-x86_64-linux.AppImage`, one file that runs the app on a computer with FUSE (see [Run the AppImage without FUSE](#run-the-appimage-without-fuse)) |

To run the app from a terminal while you work on it, run its launcher there, and your program's output appears in the terminal. On a Mac the launcher is inside the bundle:

<!-- SPDX-SnippetBegin -->
<!--
  SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
  SPDX-License-Identifier: MIT-0
-->
```console
$ "dist/Cool App-arm64-darwin/Cool App.app/Contents/MacOS/Cool App"
```
<!-- SPDX-SnippetEnd -->

## Run the AppImage without FUSE

An AppImage mounts the app it holds with FUSE, the Linux feature that lets a program serve a file system, so the computer that runs it needs FUSE and its `fusermount` program on `PATH`. The AppImage carries the FUSE library itself, so the person needs no libfuse package. Where FUSE is missing, the AppImage fails, and prints this message:

<!-- SPDX-SnippetBegin -->
<!--
  SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
  SPDX-License-Identifier: MIT-0
-->
```
Cannot mount AppImage, please check your FUSE setup.
```
<!-- SPDX-SnippetEnd -->

To run it there, pass `--appimage-extract-and-run`, or set `APPIMAGE_EXTRACT_AND_RUN` in the environment to any value. The AppImage then unpacks the app into a folder under `TMPDIR` (or `/tmp`), runs it, and deletes the folder when the program exits:

<!-- SPDX-SnippetBegin -->
<!--
  SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
  SPDX-License-Identifier: MIT-0
-->
```console
$ "./Cool App-x86_64-linux.AppImage" --appimage-extract-and-run
```
<!-- SPDX-SnippetEnd -->

<!-- SPDX-SnippetBegin -->
<!--
  SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
  SPDX-License-Identifier: MIT-0
-->
```console
$ APPIMAGE_EXTRACT_AND_RUN=1 "./Cool App-x86_64-linux.AppImage"
```
<!-- SPDX-SnippetEnd -->

Each start unpacks the whole app again. For people whose computers lack FUSE, the archive `fledge build` writes runs from its folder once unpacked, and a `.deb` installs the app as files (see [Choose the installers](#choose-the-installers)).

## Choose the installers

A windowed app gets `dmg`, `nsis`, and `appimage` unless `fledge.yml` says otherwise. Each build makes only those for its system, so one list serves every platform:

<!-- SPDX-SnippetBegin -->
<!--
  SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
  SPDX-License-Identifier: MIT-0
-->
```yaml
installers: [dmg, nsis, appimage, deb]
```
<!-- SPDX-SnippetEnd -->

- `deb` adds a Debian package for Debian, Ubuntu, and their relatives, on x86-64 or ARM64 with glibc. It installs the app under `/usr/lib/com.example.coolapp`, with its desktop entry where desktops find it, and depends on the glibc the app needs.
- `msix` adds an MSIX package, for the Microsoft Store or App Installer. It needs a `windows` mapping with the package's publisher, `msix_publisher`; see [msix](../reference/fledge-yml.md#msix).
- `installers: []` gives none: only the archive.

A `license_file` adds a page to the Windows setup program that shows the license before it installs, and goes in a `.deb` as its copyright file. A `homepage` adds links to the setup program's entry in Windows' installed apps, and a `Homepage` to a `.deb`.

## Open files

A windowed app can open files and folders a person gives it, from their file manager or by dropping them on it: see [Open files and folders](file-associations.md).

## Ship it with a console program

A windowed app and its command-line tool can share one app folder: see [Ship several programs in one app](several-programs.md). On a Mac, the console programs then live inside the bundle, with a link to each beside it.

## What changes for your program

Nothing in how it runs: it starts as `ruby main.rb` would, with the gems set up. Two things differ from a terminal:

- A person starts it from the desktop, so there is no terminal to show what it prints, and it should show its errors in a window, or write them to a log.
- On Windows, a windowed program has no console. A program that needs one, to print to a terminal it was started from, is a console program.
