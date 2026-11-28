# Phone projects

This part writes a phone's app as a project its platform's tools build: an Xcode project for iOS, through XcodeGen, and a Gradle project for Android. It compiles each gem's extension for the phone's targets, links the results into the project, and, for the phones' `run` commands, builds the project, installs it on a Simulator or device, and follows its log. [Phone runtimes](phone-runtimes.md) maps the runtimes it places in the project; [Ruby on a phone](../../explanation/phones.md) explains the shape to users.

## The pieces

| Piece | Role |
| - | - |
| `MobileProject` | the shared steps: copy the template, place the runtime, the app, the gems, and the extensions, lay the host over it, fill the marks, place the icons, and finish |
| `MobileProject::IOS` | places the XCFramework, makes frameworks of Ruby's own extensions and of libraries for FFI, links the gems' extensions into a static XCFramework, and runs XcodeGen |
| `MobileProject::Android` | places the runtime's AAR and Ruby's tree, links the gems' extensions into native libraries under `jniLibs`, and checks the result |
| `IOSRubyExtensions`, `IOSLibraries` | the iOS runtime's own extensions, and libraries for FFI, each as a framework the app embeds, with links from the paths Ruby loads them by |
| `AndroidLibraries`, `AndroidLinkage`, `AndroidPackaging` | Android's native libraries and the links Ruby reads to find them; their needs judged against what Android, the runtime, the app, and the host provide; and the Gradle setting that makes Android install them as files |
| `MobileExtensions` | compiles every gem's extensions for every target of the phone, and returns what to link and register |
| `MobileExtensions::Targets` | each target's toolchain: the two iOS slices with Xcode's compilers, the two Android ABIs with the NDK's, with CMake toolchain files and Rust's variables |
| `ExtconfBuild`, `RakeBuild`, `Rust`, `CMake` | each way an extension builds, run with the phone's `rbconfig` through a shim |
| `Separation` | keeps names two extensions both define apart, so one app can link them all |
| `Linking`, `Library`, `FfiLibrary`, `Stub`, `LeftFiles`, `BuiltFor`, `HostGems`, `NDK`, `Sources`, `Runner` | link flags and carried shared libraries; what was built; the Ruby stub that loads a linked extension by its path; files builds left; what a library was built for; gems a Rakefile needs on the host; finding the NDK; unpacking a package's source; running commands with a clean environment |
| `PhoneRun`, `PhoneRun::IOS`, `PhoneRun::Android` | build the debug app, install it, launch it, and print its log until the host logs the program's exit status |
| `lib/fledge/templates/ios`, `templates/android` | the template projects, with `@@NAME@@` marks |

## Writing a project

`MobileProject#call` works in a temporary folder inside the output folder and moves the finished project into place, so a failure leaves nothing. The steps, in order:

1. Copy the template, and compile the gems' extensions for every target (`MobileExtensions#call`).
2. Place the runtime: on iOS, `FledgeRuby.xcframework`; on Android, `FledgeRuby.aar` in `libs` and Ruby's tree under `fledge`.
3. Place the linked extensions and the libraries for FFI, and the registration source that adds each linked extension to Ruby before the program runs.
4. Write `fledge.cfg` and copy the notices into `fledge`, then the app's entries, the gems, the stubs, and the files the builds left, as on a desktop.
5. Lay the host folder over the project, fill the marks in the template files, and place the icons.
6. Finish: on iOS, check that a dynamic Ruby is embedded, and run XcodeGen; on Android, judge every native library's needs and the packaging setting, and refuse the project with every problem at once.

## Compiling extensions

Each package with extensions is unpacked once per target, and each extension built with the phone's `rbconfig` and the runtime's headers, through a shim loaded before `extconf.rb` or the Rakefile that points `mkmf` at the target's compilers, removes the build host's folders from the recorded flags, and records what `create_makefile` made. Rakefiles run with the gem's runtime dependencies on the load path, compiled for the host by `HostGems` when they have extensions of their own. Rust extensions build through `rb_sys` as static libraries, with the target's Rust triple.

What happens to each built extension differs by system:

- **iOS** loads no loose library. Each extension's archive is linked into one static library per slice, packed as `FledgeExtensions.xcframework`, and registered with `fledge_ruby_add_extension` under its feature name. An `extconf.rb` that builds a library with no `Init_` function is a library for FFI, made into a framework the app embeds.
- **Android** installs native libraries as files. An `extconf.rb` extension builds as a shared object, `libfledgeext.FEATURE.so`; Rakefile and Rust extensions link into `libfledgeext.so` with the registration source. Each is placed under `jniLibs/ABI`, and `fledge.links` tells the runtime which path in Ruby's tree each library answers to.

Both build the same extensions for every target, and `MobileExtensions` refuses targets that built different ones. Where two extensions linked into one library define the same name, `Separation` makes each one's own names local before linking, and refuses a clash it can't resolve, naming both gems. Files a build left that are the same for every target ship once; those that differ ship per ABI on Android, and the runtime places the right ones when the app starts.

## Running a program

The phones' `run` command builds the project with the developer's program as its entry, then hands it to `PhoneRun`. iOS builds for the Simulator with `xcodebuild` (unsigned), installs and launches it with `simctl` on the one booted Simulator, and reads the unified log for the app's subsystem; Android builds the debug APK with the project's Gradle wrapper, installs and starts it with `adb`, and reads logcat for the app's tag. Each prints the program's lines as they come, and returns the status from the host's last line, `NAME exited with status N`. A process that ends without that line is a failure, not status 0.

## Traps

- **A phone takes every gem's source build.** `MobilePlatform#force_ruby_platform?` is true, so `Bundle` selects for the `ruby` platform and the lockfile must lock it, and a precompiled gem's desktop library is refused for a phone.
- **Extensions compile on a Mac or Linux.** Android's NDK and Xcode run there; a Windows computer can write an Android project only for an app whose gems have no extensions.
- **The Android host must keep legacy packaging.** Without `useLegacyPackaging = true`, Android keeps native libraries in the APK, and Ruby's extensions, which load by path, can't load. `AndroidPackaging` reads the host's `build.gradle`, ignoring comments and the `dex` block, and refuses one that drops it.
- **The template is a contract with the runtime.** The hosts call the embedding API by name (`fledge_ruby_run_app`, `FledgeRuby.startAppOnMainThread`), and the project scripts copy the runtime into the app by its folder names. A change to either side changes both.
- **Every phone program runs on the main thread** (ADR 105). The templates' hosts never choose a thread by `kind`.

## What this part doesn't do

- Build, sign, or archive the release app: Xcode and Gradle do, from the project.
- Give the app's Ruby any API: the host only starts Ruby and forwards its output.
- Compile an extension that builds by anything but an `extconf.rb` (with or without CMake), a Rakefile, or `rb_sys`.
