# Desktop apps

This part lays a runtime, a project, and its gems out as an app folder, gives each system the identity it expects, writes the installers, and packs the archive. Its input is everything [Gems](gems.md) and [Runtimes](runtimes.md) produce; its output is the files the CLI prints.

## The pieces

| Piece | Role |
| - | - |
| `Assembly` | builds one app: the folder, `fledge.cfg`, the launchers, signing, installers, notarizing, and the archive, removing everything it wrote if any step fails |
| `Assembly::RuntimeFolder` | an unpacked runtime: its launchers, its tools folder, and the files that move into the app, less what the runtime holds only for compiling gems |
| `Assembly::BuildTools` | copies the runtime's build tools into the app, for `build_tools` |
| `BuiltApp`, `BuiltApp::Tree` | an app fledge built, read for `--from`: its `fledge.cfg`, kept gems and lockfile, and launchers, standing in for a runtime folder |
| `MacBundle` | a windowed Mac app's bundle: `Info.plist`, links in `Contents/MacOS`, the icon, and the signature |
| `DesktopEntry`, `SharedMimeInfo` | a windowed Linux app's desktop entry and icons, and the definitions of the file types it defines |
| `WindowsResources` | a Windows program's version resources and icon, written with rcedit |
| `Installers` | which installers an app gets on a platform, their file names, and what each needs from the app |
| `Dmg`, `Nsis` and `Nsis::Script`, `AppImage`, `Deb`, `Msix` | one installer each, written with that system's tool |
| `Archive` | packs a folder as `.tar.gz` or `.zip`, and lists, reads, and unpacks archives, with the system's `tar` |
| `Checksum` | writes the `.sha256` beside each file |
| `CacheTag` | marks the output folder, and recognizes marked folders |
| `Entry` | a file, folder, or link to write into the app at a safe relative path |

## Building the folder

`Assembly` works in a temporary folder inside the output folder, so that the final moves stay on one file system:

1. Unpack the runtime, or for `--from` the old app's tree, and move its files into the app's contents: the folder itself, or a Mac bundle's `Contents/Resources`.
2. Write `fledge.cfg`, then the project's entries under `app/`, with the files `AppGems` rewrote (the app's `.bundle/config`, evaluated gemspecs, path gems' compiled files) in place of the project's, then the gems' entries.
3. Place a launcher for each program: the runtime's `launcher`, or `launcherw` for a windowed Windows program, renamed for the program. On Windows, apply each program's version resources; on Linux, a windowed program's desktop entry.
4. Sign, finish the Mac bundle, and copy the build tools.
5. Write each installer, notarize, and pack the archive.

Every entry is written through `Entry#write_into`, which refuses a path that leaves the app and a write through a link, and `Assembly#add` refuses to overwrite anything the runtime already holds. A name that collides with the runtime's files, with `app`, with `fledge.cfg`, or with `tools`, is refused before anything is written. A symbolic link can't go in a Windows `.zip`, so one is refused there.

## Identity on each system

One `Identity` feeds every system's idea of an app:

| Value | macOS | Windows | Linux |
| - | - | - | - |
| name | bundle name and executable, `CFBundleName`, `CFBundleDisplayName` | `NAME.exe`, `ProductName`, `FileDescription`, Start menu shortcut, install folder | the program's file, the desktop entry's `Name`, the AppImage's `AppRun` |
| identifier | `CFBundleIdentifier`, the bundle's signing identifier | the AppUserModelID of the process and its shortcuts, the uninstall key, the ProgIDs, the MSIX name by default | the desktop entry's and icons' file names, the `.deb`'s package name, lowercased |
| version | `CFBundleShortVersionString` and `CFBundleVersion` | file and product versions, four numbers | the `.deb`'s version, prereleases after `~` |
| icon | `NAME.icns` in the bundle | the `.exe`'s icon, the installer's icon | `share/icons/hicolor/SIZE/apps/IDENTIFIER.png`, the AppImage's `.DirIcon` |
| file associations | `CFBundleDocumentTypes`, ranked Alternate | Open with entries and a folder verb, written by the setup program; file type associations in the MSIX manifest | the desktop entry's `MimeType`, and shared-mime-info definitions |

The launcher is the same program in every app: each app's details live in `fledge.cfg` beside it, so nothing of one app is compiled into it (ADR 001). What Assembly changes in an app's copy, before signing it, is what each system reads from the file itself: on Windows, rcedit writes the version resources and icon. On macOS the launcher, renamed, is the bundle's executable; the bundle's `Contents/MacOS` holds links to the runtime's folders in `Contents/Resources`, so the launcher finds its `fledge.cfg` and Ruby beside it, as on other systems. A console program in a windowed Mac app's project lives in `Contents/MacOS` too, inside the bundle's signature, with a link to it at the top of the app folder.

## Installers

`Installers.formats` picks, from `fledge.yml`'s list or the default, those whose system is the platform's (a `.deb` also needs a glibc platform with a Debian architecture). Each installer takes the finished app folder and writes one file beside it, named `BASE` plus its suffix:

- **`Dmg`** stages the bundle and a link to `/Applications`, and runs `hdiutil create`, retrying while the volume is busy.
- **`Nsis`** writes a script for NSIS's Modern UI and compiles it with the `makensis` in the runtime's tools: a per-user install under `%LOCALAPPDATA%\Programs`, with no elevation, an uninstaller registered under `HKCU`, shortcuts carrying the AppUserModelID, Open with registrations that take no default, and, for a `central` Visual C++ runtime, a section that downloads and runs Microsoft's Redistributable when a DLL is missing. A new version runs the old uninstaller first.
- **`AppImage`** copies the folder to an AppDir with `AppRun` and the icon, runs `mksquashfs` with the runtime's AppImage runtime as the image's head, and honors `SOURCE_DATE_EPOCH`.
- **`Deb`** lays the app out under `/usr/lib/IDENTIFIER`, moves its `share` into `/usr/share`, writes its documents and control file, and builds with `dpkg-deb`. Its `Depends` is the glibc the build recorded, what `dpkg-shlibdeps` finds for the listed system libraries, the typelibs' `gir1.2-` packages, and `deb_depends`.
- **`Msix`** writes the package manifest and a mapping of the folder, and packs with the Windows SDK's `makeappx`. An unsigned package gets the OID Windows requires of one, unless `fledge.yml` turns it off.

## Building from a built app

`BuiltApp` reads an app's `fledge.cfg` to recover what its build knew: the Fledge version and platform (which must be this one's), the Gemfile and Bundler, the system libraries and typelibs, the Visual C++ runtime, and the glibc floor. It refuses a new project that would change the gems, or that holds a file the old app's project supplies. Its `Tree` takes a runtime folder's place in Assembly: the old app's files (less its programs, identity files, and `fledge.cfg`) as the runtime, and launchers from the old app's tools folder, from a runtime on this computer, or, on macOS and Linux, a copy of the old app's launcher, signed ad hoc on macOS.

## Traps

- **A failed build leaves nothing.** `Assembly` removes the folder, the archive, and every installer of the same base name before it starts, and again when any step raises. Don't write output anywhere it doesn't know to remove.
- **The output folder may be inside the project.** `dist` usually is. `App#entries` skips it by its `CACHEDIR.TAG`, and Assembly skips the output folder by path, so an app never contains itself.
- **Windows paths go to Windows tools as Windows paths.** NSIS's script, `makeappx`'s mapping, and signtool's arguments all take `Nsis.host_path`, with backslashes.
- **`tar` differs.** GNU tar and BSD tar take different options to record a neutral owner; `Archive` asks the tar which it is. On Windows, `Archive` runs the `tar.exe` in System32, which reads each archive from standard input, and writes a `.zip` with .NET through PowerShell, with forward slashes.

## What this part doesn't do

- Give a console app installers, or a Linux app a signature.
- Change the runtime's files. An app is the runtime's files as released, plus what the build adds beside them.
- Make an app update itself.
