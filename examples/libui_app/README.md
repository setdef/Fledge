<!--
  SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
  SPDX-License-Identifier: CC-BY-SA-4.0
-->
# Focus Timer Example

A work timer in a window, drawn by the operating system's own toolkit through the [LibUI](https://github.com/kojix2/LibUI) gem, shipped as an installer for each desktop.

A program that opens a window is where shipping Ruby hurts most. The person who double-clicks it expects an icon in the Dock or the Start menu, an installer, and a name and version where the system shows them, and a GUI gem brings a compiled library that has to load on a computer that never saw your development machine. Focus Timer is such a program: it counts down a stretch of focused work, then a break, then work again, with a progress bar, a Start and Pause button, a Timer menu, and a settings window. Its `fledge.yml` says everything the systems ask of a windowed app.

## What it shows

- **A windowed app.** `kind: windowed` makes a `.app` bundle on macOS, a program Windows starts without a console, and a folder with a desktop entry and icons on Linux.
- **Identity.** `name`, `identifier`, `version`, `publisher`, `copyright`, `description`, `long_description`, and `homepage`, each where its system shows it, and `license_file`, which the Windows setup program shows before it installs.
- **Icons.** `icon: icons/icon` names `icons/icon.icns` for macOS, `icons/icon.ico` for Windows, and `icons/icon-16.png` to `icons/icon-512.png` for Linux.
- **Installers.** `installers: [dmg, nsis, appimage]` asks for a disk image, a setup program, and an AppImage beside each archive.
- **A gem that carries a library.** LibUI's builds for each platform carry libui-ng's shared library, and its `Gemfile.lock` locks the four platforms those builds exist for: `arm64-darwin`, `x86_64-linux`, `aarch64-linux`, and `x64-mingw-ucrt`.
- **Libraries the desktop provides.** On Linux, libui-ng links GTK 3, Pango, Cairo, and GDK, which no gem carries, so `linux: system_libraries` names them as the distribution's ([Gems in a Fledge app](../../doc/gems.md#a-gem-that-links-a-library-from-the-linux-distribution)).
- **Microsoft's Visual C++ runtime.** On Windows, LibUI's DLL needs it, and `windows: visual_c_runtime: local` has the app carry the building computer's copies ([Gems in a Fledge app](../../doc/gems.md#a-gem-whose-dll-needs-the-visual-c-runtime)). You may distribute those copies only if you hold the rights to them.

Focus Timer is a desktop app: LibUI has no build for a phone.

## Run it with Ruby

With Ruby 4.1, in this folder:

<!-- SPDX-SnippetBegin -->
<!--
  SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
  SPDX-License-Identifier: MIT-0
-->
```console
$ bundle install
$ bundle exec ruby main.rb
```
<!-- SPDX-SnippetEnd -->

The window opens with 25 minutes of focus to count down. Start counts it down a second at a time. The Timer menu's Preferences item (on macOS, the app menu's) opens the Settings window, which sets how long each stretch lasts, what you are working on, and what happens when time is up. Closing the main window quits.

The clock itself is plain Ruby, in `timer.rb`, apart from the window, so you can try it with no window at all:

<!-- SPDX-SnippetBegin -->
<!--
  SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
  SPDX-License-Identifier: MIT-0
-->
```ruby
require_relative "timer"

timer = Timer.new(focus: 25, rest: 5)
timer.clock   # => "25:00 left"
timer.toggle  # starts the clock
timer.tick    # => nil: one second gone, and the stretch goes on
timer.clock   # => "24:59 left"
```
<!-- SPDX-SnippetEnd -->

## Build it with Fledge

Install Fledge as the README's [Installation](../../README.md#installation) says, in a `Gemfile` of a folder of its own outside this one, such as `~/fledge-builder`, and run `bundle install` there. Then, from that folder, build Focus Timer by its path. Here Fledge's repository is in `~/Fledge`, and the build is on a Mac with Apple silicon:

<!-- SPDX-SnippetBegin -->
<!--
  SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
  SPDX-License-Identifier: MIT-0
-->
```console
$ bundle exec fledge build ~/Fledge/examples/libui_app
Downloading libui-0.2.5-arm64-darwin.gem from https://rubygems.org/
Writing the gems' executables for arm64-darwin
dist/Focus Timer-arm64-darwin.tar.gz
dist/Focus Timer-arm64-darwin.dmg
```
<!-- SPDX-SnippetEnd -->

Fledge downloads the build of LibUI that the lockfile locks for this computer, which carries libui-ng's library for it, and compiles nothing. It writes the archive, 27 MB, which holds `Focus Timer.app`, and the disk image, 32 MB, which holds the app and a link to Applications to drag it onto, each with its `.sha256` beside it.

The same command builds each system's app on a computer of that system:

| System | What Fledge writes | What it needs there |
| --- | --- | --- |
| macOS, Apple silicon | `Focus Timer-arm64-darwin.tar.gz` and `Focus Timer-arm64-darwin.dmg` | nothing but the Mac's own tools |
| Windows, x64 | `Focus Timer-x64-mingw-ucrt.zip`, holding `Focus Timer.exe`, and `Focus Timer-x64-mingw-ucrt-setup.exe`, which shows `LICENSE.txt` and installs without an administrator | Microsoft's Visual C++ runtime on the building computer, which the app carries |
| Linux, x86-64 or ARM64, with glibc | `Focus Timer-x86_64-linux.tar.gz`, with a desktop entry and icons, and `Focus Timer-x86_64-linux.AppImage` (or `aarch64-linux`) | squashfs-tools 4.4 or newer, for the AppImage; the people who run the app need a desktop with GTK 3 |

Those four platforms are the ones LibUI has a build for, so Focus Timer builds on no other, such as Linux with musl or Windows on ARM64.

## Read the code

- [`main.rb`](main.rb): the window, the menu, and the settings form, made with LibUI's calls, and the one-second tick that drives the clock. libui-ng's menus must exist before its first window, and every control must be destroyed before the app ends, or on Windows libui-ng exits with status 3; the comments say where each of those happens.
- [`timer.rb`](timer.rb): the clock, with no window.
- [`fledge.yml`](fledge.yml): every key a windowed app shows its systems, and why the Linux and Windows keys are there.
- [`Gemfile`](Gemfile) and [`Gemfile.lock`](Gemfile.lock): one gem, locked for the four platforms it has a build for.

## Use this example if you need to

- Ship a program that opens a window, with an installer for each desktop.
- Give an app a name, an icon, a version, and a license where each system shows them.
- Ship a gem whose compiled library links the Linux desktop's libraries, or needs the Visual C++ runtime on Windows.
- Keep the logic of a GUI app in plain Ruby you can run without the GUI.

[Read the source code →](main.rb)
