# Ruby on a phone

On a desktop, an app is a folder with Ruby beside the program a person runs. A phone allows nothing of the kind. An iOS app is one signed program in a bundle, which may load code only from frameworks the bundle carries; an Android app is an APK whose native code Java loads, and whose files are not files until the app unpacks them. So on a phone, Ruby is a library, linked into an app that Xcode or Gradle builds, and Fledge's part is to write that app's project. This page explains the shape that gives a phone's app, and why your Ruby still runs there as it does under `ruby`.

## The runtime is a library, and a host starts it

Fledge's phone runtimes are Ruby built from its source with Ruby's `configure` and `make`, cross-compiled with Xcode's compilers and the Android NDK's, and packed as an XCFramework for iOS and an AAR for Android. Each holds the whole standard library and every default and bundled gem, as a desktop runtime does.

The project fledge writes adds a host: the few lines of native code a phone needs to start a program, `Host/main.m` on iOS and `MainActivity.java` on Android. The host sends what the program prints to the system's log, starts Ruby on your program, and logs the exit status when the program ends. That is all it does, and you can replace it with a host you write (see [Change the host](../how-to/phones.md#change-the-host)).

Your project and its gems travel inside the app: in the bundle's resources on iOS, and on Android in an archive among the APK's assets, which the app unpacks into its files folder the first time each version of it starts.

## Ruby runs on the main thread

A desktop runs your program on the thread the process started on, and Ruby calls it `Thread.main`. A phone's host does the same, for every program, whatever `fledge.yml`'s `kind` says. That matters because both phones call an app's interface code back on that thread alone: UIKit's views, and Android's, may be touched only from the main thread, and CRuby can answer a callback only on a thread where Ruby runs. Running Ruby anywhere else would leave your program unable to draw a widget or answer a tap.

The cost is the one every native app pays: while your Ruby holds the main thread, the screen doesn't change. A program that works for long does its work on a Ruby thread, and lets the main thread run the interface.

## Your Ruby reaches the platform itself

Fledge gives your Ruby no bridge to Objective-C or Java. Under `ruby` on a Mac, a script can call the Objective-C runtime through Fiddle, the gem Ruby bundles for calling C functions; on a phone, the same code reaches UIKit, and the same approach reaches Android's views through JNI. Your app, or a gem you choose, carries that code, and it is a Ruby program like any other: you can run its tests under `ruby` on a desktop.

A bridge of Fledge's would be easier to start with, and would make your program one that runs only under Fledge. Keeping the phone's Ruby a plain Ruby means that what you learn, write, or install for it works under `ruby` too, and that a better bridge, or a widget toolkit, can come from a gem without waiting for Fledge.

On an iPhone, iOS refuses code written into memory at run time, which is how Fiddle's closures, Ruby blocks the platform calls back, usually work. Fledge's iOS runtime builds Fiddle's libffi so that closures come from code the app already carries, so callbacks work on a device as in the Simulator.

## How extensions load

A desktop's gems load their C extensions as files, found by path. fledge compiles each gem's extension for each of the phone's targets, and keeps as much of the desktop's shape as each phone allows:

- **iOS** loads no library from a loose file, so every gem's extension is linked into the app itself, and Ruby finds it, when the program requires it, by the name it would find the file by.
- **Android** installs an app's native libraries as files. An extension that an `extconf.rb` builds becomes a separate native library, which Android installs with the app, and Ruby loads it through a link at the path where a desktop keeps its file. A Rust extension, or one that a Rakefile builds, is linked with the others of its kind into one native library, and Ruby finds it by name, as on iOS.

Where an extension is linked in, and a gem's Ruby code requires it by a path, fledge leaves a Ruby file at that path that loads the linked extension, so that the gem's code needs no change.

## Output goes to the log

A phone app has no terminal. The host sends each line your program prints to the system's log: to the unified log on iOS, under the app's identifier, and to logcat on Android, tagged with the identifier. `fledge ios run` and `fledge android run` read it back from there and print it, and so can Console on a Mac, or `adb logcat`.
