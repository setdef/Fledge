<!--
  SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
  SPDX-License-Identifier: CC-BY-SA-4.0
-->
# Basket Example

A shopping list for macOS, Linux, Windows, iPhone, iPad, and Android: type an item, add it, and remove it once it is in the cart. The list is still there when you open Basket again.

An app that looks at home on a system draws its window with that system's widgets. Basket is a Ruby program that calls each system's widget library directly, with [`fiddle`](https://github.com/ruby/fiddle), which Ruby bundles. Fledge adds no widget, library, or binding for it, so every file here is Basket's Ruby, and you can copy any of it into your app.

## What it shows

- **A screen for each system, from Ruby alone.** On every system the app's Ruby runs as it does under `ruby main.rb`, on the main thread, where widgets are made.
- **macOS: AppKit.** A window with a text field and an Add button above a table, and a menu bar. Return adds. A row goes by Edit > Delete (Command-Delete), by its context menu, or by the Delete key. ([`macos.rb`](lib/basket/macos.rb), over [`objc.rb`](lib/basket/objc.rb))
- **iOS and iPadOS: UIKit.** A table under a large navigation title, with a text field and an Add button above it. A swipe to the left deletes a row. ([`ios.rb`](lib/basket/ios.rb), over [`objc.rb`](lib/basket/objc.rb))
- **Android: Android's views.** A text field and an Add button above a list, under the app bar. The keyboard's Done key or Enter adds, and a long press removes. ([`android.rb`](lib/basket/android.rb), over [`android/`](lib/basket/android))
- **Linux: GTK 4 and libadwaita.** A header bar, an entry with an Add button beside it, and a boxed list whose rows each have a button that removes them, after which a toast offers to undo. ([`linux.rb`](lib/basket/linux.rb), over [`gtk.rb`](lib/basket/gtk.rb))
- **Windows: WinUI 3, or Win32.** A text box and an Add button above a list, and a Remove button below it. Return adds, and Delete removes the selected row. WinUI 3 draws it in Fluent's styles ([`winui.rb`](lib/basket/winui.rb), over [`winrt.rb`](lib/basket/winrt.rb)); where the computer has no Windows App Runtime, or WinUI fails to start, the common controls of `user32` and `comctl32` draw it ([`windows.rb`](lib/basket/windows.rb), over [`win32.rb`](lib/basket/win32.rb)).
- **One list, one choice of screen.** [`main.rb`](main.rb) picks the screen. [`list.rb`](lib/basket/list.rb) keeps the items as JSON in `basket.json`, in the folder the system keeps an app's data in, which the [etcetera](https://rubygems.org/gems/etcetera) gem finds. Basket prints the path when it starts.

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

A window opens with the screen of the system you run it on. A Linux computer needs GTK 4 and libadwaita installed. On Windows, a computer with the Windows App Runtime shows the WinUI screen (see below).

The tests are in `test/`. On a Mac, `bundle exec ruby test/screen_test.rb` drives AppKit's widgets without showing a window. On a phone, `fledge test ios test/phone.rb` and `fledge test android test/phone.rb` run them inside the app.

## Build it with Fledge

Basket's `Gemfile` does not list Fledge. Install Fledge as the README's [Installation](../../README.md#installation) says, in a `Gemfile` of a separate folder outside this one, such as `~/fledge-builder`, and run `bundle install` there. Then, from that folder, build Basket by its path. Here Fledge's repository is in `~/Fledge`:

<!-- SPDX-SnippetBegin -->
<!--
  SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
  SPDX-License-Identifier: MIT-0
-->
```console
$ bundle exec fledge build ~/Fledge/examples/basket
$ bundle exec fledge build ios ~/Fledge/examples/basket
$ bundle exec fledge build android ~/Fledge/examples/basket
```
<!-- SPDX-SnippetEnd -->

`fledge build` with a path alone builds the desktop app for the system you run it on, and writes it to `dist`. [`fledge.yml`](fledge.yml) asks for every installer a desktop makes: a disk image on a Mac, a setup program and an `.msix` package on Windows, an AppImage and a `.deb` on Linux. The tools each needs are in the README's [Compatibility](../../README.md#compatibility). The `.deb` depends on `libgtk-4-1` and `libadwaita-1-0`, so `apt` installs them. A Basket that starts on Linux without them says which library is missing and exits with status 72.

The other two write a project for a phone: an Xcode project from `fledge build ios` on a Mac, and a Gradle project from `fledge build android`. [Build for iPhone and Android](../../docs/how-to/phones.md) says how to build, sign, and run them.

## See each Windows screen

Basket draws WinUI 3 where the computer has Microsoft's Windows App Runtime, and Win32's common controls where it has not. Basket carries none of Microsoft's files, so a computer without the runtime shows the Win32 screen, and no message.

- **WinUI 3.** Install the runtime from Microsoft's [Windows App SDK downloads](https://learn.microsoft.com/en-us/windows/apps/windows-app-sdk/downloads) page: under "Stable release", take the installer for your processor from the row for version 2.7.0 or later, and run it. Basket asks for version 2.7 or later of its framework package, `Microsoft.WindowsAppRuntime.2`. Start Basket again, and it draws WinUI's screen.
- **Win32.** A computer without the runtime shows it by default. Where the runtime is installed, set `BASKET_SCREEN` to `win32` before you start Basket. In PowerShell: `$env:BASKET_SCREEN = "win32"`.
- **WinUI fails to start.** Basket then draws Win32's screen after it logs one line, `Basket could not start WinUI (REASON), so it draws Win32's screen`. Basket is a windowed app with no console, so redirect its output to read the line. On Windows on ARM64, WinUI fails to start even with the runtime installed ([issue 162](https://github.com/setdef/Fledge/issues/162)), so Basket draws Win32's screen there.

The `.msix` package depends on the runtime, so install the runtime first. `fledge build` leaves the package unsigned, and Windows 11 installs an unsigned package for trying, not for giving to people. Microsoft's [Create an unsigned MSIX package](https://learn.microsoft.com/en-us/windows/msix/package/unsigned-package) says that a package with programs in it installs for all users, which needs an administrator. In an administrator PowerShell, in the folder with the package:

<!-- SPDX-SnippetBegin -->
<!--
  SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
  SPDX-License-Identifier: MIT-0
-->
```console
> Add-AppxPackage -Path .\Basket-x64-mingw-ucrt.msix -AllowUnsigned
```
<!-- SPDX-SnippetEnd -->

The setup program and the `.zip` ask Windows for nothing, so Basket draws the screen the computer allows. [Make a windowed app](../../docs/how-to/windowed-app.md#choose-the-installers) says how the package's publisher works, unsigned and signed.

## Read the code

- [`main.rb`](main.rb): the choice of screen, and a comment on why each system's Ruby reaches its widgets as it does.
- [`lib/basket/list.rb`](lib/basket/list.rb) and [`lib/basket/data_folder.rb`](lib/basket/data_folder.rb): the list every screen shares, and where it keeps its file.
- [`lib/basket/objc.rb`](lib/basket/objc.rb), [`gtk.rb`](lib/basket/gtk.rb), [`winrt.rb`](lib/basket/winrt.rb), [`win32.rb`](lib/basket/win32.rb), and [`android/`](lib/basket/android): Basket's calls into each system's libraries over Fiddle, which each screen builds on.
- [`fledge.yml`](fledge.yml): Basket's name, icon, and installers, and why its `.msix` depends on the Windows App Runtime and its `.deb` on the packages GTK needs.
- [Build for iPhone and Android](../../docs/how-to/phones.md#draw-the-platforms-widgets) says how a phone's screen works, and what differs from a program in C or Objective-C.

## Use this example if you need to

- See what an app's Ruby can draw with a system's widgets, with no gem that has a native extension.
- Start a window for one system: copy that system's screen and the file it builds on.
- Choose between two screens at start, one that needs a system library and one that does not, as Basket does on Windows.
- Keep an app's data where each system keeps it.

[Read the source code →](main.rb)
