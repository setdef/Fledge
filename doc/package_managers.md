<!--
  SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
  SPDX-License-Identifier: CC-BY-SA-4.0
-->
# Publishing a console app with a package manager

People who live in a terminal install tools with a package manager. This guide shows how to publish a console app that [Fledge](../README.md) built through [Scoop](https://scoop.sh/), a [Homebrew](https://brew.sh/) tap, [winget](https://learn.microsoft.com/windows/package-manager/), [Chocolatey](https://chocolatey.org/), and the [AUR](https://aur.archlinux.org/). Each manager takes the archive `fledge build` writes, from a release you publish, such as a GitHub Release, and a text file you write that names the archive's address and its SHA-256.

The examples publish a console app named `hello`, from a repository at `github.com/example/hello`, as the command `hello`. A console app is named after its entry point, so `hello`'s program is `hello` (`hello.exe` on Windows), and its archive is `hello-PLATFORM`. Replace each `HASH FROM FILE.sha256` with the hash in that file, which `fledge build` writes beside each archive.

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
      "url": "https://github.com/example/hello/releases/download/v1.0.0/hello-x64-mingw-ucrt.zip",
      "hash": "HASH FROM hello-x64-mingw-ucrt.zip.sha256",
      "extract_dir": "hello-x64-mingw-ucrt"
    },
    "arm64": {
      "url": "https://github.com/example/hello/releases/download/v1.0.0/hello-aarch64-mingw-ucrt.zip",
      "hash": "HASH FROM hello-aarch64-mingw-ucrt.zip.sha256",
      "extract_dir": "hello-aarch64-mingw-ucrt"
    }
  },
  "bin": "hello.exe",
  "checkver": "github",
  "autoupdate": {
    "architecture": {
      "64bit": {
        "url": "https://github.com/example/hello/releases/download/v$version/hello-x64-mingw-ucrt.zip",
        "hash": { "url": "$url.sha256" }
      },
      "arm64": {
        "url": "https://github.com/example/hello/releases/download/v$version/hello-aarch64-mingw-ucrt.zip",
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
      url "https://github.com/example/hello/releases/download/v1.0.0/hello-arm64-darwin.tar.gz"
      sha256 "HASH FROM hello-arm64-darwin.tar.gz.sha256"
    end
  end

  on_linux do
    on_intel do
      url "https://github.com/example/hello/releases/download/v1.0.0/hello-x86_64-linux.tar.gz"
      sha256 "HASH FROM hello-x86_64-linux.tar.gz.sha256"
    end
    on_arm do
      url "https://github.com/example/hello/releases/download/v1.0.0/hello-aarch64-linux.tar.gz"
      sha256 "HASH FROM hello-aarch64-linux.tar.gz.sha256"
    end
  end

  def install
    libexec.install Dir["*"]
    bin.install_symlink libexec/"hello"
  end

  test do
    assert_match "Hello", shell_output("#{bin}/hello")
  end
end
```
<!-- SPDX-SnippetEnd -->

## winget

A winget package is three files, which you add to [`microsoft/winget-pkgs`](https://github.com/microsoft/winget-pkgs) by a pull request, under `manifests/e/Example/Hello/1.0.0/`. The version file names the package and its default locale, the locale file its publisher, name, license, and description, and the installer file the archives. winget unpacks the `.zip` and links the program into its folder on `PATH`, as `hello`:

<!-- SPDX-SnippetBegin -->
<!--
  SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
  SPDX-License-Identifier: MIT-0
-->
```yaml
# yaml-language-server: $schema=https://aka.ms/winget-manifest.version.1.12.0.schema.json
# Example.Hello.yaml
PackageIdentifier: Example.Hello
PackageVersion: 1.0.0
DefaultLocale: en-US
ManifestType: version
ManifestVersion: 1.12.0
```
<!-- SPDX-SnippetEnd -->

<!-- SPDX-SnippetBegin -->
<!--
  SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
  SPDX-License-Identifier: MIT-0
-->
```yaml
# yaml-language-server: $schema=https://aka.ms/winget-manifest.defaultLocale.1.12.0.schema.json
# Example.Hello.locale.en-US.yaml
PackageIdentifier: Example.Hello
PackageVersion: 1.0.0
PackageLocale: en-US
Publisher: Example
PackageName: Hello
License: MIT
ShortDescription: Says hello
ManifestType: defaultLocale
ManifestVersion: 1.12.0
```
<!-- SPDX-SnippetEnd -->

<!-- SPDX-SnippetBegin -->
<!--
  SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
  SPDX-License-Identifier: MIT-0
-->
```yaml
# yaml-language-server: $schema=https://aka.ms/winget-manifest.installer.1.12.0.schema.json
# Example.Hello.installer.yaml
PackageIdentifier: Example.Hello
PackageVersion: 1.0.0
InstallerType: zip
NestedInstallerType: portable
Installers:
  - Architecture: x64
    InstallerUrl: https://github.com/example/hello/releases/download/v1.0.0/hello-x64-mingw-ucrt.zip
    InstallerSha256: HASH FROM hello-x64-mingw-ucrt.zip.sha256
    NestedInstallerFiles:
      - RelativeFilePath: hello-x64-mingw-ucrt\hello.exe
        PortableCommandAlias: hello
  - Architecture: arm64
    InstallerUrl: https://github.com/example/hello/releases/download/v1.0.0/hello-aarch64-mingw-ucrt.zip
    InstallerSha256: HASH FROM hello-aarch64-mingw-ucrt.zip.sha256
    NestedInstallerFiles:
      - RelativeFilePath: hello-aarch64-mingw-ucrt\hello.exe
        PortableCommandAlias: hello
ManifestType: installer
ManifestVersion: 1.12.0
```
<!-- SPDX-SnippetEnd -->

An app built with Fledge 0.4.0 or earlier cannot run through winget's link. For one, add `ArchiveBinariesDependOnPath: true`, and winget puts the app's folder on `PATH` instead.

## Chocolatey

A Chocolatey package is a `.nuspec` file and an install script, which `choco pack` packs into a `.nupkg`. You publish it to the community repository with an account of yours, or to a feed of your own, and your users run `choco install hello`:

<!-- SPDX-SnippetBegin -->
<!--
  SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
  SPDX-License-Identifier: MIT-0
-->
```xml
<?xml version="1.0" encoding="utf-8"?>
<package xmlns="http://schemas.microsoft.com/packaging/2015/06/nuspec.xsd">
  <metadata>
    <id>hello</id>
    <version>1.0.0</version>
    <title>Hello</title>
    <authors>Example</authors>
    <projectUrl>https://github.com/example/hello</projectUrl>
    <description>Says hello</description>
  </metadata>
  <files>
    <file src="tools\**" target="tools" />
  </files>
</package>
```
<!-- SPDX-SnippetEnd -->

Chocolatey puts a shim on `PATH` for every `.exe` in the package, and a Fledge app holds `ruby.exe` and more. An empty file named after a program, with `.ignore` added, stops its shim, so `tools\chocolateyInstall.ps1` writes one for every program but the app's:

<!-- SPDX-SnippetBegin -->
<!--
  SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
  SPDX-License-Identifier: MIT-0
-->
```powershell
$ErrorActionPreference = 'Stop'
$toolsDir = Split-Path -Parent $MyInvocation.MyCommand.Definition

Install-ChocolateyZipPackage -PackageName 'hello' -UnzipLocation $toolsDir `
  -Url64bit 'https://github.com/example/hello/releases/download/v1.0.0/hello-x64-mingw-ucrt.zip' `
  -Checksum64 'HASH FROM hello-x64-mingw-ucrt.zip.sha256' -ChecksumType64 'sha256'

Get-ChildItem -LiteralPath $toolsDir -Recurse -Filter '*.exe' |
  Where-Object { $_.Name -ne 'hello.exe' } |
  ForEach-Object { New-Item -ItemType File -Force -Path "$($_.FullName).ignore" | Out-Null }
```
<!-- SPDX-SnippetEnd -->

Windows finds `hello.exe` when your users type `hello`, whatever its case.

## The AUR

On Arch Linux, a `-bin` package in the [AUR](https://aur.archlinux.org/) names a prebuilt release. Put a `PKGBUILD` such as this in the package's git repository. The `options` line keeps `makepkg` from stripping or pruning the app, which stays whole in `/opt`, with only a link in `/usr/bin`:

<!-- SPDX-SnippetBegin -->
<!--
  SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
  SPDX-License-Identifier: MIT-0
-->
```sh
pkgname=hello-bin
pkgver=1.0.0
pkgrel=1
pkgdesc="Says hello"
arch=('x86_64' 'aarch64')
url="https://github.com/example/hello"
license=('MIT')
options=('!strip' '!debug' '!staticlibs' '!purge')
source_x86_64=("https://github.com/example/hello/releases/download/v1.0.0/hello-x86_64-linux.tar.gz")
source_aarch64=("https://github.com/example/hello/releases/download/v1.0.0/hello-aarch64-linux.tar.gz")
sha256sums_x86_64=('HASH FROM hello-x86_64-linux.tar.gz.sha256')
sha256sums_aarch64=('HASH FROM hello-aarch64-linux.tar.gz.sha256')

package() {
  install -d "$pkgdir/opt/hello" "$pkgdir/usr/bin"
  cp -a "$srcdir/hello-$CARCH-linux/." "$pkgdir/opt/hello/"
  ln -s /opt/hello/hello "$pkgdir/usr/bin/hello"
}
```
<!-- SPDX-SnippetEnd -->

## mise

[mise](https://mise.jdx.dev/) installs a tool from an archive at a URL with its [`http` backend](https://mise.jdx.dev/dev-tools/backends/http.html), and from a GitHub Release with its [`github` backend](https://mise.jdx.dev/dev-tools/backends/github.html). Your users put a recipe in `~/.config/mise/config.toml`, or in a project's `mise.toml`, and run `mise install`.

mise puts an archive's `bin/` folder on `PATH`. On macOS and Linux, a Fledge app's `bin/` holds the runtime's `ruby`, `bundle`, `gem`, `rake`, and `irb`, not the program. On Windows, the app has no `bin\`, and mise puts the runtime's `ruby\bin` on `PATH`. So with only a `url`, the program is not found, and `ruby` runs the app's private Ruby ahead of the one your users' projects pin. `strip_components = 1` removes the app's top folder, and `bin_path = "."` puts the folder that holds the program on `PATH`, and nothing else. The command is the program's file name: `Hello` on macOS and Linux, and `hello` or `Hello` on Windows.

<!-- SPDX-SnippetBegin -->
<!--
  SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
  SPDX-License-Identifier: MIT-0
-->
```toml
[tools."http:hello"]
version = "1.0.0"
# Wrong without these two options: mise puts the runtime's ruby, bundle,
# gem, and rake on PATH, and not the program.
strip_components = 1
bin_path = "."

[tools."http:hello".platforms]
macos-arm64 = { url = "https://github.com/example/hello/releases/download/v{{ version }}/hello-arm64-darwin.tar.gz", checksum = "sha256:HASH FROM hello-arm64-darwin.tar.gz.sha256" }
linux-x64 = { url = "https://github.com/example/hello/releases/download/v{{ version }}/hello-x86_64-linux.tar.gz", checksum = "sha256:HASH FROM hello-x86_64-linux.tar.gz.sha256" }
linux-arm64 = { url = "https://github.com/example/hello/releases/download/v{{ version }}/hello-aarch64-linux.tar.gz", checksum = "sha256:HASH FROM hello-aarch64-linux.tar.gz.sha256" }
windows-x64 = { url = "https://github.com/example/hello/releases/download/v{{ version }}/hello-x64-mingw-ucrt.zip", checksum = "sha256:HASH FROM hello-x64-mingw-ucrt.zip.sha256" }
windows-arm64 = { url = "https://github.com/example/hello/releases/download/v{{ version }}/hello-aarch64-mingw-ucrt.zip", checksum = "sha256:HASH FROM hello-aarch64-mingw-ucrt.zip.sha256" }
```
<!-- SPDX-SnippetEnd -->

For an app released on GitHub, the `github` backend takes the same two options. Set `asset_pattern` to the archive's file name on each platform:

<!-- SPDX-SnippetBegin -->
<!--
  SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
  SPDX-License-Identifier: MIT-0
-->
```toml
[tools."github:example/hello"]
version = "1.0.0"
strip_components = 1
bin_path = "."

[tools."github:example/hello".platforms]
macos-arm64 = { asset_pattern = "hello-arm64-darwin.tar.gz" }
linux-x64 = { asset_pattern = "hello-x86_64-linux.tar.gz" }
linux-arm64 = { asset_pattern = "hello-aarch64-linux.tar.gz" }
windows-x64 = { asset_pattern = "hello-x64-mingw-ucrt.zip" }
windows-arm64 = { asset_pattern = "hello-aarch64-mingw-ucrt.zip" }
```
<!-- SPDX-SnippetEnd -->

## What has been tested

Fledge's CI takes the recipes above from this page, fills in a hash and a local server's address, and installs a build of `examples/hello` with each manager's own tool on a fresh runner. It runs the app by its command, with no Ruby on `PATH`, checks that its exit status comes through and no `ruby` command appeared, and uninstalls it. In run [42497054150](https://github.com/setdef/Fledge/actions/runs/42497054150), with v0.9.0's published runtimes:

| Manager | Installed on | From |
| --- | --- | --- |
| Scoop | Windows x64 and ARM64 | a local manifest |
| Homebrew 7.0.11 on Linux, 7.0.12 on macOS | macOS on Apple silicon, Linux x86-64 and ARM64 | a local tap |
| winget 1.11.510 | Windows x64 | local manifests |
| Chocolatey 2.7.5 | Windows x64 | a local `.nupkg` |
| `makepkg` and `pacman` | Arch Linux x86-64, in a container | a `PKGBUILD` |

`brew install` left the app runnable on all three platforms, and Scoop, Chocolatey, and Homebrew each put exactly one command on `PATH`. winget 1.11 warns about the 1.12.0 schema headers and installs anyway. GitHub's `windows-11-arm` runners have no `winget`, so winget on ARM64 is untried, and Chocolatey ran only on x64.

Each of those installs read a local server, not a real release, and none went through a public repository. What the public routes do is unknown: Microsoft's review and virus scans of `winget-pkgs`, Chocolatey's moderation, a `brew tap` from GitHub and any trust step it asks for, and the AUR's account and rules.

The mise recipes install and run the app on macOS on Apple silicon, Linux x86-64, and Windows x64, with mise 2026.11.7: the `http` recipe from a `file://` URL, and the `github` recipe from a local server that answers as GitHub's API does for a release. CI does not run them, and neither reached a public release. mise's `aqua` and `ubi` backends read a real GitHub Release's assets, which CI has none of for an app, so they are untried. `ubi` without `--extract-all` takes one file, and an app cannot run from one file. Snap, Nix, MacPorts, and apt or dnf repositories for a console app are also untried: Fledge builds a `.deb` only for a windowed app.

The official repositories of Homebrew (`homebrew/core`), Debian, Fedora, and Flathub accept only software they build from source, so a Fledge app goes to your own tap, bucket, or repository instead.
