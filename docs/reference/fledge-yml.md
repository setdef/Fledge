# fledge.yml

`fledge.yml` describes how an app presents itself to the person who runs it: its name, version, icon, identifier, installers, the files it opens, and what each system needs to know about its libraries. It is optional, and so is every key in it. A project with no `fledge.yml` builds as a console app named for its gemspec or its folder.

This page is the complete list of keys. For a walk through the common ones, see the [tutorial](../tutorial.md) and [Make a windowed app](../how-to/windowed-app.md).

## The file

- **Where it goes:** the project's root folder, beside the `Gemfile`. A `fledge.yml` also marks a folder as a project's root when the folder has no `Gemfile` or gemspec.
- **Format:** [YAML](https://yaml.org), a mapping of the keys on this page. A value is text (`Cool App`, or `"1.2.3"` in quotes), a list (`[dmg, nsis]`, or one `- item` to a line), `true` or `false`, or a mapping of further keys. A key with no value, such as `icon:` alone, is the same as no key, and an empty file holds no keys.
- **Strictness:** fledge refuses a key it does not know and a value of the wrong type, and names the file, the key, and what it expected. A typo fails the build instead of being ignored.
- **Checking in an editor:** `lib/fledge/config.schema.json`, in Fledge's repository, is a [JSON Schema](https://json-schema.org) of these keys and their rules. Put this line first in `fledge.yml`, with the tag your `Gemfile` installs Fledge from, and an editor that runs Red Hat's YAML language server, such as VS Code with Red Hat's YAML extension, completes each key and value, shows what each means, and marks a typo:

  <!-- SPDX-SnippetBegin -->
  <!--
    SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
    SPDX-License-Identifier: MIT-0
  -->
  ```yaml
  # yaml-language-server: $schema=https://raw.githubusercontent.com/setdef/Fledge/v0.17.0/lib/fledge/config.schema.json
  ```
  <!-- SPDX-SnippetEnd -->

The examples on this page describe one app, Cool App, a notes app made by Example, Inc.

## Identity

| Key | Value | Default | Used for |
| - | - | - | - |
| `name` | text | the gemspec's name, or the project folder's name, camelized (`cool-app` becomes `CoolApp`) | the program's file name, the app folder's name, and what every system shows |
| `version` | a quoted version that begins with a number, such as `"1.2.3"` | the gemspec's version, or `"0.0.0"` | every system's version fields (see [How each system reads the version](#how-each-system-reads-the-version)) |
| `kind` | `console` or `windowed` | `console` | whether the program runs in a terminal or opens windows |
| `identifier` | reverse-DNS, such as `"com.example.CoolApp"` | none | the name each system identifies the app by; a windowed app and a phone's app need one |
| `icon` | the icon files' path without an extension, from the project's root, such as `"icons/app"` | none, so each system shows its default icon | see [Icon files](#icon-files) |
| `publisher` | text | the gemspec's authors, joined with commas | Windows' company name, the setup program's publisher, a `.deb`'s maintainer, an MSIX package's publisher name |
| `copyright` | text, such as `"© 2026 Example, Inc."` | none | macOS's copyright line, Windows' copyright, the setup program's branding |
| `description` | one line, such as `"Keeps your notes"` | none | a Linux desktop entry's comment, a `.deb`'s synopsis, Windows' comments, an MSIX package's description |
| `long_description` | text in paragraphs | none | a `.deb`'s extended description |
| `homepage` | an `http` or `https` URL | none | a `.deb`'s homepage, and the links of the setup program's entry in Windows' installed apps |
| `license_file` | a UTF-8 file in the project, such as `"LICENSE.txt"` | none | a page the setup program shows before it installs, and a `.deb`'s `/usr/share/doc/PACKAGE/copyright` |

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
icon: icons/app
publisher: Example, Inc.
copyright: "© 2026 Example, Inc."
description: Keeps your notes
long_description: |
  Cool App keeps your notes in plain text files,
  one file to a note.
homepage: https://example.com/cool-app
license_file: LICENSE.txt
```
<!-- SPDX-SnippetEnd -->

### Rules for each value

- **`name`**, and a program's `name`, may hold spaces. fledge refuses an empty name, a name with `/ \ : * ? " < > |` or a control character, and one that ends in a period or a space. It refuses the device names Windows reserves, in any case and with or without an extension: `con`, `prn`, `aux`, `nul`, and `com` or `lpt` followed by one digit, `com0` to `com9` and `lpt0` to `lpt9`, so `COM0.txt` fails too. On macOS and Linux, where a program's file has no extension, it also refuses `app`, `fledge.cfg`, and, with `build_tools`, `tools`, in any case, since the app folder holds files of those names. On every system it refuses a name that matches a file of the runtime's.
- **`version`** must be a version RubyGems reads, beginning with a number: `"1.2"`, `"1.2.3"`, and `"2.0.0-beta.1"` all are. Write it in quotes: YAML reads `1.10` as the number 1.1, and fledge refuses a number.
- **`identifier`** is two or more parts between dots, each of letters, digits, and hyphens, at most 128 characters in all. Use a domain you control, reversed. Android takes stricter identifiers: see [android](#android).
- **`description`** is one line; put the rest in `long_description`.
- **`license_file`** is a file in the project, with `/` between folders. It may not leave the project (`..`) or name a folder.

> [!WARNING]
> A windowed app with no `identifier` fails to build, and so does a phone's app. fledge's message suggests one, made from the gemspec's GitHub homepage (`io.github.OWNER.App`) when there is one, or else `com.example.App`. Don't ship the `com.example` one: each system uses the identifier to tell your app from others, and it should not change once people have installed the app.

### How each system reads the version

Each system takes the numbers it can hold from `version`, so one `version` serves them all:

| System | Reads `"2.10.3-beta.1"` as |
| - | - |
| macOS | `2.10.3` (`CFBundleShortVersionString`, and `CFBundleVersion` unless `macos` gives a `build`) |
| Windows | `2.10.3.0` (each part at most 65535) |
| MSIX | `2.10.3.0` |
| `.deb` | `2.10.3~beta.1`, so a prerelease sorts before its release |
| Android | `versionName` `2.10.3-beta.1`, and `versionCode` `2010003`: the major version times 1,000,000, plus the minor times 1,000, plus the patch |
| iOS | `2.10.3` |

For Android's `versionCode`, the minor and the patch may be at most 999, and the code at most 2,100,000,000; fledge refuses a version that does not fit.

### Icon files

`icon` is the files' path without their extension. fledge takes, from `icons/app`:

| System | Files | Notes |
| - | - | - |
| macOS | `icons/app.icns` | make it from PNGs with `iconutil -c icns` |
| Windows | `icons/app.ico` | holding the sizes Windows shows, 16 to 256 pixels |
| Linux | `icons/app-16.png`, `-32`, `-64`, `-128`, `-256`, `-512` | at least one; fledge warns about each size missing, and desktops scale the nearest one |
| MSIX | `icons/app-44.png`, `-50`, `-150` | all three |
| iOS | `icons/app-1024.png` | Xcode makes the other sizes from it |
| Android | `icons/app-48.png`, `-72`, `-96`, `-144`, `-192` | all five, one for each screen density |

A build fails when a file its system needs is missing, and fledge names the file. A build reads only the files for its system, so you can add each system's icon when you start building for that system. With no `icon`, each system shows its default icon, and an iOS app's project has no asset catalog.

## installers

The installers a windowed app gets, besides its archive.

<!-- SPDX-SnippetBegin -->
<!--
  SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
  SPDX-License-Identifier: MIT-0
-->
```yaml
installers: [dmg, nsis, appimage, deb]
```
<!-- SPDX-SnippetEnd -->

| Value | Built on | File | What it does |
| - | - | - | - |
| `dmg` | macOS | `NAME-PLATFORM.dmg` | a disk image of the app's bundle beside a link to Applications |
| `nsis` | Windows | `NAME-PLATFORM-setup.exe` | a setup program that installs for the person who runs it, with no administrator, in `%LOCALAPPDATA%\Programs\NAME`, with a Start menu shortcut and an uninstaller |
| `appimage` | Linux | `NAME-PLATFORM.AppImage` | one executable file that holds the app and mounts it with FUSE to start it, for the computers the platform's archive runs on (see [AppImage and FUSE](#appimage-and-fuse)) |
| `deb` | Linux with glibc, x86-64 or ARM64 | `NAME-PLATFORM.deb` | a Debian package, from which `dpkg` installs the app under `/usr/lib/IDENTIFIER` with its desktop entry and icons |
| `msix` | Windows | `NAME-PLATFORM.msix` | an MSIX package, for the Microsoft Store or App Installer |

- **Default:** `[dmg, nsis, appimage]`.
- **None:** write `installers: []`.
- Each build makes only the installers for its system, so one `installers` list serves every platform.
- A console app gets no installers; fledge refuses `installers` with values for one.
- `msix` needs `windows` to give the package's publisher, `msix_publisher` (see [windows](#windows)), and needs the Windows SDK's `makeappx`.

### AppImage and FUSE

An AppImage is the AppImage runtime (AppImage's `type2-runtime`, at the version Fledge pins) followed by the app's folder as a SquashFS image. Each time a person starts the AppImage, that runtime mounts the image with FUSE, through the setuid `fusermount` it finds on `PATH`, and runs the program from the mount. The AppImage includes libfuse, so the computer needs FUSE and `fusermount`, and no libfuse package.

Where the runtime can't mount the image, the app doesn't start, and the AppImage prints:

<!-- SPDX-SnippetBegin -->
<!--
  SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
  SPDX-License-Identifier: MIT-0
-->
```
Cannot mount AppImage, please check your FUSE setup.
```
<!-- SPDX-SnippetEnd -->

A person without FUSE has three ways to run the app:

| Way | What happens | Cost |
| - | - | - |
| pass `--appimage-extract-and-run` to the AppImage, or set `APPIMAGE_EXTRACT_AND_RUN` to any value | the runtime unpacks the app into a folder under `TMPDIR` (or `/tmp`), runs it, and deletes the folder when the program exits | every start unpacks the whole app folder, a whole Ruby with it, so each start takes longer and needs that much free space under `TMPDIR` |
| unpack the platform's `.tar.gz` and run the program in its folder | the program runs from the folder as it is, with no mount | the person unpacks it once, and keeps the folder |
| install the `.deb`, on Debian, Ubuntu, or a relative | `dpkg` installs the app as files under `/usr/lib/IDENTIFIER` | there is a `.deb` only when `installers` lists `deb` and the platform is glibc on x86-64 or ARM64 |

[Run the AppImage without FUSE](../how-to/windowed-app.md#run-the-appimage-without-fuse) shows the commands for `--appimage-extract-and-run` and `APPIMAGE_EXTRACT_AND_RUN`.

## programs

A project can ship several programs in one app folder, sharing one runtime, one copy of the project, and one set of gems, such as a game and its command-line tools. Each entry of `programs` is one of them.

<!-- SPDX-SnippetBegin -->
<!--
  SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
  SPDX-License-Identifier: MIT-0
-->
```yaml
name: Cool App
version: "1.2.3"

programs:
  - path: gui/main.rb
    kind: windowed
    identifier: com.example.CoolApp
    icon: icons/app
  - path: bin/cool
    name: cool
```
<!-- SPDX-SnippetEnd -->

| Key | Value | Default |
| - | - | - |
| `path` | the program's file, from the project's root, with `/` between folders | required |
| `name` | the program's name: its file's name in the app, and what people see | for a console program, its file's name without the extension (`cool` for `bin/cool`); for a windowed one, the project's `name` |
| `kind` | `console` or `windowed` | `console` |
| `identifier` | as [identifier](#identity) | none; a windowed program needs one |
| `icon` | as [icon](#icon-files) | none |

- fledge refuses an empty `programs` list.
- With `programs`, `kind`, `identifier`, and `icon` are set on each program, and fledge refuses them at the top level. `name`, `version`, `publisher`, `copyright`, `installers`, and the rest stay the project's.
- At most one program is windowed. Build another windowed app as a separate project.
- No two programs may share a name or an identifier, ignoring case.
- The windowed program, or else the first one listed, is the app's main program: the one its installers install, and on macOS the one whose bundle holds the others.
- `fledge build` builds every program. `fledge build bin/cool` builds that program alone, as an app with that program's identity.
- A program's file must exist when fledge builds.

## file_associations

The files and folders a windowed app opens, in the terms [Tauri](https://tauri.app) and [electron-builder](https://www.electron.build) use. Each entry of `file_associations` is one kind of document.

<!-- SPDX-SnippetBegin -->
<!--
  SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
  SPDX-License-Identifier: MIT-0
-->
```yaml
file_associations:
  - name: Cool note
    role: editor
    defines_type: true
    extensions: [cnote]
    mime_types: [application/x-cool-note]
  - name: Notes folder
    folders: true
  - name: Plain text
    extensions: [txt, text]
    mime_types: [text/plain]
    content_types: [public.plain-text]
```
<!-- SPDX-SnippetEnd -->

| Key | Value | Default |
| - | - | - |
| `name` | what a person calls these documents, such as `Cool note`, which each system shows as their kind | required |
| `role` | `viewer`, for an app that reads them, or `editor`, for one that writes them too | `viewer` |
| `folders` | `true` for an entry that opens folders and lists no files | `false` |
| `defines_type` | `true` when the files are of a type the app defines, which no other program does, such as a game's save files | `false` |
| `extensions` | the files' extensions, without the dot | none |
| `mime_types` | the files' MIME types | none |
| `content_types` | the files' uniform type identifiers on macOS; given, macOS goes by them and not by extensions or MIME types | none |

- An entry lists at least one extension, MIME type, or content type, or is `folders: true` and lists none.
- A `defines_type: true` entry lists its extensions and exactly one MIME type.
- Only a windowed app has file associations.

What each system does with them:

| System | What happens |
| - | - |
| macOS | The bundle lists each entry as a document type, ranked Alternate, so macOS offers the app in Open With and never makes it the default. |
| Windows, setup program | The setup program adds the app to Open with for each extension, without taking the default, and adds "Open with NAME" to every folder's menu for a `folders: true` entry. The uninstaller removes both. |
| Windows, MSIX | The package declares a file type association for each extension. |
| Linux | The desktop entry lists the MIME types, and `inode/directory` for folders. For a `defines_type: true` entry, the app carries the type's definition, which `dpkg` installs from the `.deb` where shared-mime-info finds it, so a desktop recognizes such a file by its name. |

The program gets the paths of the files and folders it is opened with, or that a person drops on it, in `ARGV`, on every system. On macOS, the launcher takes them from the Apple event Launch Services starts the app with, and waits up to 15 seconds for it.

## macos

What a build for macOS writes in place of what it derives, and the libraries it carries from the computer that builds it. Other builds ignore it.

<!-- SPDX-SnippetBegin -->
<!--
  SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
  SPDX-License-Identifier: MIT-0
-->
```yaml
macos:
  build: "417"
  carried_libraries: [libSDL3.0.dylib]
```
<!-- SPDX-SnippetEnd -->

| Key | Value | Default |
| - | - | - |
| `build` | the build number, `CFBundleVersion`, which the App Store and updaters compare: one to three whole numbers between periods, quoted, such as `"417"` or `"1.2.417"` | the version's first three numbers |
| `carried_libraries` | the libraries from this computer that the app carries, such as one Homebrew installed, by the names that appear in the gems' compiled files | none |

For each carried library, fledge copies the file into the app's `lib/carried` folder, points each file that loads it at the copy, and signs the changed files again. fledge refuses a gem that needs a library not listed, a listed library nothing needs, a library this computer does not have where macOS's loader would look, one with no code for the app's processor, and one that needs a newer macOS than the app's minimum. When a carried library needs another, list both: fledge names every library the list lacks at once.

> [!WARNING]
> You distribute each carried library with your app, so you need the right to distribute it: read its license before you list it.

## linux

What a build for Linux needs to know of the computers the app goes to. Other builds ignore it.

<!-- SPDX-SnippetBegin -->
<!--
  SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
  SPDX-License-Identifier: MIT-0
-->
```yaml
linux:
  system_libraries: [libgtk-3.so.0, libwebkit2gtk-4.1.so.0]
  system_typelibs: [Gtk-4.0]
  deb_depends: [libgtk-4-1, "libadwaita-1-0 (>= 1.4)"]
  deb_changelog: CHANGELOG.md
```
<!-- SPDX-SnippetEnd -->

| Key | Value |
| - | - |
| `system_libraries` | the libraries the gems load from the Linux distribution, by the names that appear in their compiled files, such as `libgtk-3.so.0` |
| `system_typelibs` | the GObject introspection data the gems load from the distribution while the app runs, each a namespace and its version as its typelib file is named, less `.typelib`, such as `Gtk-4.0` |
| `deb_depends` | the packages a `.deb` depends on for what the app's Ruby code opens, such as a library it opens with Fiddle or FFI, which appears in no compiled file, each a Debian Policy relationship, such as `"libadwaita-1-0 (>= 1.4)"` or `"libfoo1t64 \| libfoo1"` |
| `deb_changelog` | the app's changelog, a file in the project, which fledge puts in a `.deb` compressed, for `dpkg` to install as `/usr/share/doc/PACKAGE/changelog.gz` |

- **`system_libraries`:** fledge accepts a gem whose compiled file needs a listed library, and refuses a listed library that no gem's compiled file needs from the system. A `.deb` depends on the packages that provide them, as `dpkg-shlibdeps` finds them on the building computer. The app checks for each one when it starts, before Ruby does, and names the one a computer lacks.
- **`system_typelibs`:** the app checks for each one when it starts, and names the one a computer lacks. A `.deb` depends on its package, `gir1.2-gtk-4.0` for `Gtk-4.0`.
- **`deb_depends`:** the `.deb`'s `Depends` lists these after what the build found. fledge uses them for the `.deb` alone, not for the AppImage or the archive. Name a package, not a library's soname: fledge refuses `libgtk-4.so.1` there and suggests the package.

A library every Linux distribution has, such as `libc.so.6`, `libm.so.6`, `libstdc++.so.6`, `libz.so.1`, `libX11.so.6`, `libGL.so.1`, or `libglib-2.0.so.0`, needs no listing.

## windows

The package identity of an MSIX package, and how the app comes by Microsoft's Visual C++ runtime. Other builds ignore it.

<!-- SPDX-SnippetBegin -->
<!--
  SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
  SPDX-License-Identifier: MIT-0
-->
```yaml
windows:
  visual_c_runtime: central
  msix_name: Example.CoolApp
  msix_publisher: CN=Example
  msix_allow_unsigned: false
  msix_dependencies:
    - name: Microsoft.WindowsAppRuntime.2
      publisher: CN=Microsoft Corporation, O=Microsoft Corporation, L=Redmond, S=Washington, C=US
      min_version: 2.7.0.0
```
<!-- SPDX-SnippetEnd -->

### visual_c_runtime

How the app comes by Microsoft's Visual C++ runtime (`vcruntime140.dll`, `msvcp140.dll`, and the rest) when a gem's DLL needs it. Windows does not include it.

| Value | What happens |
| - | - |
| none (the default) | fledge refuses a gem whose DLL needs the Visual C++ runtime, and says which DLL and what to set. |
| `local` | fledge copies the DLLs the gems need, and the DLLs those need, from this computer's System32 into the app. Microsoft allows that only to licensed Visual Studio users. |
| `central` | the app carries none. It checks at start for each DLL in System32, and, when one is missing, names it and says where to download the Visual C++ Redistributable. The setup program downloads and runs the Redistributable when a DLL is missing, and an MSIX package depends on Microsoft's framework package for it. |

### MSIX

The package identity an `msix` installer needs. Only an `msix` installer reads these keys.

| Key | Value | Default |
| - | - | - |
| `msix_name` | the package's name, Partner Center's Package/Identity/Name for an app in the Microsoft Store: 3 to 50 letters, digits, periods, and hyphens | the `identifier` |
| `msix_publisher` | the package's publisher, a distinguished name such as `CN=Example`: Partner Center's Package/Identity/Publisher, or the subject of the certificate you sign the package with | required for an `msix` installer |
| `msix_allow_unsigned` | whether an unsigned package carries the attribute Windows requires to install it with `Add-AppxPackage -AllowUnsigned` | `true` |
| `msix_dependencies` | the framework packages the app depends on, such as Microsoft's Windows App Runtime for an app that draws with WinUI 3, which the Microsoft Store or App Installer installs with the app: a list of mappings of `name`, `publisher`, and `min_version` (four numbers, each at most 65535), as each package's identity gives them | none |

Set `msix_allow_unsigned: false` for a package you sign after the build, or that the Microsoft Store signs, so that its publisher stays exactly `msix_publisher`. A package that `fledge build --sign` or `--sign-command` signs never carries the attribute. An entry of `msix_dependencies` of the name fledge would write for the Visual C++ runtime replaces fledge's.

## ios

What `fledge build ios` lays over the Xcode project it writes. Desktop builds ignore it.

<!-- SPDX-SnippetBegin -->
<!--
  SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
  SPDX-License-Identifier: MIT-0
-->
```yaml
ios:
  host: host/ios
```
<!-- SPDX-SnippetEnd -->

`host` is a folder in the project whose files fledge copies over the project it writes, before XcodeGen reads it. Each file replaces fledge's file at the same path, such as `Host/main.m`, `Host/Info.plist`, or `project.yml`, or joins the project. fledge fills its `@@NAME@@` marks in a `project.yml` the folder holds, as it does in its template's. The folder is not part of the app's files.

## android

What `fledge build android` lays over the Gradle project it writes. Desktop builds ignore it.

<!-- SPDX-SnippetBegin -->
<!--
  SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
  SPDX-License-Identifier: MIT-0
-->
```yaml
android:
  host: host/android
  host_libraries: [libSDL3.so]
```
<!-- SPDX-SnippetEnd -->

| Key | Value |
| - | - |
| `host` | a folder in the project whose files fledge copies over the project: each replaces fledge's file at the same path, such as `src/main/java/org/setdef/fledge/host/MainActivity.java`, or joins the project. fledge fills its `@@NAME@@` marks in a copy of one of its Gradle files, the manifest, `strings.xml`, or `MainActivity.java`. |
| `host_libraries` | the native libraries the host adds to the app through its Gradle dependencies, such as an AAR's, by the names that appear in the gems' compiled files, each `lib*.so` |

fledge accepts a gem's library that needs a listed host library, and refuses a listed one that none of the app's libraries needs. A library in the host's `src/main/jniLibs` needs no listing.

Android's `applicationId` is the `identifier`, and Android is stricter than other systems: each part between dots must begin with a letter and hold only letters, digits, and underscores. fledge refuses `com.example.cool-app` for Android and suggests `com.example.cool_app`.

## build_tools

<!-- SPDX-SnippetBegin -->
<!--
  SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
  SPDX-License-Identifier: MIT-0
-->
```yaml
build_tools: true
```
<!-- SPDX-SnippetEnd -->

`true` puts in the app the tools that `fledge build --from` runs and a system lacks, so that an app with Fledge in its `Gemfile`, as an ordinary gem, can build a new app from itself on a computer with no Ruby and no runtime. On Windows, the app's `tools` folder gets the runtime's launchers, rcedit, and NSIS; on Linux, the AppImage runtime; on macOS, nothing, since macOS has its tools. The default is `false`. An app that `fledge build --from` writes keeps the tools only when the `fledge.yml` of the project it is built from sets `build_tools`.

`fledge build --from` refuses a `fledge.yml` with `programs`, `linux: system_libraries`, `macos: carried_libraries`, `windows: visual_c_runtime`, `ios`, or `android`, since each changes the runtime or the gems, and `--from` keeps the old app's.

## Examples

### A command-line tool

The smallest useful `fledge.yml` renames the program, which otherwise takes the folder's name, camelized:

<!-- SPDX-SnippetBegin -->
<!--
  SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
  SPDX-License-Identifier: MIT-0
-->
```yaml
name: greet
version: "1.0.0"
```
<!-- SPDX-SnippetEnd -->

### A windowed app for every desktop

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
icon: icons/app
publisher: Example, Inc.
description: Keeps your notes
homepage: https://example.com/cool-app
license_file: LICENSE.txt
installers: [dmg, nsis, appimage, deb]

file_associations:
  - name: Cool note
    role: editor
    extensions: [cnote]
```
<!-- SPDX-SnippetEnd -->

### A game and its command line, in one folder

<!-- SPDX-SnippetBegin -->
<!--
  SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
  SPDX-License-Identifier: MIT-0
-->
```yaml
name: Rocket Run
version: "0.4.0"
installers: [dmg, nsis, appimage]

programs:
  - path: game/main.rb
    kind: windowed
    identifier: com.example.RocketRun
    icon: art/icon
  - path: bin/rocket-run-server
    name: rocket-run-server
```
<!-- SPDX-SnippetEnd -->
