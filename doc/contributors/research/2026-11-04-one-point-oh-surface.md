<!--
SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>

SPDX-License-Identifier: CC-BY-SA-4.0
-->

> Review by an agent session on 2026-11-04, of `trunk` at 19efbfa (Fledge 0.2.1 and its Unreleased changes), for Plan 003's story "1.0": "review the CLI and `fledge.yml` for anything to break first". Requested: written by an agent and not reviewed line by line. It reads `exe/fledge`, `lib/fledge/config.rb`, `lib/fledge/config/`, `lib/fledge/config.schema.json`, the CLI, the launcher's C, the phone templates, `tasks/parity.rb`, `lib/fledge/runtimes.rb`, `lib/fledge/SHA256SUMS`, ADRs 002, 005, 008, 009, 014, 019, and 021 to 026, the README, and the CHANGELOG. Nothing here changes code, docs, or rules; section 5 lists the changes to make, and one of them is a question for the maintainer.

# What 1.0 would freeze, and what to change first

## Short answer

1.0 tells developers that the CLI, `fledge.yml`, and what a built app contains will not change without a major version (Plan 003, "1.0"). Most of that surface is ready to freeze. The command is small, the exit statuses follow GNU and sysexits.h, standard output is one path per line, and `fledge.yml` refuses every key it does not know, so adding keys later breaks nobody.

Six things should change before 1.0. They are cheap now and breaking later:

1. **Write down what 1.0 freezes, and what it does not.** SemVer's first rule is that software using it "MUST declare a public API". Nothing says yet whether Fledge's Ruby classes, `fledge.cfg`, the phone templates' contents, or the embedding API are part of it. A wrapper such as Lota's `lota fuse` will guess.
2. **Decide what a Fledge version promises about Ruby's version.** Every runtime carries Ruby 4.0.9, and nothing lets a developer choose another. Ruby 4.1 is due in December; if a Fledge 1.x minor moves to it, apps break under a minor version. This one is the maintainer's to answer (AGENTS.md, Questions, kind 2: product scope).
3. **Stop pointing every `fledge.yml` at the schema on `trunk`.** The schema's `$id` and the modeline that the docs tell developers to copy name `trunk`, which will describe 2.0 while a developer still builds with 1.x.
4. **Give a windowed program in `programs` the project's name by default.** Today it takes its file's name, so `gui/main.rb` becomes `main.app`, "main" in the Dock, and `main.exe`.
5. **Say in the help that a bare word Fledge may read as a platform is read so.** `fledge build ios` reads `ios` as a phone, so a phone or platform added later (`visionos`, say) would turn `fledge build visionos`, which builds a folder today, into something else.
6. **Correct what the README and `doc/licensing.md` say Fledge puts into an app.** They name two files of Fledge's AGPL code. Since the former ADR 026, now ADR 096, `bin/ruby` on macOS and Linux holds Fledge's code too, and `runtime/licenses.yml` says so in `embedded`, but its `ships` line, the README, and the page generated from that line do not.

The three riskiest items are the Ruby version (section 4.1), the undeclared Ruby API and internal files (section 4.2), and the schema URL (section 4.3).

## 1. How to read this review

Each part of the surface is listed as it is on `trunk`, with the file it is in, and judged on three questions:

- **Freeze it?** Is the design one to keep for the life of 1.x?
- **Surprise?** The maintainer's test: "Fledge should never surprise an app dev with how it behaves or causes Ruby or its globals, built-ins, and standard library to behave compared to not using Fledge" (decisions, 2026-11-02, later again).
- **Pressure?** Is something likely to need breaking soon, and what is the cheapest way to leave room?

A change is *compatible* when every project that builds on 1.0 builds on 1.x with the same output and every app it built behaves the same. By that rule, turning a refusal into an acceptance is compatible (a new key, a new value of `kind`, lifting "at most one"); changing a default, a file name, a printed line, or the meaning of an accepted value is not.

Prior art used for the judgments:

- **SemVer 2.0.0**, items 1 and 8: a public API must be declared, and a backward-incompatible change to it increments the major version.
- **Tauri 2**: `tauri.conf.json`'s schema is served per major at `https://schema.tauri.app/config/2`, whose `$id` names the exact release (`https://schema.tauri.app/config/2.12.5`, fetched 2026-11-04). Its configuration has `bundle > iOS > bundleVersion`, which "translates to the bundle's CFBundleVersion property", and `bundle > android > versionCode`, "limited to 2,100,000,000 as per Google Play Store requirements" (`v2.tauri.app/reference/config/`, fetched 2026-11-04).
- **Briefcase**: `console_app`, "a Boolean describing if the app is a console app, or a GUI app"; `build`, "an integer, used in addition to the version specifier, to identify a specific compiled version of an application"; `revision`, "an identifier used to differentiate specific builds of the same version", default 1; settings looked up from the most specific platform table outward (its configuration reference, fetched 2026-11-04). Its Android backend makes `version_code` from each part of the version "padded to 3 digits if necessary" and the build number "as 2 significant digits", and "if provided, this value will override any auto-generated value" (its Android Gradle reference, fetched 2026-11-04).
- **cibuildwheel**: build tools "pinned with that release" by default (`dependency-versions`), so upgrading cibuildwheel is how a project takes newer tools; `--output-dir`, default `wheelhouse`; environment variables before `pyproject.toml` before defaults (its options reference, fetched 2026-11-04).
- **PyInstaller**: one bootloader per kind, console or windowed, and multipackage bundles sharing one folder (as ADR 024 cites).

## 2. The surface, as it is on trunk

### 2.1 The command

From `exe/fledge`'s header (lines 14 to 18), `lib/fledge/cli.rb` (lines 94 to 103 and 153 to 178), and `lib/fledge/cli/build/options.rb`:

| Form | What it does |
| --- | --- |
| `fledge build [OPTIONS] [PATH]` | Builds PATH (default `.`) for this computer's platform |
| `fledge build ios\|android [OPTIONS] [PATH]` | Writes an Xcode or Gradle project; the phone's name comes first, and `./ios` names a folder |
| `fledge --help`, `-h`, `-?` | Prints the header between `####` and `###`, to standard output, status 0 |
| `fledge --version`, `-v` | Prints `fledge VERSION`, status 0 |
| `-o DIR`, `--out DIR`, `--out=DIR` | Output folder, default `dist`; refused when it is the project's root |
| `--sign IDENTITY`, `--sign=IDENTITY` | A keychain identity or `-` on macOS, a SHA-1 thumbprint on Windows; refused for a phone |
| `--` | Ends options |
| `-t`, `--target`, `--target=` | Refused with "is gone: a build is for this computer" |

A bare `fledge`, an unknown option, an unknown command, a missing value, or two PATHs is a usage error: the message, the synopsis as `Usage:`, and `Try 'fledge --help'.`, on standard error, with status 2.

**Freeze it?** Yes. One command and two options is the smallest surface that does the job, and GNU's conventions (ADR 002) are what a developer expects. `-oDIR`, the attached short form GNU's `getopt` reads, is refused as an unknown option; accepting it later is compatible.

**Surprise?** The phone's name as a bare word. Briefcase reads `briefcase build iOS` the same way, so the form has precedent, but every platform Fledge adds later takes a word from the PATHs a developer may pass (section 5, item 5).

**Pressure?** `--notarize` and Azure Trusted Signing's options (Plan 003, "Notarization and real trust chains") are new options, which is compatible. A machine-readable report (`--json`) for wrappers would be new too.

### 2.2 Exit statuses

`fledge` exits 0, 1 for a failed build, 2 for a usage error (ADR 002, sections 1 and 2; `exe/fledge`, lines 293 to 303). A built app's launcher exits with the app's status, 66 (`EX_NOINPUT`) when its entry, its `fledge.cfg`, or its section of `fledge.cfg` is missing, and 70 (`EX_SOFTWARE`) for other damage (ADR 002, section 3; ADR 024, section 8). `bin/ruby` exits 70 when it finds the app's launcher and `execv` fails (the former ADR 026, now ADR 096, section 3). The phone runtimes return the same two from `fledge_ruby_run` and `fledge_ruby_run_app` (`FLEDGE_RUBY_NO_APP`, `FLEDGE_RUBY_SOFTWARE`, `runtime/mobile/fledge_ruby.h`, line 38).

**Freeze it?** Yes. One status for every failed build is coarse; a wrapper cannot tell a missing tool from a refused gem by status. Splitting 1 later would break scripts that test `$? == 1`, so freeze it as it is and let the message say what failed.

**Surprise?** An app that exits 66 or 70 by choice looks like a damaged app. `ruby missing.rb` exits 1, where a built app with no entry exits 66. ADR 002 chose this for scripts that check a download, and it holds.

### 2.3 Standard output and standard error

`fledge build` prints, on standard output, the path of each file it writes, one per line, as `File.join(out, basename)`, so relative when `--out` is relative: the archive, then each installer (`lib/fledge/cli/build.rb`, `build`). A phone build prints the project's folder. `--help` and `--version` print to standard output. Everything else goes to standard error: `Downloading NAME from URL`, compiler output, `host/ios replaces Fledge's ...` (ADR 025, section 5), and errors as `fledge build: ...`, one line each, or `fledge build: MESSAGE` for a usage error before the synopsis.

**Freeze it?** Freeze standard output: ADR 019, section 2, already promises it to wrappers. Do not freeze standard error's wording. Messages improve with every release (the Unreleased section of the CHANGELOG adds one, rewords another, and drops a third), and a wrapper that parses them should not be able to hold Fledge back. Say so (section 5, item 1).

**Surprise?** The built folder, `DIR/NAME-PLATFORM/`, is never printed, though a developer runs it first. A wrapper derives it from the archive's name. Printing it later would add a line, which breaks a script that takes the first line as the archive; leave it out for 1.x.

### 2.4 fledge.yml

From `lib/fledge/config.rb`, `lib/fledge/config/program.rb`, `lib/fledge/config/phone.rb`, and `lib/fledge/identity.rb`. Every key is optional; an empty value (`name:`) means absent; text blank to `String#strip` is refused; an unknown key is refused, naming it and listing the known ones.

| Key | Default | Refused when |
| --- | --- | --- |
| `name` | gemspec's name, else the root folder's, camelized (`my_cool_app` is `MyCoolApp`; decision 5) | not text; with `programs`, it names the folder and archives, not a program |
| `kind` | `console` | not `console` or `windowed`; at the top beside `programs` |
| `identifier` | none; a windowed app needs one, and the build suggests `io.github.OWNER.NAME` or `com.example.NAME` | not reverse-DNS of letters, digits, and hyphens, two or more parts, at most 128 characters; at the top beside `programs` |
| `version` | gemspec's, else `0.0.0` | a YAML number (quote it); not `Gem::Version.correct?`; not starting with a digit; on Windows, a part above 65535 |
| `icon` | none | ends in `.png`, `.icns`, or `.ico`; a file the target needs is missing; at the top beside `programs` |
| `publisher` | gemspec's authors | not text |
| `copyright` | none | not text |
| `installers` | `[dmg, nsis, appimage]` | not a list of `dmg`, `nsis`, `appimage`, `deb`; not empty for an app with no windowed program |
| `programs` | none: the one program built | not a non-empty list; an entry not a mapping of `path`, `name`, `kind`, `identifier`, `icon`; no `path`; a path outside the project; two names or identifiers equal ignoring case; two windowed programs |
| `programs[].name` | the path's file name without its extension | as `name` |
| `ios`, `android` | none | not a mapping of `host`; `host` not a folder in the project |

Duplicates in `installers` are dropped. The phone keys are ignored by desktop builds, and each phone ignores the other's.

**Freeze it?** The shape, yes: a flat mapping of identity keys, as Tauri's top level and Briefcase's app table are, with one list and two phone mappings. Refusing unknown keys is what makes every later key compatible. Key by key:

- `name`, `identifier`, `version`, `publisher`, `copyright`, `icon`: freeze. Each maps to one field every system shows (ADR 008), which is decision 18's list.
- `kind`: freeze. Briefcase's `console_app` is a Boolean; a string leaves room for a third kind, which is a compatible addition.
- `installers`: freeze the key and the four names. Freeze the default too: an installer added in 1.x is opt-in, as `deb` is (ADR 021), because a new default would print a new line and need a new tool on a computer that built yesterday. Write that rule down (section 5, item 1).
- `programs`: freeze, with one change to a default (section 5, item 4).
- `ios`, `android`: freeze the mappings. With one key, `host`, they look thin, but they are where a phone's next setting goes, as Briefcase's `iOS` and `android` tables and Tauri's `bundle > iOS` and `bundle > android` are. Section 3.4 names the settings likely to come.

**Surprise?** Three, none of them a reason to break:

- A gem-shaped console app's program is `MyCoolApp`, in CamelCase, where a Linux user types `my_cool_app`. That is decision 5's rule, the maintainer's, and `name: my_cool_app` changes it. The same program listed under `programs` is `my_cool_app`, by its file name. Two defaults for one program is odd, but each is documented.
- `version` is the marketing version and the only version. A phone needs a build number that grows on every upload (section 3.4).
- `icon` names files by convention, and every size a target lists must be there. A size added to a target's list in 1.x would fail builds that passed. Freeze the lists, and make any later size optional.

### 2.5 The JSON Schema

`lib/fledge/config.schema.json`, draft-07, written by hand and tested against Config (ADR 023). Its `$id` is `https://raw.githubusercontent.com/setdef/Fledge/trunk/lib/fledge/config.schema.json`, and the modeline Config's RDoc and the CHANGELOG give developers names the same URL. ADR 023, section 3, says a tag's URL names that release's file.

**Freeze it?** The schema's content follows Config, so it freezes when Config does. Its address should not be `trunk` (section 5, item 3).

**Surprise?** After 1.0, `trunk` heads toward 2.0. A developer on 1.4 whose editor reads `trunk` gets completion for a key 1.4 refuses, or a red mark on a key 2.0 removed. Tauri avoids this with an address per major.

### 2.6 What `fledge build` writes, per platform and kind

From `exe/fledge`'s FILES (lines 182 to 266), ADR 008, sections 2 to 4, ADR 009, ADR 021, ADR 024, section 4, and `lib/fledge/mac_bundle.rb`:

| | Console | Windowed |
| --- | --- | --- |
| `arm64-darwin` | `NAME-arm64-darwin/` holding `NAME`, `fledge.cfg`, `app/`, `bin/`, `lib/`, `libexec/`, `notices/`; `.tar.gz` | the same folder holding `NAME.app` (`Contents/MacOS/NAME`, links to `Contents/Resources/{app,bin,fledge.cfg,lib,libexec}`, `Resources/NAME.icns`, signed ad hoc); `.tar.gz`, `NAME-arm64-darwin.dmg` |
| `*-linux`, `*-linux-musl` | `NAME-PLATFORM/` holding `NAME`, `fledge.cfg`, `app/`, `bin/`, `lib/`, `libexec/`, `notices/`; `.tar.gz` | the same plus `IDENTIFIER.desktop` and `share/icons/hicolor/SIZExSIZE/apps/IDENTIFIER.png`; `.tar.gz`, `NAME-PLATFORM.AppImage`, and on glibc `NAME-PLATFORM.deb` when asked |
| `*-mingw-ucrt` | `NAME-PLATFORM\` holding `NAME.exe` (console subsystem, version information, icon), `fledge.cfg`, `app\`, `ruby\`, `notices\`; `.zip` | `NAME.exe` from `launcherw.exe` (GUI subsystem); `.zip`, `NAME-PLATFORM-setup.exe` |

With `programs`, each program is a renamed copy of the launcher beside the one runtime and `app/`; on macOS with a windowed program, the console programs are in its bundle's `Contents/MacOS`, linked from the folder (ADR 024, section 4). Installers belong to the windowed program. A new build replaces the folder.

Installed, a setup program puts the app in `%LOCALAPPDATA%\Programs\NAME`, makes `NAME.lnk` with the identifier as `System.AppUserModel.ID`, and registers `HKCU\...\Uninstall\IDENTIFIER` (ADR 009, section 3); a `.deb` is the package `identifier` lowercased, version with `~` before a pre-release, installed in `/usr/lib/IDENTIFIER` (`lib/fledge/deb.rb`, lines 97 and 117).

**Freeze it?** Yes. File names carry no version, so a script finds them by platform (ADR 009, section 1); Tauri's carry one (`NAME_VERSION_ARCH-setup.exe`), and either is defensible, but changing it now would only churn. The installed locations matter more than the file names: the uninstall key and the `.deb`'s package name come from the identifier, so a 1.x that changed either would leave a second copy installed beside the first. Freeze both, and say in the help that changing an app's `identifier` makes a new app as far as each system is concerned.

**Surprise?** The archive's and installer's names hold the app's name with its spaces (`My Cool App-arm64-darwin.dmg`). It works everywhere Fledge delivers, and a developer who dislikes it sets `name`. The Windows install folder follows `name`, not the identifier, so renaming an app installs it again beside the old folder; the registered uninstaller still finds the old one by identifier, and a reinstall goes where the last install went (ADR 009, section 3). Leave it.

**Pressure?** Several windowed programs (ADR 024, Consequences) would put a second bundle beside the first on macOS. Lifting the limit is compatible for projects with one windowed program, as long as the console programs stay in the first program's bundle; record that the console programs live in the bundle of the first windowed program, so the rule already reads right when there are two.

### 2.7 What a built app contains

From the 0.2.1 `arm64-darwin` runtime's archive, `lib/fledge/assembly.rb`, `runtime/launcher/config.c`, and `doc/licensing.md`:

- **`app/`**: the project, less `.git`, `.bundle`, `vendor/bundle`, `vendor/cache`, the output folder, and a phone's `host` folders; plus `app/.bundle/config`, which Fledge writes (frozen, without `development` and `test`, `with` as the project's, gems in Ruby's folder), and `app/vendor/cache/NAME` for a path gem from outside the project.
- **`notices/NOTICES.txt`** and **`notices/sbom.spdx.json`**: every component Fledge put in, its license and text, and an SPDX 2.3 bill of materials. Each gem keeps its notices in its folder.
- **`fledge.cfg`**: `key = value` lines (`entry`, `gemfile`, `identifier`), `#` comments, and, with `programs`, `[NAME]` sections holding `entry` and `identifier`. A key the launcher does not know means the file is damaged (70).
- **The runtime**: `bin/` (`ruby`, Ruby's tools, and the executables of the app's gems), `lib/ruby/` with the app's gems in `lib/ruby/gems/4.0.0`, `libexec/cert.pem`; on Windows, RubyInstaller's tree under `ruby\`. `tools/` never ships.

**Freeze it?** Freeze `app/` (the app's code finds its files through `__dir__`), `notices/` and its two file names (a developer's compliance process reads them), and the program names. Do not freeze `fledge.cfg`: `fledge build` writes it and a launcher from the same release reads it, and nothing else should. Its strictness is right for a private file and wrong for a public one, so the cheapest room is to call it private (section 5, item 1). A `format = 1` key would cost a key in every launcher for a reader that does not exist. Do not freeze the runtime's tree below what Ruby itself answers (`RbConfig.ruby`, `Gem.dir`, `Gem.bindir`); an app that asks Ruby where things are keeps working when the tree moves.

**Surprise?** A built app's `bin/` holds `gem`, `bundle`, and `irb`, which a person could run. `gem install` there writes into the runtime's gem folder. That is what a Ruby installation has, and `RbConfig.ruby` needs the tree; leave it.

### 2.8 The launcher, and how it differs from `ruby main.rb`

The launcher hides the person's `RUBYOPT`, `RUBYLIB`, `GEM_HOME`, and the rest from Ruby's boot, puts them back in `ENV` after, coerces a bare C locale to UTF-8, sets Bundler up as `bundle exec` would, and runs `app/ENTRY` by its real path (the former ADR 003, now ADR 081, ADR 005, the former ADR 026, now ADR 096). On macOS and Linux, `bin/ruby` hands `exec RbConfig.ruby, $0, *ARGV` back to the launcher; on Windows, restarting means running `NAME.exe` (the former ADR 026, now ADR 096, sections 3 and 4).

Every difference the parity check allows is in `Parity::JUSTIFIED` (`tasks/parity.rb`, lines 64 to 128) and `MOBILE_JUSTIFIED` (`tasks/parity/mobile.rb`, lines 24 to 62). On the desktop:

1. `$0`, `__FILE__`, `$PROGRAM_NAME` are the absolute path of the entry, not the path as typed.
2. `$LOAD_PATH`, `Gem.path`, `Gem.dir` name the runtime's gem folder, not the person's `GEM_HOME` or `Gem.user_dir`.
3. The Gemfile's `development` and `test` groups are absent (rake, in the probe).
4. Bundler's `GEM_HOME` and `PATH` in `ENV` name the runtime's gems.
5. `$VERBOSE` is `false` where the person's `RUBYOPT=-W0` would make it `nil`: the person's `RUBYOPT` never reaches the boot.
6. `$LOADED_FEATURES` gains RubyGems' YAML serializer (Bundler reads the app's `.bundle/config`) and loses Bundler's `feature_flag.rb` and the project's version file (the gemspec ships evaluated).
7. rv-ruby's `bootsnap` and `msgpack` are absent.
8. Fledge's `rubygems/defaults/operating_system.rb` is loaded; on Windows, RubyInstaller's runtime and `win32/dll_directory` are not.

On a phone: a system environment with `SSL_CERT_FILE` added (and `HOME` on Android); no child processes; no `bin/ruby`; `RUBY_PLATFORM`, `RUBY_DESCRIPTION`, and the architecture folders name the phone; extensions recorded by feature name; no YJIT; no `fiddle` on iOS.

**Freeze it?** Yes, as a list that may only shrink in 1.x. A new difference is a change in how Ruby behaves under Fledge, which is the surprise the maintainer's test forbids; a difference removed is a bug fixed toward `ruby main.rb`.

**Surprise?** Three that a developer can meet without reading an ADR:

- Item 1: a usage line built from `$0` prints `/path/to/MyCoolApp-x86_64-linux/app/exe/my_cool_app`, where a RubyGems binstub on a `PATH` prints its full path and `ruby main.rb` prints `main.rb`. `File.basename($0)` is the entry's file name, not the program's name (`my_cool_app`, not `MyCoolApp`). Document it beside the restart in the help.
- On Windows, `exec RbConfig.ruby, $0` restarts the app as plain Ruby in a console, with the person's settings (the former ADR 026, now ADR 096, section 4). The help and the README say so. A later release that makes it behave as on macOS removes a difference, which is compatible.
- A child Ruby running any other script (`system(RbConfig.ruby, "worker.rb")`) boots with the person's `RUBYOPT` and `RUBYLIB`, as `ruby worker.rb` would, while the app itself did not (the former ADR 026, now ADR 096, section 3). That is the right reference, but it is the one place where the app and its child see two different Rubies on one computer. Leave it, and keep it in the help.

### 2.9 Phone projects, the host key, and the embedding API

`DIR/NAME-ios/` holds `project.yml`, `NAME.xcodeproj`, `FledgeRuby.xcframework`, `fledge/` (`fledge.cfg`, `app/`, the gems, `notices/`), and `Host/` (`main.m`, `Info.plist`, `PrivacyInfo.xcprivacy`, `Assets.xcassets`). `DIR/NAME-android/` holds the Gradle files and wrapper, `libs/FledgeRuby.aar`, `fledge/` (stored as the asset `fledge.zip`), and `src/main/` with `java/org/setdef/fledge/host/MainActivity.java`, the manifest, `res/values/strings.xml`, and the icons (`lib/fledge/templates/`; `exe/fledge`, lines 214 to 238). iOS 15 and later; Android API 26 and later, targeting 36.

A `host` folder's files replace Fledge's at the same path or join the project, and Fledge fills its marks in a host's copy of a template it marks: `@@NAME@@`, `@@IDENTIFIER@@`, `@@VERSION@@`, `@@LDFLAGS@@`, `@@APP_ICON@@` and the rest on iOS; `@@APPLICATION_ID@@`, `@@VERSION_CODE@@`, `@@VERSION_NAME@@`, `@@AGP@@` and the rest on Android (ADR 025, section 5). A host calls the embedding API: `fledge_ruby_run`, `fledge_ruby_run_app`, `fledge_ruby_add_extension`, `fledge_ruby_forward_output` (`runtime/mobile/fledge_ruby.h`), and on Android `org.setdef.fledge.FledgeRuby.startApp` (`MainActivity.java`, line 43).

**Freeze it?** Freeze the project folder's name, `fledge/`, the template paths a host may replace, the marks, and the embedding API's functions and Java method. A host written for 1.0 keeps replacing the same paths and calling the same functions. Do not freeze the templates' contents: ADR 025 already makes a host's copy the developer's to keep in step, and the build names each copy. Say all of this in the contract (section 5, item 1).

**Surprise?** Android's host Activity lives in Fledge's Java package, `org.setdef.fledge.host`, while the app's `applicationId` is the developer's. Android keys an app by `applicationId`, not by its classes' packages, so nothing a person sees changes; a developer who reads the tree may wonder. Leave it; moving it would break every host.

**Pressure?** The `ios:` and `android:` mappings will need settings beside `host`: a build number (section 3.4), an Apple team for signing, permissions and entitlements, orientation. Each is a new key in a mapping that refuses unknown ones, so each is compatible.

### 2.10 Releases and runtime downloads

From ADR 014, `lib/fledge/runtimes.rb`, and `lib/fledge/SHA256SUMS`:

- A release is the tag `vX.Y.Z` and a GitHub Release at `https://github.com/setdef/Fledge/releases/download/vX.Y.Z/`.
- For each desktop platform, the assets are `fledge-runtime-VERSION-PLATFORM.tar.gz`, `-dev.tar.gz`, `-NOTICES.txt`, `.spdx.json`, and `-lgpl-sources.tar.gz`; for the phones, `fledge-runtime-VERSION-ios.tar.gz` and `-android.tar.gz` with their NOTICES and SBOM. VERSION is Fledge's, not Ruby's.
- The gem carries `lib/fledge/SHA256SUMS`, the release's `SHA256SUMS`, in `sha256sum` format; `fledge build` downloads only a file it pins, into `$XDG_CACHE_HOME/fledge/runtimes` (or `~/.cache/fledge/runtimes`), and `FLEDGE_RUNTIME_DIR` replaces the download with a folder of those names.
- Developers install Fledge from a tag: `gem "fledge", git: "https://github.com/setdef/Fledge", tag: "vX.Y.Z", group: :development`.

**Freeze it?** Freeze the tag form, the asset names, and `SHA256SUMS`'s format: a wrapper that mirrors runtimes or fills `FLEDGE_RUNTIME_DIR` depends on them. The cache's location is not a contract; on Windows, `%LOCALAPPDATA%` would be more usual than `~/.cache`, and moving it costs a download, so it can move compatibly.

**Pressure?** If developers come to choose a Ruby version (section 4.1), a runtime's name needs the Ruby version in it. Adding a new name, such as `fledge-runtime-VERSION-ruby-4.1.0-PLATFORM.tar.gz`, beside the current one, which keeps meaning the default Ruby, is compatible. Reserve that pattern in the ADR now, so nobody uses it for something else.

## 3. What is likely to need breaking soon, and the cheapest room

### 3.1 One windowed program per project

The refusal is section 2 of ADR 024. Lifting it is compatible: a project that builds today has at most one. What would not be compatible is moving the console programs out of the windowed program's bundle on macOS. Keep the rule that they live in the first windowed program's bundle, and write "first" now.

### 3.2 The "at most one" limits elsewhere

One PATH per build, one `--sign` identity, one `host` per phone: each is a refusal, and each can become an acceptance. No room is needed.

### 3.3 The programs section's keys

A program has `path`, `name`, `kind`, `identifier`, `icon`; the project has `name`, `version`, `publisher`, `copyright`, `installers`. ADR 024 lists "defaults for each program's keys from the top of `fledge.yml`" as not yet: today a top-level `kind`, `identifier`, or `icon` beside `programs` is refused, so allowing them later as defaults is compatible. A per-program `version` or `installers`, if ever wanted, is a new key in a program and compatible too. The one change to make now is the windowed program's default name (section 5, item 4), because a default cannot change after 1.0.

### 3.4 Phone build numbers

iOS's `CFBundleVersion` and `CURRENT_PROJECT_VERSION` are the version's first three numbers (`lib/fledge/mobile_project/ios.rb`, line 92; `templates/ios/project.yml`, lines 49 and 50), and Android's `versionCode` is `MMMmmmppp` from the same three (`lib/fledge/mobile_project/android.rb`, lines 85 to 90). So `1.0.0.pre.1` and `1.0.0` share a build number, and two uploads of `1.0.0` to TestFlight or Play share one too, which both stores refuse. Tauri has `bundleVersion` and `versionCode`; Briefcase has `build` and `version_code`. Adding `ios: { build: N }` and `android: { version_code: N }` (or one `build` at the top, as Briefcase does) is compatible, since today's formula stays the default. Reserve the names in the ADR so that 1.x adds them under the names chosen now. Changing the formula itself, as Briefcase's two digits of build number would, is not compatible; leave it.

### 3.5 Installer defaults

`installers` defaults to `[dmg, nsis, appimage]`. `.msi` and `.rpm` are deferred (Plan 003, "The installers developers expect"). The room is a rule, already followed for `.deb`: a new installer is opt-in for all of 1.x.

### 3.6 The schema's address

Section 5, item 3.

### 3.7 fledge.cfg's sections

The INI-like sections came in 0.2.0 and are read by the launcher, `bin/ruby`, and the phone runtimes. Declared private, they can change in any release, since a build always pairs `fledge.cfg` with the launchers of the same release. The one case where they do not pair is `FLEDGE_RUNTIME_DIR` naming runtimes of another release, which ADR 024's Consequences already call unsupported. No version key is needed.

## 4. The three riskiest items

### 4.1 Ruby's version

Every runtime of a release carries one Ruby, 4.0.9 today, and nothing chooses another. `Fledge::Bundle#check_ruby` refuses a Gemfile whose `ruby` asks for a different one (`lib/fledge/bundle.rb`, lines 263 to 268). Ruby releases a minor version every December, and a minor version changes what Ruby code sees: default gems become bundled gems, which a locked app then cannot `require`; warnings become errors. Under SemVer, a Fledge 1.y that moves its runtimes from Ruby 4.0 to 4.1 changes what a built app contains in a way an app can observe, which is a major change. The alternatives:

- **Every Ruby minor is a Fledge major.** True to SemVer, and a 2.0 every December.
- **A Ruby minor may arrive in a Fledge minor.** Simple, and a break under a minor version, the surprise the maintainer's test forbids.
- **A Fledge 1.x keeps Ruby 4.0.x, moving only its patch; a new Ruby minor arrives in a 1.y as a second runtime, chosen by the Gemfile's `ruby` directive, and becomes the default only in a major.** No new key: Bundler's directive already says which Ruby the project wants, and Fledge already reads it. It costs a runtime per Ruby per platform in each release and a CI matrix that doubles while two Rubies are carried, as cibuildwheel's builds for several Pythons do.

The third fits Design precedence 2 and 3 best, but it decides what a Fledge version promises and adds a requirement the maintainer did not ask for, a second runtime per platform while two Rubies are carried, which doubles the runtime jobs of every CI run and every release. What Fledge promises across versions is product scope, so it is the maintainer's (AGENTS.md, Questions, kind 2; How to work, on requirements and their cost). It belongs in `questions.md` with the third as the default. The same answer should cover the platform floors (macOS 14, glibc 2.39, iOS 15, API 26): raise one only in a major, unless the platform's vendor forces it, as Google Play's target API does each year.

### 4.2 An undeclared public API

`Fledge::CLI`, `Fledge::Config`, `Fledge::App`, and the rest are documented with RDoc and examples, which reads as a promise. ADR 019 lists what a wrapper may rely on, but not what it may not. A wrapper that calls `Fledge::CLI.new(...).call` in process, or reads `fledge.cfg`, or parses a `fledge build:` message, would hold those against every refactor of 1.x. SemVer's first item asks for a declaration; Briefcase and Tauri each declare a configuration file and a command, not their internals. The cheapest room is one paragraph (section 5, item 1).

### 4.3 The schema on trunk

Every developer who follows the docs copies a modeline that names `trunk` into a file they keep for years. After 1.0, `trunk` is the next major. Changing the advice after 1.0 leaves every copied modeline pointing at the wrong schema, and no build will ever say so, since the modeline is a comment. Change it before 1.0 (section 5, item 3).

## 5. Recommendations

### Must change before 1.0

1. **Declare the 1.0 contract.** Amend ADR 019's section 2 into "What 1.0 freezes" (or write ADR 027) with two lists. Frozen: the command, its options and exit statuses; standard output's lines; every `fledge.yml` key, value, and default; the output names of section 2.6; `app/`, `notices/NOTICES.txt`, `notices/sbom.spdx.json`, the program names, the bundle, desktop entry, and installed locations keyed by `identifier`; `Parity::JUSTIFIED` as a list that may only shrink; the phone project's folder names, the template paths a host may replace, the `@@` marks, and the embedding API; the release's tag form, asset names, and `SHA256SUMS`. Not frozen: Fledge's Ruby classes (only `exe/fledge` is the interface), standard error's wording, `fledge.cfg`, the runtime's tree below `RbConfig` and `Gem`, the templates' contents, and the cache folder. Add the rules: a new installer is opt-in; a new icon size is optional; reserved for later, `ios: build`, `android: version_code`, and runtime names with `-ruby-X.Y.Z-`. One sentence in the README's "Updating Fledge" points at it.
2. **Ask the maintainer about Ruby's version.** Add to `questions.md`: the context of section 4.1; the default, that 1.x keeps Ruby 4.0.x and a later Ruby minor arrives only as an extra runtime the Gemfile's `ruby` directive chooses, becoming the default in a major; how to reverse it, by letting a 1.y move the default Ruby with a CHANGELOG entry under "Changed". Record the answer in the contract of item 1, with the platform floors.
3. **Point the schema at a release.** Make `$id` the tag's URL, `https://raw.githubusercontent.com/setdef/Fledge/vX.Y.Z/lib/fledge/config.schema.json`, set in each release commit, with a test in `test/config_schema_test.rb` that `$id` names `v#{Fledge::VERSION}`. Change the modeline in Config's RDoc and the README to "the URL of the tag in your Gemfile". Point every `examples/*/fledge.yml` and test fixture at the file by a relative path (`$schema=../../lib/fledge/config.schema.json`), which Red Hat's language server reads (`<schema-url-or-path>`, its README, lines 81 to 95, as ADR 023 cites), so `trunk`'s examples check against `trunk`'s schema. Amend ADR 023, section 3.
4. **Name a windowed program after the project by default.** In `Fledge::Config::Program.from` (or where `App` builds its programs), a windowed program with no `name` takes the project's name (the `fledge.yml` `name`, else the gemspec's or folder's, camelized, as decision 5 asks), and a console program keeps its file's name. Update `programs[].name` in the schema and the help, ADR 024, section 1, and the CHANGELOG under "Changed". A project whose two programs would then share a name is refused by the rule that exists.
5. **Reserve platform words in PATH.** In `exe/fledge`'s COMMANDS, replace "for a folder named ios or android, write ./ios" with "a PATH that is a bare word Fledge reads as a platform, today ios and android, is read as one in every later release that adds it; write ./NAME for a folder". A later phone or platform then breaks nobody who followed the help.
6. **Count `bin/ruby` among Fledge's files.** Change the `fledge` component's `ships` line in `runtime/licenses.yml` to name `bin/ruby` on macOS and Linux, regenerate `doc/licensing.md` with `bundle exec rake "licensing[DIR]"`, and change the README's "Two files in each app are Fledge's" to three. the former ADR 026, now ADR 096, section 1, already says `bin/ruby` carries Fledge's AGPL code, and `licenses.yml`'s `embedded` already checks it; only the prose disagrees, and a developer reads the prose to learn what source to offer.

### Could change after 1.0, compatibly

- Several windowed programs, once the "first windowed program's bundle" rule is written (section 3.1).
- Top-level `kind`, `identifier`, and `icon` as defaults for each program (section 3.3).
- `ios: build` and `android: version_code`, under the reserved names (section 3.4).
- New installers, opt-in (section 3.5); new `kind` values; new options (`--notarize`, `--json`).
- A runtime per Ruby version, under the reserved name pattern (section 2.10), if the maintainer's answer to item 2 calls for it.
- Restarting through `RbConfig.ruby` on Windows as on macOS and Linux, which removes a difference.
- The cache folder's location on Windows.
- `-oDIR` and other GNU forms the parser refuses today.

### Fine as is

- The command, its two options, and the `--target` tombstone.
- Exit statuses 0, 1, 2, and the launcher's 66 and 70.
- Standard output's one path per line, and standard error for everything else.
- The flat `fledge.yml`, its refusal of unknown keys, and every key's meaning and default but `programs[].name` for a windowed program.
- `kind` as a string, `installers` with today's default, `icon` without an extension.
- `ios:` and `android:` as mappings with one key.
- Output names without a version, and the per-platform layout.
- `app/` and `notices/`; `fledge.cfg` as a private file.
- `Parity::JUSTIFIED` and the documented differences from `ruby main.rb`.
- The phone projects' layout, the host's Generation Gap, and Android's host Activity in Fledge's package.
- The release tag, asset names, `SHA256SUMS`, and installing from a tag.
