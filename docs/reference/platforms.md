# Platforms

Fledge 0.17.0 builds apps for these platforms. Each platform's app is built on a computer of that platform: `fledge build` builds for the computer it runs on, and has no way to build for another. A phone's project is the exception, written on a desktop whose tools build it.

## Desktops

| Platform | System | The app runs on | Archive | Installers |
| - | - | - | - | - |
| `arm64-darwin` | macOS on Apple silicon | macOS 26.0 and later | `.tar.gz` | `dmg` |
| `x86_64-linux` | Linux on x86-64, with glibc | glibc 2.28 and later, or newer when a gem's compiled files need it | `.tar.gz` | `appimage`, `deb` |
| `aarch64-linux` | Linux on ARM64, with glibc | glibc 2.28 and later, or newer when a gem's compiled files need it | `.tar.gz` | `appimage`, `deb` |
| `x86_64-linux-musl` | Linux on x86-64, with musl, such as Alpine | musl Linux | `.tar.gz` | `appimage` |
| `aarch64-linux-musl` | Linux on ARM64, with musl | musl Linux | `.tar.gz` | `appimage` |
| `x64-mingw-ucrt` | Windows on x64 | Windows 11 and later | `.zip` | `nsis`, `msix` |
| `aarch64-mingw-ucrt` | Windows on ARM64 | Windows 11 and later on ARM64 | `.zip` | `nsis`, `msix` |

The platform's name is the one RubyGems and Bundler use, and it ends every file a build writes: `greet-x86_64-linux.tar.gz`. A Mac with an Intel processor has no Fledge runtime, and neither does 32-bit Windows or Linux.

Fledge does not support Windows 10, whose support from Microsoft ended on October 14, 2025.

## Phones

| Phone | The app runs on | Processors | Project written on |
| - | - | - | - |
| `ios` | iOS and iPadOS 15.0 and later, on iPhone and iPad | the device's arm64, and the Simulator's on Apple silicon | `arm64-darwin` |
| `android` | Android 8.0 (API 26) and later | `arm64-v8a` and `x86_64` | `arm64-darwin`, `x86_64-linux`, `x64-mingw-ucrt` |

## Ruby

Every runtime of Fledge 0.17.0 is a Ruby 4.1, but not every one is the same build of it:

| Runtimes | Ruby |
| - | - |
| macOS, Linux, iOS, and Android | Ruby 4.1.0-preview1 |
| `x64-mingw-ucrt` and `aarch64-mingw-ucrt` | RubyInstaller's head build of 2026-11-10: Ruby 4.1.0dev, from Ruby's master branch at commit `0e25874222` |

The two are built from different points in Ruby's source, so a program can meet a change in Ruby's behavior on Windows that it does not meet elsewhere, or the other way around. Each runtime carries Ruby's default gems and its bundled gems, as `ruby` from a Ruby install has them.

Run `fledge build` with Ruby 4.1, the runtimes' minor version. fledge compares only the minor version: it refuses to build with another, such as 4.0, and says which Ruby to use, and it builds with any Ruby 4.1, 4.1.0-preview1 and 4.1.0dev alike.

## What the computer that builds needs

Beyond Ruby 4.1 and Bundler, a build runs the tools of the system it runs on. fledge names the tool it could not run, and how to install it.

### Every desktop

- `tar`, which macOS, Linux, and Windows 11 have, to unpack runtimes and pack archives.
- `git` on `PATH`, for a gem the `Gemfile` takes from git.
- A compiler, for a gem compiled from source: see [Ship gems with C extensions](../how-to/native-gems.md).
- The network the first time, to download the runtime and gems, unless you [build without reaching GitHub](../how-to/runtimes.md).

### macOS

Xcode's command line tools (`xcode-select --install`): `objdump` reads the gems' compiled files, `codesign` signs, `plutil` writes `Info.plist`, `hdiutil` and `ditto` make the disk image, `install_name_tool` points carried libraries at their copies, and `notarytool` and `stapler` notarize.

### Linux

- `objdump`, from binutils, to read the gems' compiled files.
- `mksquashfs` 4.4 or later, from squashfs-tools, for an AppImage.
- `dpkg-deb`, from dpkg, for a `.deb`, and `dpkg-shlibdeps`, from dpkg-dev, when `system-libraries` lists libraries the package depends on.
- To build an app that runs on old distributions, an old Linux, such as AlmaLinux 8, whose glibc is 2.28.
- For a musl app, a musl Linux, such as an Alpine container.

### Windows

- Windows PowerShell 5.1, which Windows 11 has, to pack the `.zip`.
- The Windows SDK's `signtool`, for `--sign`, and `makeappx`, for an MSIX package: `winget install Microsoft.WindowsSDK.10.0.26100`.
- MSYS2's toolchain, for a gem compiled from source, as RubyInstaller's `ridk install` sets it up.

The runtime brings the rest: Fledge's launchers, rcedit, NSIS, and LLVM's `llvm-readobj`, which reads Windows' compiled files.

### iOS

A Mac with Apple silicon, Xcode, and [XcodeGen](https://github.com/yonaskolb/XcodeGen) on `PATH`. For a Rust extension, Rust with the `aarch64-apple-ios` and `aarch64-apple-ios-sim` targets.

### Android

The Android SDK, a JDK 17 or later, and the project's Gradle wrapper, which downloads Gradle 9.8.2. For a gem's extension, the Android NDK (Fledge's runtime is built with r30), on a Mac or Linux; for a Rust extension, Rust with the `aarch64-linux-android` and `x86_64-linux-android` targets.

## What the computer that runs the app needs

Nothing of Ruby. The app needs only what its system has, plus:

- on Linux, the libraries listed in `fledge.kdl`'s `system-libraries` and `system-typelibs`, which the app checks for when it starts;
- on Linux, FUSE, to start the app from its AppImage, since the AppImage runtime at the front of that file mounts the app's file system with FUSE; the app's folder, unpacked from its `.tar.gz`, needs no FUSE;
- on Windows, Microsoft's Visual C++ Redistributable, when `visual-c-runtime` is `central`, which the app checks for when it starts, and the setup program installs.
