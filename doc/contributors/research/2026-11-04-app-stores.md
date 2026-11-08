<!--
SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>

SPDX-License-Identifier: CC-BY-SA-4.0
-->

> Research by an agent session on 2026-11-04, on `trunk` at c20a629 (Fledge 0.4.0 and its Unreleased changes). Requested: written by an agent and not reviewed line by line. Every claim about a store cites the page it came from and the date it was fetched, 2026-11-04 for all of them. A claim marked **(guess)** comes from no fetched source. Nothing here changes code, docs, or rules; the last section proposes Plan 003 stories and leaves `plan/003.md` alone.

# Can an app built by Fledge go on a store?

## Short answer

Three stores take a Fledge app with little or no change to the app: Google Play and the iOS App Store (both take the project Fledge writes, which the developer builds, signs, and submits), and the Microsoft Store through its MSI/EXE route (it takes the setup program Fledge already writes). Two need new work in Fledge: the Mac App Store (a sandboxed, differently signed `.pkg`) and the Microsoft Store's MSIX route (a package and one launcher change). On Linux, Flathub and the Debian, Ubuntu, and Fedora archives want packages built from source, which no Fledge output is. Snap and a developer-hosted apt or Flatpak repository take prebuilt output.

No Fledge output has been through any store's review. Every "compatible" below means compatible by the documents fetched, and the review itself is the unknown that only a submission settles.

## The table

| Store | Compatible today? | What Fledge lacks | Policy | Cost to the developer | Prior art with an embedded interpreter |
| --- | --- | --- | --- | --- | --- |
| Mac App Store | No. The `.app` is signed for Developer ID, with no sandbox. | App Sandbox entitlements on every executable, App ID and Team ID entitlements, a provisioning profile, Apple Distribution and Mac Installer Distribution signing, a `.pkg`, an upload step. | Compatible on paper (2.4.5, 2.5.2). Unknown: the sandbox changes what a Ruby program can do, and review of a nonstandard bundle layout. | US$99 a year | Electron and Tauri ship on it. Briefcase has a macOS Xcode path; one Briefcase app was rejected under 2.5.2 and then accepted. |
| Microsoft Store, MSI/EXE route | Yes by the documents. The NSIS setup program is per-user, silent with `/S`, and signed with `--sign`. | Nothing in the file. The developer hosts it at a versioned HTTPS URL and holds a CA-trusted code signing certificate. | Compatible on paper (policy 10.2.9). Unknown: certification, and whether a redirecting download URL passes. | No registration fee in the new flow; a code signing certificate or signing service (US$300 to 500 a year, or about US$10 a month, per Microsoft's table) | Many installers; no interpreter example found for this route. |
| Microsoft Store, MSIX route | No. | `AppxManifest.xml`, `makeappx pack`, tile assets, `runFullTrust`, Store identity keys in `fledge.yml`, and a launcher change (it sets a custom AppUserModelID, which a package may not). | Compatible on paper. Unknown: `runFullTrust` approval, writes to the install folder. | No registration fee; the Store signs the package for free | Python install manager (MSIX, Store and python.org); electron-builder and Tauri tools make Store MSIX. |
| iOS and iPadOS App Store | Yes by the documents. Ruby is linked in, native gems are static, nothing loads code from files. | Nothing in the project. The developer pays, signs, archives, and submits. A Fledge-side check that the archive validates is missing. | Compatible on paper (2.5.2, license agreement 3.3.1(B), 4.2.6). Unknown: App Review itself, and Apple's scan of the bundle. | US$99 a year | RubySketch (CRuby, on the App Store). Kivy and Briefcase Python apps. |
| Google Play | Yes by the documents. API 36, 16 KB alignment, and Ruby shipped inside the app. | Nothing in the project. The developer builds an `.aab` with `./gradlew bundleRelease` and signs it. No Fledge check builds an `.aab`. | Compatible on paper (Device and Network Abuse, target API, 16 KB). Unknown: review, the personal-account testing rule. | US$25 once | Briefcase Android publishes `.aab` to Play. |
| Flathub | No for a Fledge-built app. | A Flatpak manifest that builds Ruby and every gem from source with no network. | Flathub requires builds from source and refuses precompiled files in the pull request. Exceptions are case by case for well-known vendors. | None found | Tauri's guide builds from a prebuilt `.deb`; whether Flathub accepts that is not stated. |
| A Flatpak repository the developer hosts | Not yet. | A manifest, or a Flatpak made from the built folder, and a signed repository. | No review. | Hosting only | Flatpak documents hosting on GitLab or GitHub Pages. |
| Snap Store | Plausibly. The pinned glibc floor, 2.39, is `core24`'s **(guess)**. | A `snapcraft.yaml` that dumps the built folder under strict confinement. | Strict snaps go through automated review; classic needs manual approval and a listed category. | Not found | Tauri's guide builds a strict snap from a `.deb`. |
| Debian and Ubuntu archives | No. | Not a packaging gap. | Debian's DFSG requires source, and policy 4.13 says not to use embedded copies of other packages. Launchpad PPAs reject prebuilt uploads. | None | None. |
| A developer-hosted apt repository | Yes. The opt-in `.deb` installs from one. | Repository tooling and a signing key, which are the developer's. | Debian's wiki sets the rules for the user's side. No review. | Hosting only | Debian's wiki lists `reprepro` and `aptly`. |
| Fedora | Unknown. | Not checked. | Fedora's documents refused the fetch tool, so this research says nothing about them. | | |

## What Fledge makes today

Read from the repository at c20a629, not from other documents.

- **macOS.** `lib/fledge/mac_bundle.rb` writes `NAME.app/Contents/MacOS/NAME` (the launcher, with symbolic links to its neighbors) and puts Ruby, the app, and the gems in `Contents/Resources`. `lib/fledge/mac_signing.rb` signs every Mach-O file, the bundle, and the disk image with `codesign --options runtime` and a timestamp. `lib/fledge/templates/macos/entitlements.plist` holds two entitlements, `allow-unsigned-executable-memory` and `disable-library-validation`. There is no App Sandbox entitlement, no provisioning profile, and no `.pkg`. Fledge does not notarize.
- **Windows.** `lib/fledge/nsis/script.rb` writes a setup program with `RequestExecutionLevel user`, an install folder in `%LOCALAPPDATA%\Programs`, a silent mode (`/S`), a Start menu shortcut that carries the AppUserModelID, and an uninstaller. `lib/fledge/windows_signing.rb` signs `.exe`, `.dll`, and `.so` files with `signtool` and a certificate thumbprint. `runtime/launcher/windows.c` calls `SetCurrentProcessExplicitAppUserModelID`.
- **Linux.** A folder with a desktop entry and icons, an AppImage, and, when asked, a `.deb` (`lib/fledge/deb.rb`) that installs to `/usr/lib/PACKAGE` with `dpkg-deb`.
- **iOS.** `lib/fledge/templates/ios/project.yml` makes an Xcode project that links `FledgeRuby.xcframework`. Native gems are compiled and linked into the executable (ADR 022). The template carries `PrivacyInfo.xcprivacy` with reasons for the file timestamp and boot time APIs. No signing is configured.
- **Android.** `lib/fledge/templates/android/build.gradle` sets `targetSdk = 36`, `minSdk = 26`, and `useLegacyPackaging = false`. The runtime links with `-Wl,-z,max-page-size=16384` (`tasks/runtime_builder/android.rb`, `lib/fledge/mobile_extensions.rb`). The app unpacks `fledge.zip` from its assets on the first launch (`build.gradle`). The manifest asks only for `INTERNET`. No signing is configured.
- **What no store has seen.** ADR 011 and ADR 012 say that a real iPhone or iPad and App Store review are not yet proven.

## Mac App Store

### Technically compatible today?

No, and the gap is larger than packaging. Apple's page on distribution says "To distribute an app in the Mac App Store, you submit the app as an installer package", while Developer ID builds go out as zip, disk image, or package (Apple, "Packaging Mac software for distribution", fetched 2026-11-04 from `developer.apple.com/tutorials/data/documentation/xcode/packaging-mac-software-for-distribution.json`, the data behind the page).

What Fledge lacks:

- **The App Sandbox.** Apple's guidelines say Mac App Store apps "must be appropriately sandboxed" (2.4.5(i), `developer.apple.com/app-store/review/guidelines/`). The sandbox capability adds `com.apple.security.app-sandbox`, "which is an App Store requirement for any app that you submit to the Mac App Store for review" (Apple, "Configuring the macOS App Sandbox", JSON form, fetched 2026-11-04).
- **Entitlements on every executable.** A helper that the app starts with `posix_spawn` or `NSTask` inherits the sandbox: "a child target must use exactly two App Sandbox entitlement keys: `com.apple.security.app-sandbox` and `com.apple.security.inherit`. If you specify any other App Sandbox entitlement, the system aborts the child process", and "The main app in an Xcode project must never have a `YES` value for the `inherit` entitlement" (Apple, archived "Enabling App Sandbox", `developer.apple.com/library/archive/documentation/Miscellaneous/Reference/EntitlementKeyReference/Chapters/EnablingAppSandbox.html`, fetched 2026-11-04). A Fledge `.app` holds more than one executable (the launcher and `bin/ruby`, which ADR 026 says holds Fledge's code), so each needs the right pair. Whether the launcher's `execv` of itself (relaunch.c) is a child or a replacement of the same process is **(guess)** the latter, which needs no `inherit`.
- **App ID, Team ID, and a profile.** Tauri's guide says the app "must also set your App ID and Team ID in the code signing entitlements" and embed a "Mac App Store Connect" provisioning profile as `embedded.provisionprofile`, and that the `.pkg` needs "a Mac Installer Distribution signing certificate" (`v2.tauri.app/distribute/app-store/`, fetched 2026-11-04). Electron's guide lists the same certificates, "Apple Distribution" for the app, and says its standard build "will fail to launch when run under App Sandbox" (`electronjs.org/docs/latest/tutorial/mac-app-store-submission-guide`, fetched 2026-11-04).
- **An export declaration.** Tauri's guide says the app declares `ITSAppUsesNonExemptEncryption` in `Info.plist`. Ruby's OpenSSL makes that relevant.
- **A `.pkg` and an upload.** `productbuild` signs the `.pkg` (Tauri's guide); App Store Connect takes uploads from Xcode, Transporter, `altool`, and Xcode Cloud (`developer.apple.com/help/app-store-connect/manage-builds/upload-builds/`, fetched 2026-11-04). Guideline 2.4.5(ii) asks that apps "be packaged and submitted using technologies provided in Xcode; no third-party installers allowed", which Apple's `productbuild` and Transporter satisfy **(guess)**.

Entitlements Fledge signs with today need a second look:

- `disable-library-validation` is on so a gem's library that the app did not sign loads. Apple says library validation allows only libraries "signed by Apple or signed with the same Team ID as the main executable", and "Gatekeeper runs extra security checks on programs that have it disabled" ("Disable Library Validation Entitlement", JSON form, fetched 2026-11-04). Fledge signs every Mach-O file with one identity, so a store build could leave validation on **(guess)**. An Apple engineer, answering a developer of a sandboxed Electron app, recommends re-enabling it "unless you have specific reasons for disabling it" (`developer.apple.com/forums/thread/821584`, fetched 2026-11-04).
- `allow-unsigned-executable-memory` is for YJIT. Apple says `allow-jit` is the entitlement for `MAP_JIT` and that a program with `allow-unsigned-executable-memory` gains "common vulnerabilities in memory-unsafe code languages. Carefully consider whether your app needs this exception" (JSON forms of both pages, fetched 2026-11-04). Fledge's launcher starts Ruby without YJIT, so a store build can drop the entitlement unless the app turns YJIT on **(guess)**.
- One open risk for apps that do turn YJIT on: a sandboxed Electron app with these entitlements runs on macOS 15 and crashes on Apple silicon under macOS 26 in `mprotect` changes from read-write to read-execute, and Apple did not name a cause or a fix (`developer.apple.com/forums/thread/821584`, fetched 2026-11-04). Ruby's YJIT makes memory executable with `mprotect` (the entitlements file says so, citing `jit.c`).

Bundle layout is a second unknown. Apple says "Placing content in a nonstandard location can cause code signing and distribution problems" and that dynamic libraries belong in `Frameworks` and tools in a place Apple's rules name ("Embedding nonstandard code structures in a bundle", JSON form, fetched 2026-11-04). Fledge keeps Ruby's tree in `Resources` and links to it from `MacOS`. Nothing fetched says whether the Mac App Store's validation accepts that.

### Policy compatible?

On paper yes. 2.5.2 asks that apps "be self-contained in their bundles, and may not read or write data outside the designated container area, nor may they download, install, or execute code which introduces or changes features or functionality of the app". A Fledge app runs the Ruby it ships. 2.4.5(iv) bars downloading "additional code, or resources to add functionality or significantly change the app", so an app that runs `gem install` or `bundle install` when it starts would fail; `fledge build` already installs gems at build time. 2.4.5(vii) bars other update mechanisms. 2.4.5(ii) asks for "single app installation bundles" that "cannot install code or resources in shared locations".

What is unknown until a submission:

- A sandboxed Ruby program differs from `ruby main.rb`: it reads files only in its container or those the user picks, and needs `network.client` to reach the network. AGENTS.md's second rule says the app runs as under `ruby main.rb`, so a sandboxed build needs a justified entry in `Parity::JUSTIFIED` **(guess at the form)** and a README paragraph.
- Whether review flags the interpreter. The one Briefcase report found was a rejection under 2.5.2 for an app that "installed or launched executable code" through `itms-services`; the reporter removed binary utilities from dependencies and an `itms-services` string in `urllib` and the app was accepted (`github.com/beeware/briefcase/issues/1655`, fetched 2026-11-04).

### Cost and accounts

The Apple Developer Program costs "99 USD per membership year", with waivers for nonprofits, schools, and governments (`developer.apple.com/programs/whats-included/`, fetched 2026-11-04). Fledge cannot spend that; the developer enrolls.

### Prior art

Electron documents a Mac App Store path (above). Tauri documents one (above). Briefcase's way to the Mac App Store needs "Briefcase's macOS Xcode project packaging format", with the team set and the archive distributed from Xcode (`briefcase.beeware.org/en/latest/how-to/publishing/macOS/`, fetched 2026-11-04). A 2026 write-up about Tauri advises dropping the updater from the store build and notes that custom install steps cause rejections (`devwharf.com/2026/07/23/...`, a blog, fetched 2026-11-04).

### Smallest change, and whether it is worth it

A `pkg` value for `installers:` in `fledge.yml` for macOS (guess at the name), with these parts: a second entitlements file for the sandbox (app and helper variants), keys for the App ID prefix and a provisioning profile path, a build path that signs with the Apple Distribution identity, `productbuild --sign` with the installer identity, and no YJIT entitlement unless `fledge.yml` turns YJIT on. About 300 lines **(guess)**. It cannot be tested without a paid account and Apple's validator.

Worth doing: later, as a spike, after the iOS story, which needs the same account. The sandbox's effect on a Ruby program is the real work, not the packaging, and it deserves a decision from the maintainer on whether Fledge offers a mode that differs from `ruby main.rb`.

## Microsoft Store

### Two routes

Microsoft's guide to getting started lists two package types for a desktop program. It recommends MSIX: "complimentary binary hosting (provided by Microsoft), complementary code signing (provided by Microsoft)" (`learn.microsoft.com/en-us/windows/apps/publish/get-started`, fetched 2026-11-04). It also says "Microsoft Store has allowed unpackaged applications since June 2021" and takes a link to an `.msi` or `.exe` installer.

### Route 1: the setup program (MSI/EXE)

**Technically compatible today?** By the documents, yes. Policy 10.2.9 lists what a non-game product must meet (`learn.microsoft.com/en-us/windows/apps/publish/store-policies`, version 7.20, fetched 2026-11-04):

- "The installer binary may only be an .msi or .exe." Fledge writes an `.exe`.
- "The binary and all of its Portable Executable (PE) files must be digitally signed with a code signing certificate that chains up to a certificate issued by a Certificate Authority (CA) that is part of the Microsoft Trusted Root Program." `fledge build --sign THUMBPRINT` signs the program, the DLLs, and the setup program and uninstaller.
- "You must submit a versioned download URL in Partner Center. The binary associated with that URL must not change." This is the developer's.
- "Initiating the install must not display an installation user interface (i.e., silent install is required)". NSIS's `/S` does this, and the script makes no desktop shortcut when silent.
- "The installer is a standalone installer and is not a downloader stub." Fledge's setup program holds the whole app.

The certification page adds that the app "can be successfully installed when logged in with a standard user account", must "make an entry in the Windows Start menu and Programs list", and must "uninstall cleanly without leaving remnants" (`.../publish-your-app/msi/app-certification-process`, fetched 2026-11-04). The setup program is per-user, has a Start menu shortcut, and registers an uninstaller under `HKCU`. The Store does not sign this route: "If you submit an MSI or EXE installer, you must Authenticode-sign it yourself" (get-started page, FAQ 11).

**What Fledge lacks:** nothing in the file. Unknowns: whether a GitHub Release URL, which redirects to a download host, passes the "direct link" test **(guess that it may not)**, and the malware scan's verdict on a signed NSIS installer that holds a Ruby runtime.

**Policy.** 10.2.2 bars "dynamic inclusion of code" that "download[s] a remote script and subsequently execute[s] that script"; a Fledge app runs the Ruby it shipped. 10.2.9 says the product "may only be made available to PC devices".

**Cost.** "there are **no registration fees** for either account type" in the new onboarding flow, which starts at `storedeveloper.microsoft.com`; the page says other entry points "show the legacy flow" (`.../partner-center/open-a-developer-account`, updated 2026-10-29, fetched 2026-11-04). It does not say what the legacy flow charges. The developer still needs the certificate: Microsoft's table lists Azure Artifact Signing at "~$10/month" and an OV certificate at "$300-500/year" (`.../msix/package/signing-package-overview`, fetched 2026-11-04). Artifact Signing is open to organizations in the USA, Canada, the European Union, and the United Kingdom, and to individuals in the USA and Canada (same page). Fledge's `--sign` takes a thumbprint in the certificate store, so Artifact Signing, which signs through a `signtool` plugin, would need a check that Fledge's call accepts it **(guess that it does not today)**.

**Prior art.** None found for an interpreter on this route.

**Smallest change.** None to the artifact. Write a "publish to the Microsoft Store" section in the README and add a Delivery check that the setup program installs silently as a standard user and uninstalls cleanly. That is mostly done by the NSIS tests already **(guess)**. Worth doing now; it costs a paragraph.

### Route 2: MSIX

**Technically compatible today?** No. What Fledge lacks:

- **A package.** `MakeAppx.exe` is "included in the Windows 10 SDK" (`.../msix/package/create-app-package-with-makeappx-tool`, fetched 2026-11-04), which `lib/fledge/windows_signing.rb` already looks for to find `signtool`. A package is a folder with an `AppxManifest.xml` at its root, packed with `MakeAppx pack /d FOLDER /p NAME.msix`. Fledge would write the manifest, tile images from the icon, and the identity keys.
- **Store identity.** The name, publisher, and publisher display name come from Partner Center. `fledge.yml` has no place for them.
- **`runFullTrust`.** A medium-integrity app "needs to declare the **runFullTrust** restricted capability" (`.../package-and-deploy/app-capability-declarations`, updated 2026-10-02, fetched 2026-11-04). Whether the Store asks for approval of it for a desktop program is not settled by what I fetched. Electron's tooling adds it automatically, per a search summary that I did not confirm against a page.
- **A launcher change.** Microsoft's packaging guide says a packaged app "may only use the AUMID generated for it", and "You can't define custom AUMIDs" (`.../msix/desktop/desktop-to-uwp-prepare`, fetched 2026-11-04). Fledge's Windows launcher sets a custom AppUserModelID before any window opens (`runtime/launcher/windows.c`). It would have to skip that when it runs from a package.
- **Writes to the install folder.** The same guide: "Your application writes to the install directory for your app... This isn't supported". Whether Ruby, Bundler, or a gem writes there depends on the app **(guess)**; the Package Support Framework is Microsoft's workaround.
- **Other items in that guide.** Packaged apps cannot hold a user service or driver, and apps that start "a utility to perform tasks" or write "generated code to disk" can fail Windows 10 S compatibility, which the Store requires. A Ruby app that runs `system` or writes `.rb` files to disk may hit these **(guess)**.

**Policy.** The same 10.2.2 as route 1. The MSIX certification page was not fetched; I did not read the Store's MSIX tests.

**Cost.** No registration fee. The Store re-signs the package, so the developer buys no certificate: "the Microsoft Store automatically re-signs your package with a Microsoft certificate during the publishing process" (get-started FAQ 11). The Store also hosts the download. The fee for Microsoft's commerce platform is 15 percent for apps and 12 for games; a developer can use another platform and keep all revenue for non-game apps (same page).

**Prior art.** PEP 773 says the Python install manager "will be distributed both in the Windows Store and on python.org as an MSIX package", and the two differ only in signing (`peps.python.org/pep-0773/`, fetched 2026-11-04). electron-builder has `appx` and `msix` targets (`electron.build/docs/msix/`, seen in search results; page not fetched). Tauri has no MSIX bundler; Microsoft's `winapp` CLI and a community tool make one (search results; not fetched).

**Smallest change.** An `msix` value for `installers:` on Windows: write the manifest, call `makeappx pack`, skip signing (the Store signs; a sideload build needs `--sign`), add three `fledge.yml` keys for the Store identity, and make the launcher skip its AppUserModelID call when `GetCurrentPackageFullName` says it is packaged **(guess at the API name; I did not fetch it)**. About 250 lines of Ruby and 20 of C **(guess)**.

Worth doing: yes, after route 1 is written up. It removes the only recurring cost the other routes carry, the code signing certificate, and Microsoft hosts the download. Test it by installing the package with `Add-AppxPackage` on a Windows runner **(guess)**.

## iOS and iPadOS App Store

### Technically compatible today?

By the documents, yes, and for a reason the other stores lack: the design already follows Apple's rule. ADR 022 links native gems into the app's executable because Apple leaves "an app no code it did not ship". CPython's iOS guide says "The iOS App Store requires that _all_ binary modules in an iOS app must be dynamic libraries, contained in a framework... and there can be no executable binary material outside the `Frameworks` folder", and Kivy avoids it by merging "the app binary with all the libraries into a single binary, called libpython", so "nothing is dynamically loaded" (`docs.python.org/3/using/ios.html` and `kivy.org/doc/stable/guide/packaging-ios.html`, fetched 2026-11-04). Fledge's iOS runtime links statically. I extracted the cached iOS runtime (0.1.0) and found no `.so`, `.dylib`, or `.bundle` files in it.

Items I could not settle:

- The runtime's gem folders hold shell scripts with the executable bit (`rake`, `rdoc`, `irb`, `rdbg`). CPython's guide says "no executable binary material outside the `Frameworks` folder". Scripts are not binary, but Apple's scan is a black box **(guess that they pass)**. A `cleanup` of `exe/` and `bin/` folders from the copied runtime would remove the doubt. Briefcase's iOS reference tells developers to "purge any binary content from your app before submission" (`briefcase.beeware.org/en/stable/reference/platforms/iOS/xcode.html`, fetched 2026-11-04).
- Briefcase issue 1655 (above) was a macOS app, and the trigger was an `itms-services` string in `urllib`. I searched the extracted iOS runtime for that string and found none, which says nothing about later Ruby or gem versions.
- Apple's third-party SDK list names OpenSSL, and says the requirement covers "any SDKs that repackage those", needing a privacy manifest and, for binary dependencies, a signature (`developer.apple.com/support/third-party-SDK-requirements/`, fetched 2026-11-04). Ruby's OpenSSL extension links OpenSSL statically into the app. Whether the scanner treats that as a listed SDK is **(guess)** unknown. CPython's guide documents a privacy manifest for OpenSSL.
- The template's `PrivacyInfo.xcprivacy` lists two required-reason categories. Fledge's CI compares the list with the executable's imports, per the file's comment.

### Policy compatible?

2.5.2: apps "should be self-contained in their bundles... nor may they download, install, or execute code which introduces or changes features". The license agreement, 3.3.1(B): "an Application may not download or install executable code. Interpreted code may be downloaded to an Application but only so long as such code: (a) does not change the primary purpose of the Application... (b) does not bypass signing, sandbox, or other security features of the OS; and (c)... does not create a store or storefront for other Applications" (`developer.apple.com/support/terms/apple-developer-program-license-agreement/`, fetched 2026-11-04; no agreement date shown). Fledge's Ruby ships in the bundle, so it never reaches the "downloaded" case. Guideline 4.7 is about downloaded mini apps and emulators and does not mention interpreters.

4.2.6, "Apps created from a commercialized template or app generation service will be rejected unless they are submitted directly by the provider of the app's content", is why ADR 012 has the developer submit. Fledge writes a project and does not submit anything, so it is not the "service" in that sentence **(guess)**.

4.2, minimum functionality, rejects "a repackaged website"; whether a Ruby app has enough UI is the developer's matter.

### Cost and accounts

US$99 a year (above). Fledge cannot enroll. ADR 012 already records that the maintainer will get an account "at the last responsible moment".

### Prior art

RubySketch is a free iPhone and iPad app by Noritaka Suzuki whose description says it "includes Ruby language interpreter known as CRuby or MRI", on the store since version 1.1 of 12/02/2020 (`apps.apple.com/us/app/rubysketch-fun-w-processing/id1491477639`, fetched 2026-11-04). It builds CRuby into an XCFramework with `xord/cruby`, the project ADR 011 names. RubyMotion apps ship too, but RubyMotion compiles Ruby and does not interpret it (its FAQ, per search results; not fetched). CPython documents the App Store path in PEP 730 terms (above), and Kivy answers "Yes, absolutely" to whether anyone has submitted a Kivy app.

### Smallest change, and whether it is worth it

Nothing in the project must change for a first submission. Worth adding, once an account exists: a CI step that runs `xcodebuild archive` for a device without signing and lists non-code executables in the archive, and a short "publish" section in the README with the exact `xcodebuild -exportArchive` and Transporter steps. Delete the scripts under the copied gems' `exe/` and `bin/` folders if the first validation complains. This is the story Plan 003 already has ("iOS on a real device, and App Review"); this research adds only the OpenSSL and shell-script unknowns to its list.

## Google Play

### Technically compatible today?

By the documents, yes. Each current rule has an answer in the template:

- **Target API.** "Starting August 31 2026: New apps and app updates must target Android 16 (API level 36) or higher" (`developer.android.com/google/play/requirements/target-sdk`, fetched 2026-11-04). The template targets 36.
- **16 KB pages.** "all apps targeting Android 15 (API level 35) and higher must support 16 KB memory page sizes on 64-bit devices on Google Play. Starting February 1, 2027, if your app updates don't support 16 KB memory page sizes, you won't be able to release these updates" (`developer.android.com/guide/practices/page-sizes`, fetched 2026-11-04). That page asks for AGP 8.5.1 or newer, uncompressed shared libraries, and ELF segments at 16 KB alignment. The template sets `useLegacyPackaging = false` and the runtime links with `-Wl,-z,max-page-size=16384`. `tasks/mobile_parity/android.rb` already runs `zipalign -c -P 16 -v 4` on the built APK and checks with `aapt2 dump badging` that it targets API 36 from API 26. It does not run Google's `check_elf_alignment.sh` or look at an `.aab`.
- **App Bundle.** "From August 2021, new apps are required to publish with the Android App Bundle" (`developer.android.com/guide/app-bundle`, fetched 2026-11-04). The template is a standard application module, so `./gradlew bundleRelease` should produce one. No Fledge test builds an `.aab` **(guess)**.
- **Signing.** The `.aab` is signed with the developer's upload key; Google re-signs for users. The template leaves signing to the developer.

### Policy compatible?

The Device and Network Abuse policy says "an app may not download executable code (such as dex, JAR, .so files) from a source other than Google Play", and that "Apps or third-party code, like SDKs, with interpreted languages (JavaScript, Python, Lua, etc.) loaded at run time must not allow potential violations of Google Play policies" (`support.google.com/googleplay/android-developer/answer/9888379`, fetched 2026-11-04; the fetch tool paraphrased the second sentence, so treat its exact wording as unverified). A Fledge app downloads nothing; its Ruby and gems come from the `.aab`. The second sentence is the one a reviewer could cite against an app whose Ruby code evaluates text it fetches at run time, which is the developer's choice.

Unknown until a submission: review, the testing rules for new personal accounts (the Play Console help page says personal accounts "must meet app testing requirements" and links the details, which I did not fetch), and the first-launch unpack of `fledge.zip` into app storage on a device with little space.

### Cost and accounts

"There is a US$25 one-time registration fee" (`support.google.com/googleplay/android-developer/answer/6112435`, fetched 2026-11-04), and Briefcase's guide says the same (`briefcase.beeware.org/en/latest/how-to/publishing/android/`, fetched 2026-11-04). Verifying an Android device is also a step (same Google page).

### Prior art

Briefcase's Android backend makes `.aab` the default output and lists the Play steps (above, and `.../reference/platforms/android/gradle.html`, fetched 2026-11-04). Its `version_code` "*must* increase with every new release pushed to the Play Store"; Fledge's `versionCode` rule (ADR 012) does that.

### Smallest change, and whether it is worth it

Extend the Android parity task: run `./gradlew bundleRelease` on the hello project and check `bundletool dump config` for `PAGE_ALIGNMENT_16K` (the page above gives this command). The APK checks exist. About 20 lines **(guess)**. Worth doing now: it needs no account and proves the format Play requires.

## Linux

### Flathub

**Compatible?** No, for a Fledge-built app. Flathub says "All source available submissions must be built entirely from source code", "Binary or precompiled files must not be present in the submission pull request", and "There is no network access during the build process" (`docs.flathub.org/docs/for-app-authors/requirements`, fetched 2026-11-04). The exception text reads: "Exceptions may be granted to well-known vendors on a case-by-case basis", and "the use of niche tooling or uncommon build setups may not constitute grounds for an exception". A Fledge app is a copy of the program inside a prebuilt runtime, the opposite of building from source.

A source-built Flatpak of a Ruby app is possible: Flatpak's `archive` sources take a URL and `sha256`, and the `simple` build system runs commands (`docs.flatpak.org/en/latest/manifests.html`, fetched 2026-11-04). The tool that turns a Gemfile into sources, `flatpak-builder-tools/rubygems`, says "This is not actively maintained" (README, fetched 2026-11-04). The app would also build Ruby itself, so a Flatpak of a Fledge app is a different build, not a Fledge output.

Other Flathub rules a submission meets: an application ID of at least three components that matches the metainfo (Fledge's identifier is reverse-DNS, ADR 008); a validated metainfo file; minimal static permissions with portals preferred; verification by domain ownership (`.../for-app-authors/verification`, fetched 2026-11-04). Fledge writes no metainfo file today.

**Tauri's guide** builds its Flatpak from a prebuilt `.deb` at a release URL (`v2.tauri.app/distribute/flatpak/`, fetched 2026-11-04). The page "does not state specific Flathub acceptance criteria", so it neither supports nor contradicts the Flathub rule above.

**A repository the developer hosts** needs no review. Flatpak's documents say the generated repository "can be hosted on a web server", with a `.flatpakrepo` file carrying the GPG key, and describe GitLab Pages as a free host (`docs.flatpak.org/en/latest/hosting-a-repository.html`, fetched 2026-11-04). The default sandbox gives no host files and no network (`.../sandbox-permissions.html`, fetched 2026-11-04), so a Fledge app that reads the user's files needs `--filesystem` or portals, a differing behavior as on the Mac App Store.

**Cost.** None found; Flathub's pages I read list no fee.

**Smallest change.** Not worth it before 1.0. A Flatpak made from the built folder (a manifest with a `dir` source and a `sha256`-pinned archive) would serve the developer-hosted repository, and Fledge would write the manifest and `flatpak-builder` would run it. About 150 lines **(guess)**. Do it only if a developer asks. Flathub itself is not a Fledge feature, because the build-from-source rule excludes Fledge's output.

### Snap Store

**Compatible?** Plausible, not checked by any source for Ruby. Snap's strict confinement means "Strictly confined snaps run in complete isolation, up to a minimal access level that's deemed always safe", and access to files or the network needs an interface; classic confinement "requires manual approval" (`ubuntu.com/docs/snapcraft/stable/explanation/security/snap-confinement/`, fetched 2026-11-04). Classic review lists categories, among them "Programming languages" and "running arbitrary command" as a criterion; a Fledge app is not an interpreter, so it should use strict confinement (`snapcraft.io/docs/reference/administration/reviewing-classic-confinement-snaps/`, fetched 2026-11-04). Tauri's guide builds a strict snap with the `dump` plugin from a `.deb` (`v2.tauri.app/distribute/snapcraft/`, fetched 2026-11-04). Snaps are built by the developer and uploaded, so a prebuilt Fledge folder fits; the Snap Store does not require a source build in what I read, though I fetched no page that says so.

Names are registered with `snapcraft register` and are unique and permanent ("can't be changed after registration"); the page does not say whether registering costs money (`ubuntu.com/docs/snapcraft/stable/how-to/publishing/register-a-snap/`, fetched 2026-11-04).

The glibc floor in ADR 029 is 2.39, the same as Ubuntu 24.04's, which is `core24`'s base **(guess; I did not fetch the base's glibc version)**.

**Smallest change.** A `snapcraft.yaml` generator: `base: core24`, `confinement: strict`, a `dump` part that copies the built folder, the `home` and `network` plugs, and an `apps:` entry for the launcher. About 80 lines **(guess)**. A reasonable post-1.0 story; first try it by hand to see whether the launcher's relocation survives the snap's read-only mount.

### Debian and Ubuntu archives

**Compatible?** No, by policy. Debian's main archive requires that "Every package in main must comply with the DFSG" (Policy 2.2.1, `debian.org/doc/debian-policy/ch-archive.html`, fetched 2026-11-04), and DFSG 2 reads "The program must include source code" (`debian.org/social_contract`, fetched 2026-11-04). Policy 4.13 says "Debian packages should not make use of these convenience copies unless the included package is explicitly intended to be used in this way" (`.../ch-source.html`, fetched 2026-11-04), which excludes a package that bundles a copy of Ruby. Launchpad PPAs take "Source packages only; pre-built binary uploads are rejected" (`ubuntu.com/docs/launchpad/user/reference/packaging/ppas/ppa/`, fetched 2026-11-04). Fledge's `.deb` is a prebuilt binary package.

Fledge also could not become a Debian package of the app by itself: Debian would need to package Ruby, each gem, and the app, all from source. That is Debian's Ruby team's work, not a tool Fledge could provide.

**A repository the developer hosts** takes the `.deb` as is. Debian's wiki says to put the key in `/usr/share/keyrings/`, add a `.sources` file, and set `Signed-By`, and lists `reprepro` and `aptly` as repository tools (`wiki.debian.org/DebianRepository/UseThirdParty` and `/Setup`, fetched 2026-11-04). The wiki warns "If you do not trust the maintainers of a 3rd party repository, you should not enable it", since a package can run maintainer scripts as root; Fledge's `.deb` carries none **(guess; I did not check `lib/fledge/deb.rb` for scripts)**.

**Smallest change.** A README section on hosting the `.deb` in an apt repository with `reprepro` or `aptly`. No code. Worth doing when the `.deb` is documented for 1.0.

### Fedora

I could not fetch Fedora's Packaging Guidelines or licensing pages (the site returned an access-denied page to the fetch tool). The one page that loaded, the wiki's "Bundled Libraries", says only to "Follow the Bundling and Duplication of system libraries section of the Packaging Guidelines" (`fedoraproject.org/wiki/Bundled_Libraries`, fetched 2026-11-04). This research says nothing else about Fedora. A search summary says Fedora builds from source and forbids prebuilt binaries in packages; I did not confirm it from a page.

## The five findings that matter most

1. **The iOS and Android projects already follow the stores' rules.** Native code is static on iOS, and the Android parity task checks 16 KB alignment and API 36 on the APK. What no gate builds is the `.aab` Play requires, or the archive App Store Connect takes. Both checks are cheap and need no account.
2. **The Microsoft Store's EXE route fits the setup program Fledge writes today.** Policy 10.2.9 asks for a signed, silent, standalone `.exe` at a versioned HTTPS URL, and the NSIS script already is that. The developer still needs a trusted certificate.
3. **MSIX would remove the certificate and the hosting**, and costs one launcher change: the custom AppUserModelID that `windows.c` sets is not allowed in a package.
4. **The Mac App Store is a different program, not a different file.** The sandbox changes what a Ruby app may read, run, and write, which AGENTS.md's second design rule treats as a parity difference. It also puts the `allow-unsigned-executable-memory` entitlement in doubt, and an Apple forum thread reports sandboxed `mprotect` JIT crashes on macOS 26.
5. **Flathub, Debian, Ubuntu's PPAs, and possibly Fedora refuse prebuilt output by rule.** Only Snap, a Flatpak repository, and an apt repository the developer hosts take what Fledge builds.

## Proposed Plan 003 stories

These are proposals; `plan/003.md` is unchanged. Each says which part of the plan it touches.

1. **Publish checks for Android and iOS** (1.0, no money). In the Android parity task, which already checks the APK, build an `.aab` and check `PAGE_ALIGNMENT_16K`. On the iOS job, archive for a device without signing and list executables outside the main binary. Add the OpenSSL and shell-script unknowns to the existing "iOS on a real device, and App Review" story as things to look at in the first validation. Reason: the one format Play requires, and one Apple scan.
2. **Publishing to the Microsoft Store from the setup program** (1.0). A README section: what the Store checks, how to host the installer, how to sign it. Check that Fledge's `--sign` accepts Azure Artifact Signing, or say that it does not. Reason: a paragraph and one check make a store reachable.
3. **An MSIX installer** (maybe 1.0, or after). `installers: [msix]` on Windows, three `fledge.yml` keys for the Store identity, and a launcher that skips its AppUserModelID call in a package. Reason: it is the only route that needs no certificate.
4. **A Mac App Store package** (after 1.0, waits on money and a decision). First a spike, with an Apple Developer account: run a hello app in the sandbox, with and without YJIT, on macOS 15 and 26. Then, if the maintainer accepts a sandboxed mode that differs from `ruby main.rb`, `installers: [pkg]`. Add a question to `questions.md` about the sandboxed mode when this story starts (kind 1: it touches the second design rule).
5. **Linux channels** (after 1.0). A README section on hosting the `.deb` in an apt repository. A `snapcraft.yaml` generator tried by hand first. Flatpak only for a developer-hosted repository, if asked. Record in an ADR that Fledge does not target Flathub or distribution archives, and why (build-from-source rules).
