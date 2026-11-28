# Phone runtimes

A phone runs no program of Fledge's, so a phone's runtime is Ruby as a library: an XCFramework for iOS, with a slice for devices and one for the Simulator, and an AAR for Android, with a library for each ABI. Each is CRuby built from its release tarball with Ruby's `configure` and `make`, cross-compiled with Xcode's or the NDK's compilers (ADR 099), plus an embedding API in C, of four functions, that a host program calls. [Phone projects](phone-projects.md) places these runtimes in a project; this document maps what they are.

## The pieces

| Piece | Where | Role |
| - | - | - |
| the embedding API | `runtime/mobile/fledge_ruby.h`, `fledge_ruby.c` | starts Ruby on an app's program or a script, registers linked extensions, and forwards output |
| output forwarding | `output.c`, `apple.c`, `android.c` | sends standard output and error, line by line, to the system log, and to a console when there is one |
| Android's file layout | `library_links.c`, `commands.c`, `ruby_program.c` | links Ruby's tree to the native libraries Android installed, places each ABI's files, and runs gems' commands through Ruby's program |
| certificates | `openssl_certificates.c` | points OpenSSL at the CA bundle the runtime carries, as rv's portable Rubies do, unless `PORTABLE_RUBY_SSL_CERT_FILE` points at another |
| Android's Java | `runtime/mobile/android/.../FledgeRuby.java` | unpacks the app's archive from the APK's assets, sets `HOME`, and starts Ruby on the main thread or a thread of its own |
| the build | `tasks/runtime_builder/mobile.rb`, `ios.rb`, `android.rb`, `ruby_source.rb` | cross-builds Ruby and its libraries for each target, applies Fledge's edits to Ruby's source, and packs the XCFramework or AAR |
| the pins | `runtime/sources.yml`, `mobile` | Ruby's tarball, OpenSSL, libyaml, libffi, the CA bundle, Xcode, the NDK, Gradle, the Android Gradle plugin, XcodeGen, and bundletool |

## The embedding API

A host calls four functions, declared in `fledge_ruby.h`:

- `fledge_ruby_forward_output(tag)` before anything prints, so the program's output reaches the log under the app's identifier;
- `fledge_ruby_run_app(root, argc, argv)` to run the program in `root`'s `fledge.cfg`, with Bundler set up as the desktop launcher sets it up, returning its status, or 66 or 70 as [the launcher](launcher.md) does;
- `fledge_ruby_run(root, script, argc, argv)` to run another script as plain Ruby;
- `fledge_ruby_add_extension(feature, init)`, which the generated registration source calls from a constructor for each linked extension, before Ruby boots.

The templates' hosts call `fledge_ruby_run_app` on the main thread: iOS's `main` calls it directly, so the program's Ruby is what calls `UIApplicationMain`, and Android's `MainActivity` calls `FledgeRuby.startAppOnMainThread`, which unpacks the app on a thread of its own and then runs Ruby on the main thread. iOS links the app with a 64 MB main-thread stack, so Ruby has the stack it has on a desktop.

## Why Ruby is a shared library, with each extension a file

On a desktop, Ruby's own extensions, and default gems such as `openssl` and `psych`, are files that `require` finds by path, and the gems' specifications list them. A phone's runtime keeps that shape wherever its system allows, so that the program, and the gems' own code, see what they would see on a desktop:

- **iOS:** Ruby is `FledgeRuby.framework`, and each of Ruby's own extensions is a framework of its own, named for its feature, which the app embeds. `fledge.links` lists, per slice, the path in Ruby's tree each framework answers to, and the project writes a link at that path, so `require` and `$LOADED_FEATURES` see the desktop's paths. A gem's extension, which the app links statically, registers under its feature name and has a stub at its path (see [Phone projects](phone-projects.md)).
- **Android:** Ruby is `libfledgeruby.so`, and each extension a native library Android installs with the app. At start, `fledge_link_libraries` makes a link at each path `fledge.links` lists to the library Android extracted, so the tree looks as it does on a desktop, and `fledge_place_abi_files` moves the files that differ by ABI into place.

So the parity check finds only the differences a phone forces.

## A console

Output goes to the system log line by line, split between characters into entries of at most 1,000 bytes, with NUL bytes in a form each log keeps. Each stream keeps a copy of the original descriptor too, so a line also reaches a console when the process has one, such as `xcrun devicectl device process launch --console`, and not when it is `/dev/null`. When Xcode's debugger already mirrors the log to standard error (`OS_ACTIVITY_DT_MODE`), forwarding stays off, so lines appear once. Forwarding drains every stream at exit, so a program that ends at once leaves every line in the log.

## A program that runs long

Every phone program's Ruby holds the main thread (ADR 105), so a program that runs long holds the screen. iOS's launch watchdog ends a program that has not called `UIApplicationMain` within 20 seconds on a device; Android reports one as not responding when an input event waits 5 seconds. The runtime does nothing about it, by design: a program that runs long starts its interface first and does its work on a Ruby thread, as a native app does its work off the main thread. The Simulator ends no program that holds the main thread, which is why `fledge ios run` can run a test suite of any length there.

## Ruby's source, edited

A cross build needs what Ruby's build doesn't do, so `ruby_source.rb` applies scripted edits to Ruby's source before configuring it, each with a test of its own: naming where libruby is for an embedder, reading a command through its link (for Android's gem commands), titling the process within its own memory, finding a linked extension by its file's path, working where Android's seccomp filter refuses some calls, and fixes taken from Ruby's master. A new Ruby means checking each edit again; `test/ruby_source_test.rb` and `test/mobile_runtime_test.rb` name them.

## Traps

- **Closures on an iPhone.** iOS ends a process that runs code from a page it made executable. Fiddle's closures work on a device only because the iOS runtime's libffi takes closures from its trampoline table and Fiddle is built with `ffi_closure_alloc`. The Simulator doesn't enforce it, so only `test/integration/mobile_closures_test.rb`, which checks the device slice, catches a change that breaks it.
- **The Android ABIs differ.** `arm64-v8a` runs on phones and `x86_64` on emulators; a build check on one says nothing of the other's libraries.
- **JITs.** Android's Ruby has YJIT and ZJIT, as a desktop's does; iOS's has neither.
- **No bridge returns.** Nothing automated fails when a library of Fledge's for an app to call comes back into a runtime; only review against [what the design answers to](architecture.md#what-the-design-answers-to) catches it (ADR 105).

## What the phone runtimes don't do

- Give an app's Ruby a bridge to Objective-C or Java, an Activity, or a screen.
- Choose a thread by the app's `kind`.
- Ship a prebuilt Ruby from another project: none is published for phones (ADR 099).
