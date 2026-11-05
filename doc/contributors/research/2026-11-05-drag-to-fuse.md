<!--
SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>

SPDX-License-Identifier: CC-BY-SA-4.0
-->

> Research by an agent session on 2026-11-05, on `trunk` at e84189e, for ADR 032. Requested: written by an agent and not reviewed line by line. Written for agents: accuracy over prose. Every web page was fetched on 2026-11-05. love2d.org answers a fetch with Cloudflare's 403, so the LÖVE wiki was read through the Wayback Machine snapshots named below. GitHub sources were read at the commit named, with "main" resolved through the GitHub API on 2026-11-05: love2d/love `main` = def2451, libsdl-org/SDL `main` = 87f0e4a, pyinstaller `develop` = 14adba9, electron-builder `master` = cdd9f7e, dgiagio/warp `master` = b82c90b, tamatebako/tebako `main` = c5f12a3, AppImage/type2-runtime `main` = fedfad5. A claim marked **(inference)** follows from the cited sources but no source states it. A claim marked **(second-hand)** comes from a search summary of a page not fetched. The maintainer's words this serves are the last entry of `doc/contributors/decisions.md` (on the maintainer's side; not on `trunk` at e84189e).

# Drag to fuse: how LÖVE does it, what single-file packagers cost, and what Fledge has

The maintainer's correction of 2026-11-05 binds what follows: Fledge depends on no framework and knows none of their concepts. Words such as "fuse", "player", and "game" below describe LÖVE and one framework that consumes Fledge (section 8); Fledge's own design, ADR 032, uses none of them.

## 1. What LÖVE actually does

LÖVE's drag is a drag to **run**, and its fuse is a copy. They are two steps.

**Drag to run.** The wiki's Getting Started: "the easiest way to run the game is to drag the folder onto either love.exe or a shortcut to love.exe. Remember to drag the folder containing main.lua", and on macOS "a folder or .love file can be dropped onto the love application bundle" (https://web.archive.org/web/20251003210135/https://love2d.org/wiki/Getting_Started).

**Fuse.** The wiki's Game Distribution (https://web.archive.org/web/20251003211525/https://love2d.org/wiki/Game_Distribution):

- A `.love` is a zip of the game folder, `main.lua` at its root, renamed.
- Windows: `copy /b love.exe+SuperGame.love SuperGame.exe` in a command prompt. The page also gives a `.bat` of one line, `copy /b love.exe+%1 "%~n1.exe"`, "then you can simply drag your SuperGame.love file onto the .bat file", a PowerShell form, and `cat love.exe SuperGame.love > SuperGame.exe` from Linux or macOS. The fused exe needs LÖVE's DLLs beside it (SDL2, OpenAL32, love, lua51, mpg123, msvcp120, msvcr120) and `license.txt`. Changing its icon needs Resource Hacker. **So LÖVE's Windows game is a folder, shipped zipped, not a single file.**
- macOS: rename `love.app`, copy the `.love` into `Contents/Resources/`, edit `Info.plist`'s `CFBundleIdentifier` and `CFBundleName`, "and remove the section UTExportedTypeDeclarations which ensures that macOS does not associate all .love files with your app", then zip with `-y` to keep links. The page says nothing of re-signing.
- Linux: "there is not yet a simple way"; from 11.4, extract the official AppImage, `cat` the `.love` onto its `bin/love`, edit `love.desktop` and `AppRun`, and rebuild with `appimagetool`.

So a newcomer on Windows fuses with a command line or a one-line batch file, and on macOS with Finder and a text editor. Community tools wrap both (love-release, makelove; not fetched).

**Detection, in LÖVE's source.**

- `src/modules/love/boot.lua` (11.5): L49-53 take the executable's path; L60 `local can_has_game = pcall(love.filesystem.setSource, exepath)`: a game is fused when the executable itself mounts as an archive; L72-74 `is_fused_game = can_has_game or love.arg.options.fused.set`. Same at `main` L67, L77, L92-94; the vendored copy in Lota (`~/Developer/rove_2d/vendor/love/src/modules/love/boot.lua`, LÖVE 12.0) L64-96.
- `src/modules/filesystem/physfs/Filesystem.cpp` `setSource` (`main` L259-350, read in Lota's vendored copy): L323 `PHYSFS_mount` of the executable's path as a zip, which works because a zip's central directory is at its end; L325-343, "It's possible there is additional data at the end of the fused executable, e.g. for signed windows executables (the signature)", falls back to `StripSuffixIo`. **A signed fused exe is fused first, then signed, and LÖVE strips the signature to find the zip.**
- macOS: `src/common/macos.mm` (Lota's vendored copy) L41-55 `getLoveInResources`, `[[NSBundle mainBundle] pathForResource:nil ofType:@"love"]`; `src/love.cpp` L88-104 puts that path in argv with `--fused`. A drop on the bundle's icon: `macos.mm` L57-84 `checkDropEvents` starts SDL's video, pumps events, and takes one `SDL_EVENT_DROP_FILE`; `love.cpp` L105-119 makes it argv[1], only `if (!isatty(STDIN_FILENO))`.
- `platform/xcode/macosx/love-macosx.plist` (Lota's vendored copy) L7-53 `CFBundleDocumentTypes`: `.love` (Viewer, `LSHandlerRank` Owner), "Folder" (`CFBundleTypeOSTypes` `fold`, Viewer, `LSHandlerRank` None), and "Document" (`****`, Editor); L78-106 `UTExportedTypeDeclarations` for `org.love2d.love-game`.
- Saves: `Filesystem.cpp` (Lota's vendored copy) L608-612: fused, `APPDATA/IDENTITY`; not fused, `APPDATA/LOVE/IDENTITY`. The base is `%APPDATA%`, `~/Library/Application Support`, or `$XDG_DATA_HOME` (11.5 `getAppdataDirectory` L546-573; `Filesystem.h` L36-51 `LOVE_APPDATA_FOLDER`).

## 2. Single-file packagers

| Tool | How the one file runs | Where it unpacks | Cost the project itself states |
| --- | --- | --- | --- |
| PyInstaller `--onefile` | Bootloader unpacks into `_MEIxxxxxx` on every launch, deletes it on exit (`doc/operating-mode.rst` @14adba9, L187-210) | System temp, or `--runtime-tmpdir` | "a little slower to start up" (L174-175); every copy unpacks its own (L221-224); a crash leaves the folder (L227-231); not as administrator (L240-249); antivirus: "Antiviral false positives are a common theme ... an indefinite cycle" (`.github/ISSUE_TEMPLATE/antivirus.md` L10-14). On macOS: "Onefile mode in combination with macOS .app bundles ... don't make sense (a .app bundle can not be a single file) and clashes with macOS's security ... This will become an error in v7.0" (`PyInstaller/building/osx.py` L33-37); 6.13.0's changelog: "heavily penalised by macOS's security scanning" (`doc/CHANGES.rst` L668-670). |
| electron-builder `portable` | NSIS: `RMDir /r`, extract, `ExecWait`, `RMDir /r` on every launch (`templates/nsis/portable.nsi` @cdd9f7e L33-90) | `$TEMP\<build id>` by default (`NsisTarget.ts` L441-442) | `splashImage` "to show while the portable executable is extracting" (`nsisOptions.ts` L259-262); "can take more than a few seconds" (issue 3972, **second-hand**) |
| warp-packer | Extracts once, reuses while the cache is newer than the exe (`warp-runner/src/main.rs` @b82c90b L65-77, mtime only, no hash) | `%LOCALAPPDATA%\warp\packages\EXE-NAME`, `~/.local/share/warp/packages`, keyed by file name only (L32-38; README L543-546) | First run slower (README L541). Last release 2018, last commit 2019: unmaintained. |
| Tebako v2 | Rust bootstrap mounts read-only images in-process through an interposition shim; native tools "run from its image ... no extraction" (README @c5f12a3 L68-69, L95-123, L152-156) | None, or `~/.tebako` for the "lean" runtime | A patched Ruby (`tamatebako/ruby`, L160-162); BSD-2-Clause, but "the DwarFS backend links dwarfs-t (GPL-3.0)" (L223-224). v1 (patched Ruby on DwarFS) is end of life (L29-35). |
| AppImage | ELF runtime mounts the appended SquashFS with FUSE at `$TMP/.mount_*` (`src/runtime/runtime.c` @fedfad5 L279ff, L978-1018) | A FUSE mount; `--appimage-extract-and-run` extracts to temp (L672-674) | Fledge already ships it (ADR 009, ADR 010). |
| Briefcase | No single file: ".app", "Windows app", AppImage, Flatpak, system package (https://briefcase.beeware.org/en/stable/reference/platforms/index.html). Its maintainer: "Briefcase specifically *doesn't* use the 'Single file executable' model, because of problems I've historically seen with that approach" (https://github.com/beeware/briefcase/issues/556#issuecomment-761892333, 2021-01-17). | | |
| Tauri | No single file: App Bundle and DMG, Debian, Snap, AppImage, Flatpak, RPM, Windows installer, Microsoft Store (https://v2.tauri.app/distribute/). | | |

## 3. What an operating system gives a program for a drop

**Windows.** "By default, when the drop target is an executable file and no value is provided for DropTarget, the shell converts the list of dropped files into a command-line parameter and passes it to ShellExecuteEx in the lpParameters parameter" (https://learn.microsoft.com/en-us/uwp/schemas/appxpackage/uapmanifestschema/element-uap5-executionalias). LÖVE's wiki says a folder drops the same way (section 1). A command line holds at most 32,767 characters (https://learn.microsoft.com/en-us/windows/win32/api/processthreadsapi/nf-processthreadsapi-createprocessw). Fledge's Windows launcher passes its wide-character arguments to Ruby's `ARGV` (`runtime/launcher/windows.c`), so a dropped path arrives as `ARGV[0]` with nothing new.

**macOS.** A drop on an app's icon in Finder or the Dock opens the app and sends it an Open Documents Apple event; the paths are not in argv. AppKit hands them to `application(_:open:)`, and "You configure document types ... by adding the CFBundleDocumentTypes key" (https://developer.apple.com/documentation/appkit/nsapplicationdelegate/application(_:open:)). Finder accepts a drop only on an app whose `CFBundleDocumentTypes` covers the item **(inference from LÖVE's plist declaring `fold` and `****`)**. SDL3 turns `application:openFile:` into `SDL_EVENT_DROP_FILE` (`src/video/cocoa/SDL_cocoaevents.m` @87f0e4a L312-315), only when no other delegate is installed (L562-574). Fledge writes `Info.plist` with no `CFBundleDocumentTypes` (`lib/fledge/mac_bundle.rb` L153-172), and its launcher runs no event loop: a Ruby program receives the drop only through a GUI library that does, as Lota does through SDL3.

**Linux.** A drop on a desktop entry passes paths through `Exec`'s `%f`/`%F`; dropping onto an executable file is not a general file manager feature **(inference; not fetched)**. A drop on the player's own window reaches SDL3 as the same event on X11 and Wayland.

## 4. Signing and quarantine

- "If you modify a signed bundle, you must re-sign it afterwards"; "Appending data to a Mach-O executable is expressly prohibited" (TN2206, https://developer.apple.com/library/archive/technotes/tn2206/_index.html). Slot -3 hashes `CodeResources`, so a changed resource breaks the seal (TN3126). LÖVE's macOS recipe therefore leaves an invalid signature.
- On Apple silicon "any executable must be signed ... a simple ad-hoc signature is sufficient ... binaries signed this way cannot pass through Gatekeeper" (https://developer.apple.com/documentation/macos-release-notes/macos-big-sur-11_0_1-universal-apps-release-notes).
- `/usr/bin/codesign` is a real binary in the base system, not an `xcselect` shim (checked on macOS 27.0.1); `plutil` and `ditto` are there too (ADR 010, section 3).
- `LSFileQuarantineEnabled`, "whether the files this app creates are quarantined by default", is off by default (https://developer.apple.com/documentation/bundleresources/information-property-list/lsfilequarantineenabled): an unsandboxed player's output carries no quarantine **(inference)**; the spike checks `xattr`.
- Windows: Mark-of-the-Web is written by the downloader; Explorer's zip extraction propagates it (Eric Lawrence, https://textslashplain.com/2016/04/04/downloads-and-the-mark-of-the-web/). A file a local program writes from scratch carries none **(inference)**.
- Authenticode: the image digest leaves out the checksum and the certificate table entry (https://learn.microsoft.com/en-us/windows/win32/debug/pe-format); whether bytes after the certificate table fail verification was not found in Microsoft's text. LÖVE fuses before it signs (section 1).

## 5. What Fledge has today that a fuse step can use

- A built app is the launcher, `fledge.cfg`, `app/` (the project as copied), the runtime's tree, and `notices/` (ADR 029, section 2). The launcher reads `fledge.cfg` beside itself (`runtime/launcher/config.c` L6-53): `entry`, `gemfile`, `identifier`, `system_libraries`. `fledge.cfg` is not frozen and no one but Fledge may read or write it (ADR 029, section 3).
- macOS identity is `Info.plist`, written with `plutil`, and an ad hoc seal with `codesign`, both in `/usr/bin` (`lib/fledge/mac_bundle.rb` L136-236; ADR 010, section 3). Windows identity is rcedit, from the Windows runtime's `tools/`, "which no app holds" (`lib/fledge/windows_resources.rb`; ADR 010, section 5). Archives are the system's own tar, `System32\tar.exe` on Windows (ADR 010, section 2).
- `fledge build` needs: Ruby 4.0 to run Fledge, a runtime (download or `FLEDGE_RUNTIME_DIR`), Bundler and the network for the lockfile's gems, and a compiler for a gem with no build for the platform (ADR 005, ADR 006, ADR 019 section 2). None of that is on a newcomer's computer.
- One framework's earlier plan, Lota's `lota fuse` (Lota ADR 002 section 5, `~/Developer/rove_2d/doc/contributors/adr/002.md` L51-62), writes a Gemfile that names Fledge by git tag, so it "needs the network and Git", and runs `fledge build`. It is a developer's command line.

## 6. The spike

`experiment/drag-to-fuse` (from ece8356, whose CI run 41966470848 built the runtimes it uses). Its files keep the names the spike was written with (`player`, `game`, "fuse"); here they are the *template app* and the *project*. A template app built once with `fledge build` (`.github/drag_to_fuse/player`), handed a project folder or zip (`.github/drag_to_fuse/game`: `conf.rb`, `main.rb`, `lib/`, `assets/`) as its first argument, copies itself with the project in `app/game`, renames its program, rewrites its identity (`Info.plist` with `plutil`, `fledge.cfg`'s identifier) and seals it again with `codesign` on macOS, using only Ruby's standard library and the system's tools, on a fresh runner with Ruby off `PATH` and `RUBYOPT`, `RUBYLIB`, and `GEM_HOME` set. It is the mechanism of ADR 032's `fledge build --from` with the project placed in a subfolder; nothing in it depends on what the project is. The results are in section 7.

## 7. Results

Run 41978615197 on `experiment/drag-to-fuse` at b61f811, every job green: template app builds (jobs 127083236998, 127083237392), fuse on macOS-15 (job 127084350424) and windows-latest (job 127084350234), each fuse job on a fresh runner that never ran `fledge build`.

| Check | arm64-darwin | x64-mingw-ucrt |
| --- | --- | --- |
| Copy with a project folder handed as `ARGV[0]`, no Ruby on `PATH`, hostile `RUBYOPT` | 1.41 s inside the template app | 1.81 s inside the template app (2.07 s with process start) |
| The same from a zip (`ditto -x -k`; `System32\tar.exe -xf`) | 2.29 s | 1.95 s |
| The copy runs, reads `assets/` through `__dir__`, `require_relative` works, `RUBYOPT` restored as under `ruby` | yes | yes |
| `__FILE__` of the project's program | `.../Spike Game.app/Contents/Resources/app/game/main.rb` | `.../Spike Game-x64-mingw-ucrt/app/game/main.rb` |
| Identity of the copy | `codesign --verify --deep --strict`: "valid on disk", "satisfies its Designated Requirement"; `Identifier=org.lota.game.spike-game`, `Signature=adhoc`; `Info.plist` renamed | `fledge.cfg` identifier rewritten, but `VersionInfo` still says `FusePlayer` (FileDescription, ProductName, OriginalFilename): its resources need rcedit, which no app carries today |
| Quarantine on the output | `xattr -l` printed nothing | not checked |
| Size | template 63 MB, copy 63 MB (the project is a few KB) | copy's folder zipped: 19.5 MB; 2,906 files, 50.8 MB unpacked |
| Started through LaunchServices | `open -W Fused.app --args REPORT` ran it (with `open`'s "Unable to block on application" warning) | `Start-Process -Wait`, as Explorer starts it |
| A folder opened with the template app through LaunchServices (`open -a App.app FOLDER`, what a drop on the icon does) | The app started, and its `ARGV` was empty: the folder came as an Apple event its program did not receive | (Windows passes it as an argument, row 1) |
| Single file: the copy's folder zipped, appended to a program with `copy /b`, read back by `System32\tar.exe -xf single.exe` | | exit 0 in 1.13 s; the extracted app runs |

What the spike does not show: a drop by a person in Finder or Explorer (no runner can drag); whether Finder accepts a folder on an app without `CFBundleDocumentTypes`; a GUI library receiving the drop; an app holding a framework's compiled gems; `fledge build --from` itself, which does not exist; Gatekeeper and SmartScreen on a downloaded copy.

## 8. An example consumer: Lota

Lota, a port of LÖVE to Ruby, is one framework that would build drag-to-fuse on ADR 032. This section is Lota's mapping, for Lota's session; none of it is Fledge's design. Lota's session sent seven requirements on 2026-11-05.

| Lota's need | On ADR 032's primitives |
| --- | --- |
| 1. Drop a game folder (`conf.rb`, `main.rb`, assets, `lib/`) or its zip on one thing; get one thing out with no Ruby or compiler | Lota publishes a "player" per platform: an app built with `fledge build` in Lota's CI, its Gemfile shipping `lota` and Fledge, with `build_tools: true` and `file_associations` for folders and zips. Its SDL3 window and icon take the drop. Out comes `NAME.app` (and its archive or `.dmg`), a zipped folder or setup program on Windows (LÖVE's Windows game is also an exe beside its DLLs), an archive or AppImage on Linux. |
| 2. A prebuilt player; a fuse with no Bundler, gem install, or network; native gems not draggable | The player runs `fledge build --from PLAYER SCRATCH` through its `Gem.bindir` executable. A game with a Gemfile is refused by `--from`; pure-Ruby code the game vendors is the project's own files. |
| 3. Read the game from a packed form? | No: Lota unpacks a dropped zip into a scratch project (`ditto` on macOS, `tar.exe` on Windows), and `--from` copies it as plain files, so `require_relative`, `__FILE__`, and backtraces are real. |
| 4. Settings from `conf.rb` only | Lota reads `conf.rb` and writes the scratch project's `fledge.yml`: `name` from `t.window.title`, an `identifier` derived from `t.identity` under a prefix Lota chooses (unique per game, since macOS, the AppUserModelID, and the uninstall key know an app by it; ADR 029, section 2), `kind: windowed`, and the icon. `t.version` is a LÖVE version, not the app's (Lota ADR 002, section 5). Lota writes the entry program that boots the game in fused mode. |
| 5. Cross-fusing | Allowed by the maintainer when it adds no cross-compiling and little code (decisions, 2026-11-05): the copy-only form, with what it leaves undone named (ADR 032, section 6). |
| 6. Notices and gem record | `--from` keeps `notices/` and `Gemfile.lock` unchanged. Lota adds its own credits (FreeType, OpenAL Soft) as Lota ADR 002 says. |
| 7. Saves where LÖVE's fused game saves | Lota's run-time code: `APPDATA/IDENTITY` fused, `APPDATA/LOVE/IDENTITY` not (section 1). Fledge changes nothing about where an app writes. |
