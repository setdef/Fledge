# Signing

This part signs a desktop app's code with the developer's identity, and on macOS has Apple notarize it. It holds no keys: it runs the system's signing tool, or the developer's own command, and passes it only names.

## The pieces

| Piece | Role |
| - | - |
| `Signing.for` | picks the signer for a platform from the CLI's options: `MacSigning`, `WindowsSigning`, `SignCommand`, or none, and refuses an option the platform can't use |
| `MacSigning` | runs `codesign` with the hardened runtime, a timestamp, and `templates/macos/entitlements.plist`; signs folders, bundles, and disk images |
| `Notary` | submits to Apple's notary service with `notarytool`, waits, reports Apple's issues, and staples |
| `WindowsSigning` | runs the Windows SDK's `signtool` with a certificate thumbprint, SHA-256, and a timestamp |
| `SignCommand` | runs the developer's command once per file, with the path in place of `%1` |
| `WindowsSdk` | finds an SDK tool on `PATH` or in the newest installed Windows SDK |
| `Signing.code_files` | finds the files to sign by their first bytes, not their names |

## Where signing comes in the build

Signing seals files, so it comes after everything that changes them, and before everything that packs them:

1. **The app folder.** Assembly signs once every file is in place: every Mach-O file that isn't an object file on macOS; every PE `.exe`, `.dll`, and `.so` on Windows. Files are signed in batches, in a stable order.
2. **The Mac bundle.** `MacBundle#finish` signs the bundle's resources, then the console programs it holds, then the bundle itself with the app's identifier. With no identity, it signs the bundle ad hoc.
3. **The installers.** The disk image is signed after `hdiutil` writes it. NSIS signs the uninstaller and then the setup program as it writes them, through `!uninstfinalize` and `!finalize` lines that run the signer's command line. An MSIX package is signed after `makeappx` packs it.
4. **Notarizing,** after the installers and before the archive: the disk image, or else the bundle, or else the folder, zipped with `ditto`. Stapling changes the bundle and the image, so the archive packs the stapled ones.

Because every app's specifics are in `fledge.cfg`, the launcher compiles nothing of one app in (ADR 001): what signing seals is the runtime's launcher, renamed, with, on Windows, the version resources and icon rcedit wrote.

## Retries

Apple's timestamp service and `hdiutil` fail now and then for reasons outside the build. `MacSigning` retries `codesign` after 5, 10, 20, and 40 seconds when its output reports a timestamp failure, and nothing else. Every other failure fails the build at once, with the tool's words.

## Traps

- **Credentials never reach a command line.** `--notarize` takes a keychain profile's name; the credentials stay in the keychain. A Windows identity is a certificate's thumbprint in the store. Anything else would show in the process list.
- **An ad hoc signature takes no timestamp,** and Apple notarizes no ad hoc signature, so `Signing.for` refuses `--notarize` with `--sign -`.
- **NSIS must quote the signing command.** `Nsis::Script` picks a quote character the command doesn't contain, and refuses a command that contains all three.
- **The Microsoft Store signs Store packages.** An MSIX signed by Fledge never carries the unsigned OID; one left unsigned does unless `fledge.kdl` says not to, since its publisher must then match Partner Center's exactly.

## What this part doesn't do

- Sign Linux apps, which their systems don't check.
- Sign phone apps: Xcode and Gradle sign the projects Fledge writes.
- Store, create, or renew certificates.
