<!--
SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>

SPDX-License-Identifier: CC-BY-SA-4.0
-->

> Research by an agent session on 2026-11-05, on `trunk` at dd11739 (release 0.5.1). Requested: written by an agent and not reviewed line by line. Written for agents: accuracy over prose. A wrapper's session asked what Fledge could add so that a framework built on it can describe its apps (descriptions, a category, a homepage, a license), install a prerequisite on Windows, and ship an icon set it already has. Fledge depends on no framework and knows no framework's words (Clean Architecture's Dependency Rule, per the maintainer's correction of 2026-11-05): everything below is a Fledge capability, named by Fledge's own concepts. Other tools appear only as prior art, in the "Prior art" paragraph of each section. Nothing here is decided; every proposal is for the maintainer, whose scope it is (AGENTS.md, Questions: "product scope").
>
> Sources. Fledge: the files named, at dd11739. Prior art read from source: Tauri `9f0306fbc` (`refactor: rewrite some &String to &str (#14857)`), read in a local checkout, not fetched from the network (the paths are `crates/...` in `tauri-apps/tauri`); electron-builder `cdd9f7e` (`master` resolved with the GitHub API on 2026-11-05). Web pages were fetched on 2026-11-05: Microsoft Learn, "Distribute your app and the WebView2 Runtime" (`learn.microsoft.com/en-us/microsoft-edge/webview2/concepts/distribution`, `updated_at` 2026-10-02) and "Evergreen vs. fixed version of the WebView2 Runtime" (same site, `.../concepts/evergreen-vs-fixed-version`, `ms.date` 2025-10-10); freedesktop.org Icon Theme Specification 0.13 (`specifications.freedesktop.org/icon-theme/latest/`); Desktop Entry Specification (`.../desktop-entry/latest/recognized-keys.html`); Debian Policy `ch-controlfields.html`; Briefcase `briefcase.beeware.org/en/stable/reference/configuration.html`; Inno Setup `jrsoftware.org/ishelp/topic_runsection.htm`; rcedit v2.0.0 README; NSIS wiki "NSISdl plug-in". A claim marked **(unverified)** is from memory or inference, or a fetched page did not state it.

# What an app can say about itself, what a Windows installer can install first, and which icons a build accepts

Three capabilities, each independent. Each section gives: today, where a system takes it, what Fledge would add (neutral names), effort, ADR 029 section 4 class, and the smallest request, worded as a plan story. Effort: S is under a day in one or two files with tests; M is a few files and a Delivery check; L is a new tool or a new installer path.

## 0. Today, from the code

- `fledge.yml` keys (`lib/fledge/config.schema.json`, `lib/fledge/config.rb:82`): `name`, `kind`, `identifier`, `version`, `icon`, `publisher`, `copyright`, `installers`, `programs`, `ios`, `android`, `linux` (`system_libraries` only). Unknown keys fail the build. `Fledge::Identity` (`lib/fledge/identity.rb:48`) carries `name kind identifier version publisher copyright icon`; every writer below reads it.
- macOS `Info.plist` (`lib/fledge/mac_bundle.rb:154-171`): `CFBundleDevelopmentRegion`, `CFBundleDisplayName`, `CFBundleExecutable`, `CFBundleIdentifier`, `CFBundleInfoDictionaryVersion`, `CFBundleName`, `CFBundlePackageType`, `CFBundleShortVersionString`, `CFBundleVersion`, `LSMinimumSystemVersion`, `NSHighResolutionCapable`, `CFBundleIconFile`, and `NSHumanReadableCopyright` when `copyright` is set. No `LSApplicationCategoryType`.
- Linux desktop entry (`lib/fledge/desktop_entry.rb:92-102`): `Type`, `Version=1.5`, `Name`, `Exec`, `Icon`, `Terminal=false`. No `Comment`, `GenericName`, `Categories`.
- `.deb` control (`lib/fledge/deb.rb:154-166`): `Package`, `Version`, `Architecture`, `Maintainer` (publisher, else name), `Installed-Size`, `Depends`, `Section: misc`, `Priority: optional`, `Description: NAME` (synopsis only; ADR 021 says no description key was added "for this"). No `Homepage`, no extended description, no `/usr/share/doc` files.
- Windows program (`lib/fledge/windows_resources.rb:119-127` (`strings`), rcedit): `CompanyName`, `FileDescription` (= name), `InternalName`, `LegalCopyright`, `OriginalFilename`, `ProductName`, file and product version, icon.
- Windows installer (`lib/fledge/nsis/script.rb`): `RequestExecutionLevel user`, `InstallDir $LOCALAPPDATA\Programs\NAME`, version-information keys (`:124-131`), `BrandingText` = copyright or name, uninstall key values `DisplayName DisplayVersion Publisher DisplayIcon InstallLocation UninstallString QuietUninstallString NoModify NoRepair EstimatedSize` (`:185-202`). No `URLInfoAbout`, `HelpLink`, license page, prerequisites.
- Icons (`lib/fledge/icon.rb`): `icon: icons/app` is a path without an extension. macOS needs `app.icns`, Windows `app.ico`, Linux all of `app-16.png`, `-32`, `-64`, `-128`, `-256`, `-512` (`Icon::LINUX`, `:61`), because `DesktopEntry#entries` calls `icon.png(size)` for each (`desktop_entry.rb:72`) and `Icon#png` raises `Fledge::Error` when the file does not exist (`icon.rb:122-128`). `AppImage` also needs the 256 (`app_image.rb:56`, `ICON_SIZE`, used at `:106`). Fledge reads no image file (ADR 010, section 4): it checks no sizes, so a file's size is its name's claim.
- Windows installer privileges: per user, no administrator (`RequestExecutionLevel user`); ADR 009, section 3 freezes `%LOCALAPPDATA%\Programs\NAME`, the shortcut's AppUserModelID and the uninstall key under `HKCU` (ADR 029 section 2, "Where an installer puts the app").

ADR 029 section 4 governs every addition: "A new option, key, value, `kind`, command, or environment variable is compatible, since today's parser and `fledge.yml` refuse every one they do not know", and "A new icon size for a target is optional: a build that passed keeps passing." Section 2 freezes what exists (keys, values, defaults, the refusal of unknown keys), so a *new* key never breaks a project. A new default for an existing output is the only trap: a build that passed yesterday must produce the same installer unless the developer opted in.

## 1. App metadata: description, long description, homepage, license, category

### 1.1 Neutral keys

Names follow the prior art's common vocabulary and the gemspec Fledge already reads for `version` and `publisher` (`lib/fledge/identity.rb`, `Identity.from`):

| fledge.yml key | Meaning | Default (as `publisher` defaults to the gemspec's authors) |
|---|---|---|
| `description` | One line saying what the app does | gemspec `summary` (unverified that `Identity.from` can read it: it already reads `authors` and `version`) |
| `long_description` | Paragraphs; not a repeat of `description` | gemspec `description` |
| `homepage` | A URL | gemspec `homepage` |
| `license` | An SPDX license expression naming the app's license | gemspec `licenses` joined |
| `license_file` | Path in the project to the license text | none |
| `category` | One value from a short list (see 1.3) | none |

Prior art for the names. Briefcase: `description` ("A one-line summary of what the application does", required), `long_description` ("must not repeat `description`"), `url`, `license` (a PEP 639 expression), `license_files` (plural), `author`. electron-builder: `synopsis` ("The short description" with a link to Debian Policy), `description`, `category` per system (`mac.category`, `linux.category`), `license`, `homepage` from package.json (`packages/app-builder-lib/src/options/linuxOptions.ts:78-95`; macOptions: `category`, "as shown in the Finder via View -> Arrange by Application Category"). Tauri: a one-line and a long description, `homepage`, `license`, `licenseFile`, `category` (`crates/tauri-utils/src/config.rs:1287-1400`). Fledge's `copyright` and `publisher` already exist.

Whether Fledge adds six keys or fewer is the maintainer's scope. Priority by what a person sees: `description` (a software center, Task Manager, a desktop menu tooltip), `category` (menus and Finder), `homepage` (a link in Settings > Apps and in a software center), then the rest.

### 1.2 Where each key lands, per system, and what a system does with it

| Key | macOS | Linux desktop entry | `.deb` control | Windows program (rcedit) | Windows installer (NSIS) |
|---|---|---|---|---|---|
| `description` | no `Info.plist` key shows it (**unverified**: Apple's page for `LSApplicationCategoryType` came back empty; none of the keys Tauri writes is a description) | `Comment=` ("A tooltip for the entry. It should not repeat the Name or GenericName values", Desktop Entry spec) | `Description:` first line, the synopsis (Policy 5.6.13 "consisting of two parts, the synopsis or the short description, and the long description") | `--set-version-string Comments` (rcedit README: any property, `Comments` is its example). Keep `FileDescription` = name: Task Manager shows it | none required; the setup program's own `FileDescription` is "NAME Setup" already (`script.rb:126`) |
| `long_description` | none | none (the entry has no long text; AppStream is a separate file, out of scope) | `Description:` continuation lines, each prefixed with one space, a blank line as ` .` (Policy 5.6.13: "These are rendered as blank lines") | none | none |
| `homepage` | none | none | `Homepage:` (Policy 5.6.23, "a simple URL without any surrounding characters such as `<>`") | none | uninstall key `URLInfoAbout`, `HelpLink`, `URLUpdateInfo` under the existing key (`script.rb:185`) |
| `license_file` | disk image license agreement (hdiutil's license resource; **L**, see 1.4) | none | `/usr/share/doc/PACKAGE/copyright` (Policy 12.5, **unverified**: not fetched) | none | a license page, `MUI_PAGE_LICENSE`; the file must be UTF-8 with a BOM for a Unicode installer (prior art below) |
| `license` (id) | none | none | in the `copyright` file only; the control file has no license field | none | none |
| `category` | `LSApplicationCategoryType` = `public.app-category.NAME` | `Categories=Main;Additional;` | `Section:` (a package area, Policy 5.6.5; **not** the same vocabulary) | none | none |
| `copyright` (exists) | `NSHumanReadableCopyright` (done) | none | `/usr/share/doc/PACKAGE/copyright` | `LegalCopyright` (done) | `VIAddVersionKey LegalCopyright` (done) |

Observations. (a) `license` as an id has almost no placement; only a `.deb`'s copyright file and an RPM's License field take it, and Fledge has no RPM. It is useful to Fledge only if notices or the SBOM carry it. (b) `license_file` has real placements on three installers. (c) `Section` and `Categories` and the macOS category are three vocabularies; no source gives a mapping, prior art makes its own (below).

Prior art, placement:

- Tauri writes `LSApplicationCategoryType` at `crates/tauri-bundler/src/bundle/macos/app.rs:256-261` and `NSHumanReadableCopyright` at `:406-408`; the desktop file from `linux/freedesktop/main.desktop` and `mod.rs:98-186` (`Categories={{categories}}`, `Comment` when the short description is not empty, `StartupWMClass`, `MimeType`); `debian.rs:162-262` writes `Section` (only from its `deb.section` key), `Homepage` (`:200-202`), and `Description` (`:244-262`, "(none)" when empty); the NSIS script writes `URLInfoAbout`, `URLUpdateInfo`, `HelpLink` from the homepage (`windows/nsis/installer.nsi:692-694`) and a license page (`:151`) from the license file with a BOM added (`nsis/mod.rs:321-326`); the disk image takes the license file as an agreement (`macos/dmg/mod.rs:161-169`); `license` (the id) is used only by the RPM (`linux/rpm.rs:61`) and the homepage by the RPM too (`:87-88`).
- Briefcase writes `Homepage`, `Description`, `Section`, `Priority` into the `.deb` control (cited in ADR 021, Briefcase `_package_deb`, commit c760cf5b, lines 1367 to 1376).
- electron-builder splits the category by system and says nothing about mapping (linuxOptions: "The application category" with a link to the Desktop Menu Specification's main category registry; macOptions: a link to Apple's list).

### 1.3 The category vocabulary: the one design choice

Three honest options:

1. **Per-system raw values**, the smallest: `linux: categories: [Utility]` (desktop entry; a list, Desktop Entry spec "Categories ... using values from the Desktop Menu Specification"), `linux: section: utils` (a `.deb`'s), `macos: category: public.app-category.productivity`. Fledge validates nothing (or only that macOS's value starts with `public.app-category.`) and writes the strings. Three keys, one place each, no table. The wrapper, which already has its own list, maps it to each system (Tauri's own list maps to both systems' values at `crates/tauri-bundler/src/bundle/category.rs:149-196` and `:196-240`). This matches how `linux: system_libraries` is shaped.
2. **One neutral `category`** from a short list with Fledge's own mapping table to the three systems (about 40 lines of data; electron-builder and Briefcase do not do this).
3. Both: the neutral key as the default, the per-system keys as an override.

Recommended: 1 now (S, no invented vocabulary, and the wrapper owns the mapping it needs), with 2 as a later convenience if more than one wrapper wants it. 1.x compatibility: all compatible (new keys). Pre-1.0 nothing is frozen anyway.

### 1.4 Effort

| Capability | Files | Size | Tool |
|---|---|---|---|
| `description`, `long_description` into the `.deb` and the desktop entry | `config.rb`, `config.schema.json`, `identity.rb`, `desktop_entry.rb`, `deb.rb`, `sig/` mirrors, `exe/fledge` header if text, tests | S to M | none (text) |
| `description` as rcedit `Comments` | `windows_resources.rb` (`strings`) | S | rcedit, pinned (`runtime/sources.yml:176`) |
| `homepage` | `deb.rb`, `nsis/script.rb` registry, config, identity | S | none |
| `category` (per-system raw) | `mac_bundle.rb:info`, `desktop_entry.rb:text`, `deb.rb:control_file`, `config/linux.rb` and a new `config/macos.rb` (or flat keys), schema | S | none |
| `license_file` into a NSIS page and a `.deb` copyright file | `nsis/script.rb` (`pages`, write the file with a BOM), `deb.rb` lay_out | M | none |
| `license_file` as a disk image agreement | `dmg.rb` | L (hdiutil `udifrez` / a `sla` resource, **unverified**) | hdiutil |
| `license` (id) | `config.rb`, SBOM/notices maybe | S, little value | none |

Each addition also needs README, README.rdoc, CHANGELOG (observable output), the schema test (`Config` and schema must agree), and extending the example app's Delivery (`.github/scripts/deliver-windowed.*`, `deliver-deb.sh`) to read the new fields back with the system's tool (`dpkg-deb -f`, `plutil`, `desktop-file-validate`, `(Get-Item).VersionInfo`), as ADR 008, section 6 does for the identity.

Constraint to keep: a project that sets none of the keys builds a byte-identical `Info.plist`, desktop entry, control file and NSIS script. That keeps the change compatible and keeps the ADR 021 text "Description is the app's name" true for projects without a description.

### 1.5 Smallest requests, as plan stories

- **A1. A description for the app.** "A windowed app may say what it does. `fledge.yml` takes `description` (one line) and `long_description`. A Linux desktop entry shows the first as its `Comment`; a `.deb` carries them as its `Description` (synopsis and extended lines, per Debian Policy 5.6.13); a Windows program carries the first as its `Comments` version string. Done when: the example app sets both, and Delivery reads each back with `desktop-file-validate`, `dpkg-deb -f`, and `(Get-Item).VersionInfo`; a project without them builds the files it builds today. Size S to M. Compatible (new keys)."
- **A2. A homepage for the app.** "`fledge.yml` takes `homepage`. A `.deb` states it as `Homepage`; Windows lists it as the app's information, help and update links in Settings. Done when: Delivery reads `Homepage` and the uninstall key's `URLInfoAbout`. Size S. Compatible."
- **A3. A category for the app.** "`fledge.yml` takes `macos: category`, `linux: categories` and `linux: section`, each the string its system takes; Fledge writes `LSApplicationCategoryType`, `Categories=`, and `Section:`. Done when: `desktop-file-validate` accepts a known and refuses an unknown category (it warns on values outside the registry), and `plutil` reads the key. Size S. Compatible."
- **A4. A license text with the app.** "`fledge.yml` takes `license_file`. The Windows setup program shows it on a page before the install, and a `.deb` installs it as `/usr/share/doc/PACKAGE/copyright`. Size M. Compatible. The disk image's agreement is a later story."

## 2. Windows prerequisites: something the installer installs before the app

A wrapper's apps may need a component the app cannot ship in its own folder and that Windows may lack (the case prior art shows: a web view runtime; others: a C++ redistributable, a driver). Fledge's setup program installs only the app. This section is the generic capability, then what the one known component means.

### 2.1 What prior art does

- **Tauri** (the closest installer: NSIS, per user by default). The installer template has one section, `Section WebView2` (`crates/tauri-bundler/src/bundle/windows/nsis/installer.nsi:522-607`), that runs before `Section Install` (`:609`). It (1) reads the component's version from the registry: `pv` under `...\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}` in `HKLM` (WOW6432Node on 64-bit Windows), then `HKCU` (`:523-531`, the same keys Microsoft documents); (2) if empty and not an update, by mode (`:538-568`): `downloadBootstrapper` downloads `https://go.microsoft.com/fwlink/p/?LinkId=2124703` into `$TEMP` with `NSISdl::download`, aborting the install on failure; `embedBootstrapper` stores that bootstrapper in the setup program with `File` (about 1.8 MB, per the config's doc comment, `crates/tauri-utils/src/config.rs:943-985`); `offlineInstaller` stores the Standalone Installer (about 127 MB, `fwlink` 2124701 for x64, 2099617 for x86, `windows/util.rs:13-18`); (3) runs `$6 ${WEBVIEW2INSTALLERARGS} /install` (`:574`) with `/silent` by default (`nsis/mod.rs:510-534`) and aborts the install on a nonzero exit (`:575-580`); (4) optionally, if installed but older than `minimumWebview2Version`, runs Microsoft's updater (`:584-606`). The embedded files are downloaded **at build time** into a cache (`util.rs:42-60`). `skip` writes none of it. `fixedRuntime` writes none of it either: the build copies the runtime folder in as a resource (`crates/tauri-build/src/lib.rs:544`, `crates/tauri-cli/src/interface/rust.rs:1436`) and the app points the web view at it by setting an environment variable before it starts the web view (`crates/tauri/src/app.rs:2167-2185`). No hash is checked anywhere in this path; the offline file's name is resolved from a redirect.
- **WiX** (the MSI route): the same modes in the MSI template (`windows/msi/mod.rs:495-530`); not relevant to Fledge, which builds NSIS.
- **Inno Setup**: `[Run]` "lists programs to execute after installation succeeds", in order, waiting for each; flags `waituntilterminated`, `runasoriginaluser` (Inno Setup help, "[Run] section"). The page does not mention prerequisites: the idiom is a `[Files]` entry extracted to a temp folder plus a `[Run]` line with `Check:` for an "is it installed" test (**unverified**: that `Check:` and `[Files] ... deleteafterinstall` form was not fetched).
- **electron-builder**: no prerequisite concept; its NSIS options offer `include` (an `.nsh` file of your own) and `script` (the whole script) (`packages/app-builder-lib/src/targets/win/nsis/nsisOptions.ts`, properties `include`, `script`), so a developer writes the install step in NSIS themselves.
- **Briefcase**: its Windows backend is WiX (MSI); the configuration reference page fetched lists no prerequisite setting (**unverified** beyond that page).

So prior art has either a hard-coded component (Tauri) or an escape hatch (electron-builder's NSIS include). Fledge's rule "Never write what a pinnable tool already provides" is met by NSIS itself: `File`, `ExecWait`, `ReadRegStr`, `nsExec`.

### 2.2 The neutral capability: `windows: prerequisites`

A list under a new `windows:` object (parallel to `linux:`), each entry something the setup program installs when it is missing, before it copies the app:

```yaml
windows:
  prerequisites:
    - name: Example runtime              # shown in the install log
      installed_when:                    # a registry value, in HKLM (both views) or HKCU, that is non-empty
        key: SOFTWARE\Example\Clients\{GUID}
        value: pv
      installer:
        file: vendor/example-setup.exe   # in the project; or
        # url: https://example.com/setup.exe
        # sha256: 64 hex digits           # required with url
      arguments: [/silent, /install]
```

Why this shape.

- **Fledge knows no component.** It runs a program the developer names when a registry value is empty. It carries no Microsoft URL, GUID, or flag. The wrapper supplies them (the registry location and the bootstrapper's flags are public in Microsoft's page; see 2.3).
- **Pinned by SHA-256, as AGENTS.md demands of every external input.** `url` requires `sha256`; the build downloads on the build computer with the existing downloader (`lib/fledge/download.rb`, `checksum.rb`), verifies, and embeds the file with NSIS `File`. A `file` path is the developer's own input and is not checked. An install-time download would leave the input unpinned and needs a downloader inside NSIS (`NSISdl` is, per the NSIS wiki, "but not HTTPS", **unverified** for NSIS 3.13, though the prior art above uses it with an `https` address, `installer.nsi:541`); so embedding is the only form this note proposes. The size cost is the file's: 1.8 MB for a bootstrapper, 127 MB for a Standalone Installer (Tauri's doc comments).
- **Moving targets.** Microsoft's bootstrapper link is a redirect (`fwlink`) to a file Microsoft replaces; a SHA-256 pin of it goes stale. The wrapper must pin a specific file and re-pin on purpose, which is the cost of "pin every external input". A wrapper that prefers an unpinned download can say so in its own words; Fledge does not offer it (smallest scope).
- **Per user, no administrator.** `RequestExecutionLevel user` stays. A prerequisite whose installer needs administrator will prompt for elevation by itself (it is its own program); Microsoft documents that its installers install per user when not elevated and per machine when elevated, and that "a per-user install is automatically replaced by a per-machine install, if a per-machine Microsoft Edge Updater is in place" (Distribute your app, "Installing the Runtime as per-machine or per-user"). Whether that replacement shows a UAC prompt is **not stated**; check on a clean Windows 10 before relying on "no prompt".
- **Silent behavior.** The setup program run with `/S` must be silent end to end: `arguments` should be the prerequisite's own silent flags (the developer's choice), `ExecWait` its exit code, nonzero aborts the install with the entry's `name` in the message (`Abort`, as Tauri does at `:575-580`). The uninstaller removes nothing the prerequisite installed (Microsoft's runtime is shared by all apps, per the same page).
- **Where in the install.** A new section before `Section Install` (`nsis/script.rb:58`), skipped when the registry value is non-empty. The existing first step (the old version's uninstaller) comes after, so an update that finds the component present does nothing, as Tauri skips when updating (`$UpdateMode <> 1`).
- **Registry views.** `installed_when` should read `HKLM` in the 64-bit and 32-bit views, then `HKCU`, because Microsoft's check does both (Distribute your app, "Detect if a WebView2 Runtime is already installed"). NSIS reads the 64-bit view after `SetRegView 64` (**unverified** against NSIS 3.13's manual).

### 2.3 The web view runtime specifically, stated neutrally

Facts from Microsoft's page (fetched 2026-11-05):

- "The Evergreen WebView2 Runtime will be included as part of the Windows 11 operating system"; "The vast majority of Windows 10 devices have the WebView2 Runtime installed already"; a small number do not, and Microsoft recommends "Programmatically deploy the Evergreen Runtime with your app".
- Registry check: the `pv` value, at the two locations above; "at least one of these regkeys must be present and defined with a version greater than 0.0.0.0".
- Online: the Bootstrapper "is a tiny (approximately 2 MB) installer", run as `MicrosoftEdgeWebview2Setup.exe /silent /install`. Offline: the Standalone Installer, `MicrosoftEdgeWebView2RuntimeInstaller{X64/X86/ARM64}.exe /silent /install`. Both support per-user and per-machine installs by elevation.
- The Fixed Version "binaries are over 250 MB", and "on Windows 10 devices, starting with Fixed Version 120, developers of unpackaged Win32 applications using Fixed Version are required to run" two `icacls` commands granting `*S-1-15-2-2` and `*S-1-15-2-1` read and execute on the folder. "Currently, Fixed Version cannot be run from a network location or UNC path." "The Fixed Version runtime can't be installed by using an installer" (Evergreen vs. fixed).
- Redistribution terms: Microsoft Learn says "The WebView2 Runtime is a redistributable runtime" and describes "package the bootstrapper with your app installer" and "package the standalone installer with your app installer" as supported distribution (Evergreen vs. fixed, "Understanding the options at the Runtime download page"). **The license text itself was not found**: the download page (`developer.microsoft.com/en-us/microsoft-edge/webview2/`) states no terms, and NuGet's page for the SDK shows only a "License Info" link. Before Fledge or a wrapper ships a Microsoft installer inside an app, someone must read the license terms of the file being redistributed. Since the proposal above has the **wrapper** supply the file and its hash, and Fledge ships nothing of Microsoft's, Fledge's runtime license audit (`runtime/licenses.yml`, AGENTS.md "Licensing") is not touched; the Fledge-side question is only whether `fledge build` may embed a developer-chosen file, which it already does for the app's own files (an app's gems are the developer's responsibility, AGENTS.md).

Mapping the known modes onto the neutral list:

| Mode | With `prerequisites` |
|---|---|
| Install nothing (the app finds the runtime or fails to open a window) | `prerequisites` omitted. **Supported today.** |
| Bootstrapper embedded, run silent | one entry: `file` or `url`+`sha256` of the bootstrapper, `arguments: [/silent, /install]`, `installed_when` the `pv` key. Needs the capability. |
| Standalone installer embedded | the same with the big file (about 127 MB in the installer). Needs the capability. |
| Bootstrapper downloaded at install time | **not offered** (unpinned download; see above). A wrapper can fall back to embedding. |
| Fixed Version | no installer step; the folder ships in the project (`app/`), installed with it, and the app sets the environment variable before opening the view (Tauri's approach, `app.rs:2167-2185`) — all in the wrapper's Ruby. **Mostly supported today** by shipping the files, **except** the `icacls` grant Windows 10 needs for Fixed Version 120 and later, which is an install-time command with no home in `fledge.yml`. A prerequisite entry with no installer file but a command, or a general `windows: post_install` list, would cover it; this note does not propose it (a command that runs an arbitrary program at install time is a larger surface than "install this if missing"). Size cost 250 MB or more, per Microsoft. |
| Minimum version (update the runtime if older) | `installed_when` would have to compare versions, and the update path calls Microsoft's updater (`installer.nsi:584-606`). **Not proposed.** |

### 2.4 Effort

M to L. Files: `config.rb` + `config/windows.rb` (new, beside `config/linux.rb`), schema, `identity.rb` or a new value object, `nsis/script.rb` (a section of about 25 NSIS lines; escaping through the existing `nsis`/`quote` helpers), `nsis.rb` (copy or fetch the file to a work folder; NSIS `File` takes a path), `download.rb` (reuse, `url`+`sha256`), `sig/` mirrors, README, RDoc, CHANGELOG, ADR 033 (new): why a list and not an include file, which tools were considered (NSIS built-ins, WiX Burn chain, Inno `[Run]`). Delivery: `.github/scripts/deliver-windowed.ps1` needs a **fake** prerequisite (a tiny program that writes a registry value) to prove the section runs once, skips the second time, aborts on a nonzero exit, and runs silent under `/S`. No new pinned tool: NSIS is already in the runtime (`runtime/sources.yml:247`).

1.x class: compatible. New object and key; nothing else changes for a project that does not set it (the script has no new section when the list is empty).

Risks to state in the ADR: an embedded installer is a binary Fledge's SBOM does not describe (ADR 004); the Windows installer grows by the file's size; SmartScreen/antivirus scans of a setup program that bundles an unrelated installer (unverified, no source).

### 2.5 Smallest request, as a plan story

- **B1. A Windows setup program installs what the app needs first.** "`fledge.yml` takes `windows: prerequisites`, a list of components. Each names a file (in the project, or a `url` with its `sha256`), the arguments to run it with, and a registry value that is non-empty when it is already installed. The setup program, which needs no administrator, runs each missing one silently before it copies the app and stops with the component's name when one fails. Done when: on every Windows platform Fledge builds for, a Delivery run installs an app whose prerequisite is a fake installer that sets the registry value; a second install skips it; a failing one stops the install; `/S` shows no window. Size M to L. Compatible (new object)."

The wrapper's use of it: it names the bootstrapper and the value Microsoft documents. Whether to ship a Microsoft installer inside an app is the wrapper's call after it reads Microsoft's license terms.

## 3. Icons: accept the sizes a developer has

### 3.1 The rule today and its cost

`DesktopEntry#entries` needs all six PNGs (`desktop_entry.rb:72`); `AppImage` needs the 256 (`app_image.rb:106`); a missing one fails with "the icon icons/app-16.png does not exist ... Linux apps take one PNG of each size, -16, -32, -64, -128, -256, -512." (`icon.rb:79-81`, `:121-127`). The six sizes come from Briefcase's AppImage list (ADR 010, section 4). The reason to ask for all six is quality, not correctness.

### 3.2 What the standards need

- Icon Theme Specification 0.13 (fetched): the spec "does not require any particular set of sizes, and it never mentions 16 px". For application icons, section 7: "Minimally you should install a 48x48 icon in the hicolor theme." "there should always exist a theme called hicolor"; "Implementations are required to look in the hicolor theme if an icon was not found in the current theme." Directory `Type` is `Fixed`, `Scalable`, or `Threshold`, default `Threshold` with threshold 2. Lookup (`LookupIcon`): an exact size match first, then any file of that name ranked by `DirectorySizeDistance`, so a themed icon of any size is used and scaled when no exact size exists: "As soon as there is an icon of any size that matches in a theme, the search is stopped." If nothing is found, "it is up to the application to pick a good fallback". So a Linux desktop shows a single 128-pixel PNG, scaled, rather than nothing.
- The AppImage format (AppImageKit): the top-level icon and `.DirIcon` are single files; appimagetool's rule is quoted by ADR 010 as "the 256-pixel icon at the top, as appimagetool recommends it".
- The icon set a prior-art tool emits: Tauri's `tauri icon` writes PNGs of 32, 64, 128, 256, and 512 pixels, named `32x32.png`, `64x64.png`, `128x128.png`, `128x128@2x.png` (the 256), and `icon.png` (the 512) (`crates/tauri-cli/src/icon.rs:662-672`), an `.icns`, and an `.ico` of 16, 24, 32, 48, 64, and 256 pixels (`icon.rs:372`); its new-project template lists only `32x32.png`, `128x128.png`, `128x128@2x.png`, `icon.icns`, `icon.ico` (`crates/tauri-cli/templates/tauri.conf.json`, `bundle.icon`). Its Linux bundler reads each PNG's pixel size with an image decoder and writes it to `hicolor/WxH/apps/` (`linux/freedesktop/mod.rs:44-83`), and picks the largest square for the AppImage's top icon (`linux/appimage/linuxdeploy.rs:97-101`). electron-builder takes a directory of `NxN.png` files named by size for Linux (**unverified**: not fetched this session).

So a developer who follows another tool's default has 32, 128, and 256 pixels, or 32, 64, 128, 256, and 512: never 16 (and 512 only with the generator's default), so Fledge refuses them today.

### 3.3 The smallest change

**Rule: a Linux build needs at least one of the six PNGs; it ships every one that exists; the AppImage's top icon is the 256 if present, else the largest present; every size absent is named once on standard error as a warning.** Details:

- `Icon#png_sizes` (new) returns the sizes among `LINUX` whose file exists. `DesktopEntry#entries` maps over those. `AppImage.add_appdir` uses the 256 when present, else the largest.
- If none exists, the error stays as it is today (it names all six and how to make them).
- No image is read: size remains the file name's claim (ADR 010: "Fledge checks no sizes: it reads none of these formats"). Code stays a liability: no codec, no new tool.
- The six names stay the only accepted names. A developer with `128x128@2x.png` renames or copies it to `app-256.png`; that renaming is a wrapper's job and is where pixel sizes are read, as it already must for its own set (the wrapper owns the decoder; Fledge never will). Accepting more sizes (24, 48 are hicolor's conventional ones, and the spec's own minimum recommendation is 48) is possible as an addition to `LINUX`, compatible by 029 section 4; it is not necessary for this request.
- Behavior with a set of 32, 128, 256: three hicolor folders instead of six, per spec lookup the desktop scales the nearest. The `.deb` moves the same files (`deb.rb:141-143`). The warning text, for instance: `fledge build: the icon icons/app has no PNG of 16, 64, 512 pixels; Linux desktops scale the nearest size`.
- macOS and Windows are unchanged: they need one `.icns` and one `.ico` each (the `.ico`'s inner sizes are the developer's; Windows shows what is there).

Compatibility class: a refusal turned into a success. Any project that built keeps building and produces the same files (all six present gives the same output, no warning). ADR 029 section 4: "A new icon size for a target is optional: a build that passed keeps passing" covers it; section 2 freezes "`icon` and its list of files for each target", which this loosens and does not change for a project that already passes. Record the loosening in the CHANGELOG (observable: a build that failed now passes). Do it before 1.0 if the maintainer prefers a frozen, simpler statement ("at least one of the six sizes").

Effort: S. Files: `icon.rb` (one method and the message), `desktop_entry.rb`, `app_image.rb`, `deb.rb` (none, it moves what exists), `sig/` mirrors, tests in `icon_test.rb`, `desktop_entry_test.rb`, `app_image_test.rb`, the schema's `icon` description and `exe/fledge` text, README, README.rdoc, CHANGELOG. No new tool.

Smallest request, as a plan story:

- **C1. A Linux build takes the icon sizes a developer has.** "A Linux build needs at least one of `ICON-16.png`, `-32`, `-64`, `-128`, `-256`, `-512`. It ships those that exist in the hicolor folders, makes the AppImage's top icon the 256-pixel one or else the largest, and says on standard error which sizes are missing. A project with all six builds exactly what it builds today. Done when: a project with only `-32`, `-128` and `-256` builds, its `.deb` and AppImage hold three hicolor icons, `desktop-file-validate` accepts the entry, and a project with none still fails with today's message. Size S. Compatible (a refusal removed)."

## 4. Summary of capabilities and the request for each

| # | Capability | Effort | 1.x class | Request |
|---|---|---|---|---|
| A1 | description and long description | S to M | compatible | story A1 |
| A2 | homepage | S | compatible | story A2 |
| A3 | category, per-system values | S | compatible | story A3 |
| A4 | license text shown by installers | M | compatible | story A4 |
| B1 | Windows prerequisites | M to L | compatible | story B1 |
| C1 | Linux icon sizes optional | S | compatible (refusal removed) | story C1 |

Not proposed, with reasons (so a wrapper does not wait): an arbitrary install-time command list (surface); a disk image license agreement (L, hdiutil resources, unverified); install-time download of a prerequisite (no pin); a custom NSIS or desktop template (it would make Fledge's generated text part of its frozen API, ADR 029 section 2); an updater (a wrapper's role).

## 5. What this note could not verify from a fetched source

- Microsoft's license terms for redistributing the WebView2 installers (no page fetched states them; section 2.3).
- Whether a per-user prerequisite install under Windows 10 shows a UAC prompt when a per-machine updater exists (Microsoft says it is replaced, not whether it prompts).
- That NSIS 3.13's stock `NSISdl` handles `https` (the wiki says not; Tauri uses it with `https`); irrelevant to the embedded form proposed.
- NSIS `SetRegView 64` behavior for reading both views, and Inno Setup's `Check:` idiom.
- Debian Policy 12.5 (the `copyright` file), Apple's `LSApplicationCategoryType` page (the fetch returned only a title), `hdiutil` license resources, electron-builder's Linux icon directory convention, and whether `Identity.from` can read a gemspec's `summary`, `description`, `homepage`, and `licenses` (it reads `authors` and `version`).
- Tauri sources were read from a local checkout at `9f0306fbc`, not fetched on 2026-11-05.
