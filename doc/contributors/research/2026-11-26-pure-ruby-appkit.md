<!--
SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>

SPDX-License-Identifier: CC-BY-SA-4.0
-->

> Findings of 2026-11-26 for the macOS half of issue #139, on what Basket's Ruby needs, beyond what `examples/basket/lib/basket/objc.rb` does on iOS, to draw the shopping list with AppKit on a Mac in an app `fledge build` makes. Requested: written by an agent and not reviewed line by line. They decide nothing: Basket, the runtime, and `doc/contributors/design/phone-widgets.md` change with the code.

# Pure Ruby and AppKit on a Mac

Issue #139 asks what AppKit needs beyond `Basket::ObjC`: `NSApplicationMain` and the app's menu, a window with a table, and whether an app bundle that `fledge build` writes needs any key. The answer below comes from a probe, a Ruby program that requires only `fiddle` and Basket's unchanged `objc.rb`, that opens Basket's window with AppKit. It ran under `ruby` and, built into an app by `fledge build`, through Launch Services.

## How the experiments ran

The probe is `main.rb` of a scratch app, about 290 lines that are neither comments nor blank, kept outside the repository. It defines a Ruby class for each of the app delegate, the table's data source and delegate, the button's target, and a subclass of `NSTableView`. It builds a menu bar, a window, a text field, an Add button, and a table, and takes its list from `examples/basket/lib/basket/list.rb`. With `BASKET_SELFTEST` set, one second after launch it drives the window (sets the field, clicks the button, selects a row, sends key events and menu commands), prints what each did, draws the window's content view into a PNG, and quits.

Each run went through `machines run macos --require gui=true`, on the Mac node (Apple M1 Max, macOS 27.2.1, Ruby 4.1.0-preview1 as `mise.toml` pins it, Xcode 27.2, SDK 27.2), whose account is in a GUI session (`launchctl managername` printed `Aqua`). Three kinds of run:

1. The probe under `ruby`, with the Edit menu and without it (run `20261126-032125-a8674c`).
2. The probe as `BasketMac.app`, built by `exe/fledge build` from a `fledge.yml` of three keys (`name`, `identifier`, `kind: windowed`), on a runtime that `rake runtime` built in the same workspace (the build said the runtime's SHA-256 does not match the pin and used it unchecked, as `FLEDGE_RUNTIME_DIR_UNCHECKED` asks). The bundle's program ran with `env -i PATH=/usr/bin:/bin`, which has no Ruby, and through `open -n -W` (runs `20261126-030741-746133`, `20261126-031017-8d2397`, `20261126-031401-d1c7f8`).
3. The same bundle through `open`, once with the Edit menu and once without.

The node's session is switched away from any screen, so no frame reached a display (`macos-nodes.md`, "A window: a node in a GUI session"). What the runs check is what the program can see: the view hierarchy, the data source's calls, key and menu dispatch, and an image AppKit draws of the content view into memory.

## 1. The launcher already gives AppKit the main thread

The launcher calls `ruby_start_main` from `main` (`runtime/launcher/unix.c`, lines 635 to 637), whose callback runs Ruby on the thread that called it, and `launcher.md` says the app's program runs on the process's main thread (line 77). In every run the probe printed `pthread_main_np=1 Thread.current==Thread.main true`, under `ruby` and in the built app, in the app delegate's callback and in the self-test's. `[NSApp run]` therefore works from Ruby as it does from an Objective-C `main`, with no host thread to hand over, and no change to the launcher or the runtime.

The launcher's one AppKit-adjacent step, `fledge_launch_documents`, runs only for a bundle that declares document types and makes no `NSApplication` and installs no delegate (`runtime/launcher/documents.c`, lines 15 to 30). Basket declares none, and the built app ran.

## 2. What the built app's bundle holds, and needs

`Info.plist` of the built `BasketMac.app` (printed with `PlistBuddy`): `CFBundleExecutable`, `CFBundleIdentifier` (`com.setdef.fledge.BasketMac`), `CFBundleName`, `CFBundleDisplayName`, `CFBundlePackageType` `APPL`, `CFBundleInfoDictionaryVersion`, `CFBundleDevelopmentRegion`, `CFBundleShortVersionString`, `CFBundleVersion`, `LSMinimumSystemVersion` `26.0`, and `NSHighResolutionCapable` true; these are the keys `lib/fledge/mac_bundle.rb` writes (lines 160 to 171). The bundle is signed ad hoc (`codesign -dv`: `Signature=adhoc`, `Format=app bundle with Mach-O thin (arm64)`). `NSBundle.mainBundle.bundleIdentifier` answered `com.setdef.fledge.BasketMac` in the built app and `""` under `ruby`.

- **`NSPrincipalClass` is not needed.** Apple's page says the key sets the bundle's `principalClass` when the bundle loads (`developer.apple.com/documentation/bundleresources/information-property-list/nsprincipalclass`, fetched 2026-11-26), and `NSApplicationMain` reads it to make `NSApp` (`NSApplication.h`, line 615). The probe calls `NSApplication.sharedApplication` itself, as a Ruby program must: `NSApplicationMain` would need `argc` and `argv` and gives Ruby no point to define its classes first. The key was absent (`principal=""`), and the app ran.
- **`NSHighResolutionCapable` is already there.** The window's image came out 960 by 720 pixels for a 480 by 360 point content view, a 2x rendering.
- **The activation policy is set by the program.** The probe calls `setActivationPolicy(0)` (`NSApplicationActivationPolicyRegular`) before `run` (`NSRunningApplication.h`, lines 34 to 42; `NSApplication.h`, line 306), and no run left it out, so whether a bundle needs the call is not known. In the bundle started by `open`, the app was active and its window key and main (`isActive=true key=true main=true`). Started by running the bundle's program from a shell, or under `ruby`, the app was not active and its window not key, even after `NSApp.activate` (`NSApplication.h`, line 236). A shell launch is not how a person starts an app, and with Launch Services no `LSUIElement` or other key was needed.
- **`LSMinimumSystemVersion` is 26.0** (`platform.rb`, line 57), and `arm64-darwin` is the only macOS platform (`platform.rb`, line 51). That fixes the calling convention in section 4 to arm64's.

## 3. What a screen by Apple's guidelines needs, and what `objc.rb` does for each

Apple's Human Interface Guidelines for the menu bar list the menus in order: the app's, File, Edit, Format, View, app-specific menus, Window, Help (`developer.apple.com/design/human-interface-guidelines/the-menu-bar`, "Anatomy", fetched 2026-11-26). The app menu holds About, Settings, Services, Hide, Hide Others, Show All, and Quit; Edit holds Undo, Redo, Cut, Copy, Paste, Delete, and Select All among others; Window holds Minimize and Zoom, "even if your app has only one window". "Because many editing commands apply to any editable content, the Edit menu is useful even in apps that aren't document-based", and "a Delete menu item behaves the same as pressing a Delete key" (`developer.apple.com/design/human-interface-guidelines/edit-menus`, "Best practices").

| Need | AppKit | `objc.rb` today | Proven |
| --- | --- | --- | --- |
| The app and its main thread | `NSApplication.sharedApplication`, `setActivationPolicy:`, `setDelegate:`, `run` (`NSApplication.h`, lines 199, 262, 306) | `application_main` calls `UIApplicationMain` only (line 201), but plain messages reach all four; `load_framework("AppKit")` loads AppKit | yes |
| The delegate | `NSApplicationDelegate`: `applicationDidFinishLaunching:`, `applicationShouldTerminateAfterLastWindowClosed:` (`NSApplication.h`, lines 427 and 518) | `PROTOCOL_ENCODINGS` (line 149) holds UIKit's three protocols; AppKit's four selectors need entries | yes, with entries added |
| The menu bar | `NSMenu`, `NSMenuItem.initWithTitle:action:keyEquivalent:`, `mainMenu`, `windowsMenu` (`NSMenu.h` lines 60 and 92; `NSMenuItem.h` lines 40, 52, 59, 81; `NSApplication.h` lines 291 and 372) | plain messages; an action is a selector String, which `to_c` already converts for `:` | yes |
| A window | `+[NSWindow windowWithContentViewController:]` (`NSWindow.h`, line 655), which takes no `NSRect`; `initWithContentRect:styleMask:backing:defer:` (line 293) takes one | the first works; the second needs a struct argument | yes, both |
| A table with a data source | `NSTableView`, one `NSTableColumn`, `dataSource` and `delegate`, `numberOfRowsInTableView:` (`NSTableView.h`, line 743), `tableView:viewForTableColumn:row:` (line 593), inside an `NSScrollView` | protocols and their encodings, as above | yes |
| A field and a button | `NSTextField`, `placeholderString`; `+[NSButton buttonWithTitle:target:action:]` (`NSButton.h`, line 41) | plain messages | yes |
| Layout | `+[NSStackView stackViewWithViews:]` (`NSStackView.h`, line 108), `edgeInsets` (line 124, an `NSEdgeInsets`), anchors | an Array becomes an `NSArray`; `edgeInsets=` needs a struct argument | yes, with the struct argument |
| Removing a row | the Delete key, the context menu (`NSView.menu`), and Edit > Delete | a subclass of `NSTableView` with `deleteBackward:` needs no superclass call | menu routes yes; key route partly (section 5) |
| Copy and paste in the field | an Edit menu whose items send `cut:`, `copy:`, `paste:`, `selectAll:` along the responder chain | plain messages | yes, and the menu is required (section 5) |

`NSApplicationMain` is not needed and not recommended (section 2). The row's view is a label made with `+[NSTextField labelWithString:]`, reused through `makeViewWithIdentifier:owner:`.

## 4. What `objc.rb` lacks, and what each lack costs

Three things stopped the unchanged `objc.rb`. Each is in the probe as a patch that a real change would move into `objc.rb`.

**Protocol encodings.** `objc_protocols` raises for a protocol it has no encodings for (line 501). The probe adds `NSApplicationDelegate`, `NSTableViewDataSource`, `NSTableViewDelegate`, and `NSMenuItemValidation` with five selectors, each taken from the SDK's headers and counted by arm64's frame (`v24@0:8@16` for one object argument, `@40@0:8@16@24q32` for `tableView:viewForTableColumn:row:`). `objc_getProtocol` found `NSTableViewDataSource` on the Mac (`protocol found=true`), where it finds no UIKit protocol on an iPhone, so the table is a convenience here, and `objc_method` accepts an encoding as its second argument without it.

**A struct passed by value.** `to_c` raises "Fiddle cannot pass an argument of type {...}" (line 306), and `FIDDLE_TYPES` (line 116) has no struct. The probe flattens a struct of up to four doubles into that many `Fiddle::TYPE_DOUBLE` arguments, as the iPhone research did for `CGRect` (`2026-11-25-pure-ruby-uikit.md`, section 3), in 27 lines that replace `send_message` for encodings that contain a `{`. It passed an `NSEdgeInsets` (`edgeInsets=`), an `NSSize` (`setContentSize:`), an `NSPoint` (the location of `+[NSEvent keyEventWithType:...]`), and an `NSRect` (`bitmapImageRepForCachingDisplayInRect:` and `cacheDisplayInRect:toBitmapImageRep:`), and AppKit used each: the window's content size and the image's 960 by 720 pixels follow from them. This holds on arm64 only, which is the only macOS platform. A struct result (a view's `frame`) still cannot return: Fiddle returns one register, so the probe reads no frame, and `NSInvocation` is the way, as the iPhone note says.

**An `NSArray` read as a Ruby array.** `objc.rb` converts a Ruby Array to an `NSArray` and has no way back, so `view.subviews.to_a` raised "does not answer to_a". The probe reads one with `count` and `objectAtIndex:` in three lines. Basket's screen does not need it; a test that walks the view hierarchy does.

What `objc.rb` already did without change: the `NSObject` and `NSTableView` subclasses (a subclass of a class AppKit owns, `BasketTable`, registered and answered), closures as methods on the main thread, strings and arrays crossing, a Ruby object kept alive for the weak `dataSource` and `delegate` properties (`NSTableView.h`, line 148), and `dealloc`'s superclass call. No block was needed, and no superclass call beyond `dealloc`.

## 5. What ran, and what did not

Facts from the built app through `open` unless the line says otherwise.

- **The view hierarchy** AppKit built from the probe's calls: an `NSStackView` of an `NSStackView` (an `NSTextField` with its field editor `NSTextView`, and an `NSButton`) above an `NSScrollView` whose clip view holds `BasketTable`.
- **The menu bar** read back: `["Basket", "File", "Edit", "Window"]`. Without the Edit item it read `["Basket", "File", "Window"]`.
- **The button.** `performClick` on Add after setting the field to `Milk`: the list held `["Milk"]`, the field emptied, the table had one row, and its row view was an `NSTextField` reading `Milk`.
- **Three ways to remove a row** each took one row away and logged `Basket removed Rice`: the context menu's Delete item (`performActionForItemAtIndex`), Edit > Delete, and the key equivalent Command-Delete sent to `NSApp.mainMenu.performKeyEquivalent` (it returned true with the Edit menu and false without it). Under `ruby`, run `20261126-032125-a8674c`.
- **The Delete key's action.** `interpretKeyEvents:` on the table with a Delete key event called the subclass's `deleteBackward:` and removed the row, so the responder-chain route works.
- **Paste.** With "Bread" on the pasteboard, the field editor first responder, and Command-V sent through `NSApp.sendEvent`, the field read `Bread` with the Edit menu and `""` without it (through `open`, so the app was active; where the app was not active, nothing pasted with or without the Edit menu). The Edit menu is what routes Command-C and Command-V to the field.
- **The context menu's Delete** was enabled with a row selected (`validateMenuItem:`, the Ruby method, answered true).
- **The window as an image.** `cacheDisplayInRect:toBitmapImageRep:` drew the content view into a 960 by 720 pixel PNG of 25 KB: the field with its placeholder "Add an item" and a rounded Add button above three rows, "Milk", "Eggs", and "Bread". The rows sit against the left margin with no inset, since a bare label has none; an `NSTableCellView` would give them padding.
- **No Ruby on `PATH`.** The bundle's program ran under `env -i PATH=/usr/bin:/bin` and made the same window and logs.

Not shown by a run:

- **A person's Return and Delete keystrokes.** Synthesized `NSEvent`s sent through `NSApp.sendEvent` did not press the default Add button or reach `deleteBackward:`, with or without `window.defaultButtonCell` and a direct `table.keyDown:`, in an active app with a key window. Command-V through the same path worked, so the path delivers events; why these two did not is unknown. A real keystroke needs a person or an accessibility-driven UI test, which a node's account may not have (`macos-nodes.md` lists it as not tried). Basket's Add reaches Ruby by the button's action, which the run proved, and Return by the default button or by the field's action, neither proven by a keystroke. Basket on iOS has the same gap that research closed on an iPhone with XCTest (`2026-11-25-pure-ruby-uikit.md`, section 4).
- **Any frame on a display.** The node presents none.
- **The `windows=` count.** `NSApp.windows.count` was 2 or 3 with one window made, which the probe did not explain.
- **Dark appearance, Retina on a real display, full-screen, the Dock menu, and VoiceOver.**
- **An Intel Mac.** Fledge builds none (`platform.rb`, line 51).

## 6. What Basket's screen and bridge would cost

These numbers are estimates from the probe's line counts, not measurements of code that exists.

- **`objc.rb`:** about 40 more lines that are neither comments nor blank: the AppKit encodings (about 12), struct arguments folded into `send_message` (about 15, where the probe's separate patch takes 27), and the NSArray reader (3). It grows from 400 to about 440.
- **`macos.rb`:** about 150 lines for the screen: an action target and a data source (about 30), the table subclass (5), the window and its views (about 35), a menu builder and the four menus (about 45), and the delegate and `run` (about 15). `ios.rb` is 117. The probe's remaining lines are its self-test, which a test file would take.
- **`main.rb`** gains a branch: on Darwin, `load_framework("UIKit")` fails on a Mac (`UIKit loads=false`) and `load_framework("AppKit")` succeeds, so the existing `ios` test chooses the platform and an `elsif` chooses `Basket::MacOS`.
- **`fledge.yml`** is unchanged: `kind: windowed` already makes a bundle.
- **Tests.** `test/basket_bridge_test.rb` runs `objc_test.rb` on a Mac without a window; struct arguments and the NSArray reader are testable there with Foundation's `NSValue` and `NSArray`. A screen test needs a window server. A Delivery job needs the built `Basket.app` run on a Mac with no Ruby, which the probe did as `env -i` with a minimal `PATH`; whether CI's runners show a window is unknown.

## 7. Decisions the implementation needs

1. **One `objc.rb` for both Apple systems, or one per system.** Recommended: one, extended in place. The struct arguments and the protocol table serve UIKit too (`CGRect`), the file is already Basket's, and a second copy would diverge. Its cost is a file that holds AppKit and UIKit protocols together, about 12 more table lines.
2. **How Return adds an item.** Recommended: the default button (`keyEquivalent` `"\r"`) with a keystroke test in an accessibility-driven UI run once one exists. The alternative is the field's action (`target` and `action`), which Cocoa text fields send on Return (not checked here; `NSControl.h`, lines 24 and 25 declare the properties) and which would double the button's call if both are set. Neither is proven by a keystroke.
3. **How Delete removes a row.** Recommended: all three routes the probe proved (Edit > Delete with Command-Delete, a context menu, and `deleteBackward:` on a table subclass), since the guidelines call Delete the same as the key. The subclass adds five lines.
4. **Whether the Mac screen is Basket's task or a framework's.** It is Basket's, as the iOS and Android screens are: no helper of Fledge's is involved anywhere above, and the runtime and launcher need no change.

## 8. What stays unproven

- A person's Return and Delete keystrokes (section 5).
- A built Basket in Delivery on a fresh Mac: the probe ran in a node's GUI session whose account has Xcode and mise installed, with `PATH` stripped of Ruby, not on a Mac that never had either.
- Gatekeeper and notarization of an app whose Ruby calls AppKit, and App Store review of one.
- Whether `NSApp.activate` brings a bundle launched by a person's double-click to the front the same as `open` did here; `open` is Launch Services, as a double-click is.
- The `windows=` count.
