<!--
SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>

SPDX-License-Identifier: CC-BY-SA-4.0
-->

# What fledge build Writes on a Desktop

This document says what `fledge build` writes for a macOS, Windows, or Linux app: what it takes from the project, the folder and archive it writes, the identity each system reads, the icons, a project of several programs, the installers, the files an app opens, and `fledge build --from`. It is for Fledge's contributors; an app's developer reads `doc/desktop_apps.md` and `doc/building_from_an_app.md`, which this document does not repeat. Why things are so is in the ADRs: ADR 005 (the program you already run), ADR 008 (identity), ADR 009 and ADR 021 (installers), ADR 010 (each platform's own tools), ADR 024 (several programs), ADR 032 (`--from`), ADR 037 (console and windowed), ADR 047 (tar), ADR 048 (icons), ADR 049 (NSIS's and AppImage's releases), and ADR 052 (files an app opens). Signing and notarizing are in `doc/contributors/design/signing.md`; the launcher and `fledge.cfg` are in `doc/contributors/design/launcher.md`; the gems are in `doc/contributors/design/gems.md`.

## The project and its name

`fledge build PATH` takes the program to ship (ADR 005). A file is the entry point. A folder means the one executable its project's gemspec names (`bindir` and `executables`), or else the folder's `main.rb`; any other folder fails, saying which program to name. With `programs` in `fledge.yml`, a folder means every listed program (see "Several programs").

The project's root is the nearest folder, from the entry point's up, that holds a `Gemfile`, a `gems.rb`, a `fledge.yml`, or a gemspec, as Bundler finds a Gemfile by walking up (`SharedHelpers.find_file`). The walk stops at a folder that holds `.git`, so a script never joins a project above its repository; a script with none of these is a project of its own folder. A root that is the developer's home folder is refused. A root with a gemspec but no Gemfile is refused, saying to add one and run `bundle lock`. (`Fledge::App.at`.)

Everything in the root ships, as the built app's `app/`, except:

- `.git`, `.bundle` (the developer's Bundler settings), and `vendor/bundle` and `vendor/cache` (gems Bundler installed or cached for the developer's computer): `App::NEVER_SHIPPED`;
- the folder this build writes to, `--out`;
- every folder that holds a valid cache directory tag, with all it holds.

The tag is how a build's output stays out of later builds, wherever they write. When a build makes the folder it writes to, or finds it empty, it writes `CACHEDIR.TAG` there, beginning with `Signature: 8a477f597d28d172789f06886806bc55`, as the Cache Directory Tagging Specification (https://bford.info/cachedir/) defines it and as Cargo tags its `target` folder (`Fledge::CacheTag`). The copy of the project leaves out every folder whose tag is a regular file, not a link, beginning with those bytes, as GNU tar's `--exclude-caches-all` does. Without the tag, a build into `dist` and then one into `out` would ship the first app inside the second. Do not replace the tag with a rule that recognizes a build by its contents: that needs a pattern for each platform and installer, misses a folder whose app was deleted but whose archive stayed, and could take a developer's own file for a build. Its limits:

- a folder that held anything when the first build went to it gets no tag, so a tag never marks a developer's own files as a cache, and a later build elsewhere ships it unless it is emptied or tagged by hand;
- any tool's valid tag keeps its folder out of the app, which is what the tag means;
- the default `dist` is no exception: a project's own `dist` of source files, which no build went to, ships when the build goes elsewhere.

**NAME** is `fledge.yml`'s `name`, or else the root's gemspec's name, or else the root folder's name, camelized as Bundler's gem template names a module (`Fledge::App.camelize`: each run of letters and digits begins with a capital, and nothing else stays; `my_cool_app` is `MyCoolApp`). A name no system can give a program and a folder fails the build, saying to name the app in `fledge.yml`: an empty one, one with a character some file systems forbid (`/ \ : * ? " < > |` or a control character), one Windows keeps for a device (`CON`, `PRN`, `AUX`, `NUL`, `COM1`, `LPT1`, and the rest, with or without an extension), and one that ends in a period or a space.

## The build's command line

The options, their forms, and the exit statuses are `exe/fledge`'s help header, which `fledge --help` prints, and ADR 002. `--out=DIR` and `--out DIR` both work, and `--` ends the options (GNU Coding Standards, 4.8; POSIX Utility Syntax Guideline 10). `--out` may not be the project's root. `-t` and `--target` are a usage error that says a build is for this computer (ADR 010). Where runtimes come from (`FLEDGE_RUNTIME_DIR`, `FLEDGE_RUNTIME_MIRROR`, the cache) is in `doc/contributors/design/runtimes.md`.

## The folder and the archive

A build writes `OUT/NAME-PLATFORM/`, to try, and `OUT/NAME-PLATFORM.tar.gz`, or `.zip` on Windows, to ship (`Fledge::Assembly`). PLATFORM is the RubyGems platform of the computer that builds (ADR 036). The folder is the runtime with the app in it, as LÖVE's fused games and PyInstaller's one-folder bundles ship a folder beside the program:

- **macOS and Linux:** the program `NAME`, `fledge.cfg`, `app/`, the runtime's `bin/`, `lib/`, and `libexec/`, and `notices/` with `NOTICES.txt` and `sbom.spdx.json` from the license audit (ADR 004). A windowed macOS app's folder holds `NAME.app` in their place (see "Identity on each system"); a windowed Linux app's adds `IDENTIFIER.desktop` and `share/icons/`.
- **Windows:** `NAME.exe`, `fledge.cfg`, `app\`, `notices\`, and RubyInstaller's tree in `ruby\` (ADR 038).

The layout of the runtime itself is in `doc/contributors/design/runtimes.md`.

**Order.** The build first removes any earlier `NAME-PLATFORM/`, its archive, and every installer of that base name, then works in a temporary folder `.fledge-build-*` inside OUT, so the moves stay on one disk. It unpacks the runtime with tar, moves it into the folder (or a bundle's `Contents/Resources`), writes `fledge.cfg`, copies the project and its gems in, and places each program last, once everything it must describe or seal is there; then it signs, copies `build_tools`, writes the installers, notarizes, and packs the archive. A build that fails removes what it wrote.

**Collisions.** A program may not be named `app`, `fledge.cfg`, or, with `build_tools`, `tools`, ignoring case, nor take the name of a file the runtime holds. Nothing the build adds may replace a file of the runtime's. A Windows app may not hold a symbolic link, which a `.zip` for Windows cannot carry; the build refuses one and says to replace it with what it points to.

**tar** (ADR 047; `Fledge::Archive`) is the computer's own:

- On Linux and macOS, `tar -czf FILE NAME-PLATFORM` run in OUT, so the archive holds one top folder. On macOS `COPYFILE_DISABLE=1` keeps bsdtar from adding AppleDouble files.
- On Windows, `%SystemRoot%\System32\tar.exe --format zip -cf FILE NAME-PLATFORM`, named in full, since Git's GNU tar, often first on a developer's `PATH`, writes no ZIP and reads `C:` as a host name.
- Unpacking is `tar -xf ARCHIVE -C INTO`, but on Windows tar reads the archive from standard input in the folder it unpacks into (`tar -xf -`), since Windows' `tar.exe` reads its arguments in the ANSI code page and cannot open a path outside it. Packing still names the app's folder as an argument, so an app whose own name is outside the ANSI code page is untested.

**Standard output.** `fledge build` prints the archive's path and then each installer's, one per line, each joined to `--out` as the developer wrote it; progress and warnings go to standard error (GNU Coding Standards, 4.8). The folder is not printed: a wrapper derives it from the archive's name.

**Checksum files.** Beside the archive and each installer, `fledge build` writes `FILE.sha256`, one line in GNU coreutils' `sha256sum` format, `HEX  NAME` (`Fledge::Checksum`), after the file is final, so a notarized or signed file's checksum is of what ships. Ruby's `Digest::SHA256` writes it, since no tool on all three systems prints that format (macOS has `shasum`, Windows `Get-FileHash` and `certutil`). The file is always written, one per archive as cargo-dist and GoReleaser's `split` write them, and never one list per release: each platform's app is built on its own computer, so one list under one name would be written once on each. `sha256sum -c` and `shasum -a 256 -c` check it, and `cat *.sha256` makes a release page's list. Every package manager that installs a console app from a release names its SHA-256 (`doc/package_managers.md`).

## Identity on each system

`fledge.yml`'s keys and their rules are `lib/fledge/config.schema.json`. Their defaults (`Fledge::Identity`):

- **name**: NAME, above.
- **kind**: `console` (ADR 037).
- **identifier**: none. A windowed app without one fails, suggesting `io.github.OWNER.NAME` when the gemspec's homepage is on `github.com`, or else `com.example.NAME`, NAME stripped to letters, digits, and hyphens. It is reverse-DNS: two or more parts of letters, digits, and hyphens between dots, each beginning with a letter or digit, in at most 128 characters, an AppUserModelID's limit.
- **version**: the gemspec's, or else `0.0.0`. It begins with a number and is a version RubyGems reads. A version YAML reads as a number is refused, saying to quote it, since YAML would read `1.10` as `1.1`.
- **publisher**: the gemspec's authors, joined with commas.
- **copyright**, **description** (one line), **long_description**, **homepage** (an `http` or `https` URL with no spaces), and **icon**: none.

### macOS

A windowed app is `NAME.app` (`Fledge::MacBundle`); a console app stays a folder, since a terminal tool has no bundle.

```
NAME-PLATFORM/NAME.app/Contents/Info.plist
                              MacOS/NAME                    the launcher
                              MacOS/{app,bin,fledge.cfg,lib,libexec} -> ../Resources/...
                              MacOS/HELPER                  each console program (see "Several programs")
                              Resources/NAME.icns
                              Resources/{app,bin,fledge.cfg,lib,libexec,notices}
                              _CodeSignature/CodeResources
```

The runtime and the app live in `Contents/Resources`, and symbolic links in `Contents/MacOS` point at them. Ruby takes its prefix from the program that holds libruby (ADR 001), and the launcher reads `fledge.cfg` and `app/` beside itself, so its neighbors must be reachable from `Contents/MacOS`; but Apple's tools expect only code there, and codesign wants a data file in a nested-code location signed on its own. The launcher runs the app from its real folder under `Resources`, so `__dir__` and `$0` agree (`doc/contributors/design/launcher.md`).

`Info.plist` holds Tauri's keys, less those that describe Tauri's own runtime (`CSResourcesFileMapped`, `LSRequiresCarbon`):

| Key | Value |
|---|---|
| `CFBundleDevelopmentRegion` | `en` |
| `CFBundleDisplayName`, `CFBundleName`, `CFBundleExecutable` | the name |
| `CFBundleIdentifier` | the identifier |
| `CFBundleInfoDictionaryVersion` | `6.0` |
| `CFBundlePackageType` | `APPL` |
| `CFBundleShortVersionString` | the version's leading whole numbers, at most three, as Apple's reference asks (`0.0.1.pre.6` is `0.0.1`) |
| `CFBundleVersion` | `fledge.yml`'s `macos: build`, or else the short version |
| `LSMinimumSystemVersion` | the runtime's floor, `Platform::MACOS_MINIMUM` |
| `NSHighResolutionCapable` | true |
| `CFBundleIconFile` | `NAME.icns`, with an icon |
| `NSHumanReadableCopyright` | the copyright, when there is one |
| `CFBundleDocumentTypes` | the files the app opens (see "Files an app opens") |

Fledge writes these as JSON and converts them with `plutil -convert xml1`. Unsigned, the bundle is signed ad hoc with `codesign --force --sign - --identifier IDENTIFIER NAME.app`, which seals `Info.plist` and every resource and signs the launcher for them: Apple Silicon runs only signed code, and `codesign --verify --strict --deep` calls a bundle broken unless its program's signature seals the rest. With `--sign`, the bundle is signed as `doc/contributors/design/signing.md` says.

### Windows

A windowed app's program is the runtime's `launcherw.exe` renamed, and a console app's is `launcher.exe`; the other never ships (ADR 037). Every program, console or windowed, gets its identity from rcedit (`Fledge::WindowsResources`), from the runtime's `tools\rcedit.exe`, copied to a temporary folder and run from there, since on Windows on ARM the emulator's cache service keeps an emulated program open after it exits (`doc/contributors/design/runtimes.md`):

- `--set-version-string` for FileDescription, ProductName, and InternalName (the name), OriginalFilename (the program's file name), and, when there are, CompanyName (the publisher), LegalCopyright (the copyright), and Comments (the description). Task Manager shows FileDescription.
- `--set-file-version` and `--set-product-version` with the version as written; rcedit keeps it as FileVersion and ProductVersion and makes its leading numbers FILEVERSION and PRODUCTVERSION.
- `--set-icon` with the developer's `.ico`.

FILEVERSION and PRODUCTVERSION hold at most four parts of 16 bits each. Fledge refuses a version that does not begin with a number, or that has a part above 65535 among its first four leading whole numbers, itself, since rcedit would let it wrap. rcedit keeps the launcher's manifest. The launcher makes `fledge.cfg`'s `identifier` the process's AppUserModelID before any window opens (`doc/contributors/design/launcher.md`).

### Linux

A windowed app is the same folder as a console one, with `IDENTIFIER.desktop` at its top, as an AppImage's AppDir keeps it, and its icons at `share/icons/hicolor/SIZExSIZE/apps/IDENTIFIER.png`, the layout of `$XDG_DATA_HOME`, so installing it by hand is copying `share` into `~/.local/share` and the desktop entry into its `applications` with the program's full path in `Exec`. A console app gets no desktop entry. The entry (`Fledge::DesktopEntry`), which `desktop-file-validate` accepts:

```
[Desktop Entry]
Type=Application
Version=1.5
Name=NAME
Comment=DESCRIPTION          when there is a description
Exec=PROGRAM                 PROGRAM %F when the app opens files
Icon=IDENTIFIER              when there is an icon
Terminal=false
MimeType=TYPE;...            when the app opens files
```

`Name` and `Comment` escape backslashes, line breaks, tabs, and a leading space as the Desktop Entry Specification asks. `Exec` doubles `%` and quotes a program whose name holds a space or a reserved character, escaping `"`, `` ` ``, `$`, and `\` inside the quotes (`Exec="Hello Window"`). A window class (`StartupWMClass`) is not written: the GUI library chooses it.

## Icons

`fledge.yml`'s `icon` is a path without an extension, relative to the root (ADR 048; `Fledge::Icon`). An `icon` that ends in an extension fails, saying to drop it. Each build takes its own files:

- **macOS:** `ICON.icns`, copied to `Contents/Resources/NAME.icns`.
- **Windows:** `ICON.ico`, written into each program by rcedit and into the setup program by makensis.
- **Linux:** `ICON-16.png`, `ICON-32.png`, `ICON-64.png`, `ICON-128.png`, `ICON-256.png`, and `ICON-512.png` (`Icon::LINUX`), Briefcase's six. The build ships each one there is into `share/icons/hicolor`, names the missing ones on standard error as a warning, and fails only when there is none, naming the smallest. The AppImage's top-level icon is the 256-pixel PNG, or else the largest there is, as Tauri's bundler picks the largest square.

A missing file fails that platform's build with what it needs and how to make it (`Icon::MAKE`). Fledge reads none of these formats and checks no sizes. A phone's icons come from the same key (`doc/contributors/design/phones.md`).

## Several programs

`fledge.yml`'s `programs` is a list of mappings, one per program, in the developer's order (ADR 024; `Fledge::Config::Program`). Each has:

- **path**, required: the program's file, relative to the root, with `/` between folders, inside the project.
- **name**: as an app's name, but for this program. A console program's defaults to the path's file name less its extension (`bin/cli` is `cli`), as Cargo names a binary: it is the command someone types. A windowed program's defaults to the project's NAME, since it is what the Dock, the Start menu, and the window list show, and `gui/main.rb` would otherwise show "main". No two programs share a name, ignoring case, since Windows' and macOS's file systems ignore it.
- **kind**: `console`, the default, or `windowed`.
- **identifier** and **icon**, as an app's, for this program. A windowed program needs an identifier, and no two programs share one, since Windows groups windows and attributes notifications by it.

With `programs`, `kind`, `identifier`, and `icon` at the top of `fledge.yml` are refused, naming where to move them. `name`, `version`, `publisher`, `copyright`, and `installers` stay at the top: `name` names the folder, its archive, and the installers, and each program's version information carries the project's version, publisher, and copyright. At most one program is windowed. A project whose programs are all console gets no installers, and `installers` with entries is refused there.

**fledge.cfg.** With several programs, `fledge.cfg` keeps `gemfile` and `system_libraries` at the top and gives each program a section headed by its name, holding its `entry` and `identifier`. Each launcher reads the section whose name is its own file name, less `.exe`, ignoring case. A project with one program, or a build of one program, writes `fledge.cfg` with no section, and its launcher runs under any name. The format, and what a launcher does with a missing or damaged section, are in `doc/contributors/design/launcher.md`.

**Layout.** One folder holds the runtime and `app/` once, and every program beside them:

- **Windows:** `NAME.exe` for the windowed program (`launcherw.exe` renamed) and one `.exe` per console program (`launcher.exe` renamed), each with its own name and icon from rcedit and the project's version, beside `fledge.cfg`, `app\`, and `ruby\`.
- **Linux:** each program beside `lib/` and `app/`, and the windowed program's desktop entry and icons.
- **macOS with a windowed program:** everything is in its bundle. Each console program is a copy of the launcher in `Contents/MacOS`, beside the bundle's executable, where Apple puts a bundle's helper tools, so the bundle's signature seals them. The folder beside the bundle holds a symbolic link for each, `my-game-cli -> MyGame.app/Contents/MacOS/my-game-cli`, and the launcher resolves the link to the runtime it lives in.
- **macOS with no windowed program:** the Linux layout.

**Installers.** The installers are the windowed program's, with its identity: its name in the disk image, the setup program's shortcut and uninstall entry, the AppImage's and the `.deb`'s desktop entry. Each holds the whole folder, so every console program installs beside the windowed one, as Tauri's installers install every binary but the main one: inside the bundle on macOS, in `%LOCALAPPDATA%\Programs\NAME` on Windows, and in `/usr/lib/PACKAGE` from a `.deb`. Nothing puts a console program on a `PATH`. An AppImage runs its windowed program; its console programs are reached through `--appimage-extract`.

**Signing.** `--sign` signs every program: signtool signs every PE file of the folder, every launcher copy among them; codesign signs each console program in `Contents/MacOS` before the bundle, inside out, and every Mach-O file of a folder with no bundle. Unsigned, each launcher copy keeps the signature it arrives with, and the bundle's ad hoc signature seals every file in it.

**Building one program.** `fledge build FILE`, where FILE is one of the listed programs, builds that program alone, as a project with no `programs` builds its one program: its folder, archive, and installers are named after the program, with the program's name, kind, identifier, and icon and the project's other keys, and its `fledge.cfg` has no section. A FILE `programs` does not list is refused, listing the programs. A phone's build takes one program: the one PATH names, or else the windowed one, or else the first.

**Messages.** `fledge build` exits 0, 1 for a build that fails, and 2 for a usage error. Each refusal names the full path of `fledge.yml` and the program, and says what to write instead:

- `fledge.yml: programs must be a list of at least one program, each a mapping such as - path: bin/cli`
- `fledge.yml: program 2 has no path, the program's file in the project, such as path: bin/cli`
- `fledge.yml: program 1's path, "../cli", must name a file in the project, with / between folders, such as path: bin/cli`
- `fledge.yml: the program bin/cli has 'paht', which Fledge does not know. A program knows path, name, kind, identifier, and icon.`
- `fledge.yml: the program bin/cli: kind must be console or windowed, not gui`
- `fledge.yml: a/cli and b/cli.rb are both named cli; give each its own`, and the same when a windowed program takes the project's name and another program has it
- `fledge.yml: gui/main.rb and editor/main.rb are both windowed, and a project has one windowed program; build another on its own, with fledge build editor/main.rb`
- `fledge.yml: with programs, kind belongs to each program; move it into the program it describes`
- `fledge.yml lists the program bin/clli, but the project has no such file. List the program you run, such as path: bin/cli.`
- `bin/protocol is not one of the programs fledge.yml lists. Build the project, or one of gui/main.rb, bin/cli, bin/tui.`

A program renamed by hand in a folder of several exits with 66 and `renamed: this app is incomplete: ROOT/fledge.cfg has no program named renamed`.

## Installers

A windowed app gets the installers its platform has (ADR 009; `Fledge::Installers`), or the ones `installers` lists, which may be `[]`. Each is written beside the archive, from the built folder, named as the archive is, with no version, so a script finds it by platform:

| Value | Platform | File |
|---|---|---|
| `dmg` | macOS | `NAME-PLATFORM.dmg` |
| `nsis` | Windows | `NAME-PLATFORM-setup.exe`, ending as Tauri's do |
| `appimage` | Linux | `NAME-PLATFORM.AppImage` |
| `deb` | glibc Linux, `x86_64-linux` and `aarch64-linux` | `NAME-PLATFORM.deb` (ADR 021) |

The default is `dmg`, `nsis`, and `appimage` (`Config::DEFAULT_INSTALLERS`); `deb` is never a default. A build makes the listed ones for its own platform and ignores the rest, so `deb` builds nothing on musl. An unknown value fails, and a console app that lists any fails. What the setup program and the AppImage copy in comes from the runtime's `tools` folder, which no app holds unless `build_tools` is set (`doc/contributors/design/runtimes.md`). With `license_file`, the setup program shows it and the `.deb` holds it; the file must be UTF-8, and a byte order mark at its start is dropped.

## The disk image

`Fledge::Dmg` makes what Tauri's create-dmg makes: the bundle, copied with `ditto` (which keeps its signature, links, and modes), beside a link named `Applications` to `/Applications`, in a staging folder; then `hdiutil create -volname NAME -srcfolder STAGE -fs HFS+ -format UDZO -ov FILE`, a read-only, zlib-compressed image of a Mac OS Extended volume, as create-dmg's are. With `--sign`, the image is then signed (`doc/contributors/design/signing.md`). A background picture and a laid-out window, which create-dmg writes as a `.DS_Store` of Finder's private format, are left out.

On macOS 26 and newer, `hdiutil create` prints that `diskutil image create` replaces it; Fledge runs it anyway and reads its output only when it fails, since macOS 14 and 15, the oldest Fledge apps run on, have only `hdiutil`.

**"Resource busy."** `hdiutil create -srcfolder` makes a container, puts a file system in it, and copies the folder to it (`man hdiutil`, DESCRIPTION), mounting that scratch volume while it copies and detaching it before it writes the image. It fails with "create failed - Resource busy" when another process holds the volume as it detaches; `man hdiutil`, DIAGNOSTICS, says EBUSY "often appears when a volume can't be unmounted". GitHub's macOS runners hit it now and then, and the runner image's maintainers traced it to `XProtectBehaviorService` holding the new image and recommend trying again (actions/runner-images#7522). Fledge cannot keep XProtect or Spotlight off a volume hdiutil mounts inside its own run, so it does what create-dmg does (`create-dmg`, lines 34 and 49 to 86, at a2b71d0): when the error holds "Resource busy", it waits and runs the same command again, after 2, 4, 8, and 16 seconds (`Dmg::WAITS`), five runs in all. Any other failure, or a fifth busy one, fails the build with hdiutil's words. Matching the text rather than the exit status, which is 1 for real errors too, keeps a real error from costing 30 seconds. electron-builder retries every hdiutil command up to five times for exit codes it calls transient, and dmgbuild retries `hdiutil detach` twelve times; create-dmg's rule is the narrowest. The race cannot be provoked on demand, so `test/dmg_test.rb` puts an `hdiutil` first on `PATH` that fails with the runner's message before it runs the real one.

## The NSIS setup program

`Fledge::Nsis` writes an NSIS script as Tauri's `installer.nsi` does for its default `currentUser` mode, without Tauri's own plug-in (`Fledge::Nsis::Script`), and compiles it with the Windows runtime's `tools\nsis\Bin\makensis.exe` (NSIS's own release, ADR 049), copied to a temporary folder, run as `makensis -V2 -NOCD -NOCONFIG -INPUTCHARSET UTF8 SCRIPT` with `NSISDIR` pointing at the copy, so every computer builds the same installer from the same pieces. The script is UTF-8 with a byte order mark. What the runtime's `tools\nsis` holds is listed in `tasks/runtime_builder/windows.rb` (`NSIS`).

- **Settings:** `Unicode true`, `ManifestDPIAware true`, `SetCompressor /SOLID lzma` (NSIS's default and Tauri's), `RequestExecutionLevel user`, Modern UI 2, and English.
- **Where:** `InstallDir "$LOCALAPPDATA\Programs\NAME"`, Windows' known folder for programs one person installs (`FOLDERID_UserProgramFiles`), as electron-builder's per-user installers use; Tauri's `$LOCALAPPDATA\NAME` sits beside apps' data. No administrator is needed. The folder page lets a person choose another, and `.onInit` reads the uninstall entry's `InstallLocation`, so a reinstall goes where the last install went.
- **Pages:** with `license_file`, Modern UI's license page first (`MUI_PAGE_LICENSE`), as Tauri's is, which a person accepts before anything else; then the folder, the files, and the finish page, which offers to run the app and, through its "show readme" check box, unchecked, as Tauri does, to make a desktop shortcut. The uninstaller shows a confirm page and its progress. A silent install (`/S`) shows no page and makes no desktop shortcut. The license page reads a copy of the file with a UTF-8 byte order mark, as Tauri's bundler writes one for its Unicode installer, and DOS line endings, which NSIS's manual asks of `LicenseData` (section 4.8.1.26).
- **Install:** if the folder holds an `uninstall.exe`, run it first, silently, in place (`ExecWait '"…\uninstall.exe" /S _?=$INSTDIR'`), as electron-builder's installers do, so a file the old version had and the new one does not is not left behind; then copy the folder, write `uninstall.exe`, and make `$SMPROGRAMS\NAME.lnk` to the program.
- **The shortcut's AppUserModelID:** each shortcut's `System.AppUserModel.ID` is set to the identifier, the AppUserModelID the launcher gives the process, through IShellLink, IPersistFile, and IPropertyStore with NSIS's System plug-in and its COM headers, as Tauri's `SetLnkAppUserModelId` macro does, but as the `VT_LPWSTR` the property is (`Win\Propkey.nsh`). Windows shows an app's toasts only when a Start menu shortcut carries the same ID the process has.
- **Uninstall key:** `HKCU\Software\Microsoft\Windows\CurrentVersion\Uninstall\IDENTIFIER`, by identifier rather than Tauri's product name, since two apps may share a name but not an identifier: `DisplayName`, `DisplayVersion`, `Publisher` (when there is one), `URLInfoAbout` and `HelpLink` (the homepage, when there is one, as Tauri's `installer.nsi` writes them), `DisplayIcon`, `InstallLocation`, `UninstallString`, `QuietUninstallString` (with `/S`), `NoModify`, `NoRepair`, and `EstimatedSize` in KiB.
- **Version information** of the setup program, by `VIAddVersionKey`: ProductName, FileDescription (`NAME Setup`), FileVersion and ProductVersion (the version as written), CompanyName and LegalCopyright when there are, and `VIProductVersion` and `VIFileVersion` of the four Windows numbers. The app's `.ico` is its icon and the uninstaller's (`MUI_ICON`, `MUI_UNICON`). `BrandingText` is the copyright, or the name.
- **Uninstall:** delete the shortcuts, then by name each file the install wrote, then each folder it made, deepest first, then the install folder only if it is empty, as Tauri's does, so nothing a person put there is lost; then the uninstall key and the file associations.
- **Signing:** with `--sign` or `--sign-command`, `!uninstfinalize` and `!finalize` lines (`doc/contributors/design/signing.md`).

A build that fails reports makensis's output, and names a signing command's failure on the setup program or its uninstaller.

## The AppImage

`Fledge::AppImage` makes a type 2 AppImage as appimagetool does (`src/appimagetool.c` at its 1.9.1 tag, `sfs_mksquashfs`, lines 97 to 215), without running appimagetool (ADR 049):

1. Copy the built folder, which already has the desktop entry at its top and its icons under `share/icons`, into an `AppDir`, keeping modes and links.
2. Add `AppRun`, a symbolic link to the program (the launcher finds its runtime through `/proc/self/exe`, so a link is all it needs), and, with an icon, `IDENTIFIER.png` at the top, the 256-pixel PNG or else the largest, and `.DirIcon`, a link to it.
3. Run `mksquashfs APPDIR FILE -offset SIZE -comp zstd -b 128K -root-owned -noappend -mkfs-time 0 -quiet`, SIZE being the runtime's size, from squashfs-tools 4.4 or newer, which a Linux developer installs from their distribution. A computer without it is told to install squashfs-tools.
4. Write the runtime, `tools/appimage-runtime` from the Linux runtime, AppImage's own release, into the room `-offset` left, and make the file executable.

Update information (zsync) and a signature, which appimagetool can embed in the runtime's sections, are left empty. The AppImage behaves as every AppImage does: with FUSE it mounts itself; without FUSE it says "Cannot mount AppImage, please check your FUSE setup." and runs only when asked to extract itself, with `APPIMAGE_EXTRACT_AND_RUN=1` or `--appimage-extract-and-run`. `--appimage-extract` unpacks the AppDir, notices included. A person who downloads one makes it executable, as with any AppImage. Delivery runs it with FUSE and without (`.github/scripts/deliver-appimage.sh`).

## The .deb

`Fledge::Deb` lays the built folder out as a package's tree, writes `DEBIAN/control`, and runs `dpkg-deb --build --root-owner-group TREE FILE`, as Briefcase does (ADR 021). `--root-owner-group` (dpkg 1.19.0 and newer) makes every entry root's. A computer without `dpkg-deb` is told to install dpkg.

**The tree.**

- `/usr/lib/PACKAGE/`: the built folder, less its desktop entry and its `share` folder. Debian Policy 9.1.1 lets a subdirectory of `/usr/lib` hold "a mixture of architecture-independent and architecture-dependent files", which a runtime and an app are.
- `/usr/share/applications/IDENTIFIER.desktop`: the desktop entry, with `Exec` the program's full path, `/usr/lib/PACKAGE/NAME`, quoted as the specification asks.
- `/usr/share/icons/`: the folder's `share/icons`, where desktops look.
- With `license_file`, `/usr/share/doc/PACKAGE/copyright`, the file's text, 0644: Policy 12.5 asks every package to carry "a verbatim copy of its distribution license(s)", neither compressed nor a link. No machine-readable copyright format (DEP-5) is written; Fledge copies the developer's text as it is.
- With `linux: deb_changelog`, `/usr/share/doc/PACKAGE/changelog.gz`, made by the system's `gzip -n -9`, whose `-n` leaves out the file's name and time, as Debian's `dh_compress` does. Policy 12.7 names a package's one changelog `changelog.gz` when "there is no separate upstream maintainer", which is a Fledge app's case.

No program is linked into `/usr/bin`, since a windowed app starts from a menu and a name with spaces is no command. There are no maintainer scripts: the desktop and icon caches are updated by the triggers that `desktop-file-utils` and the icon theme tools register, and the app writes nothing under `/usr/lib` when it runs, so removing the package removes everything it installed.

**The control file**, Debian Policy 5.3's fields:

| Field | Value |
|---|---|
| `Package` | the identifier in lower case (`com.example.CoolApp` is `com.example.coolapp`), which Policy 5.6.7's name rules allow and which cannot collide with a distribution's package |
| `Version` | the version as Policy 5.6.12 spells it: RubyGems' pre-release `1.2.3.pre.4` is `1.2.3~pre.4`, which sorts before `1.2.3` as RubyGems sorts them |
| `Architecture` | `amd64` or `arm64` |
| `Maintainer` | the publisher, or else the name, on one line; Policy 5.6.2's address is left out, and `dpkg-deb` accepts the field without one |
| `Installed-Size` | the regular files' bytes, in KiB, rounded up (Policy 5.6.20) |
| `Depends` | `libc6 (>= GLIBC)`, `Platform::GLIBC_MINIMUM`, then what dpkg-shlibdeps finds |
| `Section`, `Priority` | `misc`, `optional` |
| `Homepage` | the homepage, when there is one (Policy 5.6.23) |
| `Description` | the description, or else the name, as the synopsis; then `long_description`, each line after one space and an empty line as ` .` (Policy 5.6.13) |

**Depends.** The runtime carries its Ruby, OpenSSL, libyaml, libffi, zlib, and libcrypt, so with nothing else listed, `Depends` is glibc alone. A gem that opens a library with `dlopen`, as SDL opens X11, Wayland, OpenGL, and audio libraries, names none of them in its compiled files, so Fledge cannot know them; a desktop install has them. When `fledge.yml`'s `linux: system_libraries` lists sonames (ADR 030), the build reads the ELF files in the tree with objdump, picks those that need a listed library, and runs `dpkg-shlibdeps -O -xlibc6 -lDIR... -eFILE...` in its work folder, with an empty `debian/control` there, as Debian Policy 8.6.1's procedure does. Its `shlibs:Depends` follows `libc6`: for `examples/system_library`, built on Ubuntu 24.04, `libc6 (>= 2.39), libpng16-16t64 (>= 1.6.2)`. `-xlibc6` leaves out glibc's own entry, which the floor already names. dpkg-shlibdeps maps each soname to the package that provides it on the computer that builds, with the oldest version whose symbols the files use, so a `.deb` names that distribution's packages. It is in dpkg-dev, which build-essential brings; a computer without it is told to install dpkg-dev. With nothing listed, dpkg-shlibdeps never runs.

## Files an app opens

`file_associations` (ADR 052; `Fledge::Config::FileAssociation`) is a list of entries, each with:

- `name`, required;
- `role`: `viewer`, the default, or `editor`;
- `extensions`, without the dot and of one part, since Windows associates only an extension's last part; `mime_types`; and `content_types`, macOS's uniform types;
- or `folders: true`, which an entry for files may not also say, since macOS reads `LSItemContentTypes` in place of extensions, so one entry for both would lose the files there.

An entry that names nothing to open is refused, and so is the key in a console app's `fledge.yml`. With `programs`, the windowed program declares them.

- **macOS:** one `CFBundleDocumentTypes` entry each, with `CFBundleTypeName`, `CFBundleTypeRole` (`Viewer` or `Editor`), `LSHandlerRank` `Alternate`, `CFBundleTypeExtensions` and `CFBundleTypeMIMETypes` as electron-builder writes them, and `LSItemContentTypes` (`public.folder` for folders, or the `content_types`). No tool in `/usr/bin` maps an extension to a uniform type without a file of that type, so extensions go in as extensions, and Launch Services matches them through the dynamic type it gives each. A drop or `open -a` arrives as an Apple event, which the app's GUI library receives.
- **Windows:** a dropped file or folder arrives in `ARGV` with nothing declared. The setup program writes, under `HKCU\Software\Classes`, for each extension, a ProgID with the first listing entry's name as its default value, `DefaultIcon` the program's first icon, and `shell\open\command` = `"PROGRAM" "%1"`, and lists the ProgID as a value of `.EXT\OpenWithProgids` with `WriteRegNone`, as electron-builder writes it. It never sets the extension's default. For folders, it writes the verb `Directory\shell\IDENTIFIER`, "Open with NAME", with the same command. Then it calls `SHChangeNotify(SHCNE_ASSOCCHANGED, SHCNF_FLUSH)`, as both prior installers do. A portable folder registers nothing.
- **Linux:** `MimeType=` lists the `mime_types`, and `inode/directory` for folders, as electron-builder's `LinuxTargetHelper.ts` lists its own, and `Exec` ends in `%F` when it lists any. `extensions` alone does nothing there. Fledge writes no shared-mime-info package to define a new type.

**The ProgID** (`Nsis::Script#prog_id`) is one per extension, and depends on nothing that can move: the identifier with every character but letters, digits, and periods removed, periods squeezed, leading digits and periods removed, cut to 28 characters with no trailing period (`App` when nothing is left), then a period and the first ten hexadecimal digits of the SHA-256 of the identifier, a newline, and the lowercased extension: `io.github.someone.myverylong.5b36e4ccbc`. Microsoft's ProgID key page asks for "no more than 39 characters", "no punctuation (including underscores and slashes) except one or more periods", and not starting with a digit, where an identifier may hold hyphens and 128 characters. The hash keeps two identifiers that sanitize alike apart, and extensions apart within an app. A ProgID named for an entry's place in the list would rename itself when the list is reordered and leave the old one on people's computers, since the uninstaller knows only the current list. An entry's `name` is deliberately not part of it: renaming an entry changes only the ProgID's friendly name, which the next install overwrites. An extension two entries list gets one ProgID, named for the first entry.

The uninstaller deletes each ProgID, its value in `OpenWithProgids`, the `OpenWithProgids` key and the extension's key when nothing else is left in them, and the folders' verb, then calls `SHChangeNotify` again. An extension dropped from `file_associations` in a later version stays registered until the person removes it.

## Building from a built app

`fledge build --from APP [OPTIONS] [PATH]` (ADR 032; `Fledge::BuiltApp`) builds the project at PATH as `fledge build` does, but takes the runtime and the gems from APP, the folder `fledge build` wrote (`NAME-PLATFORM/`, or on macOS the `.app` in it), instead of downloading a runtime and installing the lockfile's gems. Nothing is downloaded: a computer that can download a runtime can run `fledge build` itself, and the person `--from` is for may have no network.

**How APP is recognized.** The first line of every `fledge.cfg` a desktop build writes is a comment the launcher skips: `# Written by fledge build VERSION for PLATFORM: what this app's program runs (ADR 005).`, or `programs run (ADR 024)` with sections (`Assembly#launch_config`). `--from` reads VERSION and PLATFORM from it (`BuiltApp::HEADER`). A key would be the cleaner record, as `pyvenv.cfg` has `version`, but the launcher refuses a key it does not know, so a key would need a launcher of the same release. A phone project's `fledge.cfg` keeps a first line with no release, since no app is built from it. The program's name comes from `fledge.cfg`'s sections, or for one program from the bundle's name or the folder's `NAME-PLATFORM`.

**What the new app takes from APP.** Its runtime, its gems, and `notices/`, unchanged, and of its project the paths Bundler needs to set up those gems: the `Gemfile` (or `gems.rb`) and its lockfile, `.bundle/config`, `vendor/cache`, and each folder inside the project that the lockfile's `PATH` sections name, read with `Bundler::LockfileParser`. `fledge.cfg`'s `system_libraries` (ADR 030) stays, since the gems that load them do. The new project's `fledge.yml` gives everything else: the program, `name`, `identifier`, `version`, `icon`, `publisher`, `copyright`, `kind`, `installers`, `file_associations`, `linux: deb_changelog`, and `macos: build`.

**What goes of APP.** Its `fledge.cfg`, its programs, its `tools` folder, and its identity: on macOS its bundle's `Info.plist`, program, seal, and `NAME.icns` (only `Contents/Resources` is copied); on Linux each `IDENTIFIER.desktop` and `share/icons/hicolor/*/apps/IDENTIFIER.png`, with the folders they leave empty.

**The program.** On macOS and Linux, the program is a copy of APP's, which is the runtime's launcher renamed; on macOS it is first signed again ad hoc (`codesign --force --sign -`), so a console app made from a bundle carries no seal naming APP's identifier. On Windows, APP's program holds APP's icon, company, and copyright, which rcedit can replace but not remove, and its subsystem is APP's kind; so the Windows build takes `launcher.exe` or `launcherw.exe`, and rcedit and NSIS, from APP's `tools` folder when APP has them, or else from Fledge's runtime for the platform when the computer has it at hand (`Runtimes#at_hand`: in `FLEDGE_RUNTIME_DIR`, or in the cache when it matches its pin), unpacking only those. On every platform a runtime at hand also gives the tools folder, which an AppImage needs. The identity is then written as `fledge build` writes it.

**Refusals.** Status 2, a usage error: `--from` without APP, and `--from` with a phone. Status 1, a failed build:

- an APP that is not a folder, has no `fledge.cfg` or no program, was built by another Fledge release, or is for another platform than the computer's ("--from APP is an app for PLATFORM, and this computer builds for PLATFORM. Build from an app for this computer.");
- a PATH with a `Gemfile`, `gems.rb`, or gemspec of its own;
- a `fledge.yml` with `programs`, `linux: system_libraries`, `ios`, or `android`, which change the runtime or the gems;
- a PATH that holds a file at one of the paths APP's Bundler needs;
- an APP whose lockfile takes a gem from the project's own folder (`gemspec`, or `path: "."`), since replacing the project would take the gem away;
- on Windows, no launchers in APP's tools and no runtime at hand, naming where to put one.

`--from` takes a folder only; unpacking a zip a person dropped is the caller's, since Linux has no zip reader every computer has.

**build_tools.** `build_tools: true` (default false) puts in the app, in a `tools` folder beside its runtime, what `--from` would take from a runtime at hand (`Assembly::BuildTools`): on Windows, the runtime's `launcher.exe` and `launcherw.exe` and its tools folder but `llvm-readobj.exe`, which `--from` has no use for, since it compiles nothing; on Linux, the tools folder, AppImage's runtime; on macOS nothing, since the app's program is the launcher and `/usr/bin` has the rest. The tools go in after the app's code is signed and before the installers and the archive, so `--sign` signs none of them: a launcher signed by the developer and then changed by rcedit in a later `--from` would carry a broken signature. They are copied as the runtime holds them, so the installers hold them too. APP's `tools` never passes to the new app; the new app carries its own only when its own `fledge.yml` sets `build_tools`. Fledge itself is a gem the app's Gemfile ships, outside the `development` and `test` groups, which the app runs as the `fledge` RubyGems writes into `Gem.bindir`; since the app's Fledge built the app, the two agree on `fledge.cfg`. `build_tools` cannot carry `mksquashfs`, which is GPL-2.0 and so no part of a runtime, nor `dpkg-deb`, which every Debian and Ubuntu has. Every tool it carries is in the runtime's license audit already, and `runtime/licenses.yml` says each ships in an app when `build_tools` is set.

**What a framework does around it.** The person's `RUBYOPT` and `RUBYLIB` reach a child Ruby as under `bundle exec`, so a framework runs `fledge` with `RUBYOPT=-rbundler/setup` and no `RUBYLIB`, or runs `Fledge::CLI` in its own process. What a framework may rely on is in `doc/contributors/design/public-interface.md`.
