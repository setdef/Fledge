<!--
SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>

SPDX-License-Identifier: CC-BY-SA-4.0
-->

> Findings of 2026-11-25 for issue #130, on whether an app's own Ruby can drive UIKit on an iPhone with nothing of Fledge's, and on what Fledge's Ruby has to change to behave there as it does under `ruby main.rb`; and for issue #128. Requested: written by an agent and not reviewed line by line. They decide nothing: the runtime, Basket, `doc/contributors/design/phone-widgets.md`, and the former ADR 103, now ADR 104, change with the code.

# Pure Ruby and UIKit on an iPhone

Fledge's iOS runtime carries `Fledge::ObjC` (`runtime/mobile/vendor_ruby/fledge/objc.rb`), a library that no Ruby has under `ruby main.rb`, and `examples/basket` calls it. Issue #130 asks first whether Basket's own Ruby, with only Ruby's standard library and bundled gems, could do what that library does on a real iPhone: whether `Fiddle::Closure` works there under code signing, which thread a program's Ruby runs on, and whether what else Basket needs (a protocol the Objective-C runtime does not hold, a struct by value, a block) is in reach of plain Fiddle. Issue #128 asks why the keyboard's Return added nothing on an iPhone while the Add button worked.

Every answer below that an experiment could settle was settled by one, on an iPhone 12 mini (`iPhone13,1`) running iOS 27.2.1 (`24B156`), with Developer Mode on.

## How the experiments ran

The iOS runtime was built afresh from `trunk` at 3830c1f0 (`ruby tasks/runtime_builder.rb ios`, which reported `ios: building, because fledge-runtime-0.17.0-ios.tar.gz is not there`), on a Mac with Xcode 27.2 (`27B52`). With it, `fledge build ios` wrote three projects: `examples/basket` as it is on `trunk`, and two builds of a probe app, one with `kind: windowed` and one with no `kind`, so the iOS host runs the probe's Ruby on the main thread in the first and on a thread of its own in the second (`lib/fledge/templates/ios/Host/main.m`, lines 52 to 62 and 92 to 103). `xcodebuild` built each for `iphoneos` with `CODE_SIGNING_ALLOWED=NO`, and the mobile parity check's UI test (`tasks/mobile_parity/ios_ui`) with `build-for-testing` the same way. Each app was then signed for development with an `Apple Development` certificate and a profile that lists the iPhone, installed with `xcrun devicectl device install app`, and launched with `xcrun devicectl device process launch --console`, which carries the app's standard output and standard error to the Mac; a run that had to go on without the console wrote its lines to a file in the app's `Documents` folder too, copied off with `xcrun devicectl device copy from --domain-type appDataContainer`, and a crash report came off with `--domain-type systemCrashLogs`. Reading an iPhone's unified log from a Mac needs root (`doc/contributors/device-test.md`, "On an iPhone, 2026-11-21"); the console and the container need nothing.

The probe is one Ruby file that requires `fiddle` and nothing else. It never loads `fledge/objc`. The same file ran under `ruby` on an Apple silicon Mac (macOS 27.2, Ruby 4.1.0-preview1 as `mise.toml` pins it) for comparison.

## 1. Fiddle's closures work on an iPhone, through libffi's trampoline table

**Finding.** A method whose implementation is a `Fiddle::Closure`, added to a class made with `objc_allocateClassPair` and `class_addMethod`, answers on the iPhone, through `objc_msgSend` and through Foundation's compiled `performSelector:`:

```
PROBE thread: pthread_main_np() = 1, Thread.current == Thread.main: true, RUBY_PLATFORM arm64-darwin, ...
PROBE closure: class_addMethod [true, true]; [probe twice:20] through objc_msgSend = 41, on Thread.main; [probe performSelector:@selector(myself)] returns the probe: true
PROBE closure: its code at 0x100b58000 is in no image (dladdr 0), kr=0 region 0x100b58000+0x4000 protection r-x max rwx
PROBE closure: fiddle's Init_fiddle at 0x100dcdbc8 is in fledgerubyext.fiddle.bundle, kr=0 region 0x100dc8000+0x1c000 protection r-x max rwx
PROBE closure: the 16 bytes at its code: 1000fe10114240a900021fd61f2003d5
PROBE closure: its first instruction is adr x16, -16384; there, kr=0 region 0x100b54000+0x4000 protection rw- max rwx, holds 0x1567d1800 and 0x100dd82b0, which is in fledgerubyext.fiddle.bundle
```

The closure's code is in no loaded image, on a page that is readable and executable and not writable. Its 16 bytes are `adr x16, -16384; ldp x17, x16, [x16]; br x16; nop`, the entry libffi assembles into its trampoline page (libffi v3.5.2, `src/aarch64/sysv.S`, lines 606 to 611). The page 16 KB below it is writable and not executable, and holds two pointers, the second inside fiddle's own extension: the closure and the function the trampoline jumps to, which is what `ffi_prep_closure_loc` writes into a trampoline table's config page (`src/aarch64/ffi.c`, lines 881 to 888). No page is both writable and executable, and no code was made at run time.

**Why it takes that path.** The runtime configures libffi with `--host=aarch64-apple-darwin` for both iOS slices (`tasks/runtime_builder/ios.rb`, lines 114 to 116; `tasks/runtime_builder/mobile.rb`, `build_autotools`), the libffi `runtime/sources.yml` pins under `mobile` (3.5.2). libffi's `configure.ac` defines `FFI_EXEC_TRAMPOLINE_TABLE` for `aarch64-apple-*`, "Cannot use PROT_EXEC on this target" (lines 233 to 240), and the build's `fficonfig.h` for the device slice says `#define FFI_EXEC_TRAMPOLINE_TABLE 1` and leaves `FFI_MMAP_EXEC_WRIT` and `FFI_EXEC_STATIC_TRAMP` undefined. With it, `ffi_closure_alloc` (`src/closures.c`, line 303) takes an entry from a table that `ffi_trampoline_table_alloc` (line 205) makes by allocating two pages (line 218) and mapping the trampoline page compiled into the signed binary over the second with `vm_remap` (line 236). fiddle 1.1.8, the version Ruby 4.1.0-preview1 bundles (`gems/bundled_gems`, line 46), calls `ffi_closure_alloc` and `ffi_prep_closure_loc` whenever its `extconf.rb` finds `ffi_closure_alloc` (`extconf.rb`, line 175; `ext/fiddle/closure.c`, lines 21 to 26, 245, and 322 to 324), and the device slice's `fiddle.bundle` defines `_ffi_closure_alloc` and `_ffi_prep_closure_loc` (`nm -m`).

**What a device refuses.** fiddle's other path, without `ffi_closure_alloc`, maps a writable page and makes it executable with `mprotect` (`ext/fiddle/closure.c`, lines 247 to 248 and 326 to 331). The probe tried each step on the iPhone:

```
PROBE w^x: mmap(PROT_READ|PROT_WRITE|PROT_EXEC) succeeded, kr=0 region 0x100b5c000+0x4000 protection rw- max rwx
PROBE w^x: mmap(PROT_READ|PROT_WRITE|PROT_EXEC, MAP_JIT) failed, errno 1
PROBE w^x: mprotect(PROT_READ|PROT_EXEC) of a page mapped writable returned 0, kr=0 region 0x100b5c000+0x4000 protection r-x max rwx
```

iOS drops the execute bit from a mapping asked for writable and executable, refuses `MAP_JIT` with `EPERM` to an app without the JIT entitlement, and lets a written page become readable and executable. Calling such a page (two instructions, `mov x0, #42; ret`) ended the probe with `SIGKILL`; its crash report gives `EXC_BAD_ACCESS`, `KERN_PROTECTION_FAILURE`, and the termination `namespace` `CODESIGNING`, `indicator` `Invalid Page`.

The same probe, built for the Simulator from the same runtime and run in an iOS 26.1 Simulator on the build machine, took the same trampoline (the same 16 bytes, the config page 16 KB below), but there `mmap` refused a writable and executable mapping with `EACCES`, granted one with `MAP_JIT`, and the page made executable with `mprotect` returned 42 when called, as under `ruby` on the Mac. So the Simulator runs a closure from a page an iPhone kills the process for, and only a device shows which path a closure takes.

**What it means.** On an iPhone, a Fiddle closure is as sound as libffi's trampoline table, which Fledge's pinned libffi uses for every Apple arm64 target. An app's own Ruby can make Objective-C methods out of Ruby blocks there with `Fiddle::Closure`, as a script under `ruby main.rb` on a Mac can; nothing of Fledge's is needed for it. What would break it is a libffi configured for a host outside `aarch64-apple-*`, or a fiddle built without `ffi_closure_alloc`: both would fall back to a page a device kills the process for. A test that the device slice's `fficonfig.h` defines `FFI_EXEC_TRAMPOLINE_TABLE`, or that `fiddle.bundle` defines `_ffi_closure_alloc`, would keep that from coming back unnoticed; the Simulator would not catch it, since it runs code from a page made executable at run time.

## 2. The thread a program's Ruby runs on

**Under `ruby main.rb`.** Ruby's `main` calls `ruby_init` on the process's main thread (`main.c`, lines 38 to 62 at v4.1.0-preview1). `Init_BareVM` makes the thread that boots the VM its main thread (`vm.c`, lines 4995 to 5027), `Init_native_thread` records that thread's `pthread_self()` as its native thread (`thread_pthread.c`, line 445), and `Thread.main` is the main ractor's main thread (`thread.c`, lines 3501 to 3505). So under `ruby main.rb` on a Mac, `Thread.main` is the thread the system started the process on, and the probe's `pthread_main_np()` is 1 there.

**Under Fledge on an iPhone.** With `kind: windowed`, the host calls `fledge_ruby_run_app` from `main` (`Host/main.m`, lines 52 to 62), and the probe printed `pthread_main_np() = 1`. With no `kind`, the host starts Ruby on an `NSThread` and calls `UIApplicationMain` on the main thread itself (lines 92 to 103), and the probe printed:

```
PROBE thread: pthread_main_np() = 0, Thread.current == Thread.main: true, ...
```

`Thread.main` there is a thread the system did not start the process on: a difference from `ruby main.rb` that a program can see, through `pthread_main_np`, `+[NSThread isMainThread]`, or any library that asks. It is also one a program cannot work around. UIKit calls a delegate, a data source, or a target on the main thread, and a Fiddle closure called on a thread Ruby did not make asks for Ruby's lock with `rb_thread_call_with_gvl` (`ext/fiddle/closure.c`, lines 229 to 233), which prints "[BUG] rb_thread_call_with_gvl() is called by non-ruby thread" and exits (`thread.c`, lines 2320 to 2335); "You cannot convert a non-Ruby thread into a Ruby thread using this API" (`include/ruby/thread.h`, lines 111 to 113). So a program on the second thread can never take a callback from UIKit.

**The truer Ruby.** Every iOS program's Ruby runs on the main thread, whatever its `kind`, as under `ruby main.rb` and as an Objective-C program's `main` runs, and to show a screen the program hands that thread to UIKit itself, by calling `UIApplicationMain` (the iPhoneOS 27.2 SDK's `UIKit.framework/Headers/UIApplication.h`, line 565) through Fiddle.

**What iOS asks of a program that never calls `UIApplicationMain`.** The probe, built with `kind: windowed`, stayed on the main thread without calling it, sleeping a second at a time and writing a line each second. iOS ended it after 21 lines:

```
  19.03 watchdog: 20 s on this thread, without UIApplicationMain
  20.03 watchdog: 21 s on this thread, without UIApplicationMain
```

Its crash report: `EXC_CRASH`, `SIGKILL`, `namespace` `FRONTBOARD`, and the reason "code:0x8BADF00D explanation:process-launch watchdog transgression: app<com.setdef.fledge.Hello(...)>:3255 exhausted real (wall clock) time allowance of 20.00 seconds", `WatchdogEvent: process-launch`. The main thread's backtrace was `ruby_run_node`, under `fledge_ruby_run_app`, under `main`. The launch was from `devicectl` with no debugger attached.

So a program whose Ruby has the main thread has 20 seconds of wall-clock time, from launch, to reach `UIApplicationMain` and let UIKit finish launching; one that prints and exits within that time, as `examples/hello` does, ends normally (the iPhone runs of `doc/contributors/device-test.md` used the second thread, so they do not show it), and one that runs longer without a screen is ended by iOS, as a native app that never calls `UIApplicationMain` would be. Basket, whose Ruby calls `UIApplicationMain` once its classes are defined, launched within it (section 4).

**What that means for `kind: windowed` on a phone.** Today the key does one thing on iOS: it moves Ruby to the main thread and gives the executable a 64 MB stack there (`lib/fledge/mobile_project/ios.rb`, lines 129 and 174). If every program's Ruby has the main thread, the key no longer chooses anything on iOS: every host is the windowed host, every executable gets the stack, and the second host's label screen goes. To show a screen, a program calls `UIApplicationMain`, as a Mac program calls `NSApplicationMain` to show windows; a program that never calls it has the watchdog's 20 seconds. Android's half is issue #131's.

## 3. What else Basket needs, in its own Ruby

Each of these ran on the iPhone, from the probe's Ruby with Fiddle alone, and on the Mac:

```
PROBE abi: rect argument as four doubles: NSRect: {{1, 2}, {3, 4}}
PROBE abi: range argument as two integers: Basket
PROBE abi: rect result through NSInvocation: [1.0, 2.0, 3.0, 4.0]
PROBE abi: block called by -[NSArray enumerateObjectsUsingBlock:]: ["0:Milk", "1:Eggs"]; Block_copy returns the same block: true
```

- **A struct argument.** fiddle 1.1.8 has no struct type (`rb_fiddle_int_to_ffi_type`, `ext/fiddle/conversions.c`, lines 163 to 215, maps scalars and pointers only). On arm64, a `CGRect`, four `double`s, goes in four floating-point registers, so passing four `Fiddle::TYPE_DOUBLE` arguments to `+[NSValue valueWithCGRect:]` gave UIKit the rectangle; an `NSRange`, two `NSUInteger`s, goes in two integer registers, so two `TYPE_LONG_LONG` arguments gave `substringWithRange:` its range. These are arm64's calling convention (Arm's "Procedure Call Standard for the Arm 64-bit Architecture"), whose text was not read for this note: the runs above are the evidence, for these two shapes.
- **A struct result.** Fiddle returns one register, so a method that returns a `CGRect` loses three of its fields. `NSInvocation`, Foundation's own, calls the method and copies the whole result into memory Ruby made (`getReturnValue:`): the rectangle came back whole. It costs an object and five messages per call.
- **A block.** A block is a structure that begins with its class, its flags, a reserved word, its function, and a descriptor (Apple's libclosure at 3668b083, `Block_private.h`, lines 321 to 326 and 289 to 290). The probe wrote one in memory Ruby owns, with `_NSConcreteGlobalBlock` as its class, `BLOCK_IS_GLOBAL` (line 244) as its flags, and a `Fiddle::Closure` as its function; `-[NSArray enumerateObjectsUsingBlock:]` called it for each item, and `_Block_copy` returned the block itself, as it does for every global block (`runtime.cpp`, lines 878 to 880), so UIKit can keep it with no copy that Ruby would have to free. That is the shape a `UIAction`'s handler takes.
- **A protocol the runtime does not hold.** `objc_getProtocol` finds no `UITableViewDataSource` in a process whose compiled code refers to none (`phone-widgets.md`, "The iOS bridge"). UIKit asks a data source and a delegate `respondsToSelector:`, so a class that answers the selectors with the right encodings serves without declaring the protocol, as `objc.rb` does today. The encodings are in UIKit's headers, and the dozen that Basket uses are strings in Basket's own code (`objc.rb`, lines 127 to 147, has them for the three protocols Basket adopts).

**How much is Basket's own bridging.** What Basket uses of `Fledge::ObjC` is a class by name, a message typed by `method_getTypeEncoding`, a class of its own with methods that are closures, Strings and Arrays as `NSString` and `NSArray`, a reference held and given back on the main queue, `UIApplicationMain`, and those protocol encodings. `objc.rb` does that and more in 478 lines that are neither comments nor blank; Basket's own copy, without the parts it does not call, is an estimate of 200 to 300 such lines beside its 117 lines of screen, not a measurement.

## 4. Issue #128: Return reaches Ruby on an iPhone

**Finding.** With `trunk`'s Basket on the runtime of section 1, the mobile parity check's own UI test (`tasks/mobile_parity/ios_ui/ListUITests/ListTest.m`) ran on the iPhone, signed as section "How the experiments ran" says: it typed `Milk`, tapped the on-screen keyboard's return key, waited for the row, swiped it left, and tapped Delete. `xcodebuild test-without-building` passed it (`Tapped the keyboard's return key`, `Typed Milk and Return: a row shows it`, `Swiped Milk left and tapped Delete: its row went`), and Basket's own console said:

```
Basket shows 0 items
Basket added Milk
Basket removed Milk
```

A second run typed `Mlik`, to give autocorrection something to change, and Basket printed `Basket added Mlik` and `Basket removed Mlik`. No Ruby backtrace reached standard error in either run.

**What it means.** Return's action, `UIControlEventEditingDidEndOnExit` ("'return key' ending editing", `UIControl.h`, line 34), reached Ruby on an iPhone, and so did the swipe's `tableView:commitEditingStyle:forRowAtIndexPath:`. #128 is not the closure question: Return and the Add button send the same selector, `add:`, to the same object, whose implementation is one closure (`examples/basket/lib/basket/ios.rb`, lines 60 to 65, 114, and 117), and that closure answered the button on the same night #128 was seen, and answered Return here. What made Return add nothing on the iPhone #128 describes, with Basket built from 49c98724, is not known: Basket's Ruby for Return is the same now as then (`git diff 49c98724 HEAD` adds only the `puts` lines, the `or return`, a reader for the field, and comment markers), and the runtime is not. A person's own keyboard differs from XCTest's in what this note could not try: predictive text and a person's autocorrection settings. A check by hand on a current build, launched with `xcrun devicectl device process launch --console` so that `Basket added` and any backtrace show on the Mac, would say whether it still happens.

## 5. What stays unproven

- **App Review** of an app whose UIKit calls are sent from Ruby, and of global blocks built in Ruby's memory (`doc/contributors/account-tests.md`, IOS-6).
- **The watchdog in the Simulator, and under Xcode's Run.** Only a device launch without a debugger was measured. A debugger may suspend the watchdog; whether CI's Simulator apps that keep their Ruby on the main thread for long without a screen would be ended was not tried.
- **How long Ruby takes to reach `UIApplicationMain`** for an app with many gems on an older iPhone; Basket's took less than the 20 seconds, and was not timed.
- **Struct shapes beyond the two tried.** A struct larger than 16 bytes that is not four or fewer floating-point fields of one type goes by another rule, which was not tried; `NSInvocation` takes any argument by pointer and so covers it, at its cost.
- **#128's cause** (section 4).
