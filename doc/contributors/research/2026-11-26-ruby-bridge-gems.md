<!--
SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>

SPDX-License-Identifier: CC-BY-SA-4.0
-->

> Findings of 2026-11-26 on whether a maintained gem already bridges Ruby to the Objective-C runtime or to Java through JNI, in pure Ruby with no native extension of its own, so that Basket could use it instead of carrying its own code. Requested: written by an agent and not reviewed line by line. They decide nothing: Basket, `doc/phones.md`, and the design documents change with the code.

# Gems that bridge Ruby to Objective-C and to Java

`examples/basket/lib/basket/objc.rb` (665 lines) is Basket's way from Ruby to UIKit, written with Fiddle alone. `examples/basket/lib/basket/android.rb` (133 lines) draws Android's views through `Fledge::JNI`, which issue #131 replaces with Ruby over Fiddle (`2026-11-25-pure-ruby-android-views.md`). Fledge's rule is that code is a liability (`AGENTS.md`, "How to work"), and Basket may use a gem that has no native extension of its own, so the question is whether a gem already does what these two files do. This note says what was searched, what each candidate is, and whether Basket could use one.

## What a gem would have to do

The two research notes of 2026-11-25 (`2026-11-25-pure-ruby-uikit.md`, `2026-11-25-pure-ruby-android-views.md`) and `objc.rb` give the list. For Objective-C, a gem would have to:

- send any message to any object, choosing the C types of the call from the method's type encoding, so that one `objc_msgSend` wrapper serves every selector;
- make a Ruby class that is an Objective-C subclass of a UIKit class, with methods written in Ruby (`objc_allocateClassPair`, `class_addMethod`, each method a `Fiddle::Closure`) and with the protocols the class adopts;
- keep objects alive and release them (retain, release, `dealloc`);
- run on an iPhone, which has UIKit and no AppKit, under code signing (`Fiddle::Closure` works there through libffi's trampoline table).

For Java, a gem would have to reach the Java VM that Android's process already holds (`JNI_GetCreatedJavaVMs`), not start a second one; call Java methods by name and signature; and let Java call Ruby, which on Android means a class written as a dex file in memory, loaded with `InMemoryDexClassLoader`, with its native method bound by `RegisterNatives` to a `Fiddle::Closure`, and listeners made with `java.lang.reflect.Proxy`.

## What was searched

RubyGems.org's search API (`/api/v1/search.json`), first page of each of these queries: objc, objective-c, objectivec, cocoa, uikit, appkit, foundation, fiddle objc, ffi objc, rubicon, jni, java bridge, android, rubycocoa, macruby, hotcocoa, objc_msgSend, objective c bridge, ios ruby, java native interface, ruby-jni, rjb, ruby objc, objc runtime, objc-runtime, macos, ruby-macos, macos native, ffi macos, cocoa ffi, nsobject, nsstring, apple frameworks, native ui, native gui, native app, swift bridge, jvm, dalvik, android jni, fiddle bridge, fiddle wrapper, libobjc, objective-c runtime, objc bridge, ruby java, java ffi, jni ffi, rubymotion, ruby2d, sparkle, metal, libui, uikit ruby, objc ffi, ffi-objc, cocoa bridge, pure ruby macos. And these: java native, android ruby, ruby android, jnr, javavm, libjvm, java vm, ruby java interop, fiddle java, mobile ruby, ruby ios app, ios, swift, darwin ffi, objc-ruby, rubyobjc, ruby-objc, objc_bridge, foundation ruby, cocoa-ruby, appkit ruby, nsapplication. Every candidate got `/api/v1/gems/NAME.json` and `/api/v1/versions/NAME.json`; the ones worth reading were downloaded from `https://rubygems.org/downloads/NAME-VERSION.gem` and unpacked (read, not run), and the gemspec's `extensions` entry was read.

GitHub, through `gh-ai search code` with `language:ruby`: `objc_msgSend`, `objc_allocateClassPair`, `class_addMethod`, `sel_registerName`, `JNI_GetCreatedJavaVMs`, `GetStringUTFChars`, `FindClass NewStringUTF`, `CallObjectMethod`; and `gh-ai search repos` for objc, objective-c, cocoa, uikit, jni, android-jni, rubymotion, macruby, rubycocoa, java bridge, and ruby-java, with `language:ruby`. A search of code for `objc_getClass` with `Fiddle` returned nothing.

Most hits were not bridges: Xcode and CocoaPods tooling, Rails front-end kits named "UIkit", code generators, Homebrew formulae, and JRuby gems that wrap one jar.

## Objective-C

| Candidate | Latest | License | Native extension | Depends on | Maintained | Runs on an iPhone |
|---|---|---|---|---|---|---|
| `echoes` 0.8.0 | 2026-06-05 | MIT | none | `fiddle`, `syslog` | yes (9 releases since 2026-05-08; repository pushed 2026-11-24) | no |
| `cocoa` 0.1.6 | 2014-04-13 | MIT | none | `ffi`, `activesupport` | no (repository pushed 2020-08-13) | no |
| `ace-support-mac-clipboard` 0.3.5 | 2026-09-05 | MIT | none | `ffi` | yes | no |
| `macos` 0.1.8 | 2025-05-30 | MIT | none | `ffi`, `fiddle`, `zeitwerk` | releases to 2025 | no |
| `corefoundation` 0.3.19 | 2026-06-30 | MIT | none | `ffi` | yes (the `chef` organization) | no |
| `RubyObjC` 0.4.0 | 2009-07-25 | none given | prebuilt binaries | none | no | no |
| `cocoawebview` 1.0.3, `cocoamenu` 0.1.0, `cocoadock` 0.4.0 | 2026-02-18, 2025-07-01, 2026-02-12 | MIT | yes (`ext/*/extconf.rb`) | none | yes | no |

### `echoes` 0.8.0

Source: https://rubygems.org/gems/echoes, https://github.com/amatsuda/echoes. "A pure Ruby terminal emulator" for macOS. `lib/echoes/objc.rb` (266 lines) is the nearest thing to Basket's bridge that the search found: it `dlopen`s libobjc through Fiddle, and defines a class with `objc_allocateClassPair`, `class_addMethod`, `objc_registerClassPair`, and `class_addProtocol`, each method a `Fiddle::Closure` given with a type-encoding string.

It differs from Basket's bridge in four ways that matter here:

- It is the terminal's internal module (`Echoes::ObjC`), in a gem whose purpose is the terminal, and the gem's description lists no library API.
- It sends messages through about two dozen `Fiddle::Function` objects, one for each argument shape the terminal uses (`MSG_PTR_RECT_L_L_I` for `initWithContentRect:styleMask:backing:defer:`, `MSG_VOID_1_PT_L` for a drag callback), with each structure flattened to doubles by hand. It does not read a method's type encoding to choose the call, so every new selector with a new shape is new code.
- It loads AppKit, Foundation, CoreGraphics, and CoreText as it is required (`APPKIT = Fiddle.dlopen('/System/Library/Frameworks/AppKit.framework/AppKit')`), and reads AppKit's string constants at load. On an iPhone, which has no AppKit, `require` fails.
- It has no object ownership (a bare `retain` and `release`), no wrapper object for a receiver, and no Ruby-class-as-Objective-C-class DSL.

It shows that Fiddle alone carries this approach on a Mac, which the header of `objc.rb` says; it is not a library Basket could call.

### `cocoa` 0.1.6

Source: https://rubygems.org/gems/cocoa, https://github.com/patrickhno/cocoa. "Ruby FFI bindings for the OSX Cocoa API." No native extension of its own, but it needs the `ffi` gem (which has one) and `activesupport`, and it loads `/System/Library/Frameworks/Cocoa.framework/Cocoa`, which exists on a Mac only. `lib/cocoa/objc.rb` attaches `objc_msgSend` once for each return type, and `lib/cocoa/extensions.rb` and `helpers.rb` call `objc_allocateClassPair` and `class_addMethod` with FFI callbacks. It has 411 files, with a `bindings` and a `structs` directory, a layer of generated Ruby constants for Cocoa's classes. It is the closest in design and the oldest: last released in 2014, and it has no iOS path.

### The rest

- `ace-support-mac-clipboard` 0.3.5 (https://github.com/cs3b/ace) reads the macOS pasteboard through four `objc_msgSend` variants attached with `ffi`. A tool, not a bridge.
- `macos` 0.1.8 (https://github.com/ksylvest/macos) types keys and moves the mouse through CoreGraphics and ImageIO. It never calls the Objective-C runtime.
- `corefoundation` 0.3.19 (https://github.com/chef/corefoundation) wraps Core Foundation's C API over `ffi`. Core Foundation is a C library; it is not a way to send an Objective-C message.
- `RubyObjC` 0.4.0 (2009) ships `lib/objc.bundle`, `lib/librubyobjc.a`, and a copy of libffi as binaries inside the gem. It is for Ruby 1.8 on a Mac.
- `cocoawebview`, `cocoamenu`, `cocoadock` list `ext/*/extconf.rb`: C extensions that expose one AppKit feature each. `metaco` 0.3.0 describes itself as a C extension.
- `objective-ruby` 0.0.3 adds Objective-C-style named parameters to Ruby methods and never calls Objective-C. `motion-objc-runtime` 0.0.5 (2013) exposes the runtime inside RubyMotion, whose compiler provides the bridge.
- Other results (`cocoapods`, `jazzy`, `objc-referee`, `uikit-rails`, `simple-view`, `hotcocoa`) are Xcode and CocoaPods tooling, Rails front-end kits, or libraries for RubyMotion and MacRuby.

### Prior art in other Rubies

- RubyCocoa (https://github.com/rubycocoa/rubycocoa, last pushed 2017-07-08, "A Ruby/Objective-C Bridge") is a C extension: `ext/rubycocoa` holds 92 C and Objective-C files in the repository's file list. It is LGPL.
- MacRuby (https://github.com/MacRuby/MacRuby, last pushed 2015-01-03) is a separate implementation of Ruby 1.9 on the Objective-C runtime. HotCocoa 0.6.3 (2012) is its UI mapping library. Neither runs on CRuby.
- RubyMotion (https://github.com/HipByte/RubyMotion, BSD-2-Clause, last pushed 2019-06-03) compiles Ruby to a native binary with its own runtime, and gets Cocoa's functions from BridgeSupport metadata, as `motion-objc-runtime`'s README says. It is not CRuby either.

### Verdict: none

No gem gives Basket what `objc.rb` gives it. The only pure-Ruby Fiddle bridge found (`echoes`) is a terminal's private code for macOS, with fixed call shapes, AppKit loaded on require, and no iOS path. `cocoa` is the design Basket's bridge also follows (a message call chosen by type, Ruby classes that Objective-C can message), but it was last released in 2014, needs `ffi` and `activesupport`, and loads Cocoa.framework, which an iPhone does not have. Everything older is a C extension or another Ruby.

## Java through JNI

| Candidate | Latest | License | Native extension | Runs on Android under Fledge |
|---|---|---|---|---|
| `rjb` 1.7.3 | 2024-05-01 | LGPL-2.1-or-later | yes (`ext/extconf.rb`) | no |
| `dr-jni` (repository) | pushed 2025-03-02 | MIT | yes (`jni.c`) | no |
| JRuby (`jruby-jars` 10.1.3.0) | 2026-11-05 | EPL-2.0, GPL-2.0, LGPL-2.1 | not applicable | no |
| `ruboto` 1.6.1 | 2017-03-15 | MIT | not applicable | no |

- `rjb` (https://rubygems.org/gems/rjb, https://github.com/arton/rjb) is the CRuby gem for this, "a Bridge library which connects Ruby and Java code using the Java Native Interface". It is a C extension (`ext/rjb.c`, `ext/load.c`), asks for `JAVA_HOME`, and starts a Java VM of its own: `ext/load.c` looks up `JNI_CreateJavaVM`. Neither `JNI_GetCreatedJavaVMs`, which would attach to the VM an Android process already has, nor any mention of Android is in the gem. It does define `Rjb.bind` for Ruby objects that implement a Java interface, through a Java source file it ships as `ext/RBridge.java`; whether that works on Android's dex files was not checked. It is maintained (102 releases since 2009) and is the answer to the question for a desktop JVM only.
- `dr-jni` (https://github.com/kfischer-okarin/dr-jni, "JNI bindings for Android DR games") holds `jni.c`, a C extension, and its test game has the `app/main.rb` layout of DragonRuby ("DR" is my reading of its description), a Ruby runtime that is not CRuby.
- JRuby (https://github.com/jruby/jruby, pushed 2026-11-26) has Java integration built in because Ruby runs on the JVM, so there is no bridge to call; it is not CRuby. `ruboto` (https://github.com/ruboto/ruboto) is JRuby on Android, last released in 2017.
- GitHub's code search for `JNI_GetCreatedJavaVMs` in Ruby found nothing; `GetStringUTFChars` and `CallObjectMethod` found only `neelance/java2ruby`, whose `rjava/jni` files hold JNI structure definitions for a Java-to-Ruby translator (one file read, `jni_structures.rb`). No Fiddle code that calls JNI turned up.

### Verdict: none

No gem reaches Android's Java VM from CRuby in pure Ruby. `rjb`, the one maintained CRuby-to-Java gem, has a native extension and starts its own JVM, and the other candidates run on another Ruby. Basket's Android bridging after #131 (the VM through `JNI_GetCreatedJavaVMs`, a dex class written in memory, `RegisterNatives`, `Proxy`) has no counterpart in a gem to point at.

## What follows for Basket and `doc/phones.md`

Nothing to link: no gem does the job, so Basket and `doc/phones.md` keep their bridging, and neither document should name a gem as an alternative. If Basket's bridging is later extracted into a gem, the search found no gem it would duplicate, and `echoes` and `cocoa` are the two designs to cite as prior art, with their limits above.

## What this does not cover

- RubyGems.org's search ranks by its own rules and returns a page at a time; a gem whose name and description use none of the words above would not appear. A gem published to a registry other than RubyGems.org was not searched.
- GitHub's code search indexes a repository's default branch only and not every repository. Candidates found there and not on RubyGems.org (`elten3`, a GPL-3 application with Fiddle code for macOS windows; `ruby_rpg`, a game engine with native extensions; `mikutter_macos_appicon`) were identified from the search hit and, for `ruby_rpg`, its README, and none looked like a library.
- `gem fetch` was not used; the gems came from `https://rubygems.org/downloads/`, and no gem's code was run.
