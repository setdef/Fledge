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
| a `.tar.gz` holding `NAME.app`, and a `.dmg` | a `.zip` holding `NAME.exe`, which opens no console; a `-setup.exe` that installs without an administrator; and an `.msix` package if you ask for one | a `.tar.gz` holding the program, a desktop entry, and icons; an AppImage; and a `.deb` if you ask for one |

Each system shows the app's name, icon, and version in its usual places. If you change `identifier` later, each system sees a new app, and Windows and `apt` install it beside the old one. [`examples/libui_app`](../examples/libui_app), a work timer on LibUI, is a complete example, with its icon's files and a disk image, a setup program, and an AppImage.

What each key does:

- **`icon`** names the icon's files without their extension. Make one `.icns` for macOS, one `.ico` for Windows, and for Linux a PNG of each size you have, of 16, 32, 64, 128, 256, and 512 pixels. Linux needs at least one. `fledge build` warns about each size you lack, and the desktop scales the nearest one. An MSIX package also needs PNGs of 44, 50, and 150 pixels, such as `icons/app-44.png`.
- In **`installers`**, list which of `dmg`, `nsis`, `appimage`, `deb`, and `msix` to build. The default is the first three. A `.deb` needs `dpkg-deb` on your computer, and an AppImage needs `mksquashfs` from squashfs-tools 4.4 or newer. An `.msix` needs MakeAppx from Microsoft's Windows SDK, and a publisher under `windows`, as [The Microsoft Store](#the-microsoft-store) says.
- **`description`** is the tooltip that Linux menus show, and the summary line of a `.deb`. **`long_description`**, in paragraphs, follows it in the `.deb`, for `apt show` and software centers.
- **`homepage`** is the `.deb`'s homepage, and the link that Windows' Settings shows for the installed app.
- **`license_file`**, a UTF-8 file in your project, is a page that the Windows setup program shows before it installs, and the `.deb`'s copyright file.
- With **`linux: deb_changelog`**, Fledge adds your changelog to the `.deb`.
- **`macos: build`** is the Mac app's build number, which the App Store and updaters compare. Without it, the build number is the version's first three numbers.

A `.deb` depends on `libc6`, on the packages of any libraries you list under `linux: system_libraries`, on the `gir1.2-` package of each typelib you list under `linux: system_typelibs` (see [Gems](gems.md)), and on each relationship you list under `linux: deb_depends`, so `apt` installs it on a computer without a desktop too. A library that a gem opens while your app runs, such as the X11, Wayland, or OpenGL libraries SDL opens, comes from the desktop, and Fledge cannot check that it is there.

Your own Ruby may open a library that no compiled file names, with `Fiddle.dlopen` or `ffi`, as the next section's GTK 4 does, so Fledge cannot find its package. Name each package under `linux: deb_depends`, as Debian writes a dependency: a package, a version bound in parentheses if you need one, and alternatives after `|`:

<!-- SPDX-SnippetBegin -->
<!--
  SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
  SPDX-License-Identifier: MIT-0
-->
```yaml
linux:
  deb_depends: [libgtk-4-1, "libadwaita-1-0 (>= 1.4)"]
```
<!-- SPDX-SnippetEnd -->

Fledge writes each entry into the `.deb`'s `Depends` as you give it, after the ones it found, and checks only its form: a package name is the distribution's, so it is the one you know. `Depends` is Debian and Ubuntu's, so use the names those two share, or give alternatives for the names that differ (`libfoo1t64 | libfoo1`). Give a package's name, not a library's file name: `libgtk-4-1`, not `libgtk-4.so.1`. An AppImage, a `.tar.gz`, and the other systems' installers ignore the key, and the app's program does not check for the library before your Ruby runs, so list under `system_libraries` any library a gem's compiled file links.

### Draw the window with GTK 4 on Linux

Your Ruby can open GTK 4 and libadwaita itself with `fiddle`, which Ruby bundles, as it does under `ruby main.rb` on a Linux computer that has them, and Fledge adds nothing for it: no library, no binding. Open each library by its soname (`Fiddle.dlopen("libgtk-4.so.1")`, `Fiddle.dlopen("libadwaita-1.so.0")`), connect each signal to a `Fiddle::Closure::BlockCaller`, and keep every closure in a variable, since Ruby frees one that only GTK refers to. [`examples/basket`](../examples/basket) is a shopping list drawn this way by GNOME's Human Interface Guidelines, with a header bar, a boxed list, and a toast that offers to undo a removal: [`lib/basket/gtk.rb`](../examples/basket/lib/basket/gtk.rb) holds its calls into GTK, 125 lines, and [`lib/basket/linux.rb`](../examples/basket/lib/basket/linux.rb) its screen.

Set `kind: windowed`, so that your Ruby runs on the main thread, which GTK needs. Three things differ from a program of C:

- Ruby runs its handler for SIGINT and SIGTERM only when its main thread next runs Ruby, which inside `g_application_run` it does not, so Ctrl-C and `kill` would do nothing while the window is open. Attach `g_unix_signal_add` for both and call `g_application_quit` from its handler, as Basket does.
- Fledge cannot tell that your app needs GTK 4, since `linux: system_libraries` lists only what a gem's compiled files link. List its packages under `linux: deb_depends` (`[libgtk-4-1, libadwaita-1-0]`), so `apt install` brings them in with a `.deb`. A computer that has the app another way, without them, gets what your Ruby does about the `Fiddle::DLError`: Basket names the library and exits with status 72, as Fledge's launcher does for a library a gem lists.
- GTK exits the process when it cannot open a display, and a library GTK loads itself, such as `libGLESv2.so.2`, may abort it; neither reaches your Ruby.

### Draw the window with Win32 on Windows

Your Ruby can open Windows' `user32` and `comctl32` itself with `fiddle`, which Ruby bundles, as it does under `ruby main.rb` on Windows, and Fledge adds nothing for it: no library, no binding, no key in `fledge.yml`. Every Windows has both libraries. [`examples/basket`](../examples/basket) is a shopping list drawn this way, with a text field, an Add button that Return presses, a list, and a Remove button: [`lib/basket/win32.rb`](../examples/basket/lib/basket/win32.rb) holds its calls into Windows, and [`lib/basket/windows.rb`](../examples/basket/lib/basket/windows.rb) its screen, which reads as `lib/basket/ios.rb` does.

Set `kind: windowed`, so that Windows gives your app no console. A program of C gets the first two of these from its manifest and writes the last two in its message loop and window procedure. `ruby.exe` and your app's program have none of them, so your Ruby does all four, the first two before it makes a window:

- Windows draws the controls of Windows 2000 unless the process asks for Common Controls 6, and neither `ruby.exe` nor your app's program does. Put the dependency in a manifest file in your project, as Basket's `lib/basket/common-controls.manifest` does, and call `CreateActCtxW` with the file's path and then `ActivateActCtx`. The same Ruby draws the same controls under `ruby main.rb` and in the built app.
- Windows stretches the pixels of a window on a monitor whose scale is above 100% unless the process is aware of each monitor's scale. Call `SetProcessDpiAwarenessContext(-4)` before the first window, and multiply every size by `GetDpiForWindow` over 96.
- Handles, `WPARAM`, `LPARAM`, and `LRESULT` are 64 bits wide and `LONG` is 32. Declare each handle as `Fiddle::TYPE_INTPTR_T`, not `TYPE_LONG`.
- Tab and Return work as in a dialog only when the message loop calls `IsDialogMessageW` before `TranslateMessage`, and the window answers `DM_GETDEFID` with the id of its default button.

A windowed app's standard output reaches no console, so a program that logs redirects it, as CI's check of Basket does with `Start-Process -RedirectStandardOutput`. A message loop runs on the main thread, where the launcher runs your Ruby.

### Draw the window with WinUI 3 on Windows

Where the computer has the Windows App Runtime, your Ruby can draw WinUI 3's controls, Microsoft's current ones for a Windows app, with `fiddle` alone, and Fledge adds nothing for it. WinUI is a WinRT API: your Ruby gets a class from `combase.dll`, calls an object's methods by their place in its interface's table of functions, which the `.winmd` files of Microsoft's Windows App SDK list in order, and passes WinUI events made of `Fiddle::Closure`s. [`examples/basket`](../examples/basket) does so when it can: [`lib/basket/winrt.rb`](../examples/basket/lib/basket/winrt.rb) holds its calls, and [`lib/basket/winui.rb`](../examples/basket/lib/basket/winui.rb) its screen, a text box, an Add button, a list, and a Remove button in Fluent's styles, with its controls written as the XAML markup a WinUI app has. Basket carries none of Microsoft's files, so a computer without the Windows App Runtime gets the Win32 screen above, and no message.

- Ask Windows to add the framework package to your process, as the Windows App SDK's bootstrapper does for an app that is not packaged: `TryCreatePackageDependency` and `AddPackageDependency` in `kernelbase.dll`, for the package family `Microsoft.WindowsAppRuntime.2_8wekyb3d8bbwe`. They fail on a computer that has not registered that package. A packaged app has the framework in its package graph already.
- WinUI takes the main thread: `Application.Start` runs its message loop there and calls your Ruby back on it, as the launcher runs your Ruby under `ruby main.rb`. A WinRT call that finishes on another thread would end the process.
- Your `Application` has to answer `IXamlMetadataProvider` by handing each call to a `XamlControlsXamlMetaDataProvider`, and merge `XamlControlsResources` into its resources, as the generated code of a WinUI app does. Without the first, a `TextBox`, a `PasswordBox`, or a `RichEditBox` ends the process with a stowed exception.
- Call `SetProcessDpiAwarenessContext(-4)` before the first window, as for Win32.

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
  - name: Lota game
    extensions: [lota]
    mime_types: [application/x-lota-game]
    defines_type: true              # a type no other program defines
```
<!-- SPDX-SnippetEnd -->

- **macOS** lists the app under "Open With" for them, and never makes it their default unless your users do. Add `content_types` for macOS's types, such as `public.zip-archive`, where you know them. For an extension no type claims, macOS makes up a type of its own and still offers the app, so `defines_type` changes nothing there.
- **Windows:** the setup program adds the app to each extension's "Open with" list and to every folder's menu, and its uninstaller removes them. An MSIX package adds the app to each extension's "Open with" list only: a package cannot add a plain command to the folders' menu. Windows registers nothing for an app your users unpack from the `.zip`.
- **Linux** desktops know a file by its MIME type, so list `mime_types` for Linux. A desktop finds a file's MIME type from its name, in a database each program adds its file types to, so it knows a `.zip` file, and the app is offered for it, but knows nothing of a type only your app has, such as a game's own format. Say `defines_type: true` for such a type, with its one MIME type and its extensions, and the app carries the type's definition in `share/mime/packages`, named for its identifier, with the entry's `name` as what a person sees the type called. The `.deb` installs it, and the system adds it to the database as the package installs, and takes it out when the package is removed. An AppImage and the `.tar.gz` install nothing: until someone installs the app by hand, copying `share` into `~/.local/share` and then running `update-mime-database ~/.local/share/mime`, such a file has no type of the app's, and the app is not offered for it. Leave `defines_type` out for a type other programs know: a definition of your app's would rename that type for every program on the computer.

Your program receives the path of each file or folder it is opened with, or that is dropped on it, in `ARGV`, as `ruby main.rb FILE` would, after any arguments it was started with. macOS sends those paths as an Apple event rather than as arguments, and the app's launcher takes that event before your program starts, so your GUI library does not see it: read the paths from `ARGV` on every system. For this the launcher waits, before Ruby starts, for the first event macOS sends an app, up to about a fifth of a second, most of which a GUI library spends anyway when it starts; only an app with `file_associations` waits. A file opened with the app while it is already running is not an argument: on macOS it reaches only your GUI library's event loop, as SDL3's `SDL_EVENT_DROP_FILE`, and a program with no event loop does not see it. The LibUI gem's library, libui-ng, has no handler for that event, so macOS handles a file opened with a running LibUI app itself, and your program never sees it; the launcher spares a LibUI app only the file it starts with, which, before the launcher took it, kept such an app from running its timers at all.

[`examples/markdown_to_html`](../examples/markdown_to_html), Markdown to HTML, is a complete example of a droplet: its `fledge.yml` lists Markdown files by their extensions and the MIME type every Linux desktop knows, so it defines no type, and its windowed program writes each file it is given in `ARGV`, dropped on the app or opened with it, as an HTML page beside the file. It opens no window and no browser. Started with no file, it says how to use it.

### Tell the person without a window

A program that opens no window has no place to say what it did, so decide for each system what, if anything, it says, as that system's own apps without a window do:

- **A success is not told.** The result is a file beside the one dropped, which the file manager shows at once, as it shows the file Finder's Compress leaves. A notification for every drop, of which a person dropping fifty files would get fifty, would be noise.
- **A failure is told, once for the drop.** On macOS, `osascript` shows a notification, and on Linux, `notify-send` shows one through the desktop's notification service (freedesktop.org's Desktop Notifications specification), if the computer has it: both are tools those systems ship or nearly always have, so the app carries nothing, and a computer without `notify-send` shows nothing. On Windows, a notification toast needs an app identity that an unpackaged app has not, so the app shows a message box through PowerShell, which Windows ships. In every case the program also writes the message to standard error and ends with status 66, `EX_NOINPUT` in sysexits.h, for a terminal or a script that started it. The message reaches each tool as an argument or an environment variable and is never part of code the tool runs, because a file's name is the person's.
- **Started with nothing,** from a menu, the Dock, or a double-click, it tells how to use it the same way, since an app that silently does nothing looks broken.

A person may turn the system's notifications off, and then a failure shows nothing but the exit status.

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

`fledge build` with no argument builds all of them, and `fledge build bin/shared-save` builds that program alone. At most one program is windowed. Fledge gives it the app's name unless you give it a `name`, builds the installers for it, and on macOS puts the console programs inside its `.app` bundle. Fledge names each console program after its file, such as `shared-save`, the command your users type.

Markdown to HTML, in [`examples/markdown_to_html`](../examples/markdown_to_html), is a complete example of two programs: `markdown_to_html.rb`, the windowed droplet a drop or a double-click starts, and `bin/md2html`, a console one that prints a Markdown file's HTML in a terminal, which share the project's `lib/` and its one copy of kramdown.

## Serve the computers on your network

An app can be a small web server that one person starts and everyone on an office or home network opens in a browser, on a computer or a phone, as people use Jupyter, Syncthing, or pgAdmin. That suits technical and internal users. Make the server a console app, the default, so its console window shows the address to open, and closing that window stops it. With `kind: windowed`, Windows gives it no console, and nothing shows that it is running.

- Listen on every address, `0.0.0.0`, so other computers reach the server, and print the address they open: this computer's private IPv4 address, which `Socket.ip_address_list.select(&:ipv4_private?)` gives. `localhost` on someone else's phone is their phone. A server only this computer's browser uses listens on `127.0.0.1`, and is often better as a windowed app.
- Expect the firewall. Windows Defender Firewall is on by default, and the first time a program listens on every address, Windows asks the person whether to let it accept connections from the network. Where no one answers, Windows adds inbound rules that block that program, by its path, and other computers cannot reach it until someone allows it in the firewall's settings. Connections from the computer itself are not blocked. macOS's firewall is off unless the person turns it on, and then macOS asks the same question.
- Ask for a password, because anyone on the network can reach the server. HTTP Basic authentication, which Rack provides as `Rack::Auth::Basic`, with a password the app makes when it starts and prints beside its address, is the least a tool on a trusted network should have. Over plain HTTP, the password and everything else cross the network unencrypted. On a network you don't trust, serve HTTPS instead, with a certificate the other devices trust.
- Refuse forms that other web pages send. A browser sends the password it remembers with a form that another site posts to your server. With Sinatra, `set :protection, reaction: :deny` refuses such a request. Sinatra's default only drops the session, and lets the request through when, as with Basic authentication, the password is not in a session.
- Keep what people send where the person who runs the app finds it, such as a folder in their home folder, and what the app keeps for itself in their data folder, such as `~/Library/Application Support/NAME` on macOS, `%APPDATA%\NAME` on Windows, and `~/.local/share/name` on Linux. Never write in the app's own folder. It may be read-only, as an AppImage and `/Applications` are, and an update replaces it.
- Write each change as it happens. Ctrl-C and `TERM` reach your code as they reach it under `ruby main.rb`, but on Windows, closing the console window ends the program before any `ensure` clause or `at_exit` hook runs, under `ruby.exe` and in the app alike.
- Set `$stdout.sync = true` if anyone may read what the server prints through a pipe or a log file. Ruby holds output to those until it has a buffer's worth, and Puma, stopped by Ctrl-C, ends the process without writing what it held.

[`examples/file_drop`](../examples/file_drop) is a complete example: Drop, a file drop on [Sinatra](https://sinatrarb.com/) and [Puma](https://puma.io/). Open its address on any device on the network, sign in with the password it prints, and send files to the Drop folder in the home folder of the person who runs it, or take the files they put there. Puma and its nio4r compile from source, so building Drop needs a compiler, as [Gems in a Fledge app](gems.md#gems-with-compiled-extensions) says.

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

Fledge runs the command through `cmd.exe` once for each program and library, then for the uninstaller and the setup program as it writes them, then for the MSIX package if you build one, with the path in quotes. Without `%1`, the path goes at the end, so a `.cmd` file of your own works too. A command that exits with anything but 0 stops the build and names the file. Fledge never prints the command, which may hold a password. To keep the command out of your build scripts, set `FLEDGE_SIGN_COMMAND` instead, as a CI secret can.

### What is proven

Fledge's CI signs with a self-signed certificate, on macOS and on Windows, and runs `signtool` through `--sign-command` too. It notarizes against a stand-in for Apple's service that answers as Apple documents. How Gatekeeper and SmartScreen treat an app signed and notarized with real credentials is untested. Fledge does not sign Linux apps, and Xcode and Gradle sign a phone's app.

## Publish to a store

No Fledge app has been through any store's review. This section says what each store's own documents ask for, as they read on 2026-11-04, against what Fledge writes. A store can still refuse an app for a reason its documents leave out, and only a submission settles that. For phones, see [Google Play and the App Store](phones.md#google-play).

### The Microsoft Store

The Store takes a Windows app in two ways: as an MSIX package, which it signs for you, or as an `.exe` installer, which you sign.

**An MSIX package needs no certificate of yours.** Microsoft [re-signs an MSIX package](https://learn.microsoft.com/windows/apps/publish/publish-your-app/msix/app-package-requirements#code-signing-for-microsoft-store-submissions) with its own certificate once the app passes certification, and hosts it. To ship one:

1. Open a [Partner Center account](https://learn.microsoft.com/windows/apps/publish/partner-center/open-a-developer-account) and reserve your app's name.
2. Copy the three values on the app's [Product identity page](https://learn.microsoft.com/windows/apps/publish/view-app-identity-details) into `fledge.yml`. The values are case-sensitive, so paste them exactly:

   <!-- SPDX-SnippetBegin -->
   <!--
     SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
     SPDX-License-Identifier: MIT-0
   -->
   ```yaml
   publisher: Example, Inc.               # Package/Properties/PublisherDisplayName
   installers: [nsis, msix]
   windows:
     msix_name: 12345Example.MyCoolApp    # Package/Identity/Name
     msix_publisher: CN=1A2B3C4D-5E6F-7A8B-9C0D-1E2F3A4B5C6D   # Package/Identity/Publisher
   ```
   <!-- SPDX-SnippetEnd -->

3. Add PNGs of 44, 50, and 150 pixels beside your icon, such as `icons/app-44.png`, `icons/app-50.png`, and `icons/app-150.png`. These are the logos the Start menu, the taskbar, and the Store show.
4. Run `bundle exec fledge build` on Windows without `--sign`. Fledge writes `NAME-PLATFORM.msix` with Microsoft's MakeAppx, which comes with the [Windows SDK](https://learn.microsoft.com/windows/apps/windows-sdk/downloads) and with Microsoft's `Microsoft.Windows.SDK.BuildTools` package. Fledge looks on your `PATH` first, then where the SDK installs it.
5. Upload the `.msix` for each architecture you build, x64 and ARM64, on the submission's Packages page.

Your app runs with full trust, as it does outside a package. The package declares `runFullTrust`, a [restricted capability](https://learn.microsoft.com/windows/apps/package-and-deploy/app-capability-declarations), so Partner Center asks you why the app needs it. Write that it is a desktop program that runs Ruby, as it runs outside a package.

**A framework your app's Ruby draws with.** An app whose Ruby opens a framework that Microsoft ships as a framework package, such as the [Windows App Runtime](https://learn.microsoft.com/windows/apps/windows-app-sdk/deploy-packaged-apps) that WinUI 3 needs, lists that package under `msix_dependencies`. The Store installs it with your app, and carries none of Microsoft's files in yours. Copy each package's `name` and `publisher` from its `Identity`, and give the oldest version of it that your app works with:

<!-- SPDX-SnippetBegin -->
<!--
  SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
  SPDX-License-Identifier: MIT-0
-->
```yaml
windows:
  msix_dependencies:
    - name: Microsoft.WindowsAppRuntime.2
      publisher: CN=Microsoft Corporation, O=Microsoft Corporation, L=Redmond, S=Washington, C=US
      min_version: 2.7.0.0
```
<!-- SPDX-SnippetEnd -->

Fledge writes one `PackageDependency` for each entry into the package's manifest. `fledge build` refuses a `min_version` that is not four numbers between periods, each from 0 to 65535, and a package listed twice. It does not check that the package exists. Only the `.msix` has the dependency: the setup program, the disk image, the AppImage, the `.deb`, and the `.zip` ignore the key, so an app that runs from one of them finds the framework only when the computer already has it. A package you install without the Store needs the framework installed first, or given to `Add-AppxPackage` with `-DependencyPath`.

The package names Windows 10 version 1809 as the oldest Windows it installs on, though Windows 11 is the oldest Fledge's apps are tested on. Its version is your `version`'s first three numbers and a 0, because the Store keeps the fourth number for itself. The Store also refuses a version whose first number is 0, so ship `1.0.0` or later.

To try the package on your own computer before you submit it, sign it with a test certificate whose subject is your `msix_publisher`, trust that certificate in the computer's Trusted People store, and install the package with `Add-AppxPackage`, as Microsoft's [signing guide](https://learn.microsoft.com/windows/msix/package/create-certificate-package-signing) says. `fledge build --sign THUMBPRINT` signs the package as it signs the setup program. Fledge's CI installs a package signed that way, runs the app from it, and removes it.

To sideload an MSIX package without the Store, sign it with `--sign` or `--sign-command` and a certificate from a certificate authority, and set `msix_publisher` to that certificate's subject. Windows installs the package only when the subject and `msix_publisher` match.

**An `.exe` installer you sign yourself.** The Store's [policy 10.2.9](https://learn.microsoft.com/windows/apps/publish/store-policies) takes a desktop program as an `.exe` installer at a link you give it, and the setup program Fledge writes fits what it lists:

- It holds the whole app, and is no downloader stub.
- `/S` installs it silently, which the policy asks for. Fledge's CI installs it this way, runs the app from the Start menu, and uninstalls it.
- It installs for one person, with no administrator, and adds a Start menu entry and an uninstaller.

What the setup program lacks, you bring:

- **A certificate.** The setup program, and every program and library in it, must chain to a certificate authority in Microsoft's Trusted Root Program. The Store does not sign this route for you, and a self-signed certificate will not pass. `--sign` signs them all, and `--sign-command` does the same through a cloud or hardware service. [Microsoft's table](https://learn.microsoft.com/windows/msix/package/signing-package-overview) lists Azure Artifact Signing at about US$10 a month and an OV certificate at US$300 to 500 a year.
- **A versioned HTTPS address**, whose file never changes. A GitHub Release's address redirects to a download host, and whether the Store's check takes that is unknown.
- **A Partner Center account.** Microsoft's [new onboarding flow](https://learn.microsoft.com/windows/apps/publish/partner-center/open-a-developer-account) charges no registration fee.

No one has submitted either to the Store. Fledge's CI signs with a self-signed certificate only, so the Store's certification, and its malware scan of a Ruby runtime, are unknown for both routes.

### The Mac App Store

Fledge does not build for the Mac App Store. Its `.app` is signed for Developer ID, for people who download it from you. The Store takes a different program: an [App Sandbox](https://developer.apple.com/documentation/xcode/configuring-the-macos-app-sandbox) on every executable, a provisioning profile, Apple Distribution and Mac Installer Distribution certificates, and a `.pkg`. Inside the sandbox, your Ruby code reads only its own container and the files a person picks, so it no longer runs as it does under `ruby main.rb`. Ship a Mac app outside the Store, signed and notarized, as [Sign your app](#sign-your-app) says.

### Linux

Flathub, the Debian and Ubuntu archives, and Launchpad PPAs take only what they build from source, so none of them takes a Fledge app. [Flathub says](https://docs.flathub.org/docs/for-app-authors/requirements) "Binary or precompiled files must not be present in the submission pull request". Fedora's rules were out of reach when this was written. Three routes take prebuilt apps, and no one has tried any of them with a Fledge app:

- **Your own apt repository.** Serve the `.deb` Fledge builds from a repository you make with [`reprepro` or `aptly`](https://wiki.debian.org/DebianRepository/Setup) and sign, and your users [add your key and a `.sources` file](https://wiki.debian.org/DebianRepository/UseThirdParty). Fledge's CI installs the `.deb` with `apt`, from the file. It has not served one from a repository.
- **The Snap Store.** Its documents ask for no source build in what was read, and [Tauri's guide](https://v2.tauri.app/distribute/snapcraft/) makes a strict snap with snapcraft's `dump` plugin from a built `.deb`. Fledge writes no `snapcraft.yaml`, so you would write one. A strict snap sees only what its interfaces open, so the app's files and network reach differ from `ruby main.rb`. Whether the launcher runs from a snap's read-only mount is unknown.
- **Your own Flatpak repository.** [Flatpak's guide](https://docs.flatpak.org/en/latest/hosting-a-repository.html) says how to host one, on a web server or GitLab Pages. Fledge writes no Flatpak, so you would write its manifest, and the default sandbox gives an app no host files or network until you open them.
