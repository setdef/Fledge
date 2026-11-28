# How-to guides

Each guide gets one task done. They assume you have built an app once, as [the tutorial](../tutorial.md) does, and link to [the reference](../reference/README.md) for every option they don't use.

## Present the app

- [Make a windowed app](windowed-app.md): make an app that opens windows, with an identifier, an icon, and installers for each desktop.
- [Open files and folders](file-associations.md): let people open your app's documents from their file manager, and read their paths in `ARGV`.
- [Ship several programs in one app](several-programs.md): put a windowed app and its command line, or a game and its server, in one folder.

## Gems

- [Ship gems with C extensions](native-gems.md): compile gems, keep a Linux app running on old distributions, and carry the libraries a gem needs from each system.
- [Ship gems from private servers, git, and folders](gem-sources.md): logins, `vendor/cache`, checksums, and which gem groups ship.

## Ship

- [Sign and notarize an app](signing.md): sign with a Developer ID or a Windows certificate, have Apple notarize, or sign with your own command.
- [Build for iPhone and Android](phones.md): write an Xcode or Gradle project, run a program on the Simulator or an emulator, and change the native host.
- [Build without reaching GitHub](runtimes.md): fill the runtime cache ahead of time, keep runtimes in a folder, or mirror Fledge's release.
- [Build an app from another app](build-from-an-app.md): build a new app with an old one's runtime and gems, even on a computer with no Ruby.
