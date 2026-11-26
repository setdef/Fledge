<!--
  SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
  SPDX-License-Identifier: CC-BY-SA-4.0
-->
# Basket Example

A shopping list for macOS, Linux, Windows, iPhone, iPad, and Android. Type an item, add it, and remove it once it is in the cart. The list is still there when you open Basket again.

Each system draws Basket with that system's widgets, from Ruby alone. Basket is a Ruby program that calls each system's libraries with [`fiddle`](https://github.com/ruby/fiddle), which Ruby bundles. [Fledge](../../README.md) adds no widget, library, or binding for it, so every file you read here is Basket's Ruby, and you can copy any of it into your app.

## What it shows

| System | Widgets | What Basket draws | Its Ruby |
| --- | --- | --- | --- |
| macOS | AppKit | A window with a text field and an Add button above a table, and a menu bar with the app's menu, File, Edit, and Window. Add is the default button. A row goes by Edit > Delete (Command-Delete), by its context menu, or by the Delete key. | [`macos.rb`](lib/basket/macos.rb) over [`objc.rb`](lib/basket/objc.rb) |
| iOS, iPadOS | UIKit | A table under a large navigation title, with a text field and an Add button above it. A swipe left deletes a row. | [`ios.rb`](lib/basket/ios.rb) over [`objc.rb`](lib/basket/objc.rb) |
| Android | Android's views | A text field and an Add button above a list, under the app bar. The keyboard's Done key or Enter adds an item, and a long press removes one. | [`android.rb`](lib/basket/android.rb) over [`android/`](lib/basket/android) |
| Linux | GTK 4 and libadwaita | A header bar, an entry with an Add button, and a boxed list whose rows each have a remove button. A toast offers to undo a removal. | [`linux.rb`](lib/basket/linux.rb) over [`gtk.rb`](lib/basket/gtk.rb) |
| Windows | WinUI 3 | A text box and an Add button above a list, and a Remove button, in Fluent's styles. Return adds, and Delete removes the selected row. The window follows the app mode (light or dark) in Windows' settings. | [`winui.rb`](lib/basket/winui.rb) over [`winrt.rb`](lib/basket/winrt.rb) |
| Windows | Win32's common controls | The same layout, in the controls of `user32` and `comctl32`. | [`windows.rb`](lib/basket/windows.rb) over [`win32.rb`](lib/basket/win32.rb) |

[`main.rb`](main.rb) picks the screen: AppKit or UIKit where the Objective-C runtime has them, Android's views on Android, GTK on Linux, and on Windows WinUI 3 or else Win32. [`list.rb`](lib/basket/list.rb) is the list, which every screen shares. It keeps the items as JSON in `basket.json`, in the folder the system keeps an app's data in, which the [etcetera](https://rubygems.org/gems/etcetera) gem finds: `~/Library/Application Support/com.setdef.Basket` on a Mac, `$XDG_DATA_HOME/basket` (`~/.local/share/basket`) on Linux, and `%APPDATA%\setdef\Basket\data` on Windows. Basket logs the file's path when it starts.

## Build it

Basket's `Gemfile` does not list Fledge, so install Fledge in a separate folder, as the [README's Installation](../../README.md#installation) says, and build Basket by its path. On a Mac, Linux, or Windows computer:

<!-- SPDX-SnippetBegin -->
<!--
  SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
  SPDX-License-Identifier: MIT-0
-->
```console
$ cd ~/fledge
$ bundle exec fledge build ~/code/Fledge/examples/basket
```
<!-- SPDX-SnippetEnd -->

Fledge builds for the computer you run it on and writes to `dist`. Basket's [`fledge.yml`](fledge.yml) asks for every installer a desktop makes: a disk image on a Mac; a setup program and an `.msix` package on Windows; an AppImage and a `.deb` on Linux. The tools each one needs are in the README's [Compatibility](../../README.md#compatibility).

- **Linux:** the computer that runs Basket needs GTK 4 and libadwaita. The `.deb` depends on `libgtk-4-1` and `libadwaita-1-0`, so `apt` installs them. A Basket that starts without them names the missing library and exits with status 72.
- **iPhone and iPad:** `bundle exec fledge build ios ~/code/Fledge/examples/basket` writes an Xcode project. [iPhone, iPad, and Android](../../doc/phones.md) says how to build, sign, and run it.
- **Android:** `bundle exec fledge build android ~/code/Fledge/examples/basket` writes a Gradle project, which the same guide covers.

## Windows: which screen you see

Basket draws WinUI 3 where the computer has Microsoft's Windows App Runtime, and Win32's controls where it does not. Basket carries none of Microsoft's files, so a Windows without the runtime shows the Win32 screen, and no message. Install the runtime from Microsoft's [Windows App SDK downloads](https://learn.microsoft.com/en-us/windows/apps/windows-app-sdk/downloads) page. Basket asks for version 2.7 or later of its framework package, `Microsoft.WindowsAppRuntime.2`.

- **Win32 is the default** on a computer that lacks the runtime, which includes any Windows you have not installed it on.
- **WinUI 3 appears** once the runtime is installed. Start Basket again and it draws WinUI's screen.
- **To see Win32's screen where the runtime is installed,** set `BASKET_SCREEN` to `win32` before you start Basket. In PowerShell, `$env:BASKET_SCREEN = "win32"`.
- **If WinUI fails to start,** Basket logs one line, `Basket could not start WinUI (REASON), so it draws Win32's screen`, and draws Win32's screen, so you see a window either way. Basket is a windowed app with no console, so redirect its output to read the line. On Windows on ARM64, WinUI fails to start even with the runtime installed ([issue 162](https://github.com/setdef/Fledge/issues/162)), so Basket draws Win32's screen there.

Only the `.msix` package asks Windows for the runtime: its manifest depends on `Microsoft.WindowsAppRuntime.2`. The setup program and the `.zip` ask for nothing. To try the package on a Windows 11 computer, install the runtime first, then run this in an administrator PowerShell, since an unsigned package with programs in it installs for every user:

<!-- SPDX-SnippetBegin -->
<!--
  SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
  SPDX-License-Identifier: MIT-0
-->
```console
> Add-AppxPackage -Path .\Basket-x64-mingw-ucrt.msix -AllowUnsigned
```
<!-- SPDX-SnippetEnd -->

`-AllowUnsigned` needs Windows 11, and Microsoft means it for trying an app, not for giving it to people. [Desktop apps](../../doc/desktop_apps.md#the-microsoft-store) says how the package's publisher works when it is unsigned or signed.

## What it does not do

- **It subclasses no Java class.** Android's listeners are Java interfaces, which Basket's Ruby implements. Basket reaches its first activity through four members of Android's `ActivityThread` that Android lists as unsupported, and a later Android may take them away.
- **Its Objective-C bridge does little.** It passes a struct of up to four doubles, such as `NSEdgeInsets`, as an Array, but returns no struct and makes no Objective-C block.

## Read more

- [Desktop apps](../../doc/desktop_apps.md#draw-the-window-with-each-systems-widgets) says how each desktop screen works, and what differs from a program in C or Objective-C.
- [iPhone, iPad, and Android](../../doc/phones.md#your-apps-screen) does the same for the phones.
