<!--
  SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
  SPDX-License-Identifier: CC-BY-SA-4.0
-->
# Publishing a console app with a package manager

People who live in a terminal install tools with a package manager. This guide shows how to publish a console app that [Fledge](../README.md) built through [Scoop](https://scoop.sh/), a [Homebrew](https://brew.sh/) tap, and [winget](https://learn.microsoft.com/windows/package-manager/). Each manager takes the archive `fledge build` writes, from a release you publish, such as a GitHub Release, and a manifest you write that names the archive's address and its SHA-256.

The examples publish an app named `Hello`, from a repository at `github.com/example/hello`, as the command `hello`. Replace each `HASH FROM FILE.sha256` with the hash in that file, which `fledge build` writes beside each archive.

## Keep the app's folder whole

Whatever the manager, unpack the app into a folder of its own, and put only the program on `PATH`, by a link or a shim. The program finds its Ruby and your code beside its real file, through any number of links. On macOS and Linux it refuses to run from a folder named `bin` or `lib`, where Ruby would look for its standard library one folder up, so never unpack the app into the manager's `bin` folder. Each recipe below follows this rule.

Fledge's CI runs every app through a link on `PATH`, two relative links, and a shell script that `exec`s it on macOS and Linux, and through a symbolic link and a junction on Windows.

## Scoop

Put a manifest such as `hello.json` in a git repository, your bucket, and your users run `scoop bucket add NAME URL` and `scoop install hello`. Scoop makes a shim only for what `bin` lists, so the app's `ruby.exe` stays off your users' `PATH`:

<!-- SPDX-SnippetBegin -->
<!--
  SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
  SPDX-License-Identifier: MIT-0
-->
```json
{
  "version": "1.0.0",
  "description": "Says hello",
  "homepage": "https://github.com/example/hello",
  "license": "MIT",
  "architecture": {
    "64bit": {
      "url": "https://github.com/example/hello/releases/download/v1.0.0/Hello-x64-mingw-ucrt.zip",
      "hash": "HASH FROM Hello-x64-mingw-ucrt.zip.sha256",
      "extract_dir": "Hello-x64-mingw-ucrt"
    },
    "arm64": {
      "url": "https://github.com/example/hello/releases/download/v1.0.0/Hello-aarch64-mingw-ucrt.zip",
      "hash": "HASH FROM Hello-aarch64-mingw-ucrt.zip.sha256",
      "extract_dir": "Hello-aarch64-mingw-ucrt"
    }
  },
  "bin": [["Hello.exe", "hello"]],
  "checkver": "github",
  "autoupdate": {
    "architecture": {
      "64bit": {
        "url": "https://github.com/example/hello/releases/download/v$version/Hello-x64-mingw-ucrt.zip",
        "hash": { "url": "$url.sha256" }
      },
      "arm64": {
        "url": "https://github.com/example/hello/releases/download/v$version/Hello-aarch64-mingw-ucrt.zip",
        "hash": { "url": "$url.sha256" }
      }
    }
  }
}
```
<!-- SPDX-SnippetEnd -->

`autoupdate` reads the hash of each new release from its `.sha256` file, so publish those files beside the archives.

## Homebrew

Put a formula such as `Formula/hello.rb` in a repository named `homebrew-NAME`, your tap, and your users run `brew install YOU/NAME/hello`. The app goes whole into the formula's `libexec`, and `bin` gets a link to its program:

<!-- SPDX-SnippetBegin -->
<!--
  SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
  SPDX-License-Identifier: MIT-0
-->
```ruby
class Hello < Formula
  desc "Says hello"
  homepage "https://github.com/example/hello"
  version "1.0.0"
  license "MIT"

  on_macos do
    on_arm do
      url "https://github.com/example/hello/releases/download/v1.0.0/Hello-arm64-darwin.tar.gz"
      sha256 "HASH FROM Hello-arm64-darwin.tar.gz.sha256"
    end
  end

  on_linux do
    on_intel do
      url "https://github.com/example/hello/releases/download/v1.0.0/Hello-x86_64-linux.tar.gz"
      sha256 "HASH FROM Hello-x86_64-linux.tar.gz.sha256"
    end
    on_arm do
      url "https://github.com/example/hello/releases/download/v1.0.0/Hello-aarch64-linux.tar.gz"
      sha256 "HASH FROM Hello-aarch64-linux.tar.gz.sha256"
    end
  end

  def install
    libexec.install Dir["*"]
    bin.install_symlink libexec/"Hello" => "hello"
  end

  test do
    assert_match "Hello", shell_output("#{bin}/hello")
  end
end
```
<!-- SPDX-SnippetEnd -->

## winget

A winget package is three files, which you add to [`microsoft/winget-pkgs`](https://github.com/microsoft/winget-pkgs) by a pull request, under `manifests/e/Example/Hello/1.0.0/`. The version file names the package and its default locale, the locale file its publisher, name, license, and description, and the installer file the archives. winget unpacks the `.zip` and links the program into its folder on `PATH`, as `hello`. This is the installer file:

<!-- SPDX-SnippetBegin -->
<!--
  SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
  SPDX-License-Identifier: MIT-0
-->
```yaml
# Example.Hello.installer.yaml
PackageIdentifier: Example.Hello
PackageVersion: 1.0.0
InstallerType: zip
NestedInstallerType: portable
Installers:
  - Architecture: x64
    InstallerUrl: https://github.com/example/hello/releases/download/v1.0.0/Hello-x64-mingw-ucrt.zip
    InstallerSha256: HASH FROM Hello-x64-mingw-ucrt.zip.sha256
    NestedInstallerFiles:
      - RelativeFilePath: Hello-x64-mingw-ucrt\Hello.exe
        PortableCommandAlias: hello
  - Architecture: arm64
    InstallerUrl: https://github.com/example/hello/releases/download/v1.0.0/Hello-aarch64-mingw-ucrt.zip
    InstallerSha256: HASH FROM Hello-aarch64-mingw-ucrt.zip.sha256
    NestedInstallerFiles:
      - RelativeFilePath: Hello-aarch64-mingw-ucrt\Hello.exe
        PortableCommandAlias: hello
ManifestType: installer
ManifestVersion: 1.12.0
```
<!-- SPDX-SnippetEnd -->

An app built with Fledge 0.4.0 or earlier cannot run through winget's link. For one, add `ArchiveBinariesDependOnPath: true`, and winget puts the app's folder on `PATH` instead.

## What has been tested

No one has yet installed a Fledge app with `scoop`, `brew`, or `winget`. The Scoop manifest and the winget files above pass each manager's JSON schema, and CI runs apps through the links and junctions these managers make. Whether `brew install` changes the app's files, and how winget's and Microsoft's virus scans treat a Ruby runtime, are unknown.

The official repositories of Homebrew (`homebrew/core`), Debian, Fedora, and Flathub accept only software they build from source, so a Fledge app goes to your own tap, bucket, or repository instead.
