<!--
SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>

SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Signing and Notarizing With Real Credentials: the First Run

Use this page the first time you sign Fledge's example apps with setdef's own Apple and Windows credentials. CI proves every step against stand-ins and a self-signed certificate (`doc/contributors/design/signing.md`, "What CI proves, and the stand-ins"), but only your credentials prove what Apple's notary service, Gatekeeper, and SmartScreen make of the result. Each step says what to click or type, where, what it does, and what you should see. When what you see differs, stop and keep the output: it is the finding.

Nothing here puts a credential anywhere but your own keychain or certificate store. Fledge reads none of them. Do not paste a key, password, or token into an issue, a commit, or a chat with an agent; the outputs below hold none.

The macOS part takes about an hour the first time, most of it waiting for Apple. The Windows part depends on which kind of certificate you buy.

## Before you start

On the Mac:

1. setdef's Apple Developer Program enrollment is approved, and you are the team's Account Holder or an Admin. Only they can make a Developer ID certificate.
2. Xcode is installed. Open Terminal and type `xcrun notarytool --version`. You should see a version, such as `1.1.4 (43)`.
3. You have a checkout of the `signing-ready` branch (or of `trunk`, once it is merged). In Terminal, in that folder, type `bundle install`.

Type every command below in Terminal, in the checkout's folder, unless a step says otherwise.

## Part 1: macOS

### 1. Make the Developer ID Application certificate (once)

This makes a private key in your login keychain and has Apple issue a certificate for it, which together are the identity `codesign` signs with.

1. Open Xcode. In the menu bar, choose **Xcode > Settings…** (or press ⌘,).
2. Click the **Accounts** tab.
3. If your Apple ID is not in the list on the left, click **+** at the bottom of the list, choose **Apple ID**, click **Continue**, and sign in.
4. Select your Apple ID on the left. On the right, under **Team**, select setdef's team (not your Personal Team).
5. Click **Manage Certificates…**.
6. Click **+** at the bottom left of the sheet, and choose **Developer ID Application**. If it is greyed out, your role on the team cannot make one; the Account Holder can.
7. A new row appears under **Developer ID Application Certificates**, with your name and today's date. Click **Done**.

Check it. Type:

```console
$ security find-identity -v -p codesigning
```

You should see a line such as:

```
  1) 0123456789ABCDEF0123456789ABCDEF01234567 "Developer ID Application: setdef (ABCDE12345)"
```

The text in quotes is your **identity**, and the ten characters in parentheses are your **Team ID**. Copy both somewhere handy. If the line is missing, the certificate is not in the login keychain: open **Keychain Access**, choose **login** on the left and **My Certificates** at the top, and look for it.

Back up the key: in Keychain Access, under **My Certificates**, right-click **Developer ID Application: setdef (…)**, choose **Export…**, and save a `.p12` with a strong password somewhere safe and offline. Apple lets a team make only a few Developer ID certificates, and a lost key cannot be recovered.

### 2. Store notarization credentials in a keychain profile (once)

notarytool keeps your Apple credentials in the keychain under a profile name, which you then hand to Fledge with `--notarize`. Use one of the two ways below. This page calls the profile `fledge-notary`; any name works.

**A. With an App Store Connect API key (best for later automation).**

1. In a browser, go to [App Store Connect](https://appstoreconnect.apple.com/) and sign in.
2. Click **Users and Access**, then the **Integrations** tab, then **App Store Connect API** on the left. (If you see **Request Access**, click it and accept the terms; only the Account Holder can.)
3. Under **Team Keys**, click **+** (or **Generate API Key**).
4. For **Name**, type `Fledge notarization`. For **Access**, choose **Developer**. Click **Generate**.
5. In the new row, click **Download**. You can download the file only once. Save it as `~/private_keys/AuthKey_KEYID.p8`, where KEYID is the **Key ID** shown in the row.
6. Copy the **Issuer ID**, the UUID shown above the list of keys.

Then type, with your own values:

```console
$ xcrun notarytool store-credentials fledge-notary --key ~/private_keys/AuthKey_KEYID.p8 --key-id KEYID --issuer ISSUER-ID
```

**B. With your Apple ID and an app-specific password.**

1. In a browser, go to [account.apple.com](https://account.apple.com/), sign in, and open **Sign-In and Security > App-Specific Passwords**.
2. Click **+** (or **Generate an app-specific password**), type `Fledge notarization` as its name, and copy the password it shows.

Then type, with your Apple ID and Team ID; notarytool asks for the password, which you paste:

```console
$ xcrun notarytool store-credentials fledge-notary --apple-id you@example.com --team-id ABCDE12345
```

Either way, notarytool checks the credentials with Apple and saves them. You should see:

```
Validating your credentials...
Success. Credentials validated.
Credentials saved to Keychain.
To use them, specify `--keychain-profile "fledge-notary"`
```

Check it: `xcrun notarytool history --keychain-profile fledge-notary` should print an empty history, not an error.

### 3. Build, sign, and notarize `examples/windowed_app`

Type, with your identity from step 1:

```console
$ bundle exec fledge build --sign "Developer ID Application: setdef (ABCDE12345)" --notarize fledge-notary examples/windowed_app
```

What happens: Fledge downloads its runtime the first time, builds the app, signs every program and library with the hardened runtime and a timestamp, then the bundle, then the disk image; sends the disk image to Apple and waits; staples Apple's ticket to the disk image and the bundle; and packs the archive. macOS may ask once whether `codesign` may use the key "Developer ID Application: setdef": click **Always Allow** and type your login password.

On the error stream you should see, after any download line:

```
Notarizing Hello Window-arm64-darwin.dmg with Apple's notary service, with the keychain profile fledge-notary; this takes minutes
Apple accepted Hello Window-arm64-darwin.dmg (submission 2efe2717-…)
Stapling Apple's ticket to Hello Window-arm64-darwin.dmg
Stapling Apple's ticket to Hello Window.app
```

and on the output stream:

```
dist/Hello Window-arm64-darwin.tar.gz
dist/Hello Window-arm64-darwin.dmg
```

The wait is usually under 15 minutes. If the build fails with "Apple did not notarize", the lines after it are Apple's issues, file by file; keep them, and the whole log, which `xcrun notarytool log ID --keychain-profile fledge-notary` prints. If it fails with "notarytool could not notarize", the words after it are notarytool's (a profile it cannot find, no network).

Then build the console app, which Fledge notarizes as a zip of its folder and does not staple, since Apple cannot staple a lone program:

```console
$ bundle exec fledge build --sign "Developer ID Application: setdef (ABCDE12345)" --notarize fledge-notary examples/hello
```

You should see "Notarizing Hello-arm64-darwin.zip" and "Apple accepted Hello-arm64-darwin.zip", and no stapling line.

### 4. Check the result on this Mac

Each of these should succeed. Type:

```console
$ xcrun stapler validate "dist/Hello Window-arm64-darwin.dmg"
$ xcrun stapler validate "dist/Hello Window-arm64-darwin/Hello Window.app"
```

Each should end with `The validate action worked!`. Then ask Gatekeeper:

```console
$ spctl --assess --type open --context context:primary-signature -vv "dist/Hello Window-arm64-darwin.dmg"
$ spctl --assess --type execute -vv "dist/Hello Window-arm64-darwin/Hello Window.app"
```

Each should say `accepted`, then `source=Notarized Developer ID`, then `origin=Developer ID Application: setdef (ABCDE12345)`. `source=Developer ID` without "Notarized" means Apple's ticket was not found.

Then run Fledge's own contract test, which does the same with a fresh build. The runtime is the one step 3 downloaded:

```console
$ FLEDGE_TEST_SIGN_IDENTITY="Developer ID Application: setdef (ABCDE12345)" FLEDGE_TEST_NOTARY_PROFILE=fledge-notary FLEDGE_RUNTIME_DIR=~/.cache/fledge/runtimes bundle exec rake test:integration N=/gatekeepers_blessing/
```

You should see `1 runs, … 0 failures, 0 errors, 0 skips` among the counts (the other tests are filtered out, not run). A skip means a variable above is empty.

### 5. Open it as someone who downloaded it

Gatekeeper judges only files a browser or another app marked as downloaded (with the `com.apple.quarantine` attribute). The truest test is a real download on another Mac, or at least another user account, that has never run the app:

1. Put `dist/Hello Window-arm64-darwin.dmg` somewhere a browser can download it, such as a draft release in a scratch GitHub repository of your own, or a file-sharing link.
2. On the other Mac, download it with Safari. In Finder, open **Downloads** and double-click the `.dmg`.
3. The disk image opens with no warning. Drag **Hello Window** onto **Applications**, then open **Applications** and double-click **Hello Window**.
4. macOS asks once: "“Hello Window” is an app downloaded from the Internet. Are you sure you want to open it?", naming Safari and the date, with **Open**. That is Gatekeeper's prompt for a notarized app. Click **Open**: a window opens. What should not appear is "Apple could not verify…" or "cannot be opened because the developer cannot be verified", the warnings for an app that is not notarized.

To try it offline, turn Wi-Fi off before step 2's double-click: the stapled ticket should be enough.

Without a second Mac, you can mark a copy as downloaded yourself, which tests Gatekeeper but not a browser:

```console
$ cp "dist/Hello Window-arm64-darwin.dmg" /tmp/
$ xattr -w com.apple.quarantine "0083;$(printf %x $(date +%s));Safari;" "/tmp/Hello Window-arm64-darwin.dmg"
$ open "/tmp/Hello Window-arm64-darwin.dmg"
```

### 6. Optional: does YJIT need its entitlement under a Developer ID?

Fledge grants every Mac app `com.apple.security.cs.allow-unsigned-executable-memory`, which Apple names for memory YJIT makes, though CI's self-signed builds showed YJIT working without it (ADR 050). This step answers whether a Developer ID needs it. Entitlements belong to the program a process runs, the bundle's own (Apple's "Hardened Runtime" page), so it signs a copy of the bundle again without them; never ship that copy.

```console
$ cp -R "dist/Hello Window-arm64-darwin" /tmp/no-entitlements
$ codesign --force --sign "Developer ID Application: setdef (ABCDE12345)" --options runtime --timestamp "/tmp/no-entitlements/Hello Window.app"
$ codesign --display --entitlements - "/tmp/no-entitlements/Hello Window.app"
$ "/tmp/no-entitlements/Hello Window.app/Contents/MacOS/Hello Window" /tmp/report.json 0; echo "exit $?"
$ grep -o '"yjit":[a-z]*' /tmp/report.json
```

The third command should print the program's path and no entitlements. The fourth should print `exit 0`. The last prints `"yjit":true` when YJIT wrote machine code without the entitlement, and `"yjit":false` (or the fourth crashes) when it needs it. Either answer goes in ADR 050.

## Part 2: Windows

Fledge signs a Windows app one of two ways:

- `--sign THUMBPRINT`, for a certificate in Windows' certificate store, including one on a USB token whose driver puts it there. Fledge runs signtool with SHA-256 and DigiCert's timestamp.
- `--sign-command COMMAND`, for a certificate in a cloud or hardware service with its own tool. Fledge runs COMMAND once for each program and library, then for the uninstaller and the setup program, with `%1` replaced by the file's path in quotes. To keep a command with secrets out of your shell history, set `FLEDGE_SIGN_COMMAND` instead, or put the command in a `.cmd` file that reads its secrets from environment variables and pass that file as COMMAND.

### Before you start

1. A Windows 10 or 11 computer, with Git, Ruby 4.0 from [RubyInstaller](https://rubyinstaller.org/) with its MSYS2 toolchain, and a checkout of the `signing-ready` branch. In PowerShell, in the checkout, type `bundle install`.
2. The Windows SDK's signtool: `winget install Microsoft.WindowsSDK.10.0.26100`. Find it with `Get-ChildItem "${env:ProgramFiles(x86)}\Windows Kits\10\bin" -Recurse -Filter signtool.exe | Where-Object { $_.Directory.Name -eq 'x64' }` (or `arm64` on an ARM computer). This page calls its full path SIGNTOOL.

Type every command below in PowerShell, in the checkout's folder.

### 3a. A certificate in the certificate store (a `.pfx` file, or a token)

1. For a `.pfx`, double-click it, choose **Current User**, click **Next** twice, type its password, leave **Automatically select the certificate store** chosen, and click **Finish**. For a token, plug it in and install its vendor's driver (SafeNet Authentication Client for most).
2. Find its thumbprint: `Get-ChildItem Cert:\CurrentUser\My -CodeSigningCert | Format-List Subject, Thumbprint, NotAfter`. Copy the 40 hexadecimal digits of the right one.
3. Build: `bundle exec fledge build --sign THUMBPRINT examples/windowed_app`. A token may ask for its PIN once for each file; its vendor's client can be set to ask once per session.

### 3b. Azure Artifact Signing (formerly Trusted Signing)

Microsoft's guide is [Set up signing integrations to use Artifact Signing](https://learn.microsoft.com/azure/artifact-signing/how-to-signing-integrations).

1. In the Azure portal, have an Artifact Signing account, a validated identity, and a certificate profile, and give yourself the **Artifact Signing Certificate Profile Signer** role on it.
2. Install Microsoft's client tools, which bring the signtool plug-in: `winget install -e --id Microsoft.Azure.ArtifactSigningClientTools`. Find the plug-in with `Get-ChildItem -Recurse -Filter Azure.CodeSigning.Dlib.dll "$env:ProgramFiles", "${env:ProgramFiles(x86)}", "$env:LOCALAPPDATA" -ErrorAction SilentlyContinue`, and use the one under `x64` (or `arm64`). This page calls its full path DLIB.
3. Make `C:\ArtifactSigning\metadata.json`, with your account's region endpoint (Microsoft's guide lists them), account name, and profile name:

   ```json
   {
     "Endpoint": "https://eus.codesigning.azure.net",
     "CodeSigningAccountName": "setdef-signing",
     "CertificateProfileName": "setdef-public"
   }
   ```

4. Sign in to Azure so the plug-in can get a token: install the Azure CLI (`winget install -e --id Microsoft.AzureCLI`), open a new PowerShell, and type `az login`.
5. Build, with your paths in place of SIGNTOOL and DLIB:

   ```powershell
   bundle exec fledge build --sign-command '"SIGNTOOL" sign /v /fd SHA256 /tr http://timestamp.acs.microsoft.com /td SHA256 /dlib "DLIB" /dmdf C:\ArtifactSigning\metadata.json %1' examples/windowed_app
   ```

   The single quotes keep PowerShell from reading the double quotes, which keep paths with spaces whole.

### 3c. DigiCert KeyLocker, SSL.com eSigner, or a key in a cloud vault

Each service documents a command that signs one file. Check its current page for the exact options; the shapes below are the usual ones.

- **DigiCert KeyLocker**, after its client tools are set up (`smctl` and the DigiCert KSP, with `SM_HOST`, `SM_API_KEY`, `SM_CLIENT_CERT_FILE`, and `SM_CLIENT_CERT_PASSWORD` set): `--sign-command '"SIGNTOOL" sign /csp "DigiCert Signing Manager KSP" /kc KEYPAIR_ALIAS /f C:\KeyLocker\certificate.crt /fd SHA256 /tr http://timestamp.digicert.com /td SHA256 %1'`.
- **SSL.com eSigner**, with CodeSignTool, which takes a password: put it in `sign.cmd`, reading the secrets from environment variables you set in the session, and pass `--sign-command C:\path\to\sign.cmd`. Fledge adds the quoted path at the end, which is `%1` inside the `.cmd` file:

  ```bat
  @echo off
  call C:\CodeSignTool\CodeSignTool.bat sign -username=%ESIGNER_USERNAME% -password=%ESIGNER_PASSWORD% -totp_secret=%ESIGNER_TOTP% -input_file_path=%1 -override=true
  ```

- **A key in Azure Key Vault, AWS KMS, or Google Cloud KMS**, with [jsign](https://ebourg.github.io/jsign/): `--sign-command 'jsign --storetype AZUREKEYVAULT --keystore VAULT_NAME --storepass %AZURE_TOKEN% --alias CERT_NAME --tsaurl http://timestamp.digicert.com %1'`.

### 4. Check the result on this computer

1. The build prints two paths: `dist\Hello Window-x64-mingw-ucrt.zip` and `dist\Hello Window-x64-mingw-ucrt-setup.exe` (`aarch64-mingw-ucrt` on ARM).
2. Verify the setup program and the program inside the archive:

   ```powershell
   & SIGNTOOL verify /pa /v "dist\Hello Window-x64-mingw-ucrt-setup.exe"
   & SIGNTOOL verify /pa /v "dist\Hello Window-x64-mingw-ucrt\Hello Window.exe"
   ```

   Each should end with `Successfully verified`, name your certificate under **Issued to**, and say **The signature is timestamped**. Fledge signed every `.exe`, `.dll`, and `.so` in the folder the same way; `Get-ChildItem -Recurse "dist\Hello Window-x64-mingw-ucrt" -Include *.exe,*.dll,*.so | ForEach-Object { & SIGNTOOL verify /pa /q $_.FullName; if ($LASTEXITCODE) { "not verified: $($_.FullName)" } }` checks them all, and should print nothing.
3. In File Explorer, right-click the setup program, choose **Properties**, and open the **Digital Signatures** tab: your publisher name is listed, and **Details** says "This digital signature is OK."

### 5. Install it as someone who downloaded it

SmartScreen judges only files marked as downloaded from the internet (the Mark of the Web, a `Zone.Identifier` stream).

1. Put the setup program somewhere a browser can download it (as in Part 1, step 5), and download it with Edge on another Windows computer, or this one.
2. Double-click it in **Downloads**. Either the setup program starts, with no administrator prompt, since it installs for you alone; or SmartScreen shows "Windows protected your PC", and **More info** names the publisher. A new certificate has no reputation with SmartScreen yet, so it may warn for a while even when all is right; what matters on a first run is that the publisher reads setdef, not "Unknown publisher".
3. Install it, open **Hello Window** from the Start menu, then uninstall it from **Settings > Apps > Installed apps**.

Without a download, you can mark a copy yourself:

```powershell
Copy-Item "dist\Hello Window-x64-mingw-ucrt-setup.exe" $env:TEMP
Set-Content -Path "$env:TEMP\Hello Window-x64-mingw-ucrt-setup.exe" -Stream Zone.Identifier -Value "[ZoneTransfer]`r`nZoneId=3"
& "$env:TEMP\Hello Window-x64-mingw-ucrt-setup.exe"
```

## What to send back

For each part, say which way you signed, and paste what the build printed, the `spctl` or `signtool verify` lines, and what the downloaded copy showed when you opened it. No output on this page holds a secret. An agent then records it in ADR 033 or ADR 051, in Plan 003's story "Notarization and real trust chains", and in the README's line on what is untested.
