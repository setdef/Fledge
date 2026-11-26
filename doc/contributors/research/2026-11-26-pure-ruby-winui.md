<!--
SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>

SPDX-License-Identifier: CC-BY-SA-4.0
-->

> Findings of 2026-11-26 on how a Ruby program with Fiddle alone starts WinUI 3 and draws a window of Windows' controls, for issue #139: the Windows App SDK's runtime, WinRT calls, callbacks into Ruby, and a probe that ran on Windows. Requested: written by an agent and not reviewed line by line. They change no design document, no ADR, and no example.

# WinUI 3 from pure Ruby: what the sources and a probe say

Basket draws its screen on iOS and Android with each phone's widgets, in Ruby over Fiddle (ADR 104). Issue #139 asks for the same on the desktops. On Windows the controls are WinUI 3, "Microsoft's modern native user interface framework for building Windows desktop applications", delivered with the Windows App SDK (Microsoft Learn, "WinUI 3", lines 12 to 14). WinUI 3 is a WinRT API, written for C# and C++/WinRT. This note asks how a Ruby program with no .NET, no C++/WinRT projection, and no file of Fledge's starts it, how it calls WinRT and takes WinRT's calls, how it builds a screen, and what a computer that runs the app needs.

## Verdict

- **WinUI 3 starts in a Ruby process with nothing installed, by the self-contained route.** The probe copied the Windows App SDK 2.7.0's DLLs from four NuGet packages into a folder, loaded them, made one activation context from the packages' class lists, called `RoInitialize` and `Application.Start`, and drew a window. Nothing went into the registry, the profile, or `Program Files`. Ruby over Fiddle does each step that the Windows App SDK's build tools do for a self-contained app, and a shell script only fetches and unpacks the packages. The probe's last run exited with status 0.
- **A Ruby program calls WinRT by vtable slot, and WinRT calls Ruby through closures.** Classes come from `RoGetActivationFactory` and `RoActivateInstance` with an HSTRING name. Each interface's IID and slot numbers come from the SDK's `.winmd` files. Ruby makes the event handlers and the `Application` subclass as COM objects whose vtables are `Fiddle::Closure`s, and WinUI called them: `OnLaunched`, `Click`, `KeyDown` (registered, not raised in the run), and a timer's `Tick`.
- **The callbacks run on Ruby's main thread.** `Application.Start` runs its message loop on the thread that calls it, until `Application.Exit`. A trace of an early form of the probe printed the Windows thread id in each of 44 callbacks, and printed one id, the one of the thread that had called `Application.Start`.
- **The screen is a window with a list, a button that adds a row, and a button that removes one, and its rows changed as the code expected.** UI Automation's invoke pattern clicked the buttons, which raised `Click` in Ruby, which appended and removed rows of a `ListView`. The layout pass ran (the content measured 1424 by 734). No pixel was looked at.
- **A text box does not work on the computer that ran the probe, by any route tried.** A `TextBox`, `PasswordBox`, `RichEditBox`, or `AutoSuggestBox` in a window ends the process with a stowed exception from `Microsoft.ui.xaml.dll`, with the self-contained route on Windows App SDK 2.7.0, on 1.8.260921001, and through the bootstrapper with the runtime Windows had registered. `ComboBox`, `CheckBox`, `Slider`, `Button`, and `ListView` work. The cause is not found. `XamlReader.Load` also fails on markup with a `TextBox`, and `XamlControlsResources`, which WinUI 3 apps merge for the Fluent styles, fails to activate. Both are in "What did not work".
- **A built app would carry 33 files and 174 more, 56 MB (21.5 MB zipped), under Microsoft's license terms, and no Visual C++ runtime.** The license allows redistribution with three conditions that fall on whoever distributes the app (section 7). The DLLs import no Visual C++ runtime library, and none loaded in the run.

## The probe

The probe is one Ruby file of 480 lines (362 besides comments and blank lines), which requires only `fiddle`, and a shell script that fetched its inputs. Appendix A is the file and Appendix B the script. It ran under the Ruby that Fledge's Windows runtime comes from, the RubyInstaller head build of 2026-11-10 that `mise.toml` pins (Ruby 4.1.0, `x64-mingw-ucrt`, Fiddle 1.1.8), as `ruby.exe`, not as a Fledge app.

It ran on one Windows 11 Pro x64 computer, build 10.0.26300, in about forty runs. Each run's script downloaded the packages into a cache, checked each against the SHA-256 below, unpacked what it needed with Windows' `tar.exe` into a temporary folder that the run made and removed, and ran the probe from there. A run installs nothing. Each ran on a desktop that was not the signed-in person's, one made for the run, where screenshots through GDI or DWM come out blank and no input can be injected, so the probe took no screenshot and clicked through UI Automation.

The packages, all from nuget.org, each pinned by version and the SHA-256 of the `.nupkg` as downloaded for this note:

| Package | Version | SHA-256 |
|---|---|---|
| Microsoft.WindowsAppSDK.Foundation | 2.7.0 | `4131660bda7476eef751ce134c9847b5a79e4051809bffbf9dd171f4246afdf8` |
| Microsoft.WindowsAppSDK.WinUI | 2.7.0 | `027ecdc0c51a2d31fd25985616ef2e9438f02ee3e7b6e72fd0601ddb119688b4` |
| Microsoft.WindowsAppSDK.InteractiveExperiences | 2.7.0 | `5df51fd9e30a6093f737698ae8ad4e8d62d87f7081b00aa6a4ea0b893f03e1c2` |
| Microsoft.WindowsAppSDK.DWrite | 2.7.0 | `d9ea79e67c2379d100a51a8ea681d1fb21af211c1a6676fd60ecf7795ac46a44` |
| Microsoft.WindowsAppSDK.Base | 2.7.0 | `a2a858ceacb3a7735ae491837f50f707502efea74d2d3e3f8684cc924f7e6829` |
| Microsoft.WindowsAppSDK.Runtime | 2.7.0 | `326b47f40f051e767bfc83ce99c753c758bbba75a25f0a4febab8cd9ea8b5152` |
| Microsoft.Windows.SDK.Contracts | 10.0.28000.2957 | `9fa4ef0e9046d17ded567cc69431924ffe0dc39eed86caea543be3bc23abb971` |
| Microsoft.WindowsAppSDK.Foundation | 1.8.260803002 | `b9232041afd605b606c6f78f442d92ead0076453f1f2a3260d2b7f8089bcab0e` |
| Microsoft.WindowsAppSDK.WinUI | 1.8.260803003 | `bdf72c0cbc385ba6e6ab916b17d3aa00950811c9d6372d11ac2f32f1c83f2496` |
| Microsoft.WindowsAppSDK.InteractiveExperiences | 1.8.260708001 | `496eea92d353b5d3601b67353f06dcadd6d2d9b635575acebe6e42587dbfad76` |
| Microsoft.WindowsAppSDK.DWrite | 1.8.25122902 | `77e0c020966a76c4755485a1011e48c6b888066b49cd6cbcd2a546817d803b6c` |

The probe copied files only from the first four. Base and Runtime were read for their build files and their MSIX packages, and Microsoft.Windows.SDK.Contracts for `Windows.Foundation.FoundationContract.winmd`. The 1.8 packages are the ones `Microsoft.WindowsAppSDK` 1.8.260921001 lists as its dependencies. The 2.7.0 meta-package depends on all of the 2.7.0 packages at exactly 2.7.0 (its `.nuspec`).

## Sources

- The packages above, unpacked for this note. Cited by package and path: `Microsoft.WindowsAppSDK.Base` 2.7.0, `build/Microsoft.WindowsAppSDK.SelfContained.targets` (lines 78 to 104, 125 to 246, and 249 to 276); `Microsoft.WindowsAppSDK.Foundation` 2.7.0, `include/MddBootstrap.h` (lines 34 and 75 to 79) and `include/UndockedRegFreeWinRT-AutoInitializer.cpp` (lines 11 and 38); each package's `license.txt` (the same file in all four, SHA-256 `5b11e6347756e40fe0274bc08c97f89201b94f0d50181a09a00f1f4740840501`), and its `runtimes-framework/package.appxfragment`, `metadata/*.winmd`, and DLLs.
- The `.winmd` files of those packages, read with a reader of ECMA-335's tables written for this note (about 150 lines of Python, run on the computer that wrote this note, and part of neither the probe nor Basket). It lists each type's `GuidAttribute` and its methods in order, which is the vtable's order after `IInspectable`'s six slots; a delegate is `IUnknown` and `Invoke`, whose slot is 3.
- Microsoft Learn's pages, read for this note from MicrosoftDocs/windows-dev-docs, branch `docs` (the branch's tip then was `a3812316d9`, dated 2026-10-14): `hub/apps/package-and-deploy/deploy-overview.md`, `hub/apps/package-and-deploy/self-contained-deploy/deploy-self-contained-apps.md`, `hub/apps/windows-app-sdk/deploy-unpackaged-apps.md`, `hub/apps/windows-app-sdk/deploy-packaged-apps.md`, and `hub/apps/winui/winui3/index.md`. Cited by title and line.
- `doc/contributors/design/desktop-apps.md` ("The MSIX package"), `doc/contributors/design/launcher.md` (the launcher's manifest and its main thread), `doc/contributors/design/phone-widgets.md`, and ADR 104.
- The import tables of 30 DLLs, read with pefile 2024.8.26.

## 1. Starting WinUI 3 with nothing installed

### The four ways Microsoft documents

| Route | What a fresh Windows 11 needs | Nothing to install by hand? | Run here? |
|---|---|---|---|
| Framework-dependent, unpackaged, with the bootstrapper (`MddBootstrapInitialize2` in `Microsoft.WindowsAppRuntime.Bootstrap.dll`) | The runtime's four MSIX packages (framework, main, singleton, DDLM), installed by `WindowsAppRuntimeInstall.exe` or by the app's setup program ("Deploy unpackaged apps", lines 20 to 22, 47 to 50, 133 to 135, and 292) | No: someone installs the runtime first. The installer can be chained into the app's setup program | Yes, on a computer where Windows had the runtime registered for the account (below) |
| Packaged (MSIX) with a `PackageDependency` on `Microsoft.WindowsAppRuntime.2` | The Store installs the framework with the app ("Deployment overview", line 21; "Deploy packaged apps", lines 34 to 46). Outside the Store the developer distributes it (line 61) | Yes through the Store, no for a package installed by hand | No: it installs a package, which no run may do |
| Sparse package (packaged with external location) | The signed sparse package registered for the person, and the same runtime packages as the first route ("Deploy unpackaged apps", lines 20 to 22) | No | No, for the same reason |
| Self-contained, unpackaged | Nothing. The app's folder holds the runtime's DLLs ("Deploy self-contained apps", lines 36 to 38: "xcopy-deploy"; "Deployment overview", line 15) | Yes | Yes, every probe run |

The first route worked from Ruby: `MddBootstrapInitialize2(0x00020007, "", 0, 0)` returned 0 and Ruby then started WinUI as in the self-contained route, with no activation context and no DLLs from the probe's folder. It worked because the Windows account that ran the probe already had `Microsoft.WindowsAppRuntime.2` 2.7.0 registered (`Get-AppxPackage` listed ten Windows App Runtime packages, among them 2.7.0 for x64 and for x86). The probe installed none of them. A computer without those packages makes `MddBootstrapInitialize2` fail, which no run tried.

The self-contained route is the one that leaves a person nothing to install. Its costs are size, that the app's updates carry the Windows App SDK's updates ("Deployment overview", line 22: "Not serviceable", "Larger deployments", "Slower to load, and uses more memory since code pages aren't shared"), and a license that Microsoft states for redistribution (section 7).

### How Ruby does what MSBuild does for a self-contained app

A self-contained WinUI 3 project has MSBuild copy each component package's `runtimes-framework/win-x64/native` files beside the program (`SelfContained.targets`, lines 78 to 104), write a manifest that lists every class the packages' `package.appxfragment` files declare, as `<winrtv1:activatableClass name='…' threadingModel='both'/>` under `<asmv3:file name='…'>` (lines 125 to 246), and merge that manifest into the program's with `mt.exe` (lines 249 to 276). The app's startup code then loads `Microsoft.WindowsAppRuntime.dll` through `WindowsAppRuntime_EnsureIsLoaded` (`UndockedRegFreeWinRT-AutoInitializer.cpp`, lines 11 and 38).

Ruby does the same without a manifest merged into a program of Fledge's:

1. It loads each DLL of the folder by its full path with `LoadLibraryExW` and `LOAD_WITH_ALTERED_SEARCH_PATH`, so that each finds the others, since `ruby.exe` or the launcher is not in that folder.
2. It writes the manifest, from the `package.appxfragment` files of the Foundation, WinUI, and InteractiveExperiences packages (942 classes), and makes an activation context from it with `CreateActCtxW`, then makes it active with `ActivateActCtx`. Activation by `RoGetActivationFactory` then finds `Microsoft.UI.Xaml.*` classes in the DLLs. A Ruby thread of either apartment type, started afterwards, found the factory of `Microsoft.UI.Xaml.Application` too.
3. It calls `RoInitialize` for a single-threaded apartment and `Application.Start`.

An ablation run took each step out of the probe's final form and ran it once:

| Step taken out | Result |
|---|---|
| Loading the DLLs by path | `RoGetActivationFactory` for `Microsoft.UI.Xaml.Application` fails with 0x80070057 |
| The activation context | The same call fails with 0x80040154, class not registered |
| `WindowsAppRuntime_EnsureIsLoaded` | The probe runs to its end |
| A `ResourceManagerRequested` handler that gave WinUI a `ResourceManager` on `Microsoft.UI.Xaml.Controls.pri` | The probe runs to its end |

The last two are not in the probe of Appendix A. The first two are why the probe has them.

The 1.8.260921001 packages started the same way. Eleven of the interfaces the probe calls (those of the application, its statics and factory, the window, the elements, the panel, the text box, and the timer) have the same IID and the same methods in that release's `Microsoft.UI.Xaml.winmd` as in 2.7.0's. A run on them reached `OnLaunched` and failed only on the text box (section 5).

## 2. Calling WinRT over Fiddle

- **Names and strings.** `WindowsCreateString` makes an HSTRING from a UTF-16 buffer, and `WindowsGetStringRawBuffer` reads one. The probe never deletes an HSTRING.
- **Classes.** `RoGetActivationFactory(name, iid, &factory)` returns a class's statics or factory interface, and `RoActivateInstance(name, &object)` makes an object with the class's default constructor and returns its default interface.
- **A call.** Ruby reads the object's vtable pointer, reads the function pointer at `slot * 8`, and calls it with `Fiddle::Function`, `this` first. A WinRT method returns an HRESULT and gives its result through a last pointer argument; Ruby allocates 8 bytes for it. The probe wraps the three shapes as `hr`, `out`, and `out_itf`. A result of type `double` comes back the same way, through a pointer, and `out_double` reads it.
- **Interfaces.** `QueryInterface` is slot 0 of every object. The probe asks for `IWindow`, `IFrameworkElement`, `IUIElement`, `IPanel`, `IStackPanel`, `IContentControl`, `IButtonBase`, `IItemsControl`, `ISelector`, `ITextBox`, `IDispatcherTimer`, and the UI Automation interfaces. Appendix A, section 2, lists its 26 IIDs, four of them delegates, with the slots it uses.
- **Parameterized interfaces.** `ItemCollection` implements `IVector<Object>`, `Panel.Children` is an `IVector<UIElement>`, and `DispatcherTimer.Tick` takes an `EventHandler<Object>`. The `.winmd` holds the template's IID (`IVector`1`: `913337e9-11a1-4345-a3a2-4e7f956e222d`; `EventHandler`1`: `9de1c535-6ae1-11e0-84e1-18a905bcc53f`). The instance's IID is a name-based (version 5) UUID of the signature `pinterface({template};arguments)`, in namespace `11f47ad5-7b73-42c0-abae-878b1e16adee`. This note computed three with that rule and did not read the rule in a source. WinUI accepted each: `QueryInterface` returned the interface for `IVector<Object>` on a `ListView`'s items and for `IVector<UIElement>` on a panel's children, and the timer called a delegate of the third.
- **Boxing.** A `ListView`'s items and a button's `Content` are Objects. `Windows.Foundation.PropertyValue.CreateString` boxes a string.

## 3. Calls from WinUI into Ruby

A COM object in Ruby is a block of 16 bytes (a vtable pointer, then unused) per interface. The vtable is `QueryInterface`, `AddRef`, and `Release`, then, for an object that is not a delegate, `GetIids`, `GetRuntimeClassName`, and `GetTrustLevel`, then the interface's methods, each a `Fiddle::BlockCaller` whose block holds the Ruby. The probe's object counts references and never frees itself, and keeps every closure and every block in an array for the life of the process.

- **A delegate** has one interface, the delegate's, and `Invoke` at slot 3. The probe makes one for each handler: `RoutedEventHandler` for `Click`, `KeyEventHandler` for `KeyDown`, `EventHandler<Object>` for `Tick`, and the callback `Application.Start` takes.
- **A Ruby exception cannot unwind through WinUI's frames.** Each block of the probe prints the exception and returns 0. What WinUI does with a failure HRESULT from a handler was not tried.
- **`Application` has to be subclassed.** `Application.Start(callback)` runs a message loop, and its callback has to make an `Application` object that WinUI calls `OnLaunched` on. WinRT does this by composition. The probe makes an outer object that answers `IUnknown`, `IInspectable`, and `IApplicationOverrides` (whose one method is `OnLaunched`), passes it to `IApplicationFactory.CreateInstance(outer, &inner)`, and forwards every other `QueryInterface` to the inner object WinUI returns. WinUI called `OnLaunched` on the Ruby object.
- **The thread.** The probe calls `Application.Start` from the main script. WinUI ran every handler on that thread. A trace of an early form of the probe printed the Windows thread id in each of 44 callbacks (the callback of `Application.Start`, `OnLaunched`, and the `QueryInterface`, `AddRef`, and `Release` calls on Ruby's objects), and printed one id, the id of the thread that called `Application.Start`. Fiddle lets go of Ruby's lock for the call and takes it for each callback, as it does for `UIApplicationMain` on iOS (`examples/basket/lib/basket/objc.rb`, `application_main`), so `Thread.main` is the UI thread, as it is under `ruby main.rb`.
- **What this does not cover.** A WinRT call that finishes on another thread, such as an `IAsyncOperation` completing on the thread pool, would ask for Ruby's lock from a thread Ruby did not make, which ends the process (ADR 104, "Context and Problem Statement"). The probe uses no such call. A Basket screen that opens a file picker would.

## 4. The screen

The probe builds the screen in code: a vertical `StackPanel` holding a horizontal one (a `TextBox` and an Add button), a `ListView`, and a Remove button, set as the window's content, with the window titled "Basket". `XamlReader.Load` would take the same tree as markup and `FindName` would find its parts, which is less bridge for the tree, and the same bridge for the handlers. It parsed `Grid`, `StackPanel`, `TextBlock`, `Button`, `ListView`, and a `StackPanel` holding a `Button` and a `ListView`, and failed on every markup with a `TextBox` (section 5). The probe's screen is therefore in code, and it is 94 lines besides comments.

What the last run printed, on 2.7.0, with the text box left out (`NO_TEXTBOX=1`; the Add button then appends a name the probe sets, as the text box would hold it):

```
[probe] window activated
[probe] layout: the content is 1424.0 by 734.0
[probe] added "Milk"; the list has 1 rows
[probe] added "Eggs"; the list has 2 rows
[probe] removed row 0; the list has 1 rows
[probe] layout: the content is 1424.0 by 734.0
[probe] the list ends with 1 rows
[probe] 143 DLLs are loaded; Visual C++ runtime among them: ["msvcp_win.dll"]; WinUI's: 13
[probe] Application.Start returned; exiting with 0
```

The through-the-bootstrapper run printed the same lines, with 127 DLLs loaded. `msvcp_win.dll` is part of Windows and not the Visual C++ Redistributable's `msvcp140.dll`; the computer has `vcruntime140.dll` and `msvcp140.dll` in System32, and neither loaded.

Each step is what a person does, through the toolkit's paths: the timer's `Tick` ran; a button's click came from `FrameworkElementAutomationPeer.CreatePeerForElement`, `GetPattern(PatternInterface.Invoke)`, and `IInvokeProvider.Invoke`, which raise the control's `Click` as an assistive tool's click does; and `ListView.SelectedIndex` set the row that Remove then removed. Appending and removing used `IVector<Object>`'s `Append` and `RemoveAt` on the list's `Items`. Nobody looked at the window, and no run read a pixel, so how the controls look is not known.

## 5. What did not work

**A text box.** On the computer that ran the probe, a window that held a `TextBox` ended the process about half a second later. The probe's handler for `Application.UnhandledException` printed `0x80040111: Windows.ApplicationModel.LimitedAccessFeatures` (0x80004005, unspecified error, on 1.8.260921001), and Windows' Application log recorded an Application Error with faulting module `Microsoft.ui.xaml.dll`, version 3.3.0.0, exception code 0xc000027b (a stowed exception). The same happened with a `TextBox` as the window's content and with a `PasswordBox`, a `RichEditBox`, and an `AutoSuggestBox`, on the self-contained route and through the bootstrapper. `ComboBox`, `CheckBox`, `Slider`, `Button`, and `ListView` ran to the end.

- `RoActivateInstance` on `TextBox` and the others succeeds. The failure comes when one joins a window.
- A handler for `Application.UnhandledException` that set `Handled` to true did not keep the process alive.
- In the same process, `RoGetActivationFactory("Windows.ApplicationModel.LimitedAccessFeatures")` succeeded on the main thread and on a Ruby thread of either apartment type, so the activation context does not block it. The registry lists it for `Windows.ApplicationModel.dll`.
- The string `LimitedAccessFeatures` is in none of the 30 SDK DLLs, in UTF-8 or UTF-16, so Windows makes the call, not WinUI.
- No run tried the computer's real desktop, a second Windows computer, or an older Windows. The desktop made for the run and this build of Windows are the two differences from the computers where WinUI 3 apps normally run that the probe could see, and neither was changed. Text input on Windows runs through the Text Services Framework, which a desktop made for a run may lack, and that is a guess.

**Markup with a text box.** `XamlReader.Load` on `<TextBox/>` fails with 0x802B000A, and so does a markup that holds one.

**The Fluent styles.** A WinUI 3 app merges `XamlControlsResources` into the application's resources for the Fluent styles. `RoActivateInstance("Microsoft.UI.Xaml.Controls.XamlControlsResources")` failed with 0x80004005 with and without a `ResourceManagerRequested` handler. With the handler, WinUI asked once, and `Microsoft.UI.Xaml.Controls.pri`'s main resource map answered for `Files/Microsoft.UI.Xaml/Themes/themeresources.xbf` and `generic.xbf` (a `makepri dump` of the file lists both under the map `Microsoft.UI.Xaml`); the only names WinUI reported as not found were `Files/app.xbf` and `Files/app.xaml`. The controls that did run therefore ran with whatever styles WinUI uses without `XamlControlsResources`, and what those look like was not seen.

## 6. What Basket's bridge would cost

These are estimates, from the probe's line counts without comments and blank lines.

| Part of the probe | Lines | What a Basket would keep |
|---|---|---|
| Calling and being called: `Win`, `Itf`, `Impl`, `delegate`, `factory`, `activate` | 175 | All of it. This is the bridge any WinUI screen needs |
| Starting: the DLLs, the manifest, the activation context, `RoInitialize` | 24 | All of it, plus a call to `SetProcessDpiAwarenessContext` (below) |
| The interface table | 26 | One line for each interface and slot a screen uses |
| The screen | 94 | Its widgets and handlers, about 25 lines of which are the probe's clicking, reading, and reporting |
| `Application.Start` and the subclass | 43 | About 25 of them: the callback and the aggregation; the rest is the probe's timer |

Basket's Windows bridge would be about 250 lines, and its screen about 100, so about 350 lines of Ruby in `lib/`, between iOS (400) and Android (an estimated 325). The screen grows with the interfaces it uses, each a line in the table. A text box needs the problem of section 5 solved, not more bridge.

Fledge's launcher declares no DPI awareness (`runtime/launcher/windows.manifest`), and WinUI 3 apps declare per-monitor DPI in theirs. The probe ran under `ruby.exe`, which declares none either, and sized its window without it; whether a window blurs on a high-DPI display was not seen. `SetProcessDpiAwarenessContext` is one call from Fiddle before the window exists.

## 7. What a built app carries

**Files.** The self-contained set is 33 files in the folder (28 DLLs, `DeploymentAgent.exe` and `RestartAgent.exe`, and three `.pri` files, 52 MB) and 174 more in the folders of the languages WinUI's strings are in and in `Microsoft.UI.Xaml/Assets`, 56 MB in all, 21.5 MB zipped. The large ones are `Microsoft.ui.xaml.dll` (14.5 MB), `Microsoft.UI.Xaml.Controls.dll` (7.1 MB), and the composition DLLs `dwmcorei.dll`, `dcompi.dll`, and `DwmSceneI.dll` (3.3, 3.1, and 2.6 MB). The probe ran all of them; no run tried which can be left out. A `win-arm64` folder holds the same set for Windows on ARM; no run used it.

**License.** Every package's `license.txt` is "Microsoft Software License Terms, Microsoft Windows App SDK". Section 3.a.i says "Any files that are binplaced with your application by the WindowsAppSDK NuGet package are, by definition, permitted to be redistributed. This applies to both framework package dependent and self-contained deployments." Section 3.b makes three conditions for the code distributed: the application adds "significant primary functionality"; the distributor requires "distributors and external end users to agree to terms that protect it and Microsoft at least as much as this agreement"; and the distributor indemnifies Microsoft against claims from the distribution or use of the application. Section 3.c bans using Microsoft's marks to suggest that Microsoft endorses the application, and bans putting the distributable code under a license that requires its source to be disclosed or lets others modify it. The terms fit none of the runtime license policy's categories, as `desktop-apps.md` found of MakeAppx. The WinUI package's `NOTICE.txt` lists one component, Newtonsoft.Json (MIT); the Foundation, InteractiveExperiences, and DWrite packages have no `NOTICE.txt`. The `.nuspec` of each of the six 2.7.0 packages says `requireLicenseAcceptance` is true.

**The Visual C++ runtime.** Microsoft's guide lists "the Visual C++ Redistributable" as a requirement for an unpackaged app and the VCLibs framework package for a packaged one ("Deploy unpackaged apps", line 27; "Deploy packaged apps", line 25). The 30 DLLs of the packages' x64 folders, which are every DLL of the self-contained set and the bootstrapper, import no `vcruntime`, `msvcp`, `concrt`, `vcomp`, `ucrtbase`, or `msvcr` DLL: they import Windows' system DLLs, the `api-ms-win-crt-*` sets that Windows 10 and 11 hold, and each other. The run's list of loaded DLLs held no Visual C++ runtime library. Those requirements are of a C++ app's code. A built Basket carries no Visual C++ runtime, which keeps to the decision of 2026-11-21 that nothing setdef publishes carries Microsoft's. Windows on a computer that never had the Redistributable was not tried, since the one used has it.

## Decisions the implementation needs

1. **How the Windows runtime reaches the person who runs Basket.** Options: self-contained (the DLLs beside the app), a packaged app whose manifest depends on `Microsoft.WindowsAppRuntime.2`, or the framework-dependent route with `WindowsAppRuntimeInstall.exe` run by the app's installer. Recommendation: self-contained. It needs no installation and ran to the end, and the same Ruby started the runtime through the bootstrapper where Windows had it registered, so an app could try the bootstrapper first and carry the DLLs as a fallback. The costs are 56 MB and Microsoft's terms (decision 2).
2. **Microsoft's redistribution terms.** Distributing the DLLs takes the three conditions of section 3.b, which are the maintainer's to accept for setdef (AGENTS.md, "Questions", puts licensing and commercial terms with the maintainer). Options: Basket's build downloads the four packages by SHA-256 for each build and nothing of Microsoft's goes into the repository or a release (the packages say `requireLicenseAcceptance` is true, so whoever builds Basket accepts Microsoft's license when it fetches them, and Delivery's fresh machine runs what the build made); or setdef distributes a built Basket for Windows, which needs an end-user agreement, as 3.b.ii says. Recommendation: the first; the second is a question issue before Basket is published for Windows.
3. **Where the DLLs enter `fledge build`.** Fledge copies the project's files into `app\`. The DLLs have to be in the project when `fledge build` runs: a script in Basket can fetch them, or a gem can hold them as data files. Fledge adds nothing to its runtime either way. Recommendation: a script in Basket that downloads, checks each SHA-256, and unpacks into a folder that `.gitignore` lists, run before `fledge build`.
4. **The text box.** Two runs would say what is wrong: one on the signed-in person's desktop of a Windows 11 computer, and one on a Windows computer of another build, such as GitHub's runners. The first needs a computer and a person's desktop that the runs here did not use, so this note ran neither. Until one of them shows a text box working, Basket's Windows screen cannot promise one.
5. **Fluent styles.** `XamlControlsResources` has to activate for Windows' current look. Nothing here shows whether it needs more of the app's resources, a `resources.pri` that merges WinUI's, or a computer without the problem of the text box. The same two runs would tell whether it is that problem.
6. **DPI awareness and the main-thread rule.** Basket's startup calls `SetProcessDpiAwarenessContext` for per-monitor V2 before the window exists, and its Ruby keeps to calls whose results arrive on the UI thread (section 3). Both are Basket's, with nothing of Fledge's.

## What stays unproven

- A text box, on any computer: the problem of section 5 is unsolved.
- How anything looks: the controls' appearance, Fluent styles, DPI scaling on a high-DPI display, and dark mode. No run read a pixel.
- A built Fledge app: the probe ran as `ruby.exe`, with the DLLs in a temporary folder, not as `launcherw.exe` from an app folder, and not on a fresh computer with no Ruby (Delivery's test).
- A computer without the Windows App Runtime registered, which is the self-contained route's point. The probe's computer had it registered. The activation context's manifest lists the DLLs of the probe's folder, so those should be the ones that loaded, and the list of loaded DLLs (143 against the bootstrapper run's 127) fits that, but no run took the registered packages away.
- Windows on ARM, Windows 10, and Windows Server.
- The keyboard: `KeyDown`'s handler was registered and never raised, and no input method or screen reader was tried (UI Automation clicked the buttons, but no reader read them).
- Calls that finish on another thread, a `ListView` with an `ItemsSource` and a data template, a delete button on each row, context menus, and a menu bar.
- The Microsoft Store's acceptance of a packaged Basket, and App Installer and signing for one (`doc/contributors/account-tests.md`).
- Whether a later Windows App SDK changes the interfaces the probe calls. Eleven of them were the same in 1.8.260921001 and 2.7.0, and the rest were not compared.

## Appendix A: the probe

`final.rb`, as the last runs used it. The setup script of Appendix B wrote it into the run's folder and ran it as `ruby probe.rb FOLDER FRAGMENTS`.

```ruby
# frozen_string_literal: true

# A WinUI 3 window from Ruby and Fiddle alone: no C, no C#, no C++/WinRT, and
# nothing installed. The window has a list, a text box, an Add button, and a
# Remove button; a timer then types, clicks, and selects as UI Automation
# would, and the program exits with status 0 when the list ends with one row.
#
# Arguments: the folder that holds the Windows App SDK's runtime DLLs (copied
# from its NuGet packages), then the packages' package.appxfragment files,
# separated by semicolons. Set NO_TEXTBOX=1 to leave out the text box.
require "fiddle"

$stdout.sync = true
$stderr.sync = true

APP_DIR = ARGV.fetch(0).tr("/", "\\")
FRAGMENTS = ARGV.fetch(1).split(";")

P = Fiddle::TYPE_VOIDP
I = Fiddle::TYPE_INT
L = Fiddle::TYPE_LONG_LONG
D = Fiddle::TYPE_DOUBLE
UINT = Fiddle::TYPE_UINT

def say(text) = puts("[probe] #{text}")

# Windows' C functions and WinRT's strings and errors.
module Win
  @fns = {}

  def self.fn(lib, name, args, ret)
    @fns[[lib, name]] ||= Fiddle::Function.new(Fiddle::Handle.new(lib)[name], args, ret)
  end

  def self.wide(text)
    bytes = (text.encode("UTF-16LE") + "\0".encode("UTF-16LE")).b
    pointer = Fiddle::Pointer.malloc(bytes.bytesize)
    pointer[0, bytes.bytesize] = bytes
    pointer
  end

  # A GUID as Windows lays it out: three little-endian fields, then 8 bytes.
  def self.guid(text)
    a, b, c, d, e = text.split("-")
    [a.hex, b.hex, c.hex].pack("Vvv") + [d + e].pack("H*")
  end

  def self.iid(text)
    pointer = Fiddle::Pointer.malloc(16)
    pointer[0, 16] = guid(text)
    pointer
  end

  def self.check(hr, what)
    hr &= 0xffffffff
    raise "#{what} failed: 0x#{hr.to_s(16)}" if hr >= 0x80000000
    hr
  end

  def self.hstring(text)
    out = Fiddle::Pointer.malloc(8)
    wide = text.encode("UTF-16LE").b + "\0\0".b
    buffer = Fiddle::Pointer.malloc(wide.bytesize)
    buffer[0, wide.bytesize] = wide
    check(fn("combase.dll", "WindowsCreateString", [P, UINT, P], I).call(buffer, text.length, out), "WindowsCreateString")
    out[0, 8].unpack1("Q")
  end

  def self.hstring_to_s(handle)
    return "" if handle.zero?
    length = Fiddle::Pointer.malloc(4)
    raw = fn("combase.dll", "WindowsGetStringRawBuffer", [P, P], P).call(handle, length).to_i
    raw.zero? ? "" : Fiddle::Pointer.new(raw)[0, length[0, 4].unpack1("L") * 2].force_encoding("UTF-16LE").encode("UTF-8")
  end
end

def hs(text) = Win.hstring(text)

# The file names of the DLLs loaded in this process.
def loaded_modules
  process = Win.fn("kernel32.dll", "GetCurrentProcess", [], P).call
  modules = Fiddle::Pointer.malloc(8 * 2048)
  needed = Fiddle::Pointer.malloc(4)
  Win.fn("kernel32.dll", "K32EnumProcessModules", [P, P, UINT, P], I).call(process, modules, 8 * 2048, needed)
  name = Fiddle::Pointer.malloc(1040)
  (needed[0, 4].unpack1("L") / 8).times.map do |i|
    length = Win.fn("kernel32.dll", "K32GetModuleFileNameExW", [P, P, P, UINT], UINT).call(process, modules[i * 8, 8].unpack1("Q"), name, 520)
    File.basename(name[0, length * 2].force_encoding("UTF-16LE").encode("UTF-8"))
  end
end

IID_UNKNOWN = "00000000-0000-0000-c000-000000000046"
IID_INSPECTABLE = "af86e2e0-b12d-4c6a-9c5a-d7aa65101e90"

# A COM object made elsewhere, called through its vtable by slot number: 0 to
# 2 are IUnknown's, 3 to 5 IInspectable's, and the interface's own follow.
class Itf
  CALLS = {}
  attr_reader :ptr

  def initialize(ptr) = @ptr = ptr

  def slot(index)
    vtable = Fiddle::Pointer.new(@ptr)[0, 8].unpack1("Q")
    Fiddle::Pointer.new(vtable + index * 8)[0, 8].unpack1("Q")
  end

  def call(index, types = [], *args)
    address = slot(index)
    (CALLS[[address, types]] ||= Fiddle::Function.new(address, [P, *types], I)).call(@ptr, *args)
  end

  # Calls a method that returns an HRESULT, and raises on a failure.
  def hr(index, types = [], *args, what: "slot #{index}")
    Win.check(call(index, types, *args), what)
  end

  # Calls a method whose last argument is where it writes its result.
  def out(index, types = [], *args, what: "slot #{index}")
    cell = Fiddle::Pointer.malloc(8)
    cell[0, 8] = [0].pack("Q")
    hr(index, [*types, P], *args, cell, what: what)
    cell[0, 8].unpack1("Q")
  end

  def out_itf(index, types = [], *args, what: "slot #{index}")
    pointer = out(index, types, *args, what: what)
    pointer.zero? ? nil : Itf.new(pointer)
  end

  def out_double(index, what: "slot #{index}")
    cell = Fiddle::Pointer.malloc(8)
    hr(index, [P], cell, what: what)
    cell[0, 8].unpack1("E")
  end

  def qi(iid)
    cell = Fiddle::Pointer.malloc(8)
    cell[0, 8] = [0].pack("Q")
    return nil if (call(0, [P, P], Win.iid(iid), cell) & 0xffffffff) >= 0x80000000
    Itf.new(cell[0, 8].unpack1("Q"))
  end
end

# A COM object implemented in Ruby, for WinUI to call. Each interface is 16
# bytes of memory that start with a pointer to a vtable of Fiddle::Closure.
# +interfaces+ maps an IID to its methods after IUnknown's and IInspectable's,
# each [argument types, block]. A delegate has IUnknown's methods and Invoke.
class Impl
  KEEP = []

  attr_reader :ptr
  attr_writer :forward

  def initialize(name, interfaces, delegate: false)
    @name = name
    @refs = 1
    @blocks = {}
    base = base_closures(inspectable: !delegate)
    interfaces.each do |iid, methods|
      closures = base + methods.map { |args, body| Fiddle::Closure::BlockCaller.new(I, [P, *args]) { |*values| guarded(body, values) } }
      @blocks[Win.guid(iid)] = block_of(closures)
    end
    @identity = delegate ? @blocks.values.first : block_of(base)
    @blocks[Win.guid(IID_UNKNOWN)] = @identity
    @blocks[Win.guid(IID_INSPECTABLE)] = @identity unless delegate
    @ptr = @identity.to_i
    KEEP << self
  end

  private def block_of(closures)
    vtable = Fiddle::Pointer.malloc(8 * closures.size)
    closures.each_with_index { |c, i| vtable[i * 8, 8] = [c.to_i].pack("Q") }
    block = Fiddle::Pointer.malloc(16)
    block[0, 8] = [vtable.to_i].pack("Q")
    KEEP << vtable << block << closures
    block
  end

  # A Ruby exception cannot unwind through WinUI's frames. WinUI treats a
  # failing handler as an unhandled exception and ends the process, so the
  # exception is printed and the handler reports success.
  private def guarded(body, values)
    body.call(*values)
  rescue Exception => e # rubocop:disable Lint/RescueException
    warn "[probe] exception in a callback: #{e.class}: #{e.message}", *e.backtrace.first(6)
    0
  end

  private def base_closures(inspectable:)
    closure = ->(args, &body) { Fiddle::Closure::BlockCaller.new(I, [P, *args], &body) }
    list = [
      closure.([P, P]) { |_this, riid, ppv| query(riid, ppv) },
      closure.([]) { |_this| @refs += 1 },
      closure.([]) { |_this| @refs -= 1 },
    ]
    return list unless inspectable
    list + [
      closure.([P, P]) { |_this, count, iids| write(count, [0].pack("L")) && write(iids, [0].pack("Q")) && 0 },
      closure.([P]) { |_this, out| write(out, [Win.hstring(@name)].pack("Q")) && 0 },
      closure.([P]) { |_this, out| write(out, [0].pack("L")) && 0 },
    ]
  end

  private def write(address, bytes) = (Fiddle::Pointer.new(address.to_i)[0, bytes.bytesize] = bytes)

  # QueryInterface answers its own interfaces, and for the rest asks the inner
  # object of an aggregation, when there is one.
  private def query(riid, ppv)
    block = @blocks[Fiddle::Pointer.new(riid.to_i)[0, 16]]
    if block
      write(ppv, [block.to_i].pack("Q"))
      @refs += 1
      return 0
    end
    return @forward.call(0, [P, P], riid, ppv) if @forward
    write(ppv, [0].pack("Q"))
    -2147467262 # E_NOINTERFACE
  end
end

# A WinRT delegate (an event handler) that runs +body+ with Invoke's arguments.
def delegate(iid, args = [P, P], &body)
  Impl.new("delegate", {iid => [[args, ->(_this, *values) { body.call(*values); 0 }]]}, delegate: true)
end

def factory(class_name, iid)
  cell = Fiddle::Pointer.malloc(8)
  Win.check(Win.fn("combase.dll", "RoGetActivationFactory", [P, P, P], I).call(hs(class_name), Win.iid(iid), cell), "RoGetActivationFactory #{class_name}")
  Itf.new(cell[0, 8].unpack1("Q"))
end

def activate(class_name)
  cell = Fiddle::Pointer.malloc(8)
  Win.check(Win.fn("combase.dll", "RoActivateInstance", [P, P], I).call(hs(class_name), cell), "RoActivateInstance #{class_name}")
  Itf.new(cell[0, 8].unpack1("Q"))
end

# ---- 1. The runtime's DLLs, and registration-free activation ----------------

say "ruby #{RUBY_VERSION} #{RUBY_PLATFORM}, fiddle #{Fiddle::VERSION}"

# Loads every DLL by its full path, with its own folder first in the search
# path, so that each finds the others.
load_library = Win.fn("kernel32.dll", "LoadLibraryExW", [P, P, I], P)
pending = Dir.glob(File.join(APP_DIR.tr("\\", "/"), "*.dll")).map { |path| path.tr("/", "\\") }
3.times { pending.reject! { |path| !load_library.call(Win.wide(path), nil, 0x8).to_i.zero? } } # LOAD_WITH_ALTERED_SEARCH_PATH
say "DLLs that did not load: #{pending.inspect}"

# The manifest of WinRT classes, from the packages' appxfragment files, as the
# Windows App SDK's own SelfContained.targets writes it.
manifest = +"<?xml version='1.0' encoding='utf-8' standalone='yes'?>\n"
manifest << "<assembly manifestVersion='1.0' xmlns='urn:schemas-microsoft-com:asm.v1' xmlns:asmv3='urn:schemas-microsoft-com:asm.v3' xmlns:winrtv1='urn:schemas-microsoft-com:winrt.v1'>\n"
manifest << "  <assemblyIdentity version='1.0.0.0' name='Basket.Probe'/>\n"
FRAGMENTS.each do |fragment|
  File.read(fragment, encoding: "bom|utf-8").scan(%r{<InProcessServer>(.*?)</InProcessServer>}m).each do |(body)|
    manifest << "  <asmv3:file name='#{body[%r{<Path>(.*?)</Path>}, 1]}'>\n"
    body.scan(/ActivatableClassId="([^"]+)"/).each { |(id)| manifest << "    <winrtv1:activatableClass name='#{id}' threadingModel='both'/>\n" }
    manifest << "  </asmv3:file>\n"
  end
end
manifest << "</assembly>\n"
manifest_path = File.join(APP_DIR, "probe.manifest")
File.binwrite(manifest_path, manifest)

# An activation context made from that manifest, which RoGetActivationFactory
# consults on every thread of the process once it is active on this one.
context = Fiddle::Pointer.malloc(56) # ACTCTXW
context[0, 56] = [56, 0x4, Win.wide(manifest_path.tr("/", "\\")).to_i, 0, 0, Win.wide(APP_DIR).to_i, 0, 0, 0].pack("LLQSSx4Q4") # ACTCTX_FLAG_ASSEMBLY_DIRECTORY_VALID
handle = Win.fn("kernel32.dll", "CreateActCtxW", [P], P).call(context).to_i
raise "CreateActCtxW failed: #{Fiddle.win32_last_error}" if handle == -1 || handle.zero?
raise "ActivateActCtx failed: #{Fiddle.win32_last_error}" if Win.fn("kernel32.dll", "ActivateActCtx", [P, P], I).call(handle, Fiddle::Pointer.malloc(8)).zero?

Win.check(Win.fn("combase.dll", "RoInitialize", [I], I).call(0), "RoInitialize") # RO_INIT_SINGLETHREADED

# ---- 2. Interfaces: IIDs and vtable slots, from the SDK's .winmd files ------

IID_APPLICATION_STATICS = "4e0d09f5-4358-512c-a987-503b52848e95" # get_Current 6, Start 7
IID_APPLICATION_FACTORY = "9fd96657-5294-5a65-a1db-4fea143597da" # CreateInstance 6
IID_APPLICATION_OVERRIDES = "a33e81ef-c665-503b-8827-d27ef1720a06" # OnLaunched 6
IID_APPLICATION = "06a8f4e7-1146-55af-820d-ebd55643b021" # Exit 17
IID_INIT_CALLBACK = "d8eef1c9-1234-56f1-9963-45dd9c80a661" # delegate
IID_WINDOW = "61f0ec79-5d52-56b5-86fb-40fa4af288b0" # put_Content 9, put_Title 15, Activate 26
IID_FRAMEWORK_ELEMENT = "fe08f13d-dc6a-5495-ad44-c2d8d21863b0" # get_ActualWidth 13, get_ActualHeight 14
IID_UIELEMENT = "c3c01020-320c-5cf6-9d24-d396bbfa4d8b" # add_KeyDown 132
IID_PANEL = "27a1b418-56f3-525e-b883-cefed905eed3" # get_Children 6
IID_STACK_PANEL = "493ab00b-3a6a-5e4a-9452-407cd5197406" # put_Orientation 9, put_Spacing 21
IID_CONTENT_CONTROL = "07e81761-11b2-52ae-8f8b-4d53d2b5900a" # put_Content 7
IID_TEXTBOX = "873af7c2-ab89-5d76-8dbe-3d6325669df5" # get_Text 6, put_Text 7, put_PlaceholderText 35
IID_BUTTON_BASE = "65714269-2473-5327-a652-0ea6bce7f403" # add_Click 14
IID_ITEMS_CONTROL = "bf1ccb54-83e2-5b98-acbc-736f876c3d35" # get_Items 8
IID_SELECTOR = "8f7e2159-e61d-576f-8476-f83fde3d689e" # get_SelectedIndex 6, put_SelectedIndex 7
IID_ROUTED_HANDLER = "dae23d85-69ca-5bdf-805b-6161a3a215cc" # delegate
IID_KEY_HANDLER = "db68e7cc-9a2b-527d-9989-25284daccc03" # delegate
IID_KEY_ARGS = "ee357007-a2d6-5c75-9431-05fd66ec7915" # get_Key 6
IID_DISPATCHER_TIMER = "58a4abf1-a4a3-53dd-ae21-08f43231e817" # put_Interval 7, add_Tick 9, Start 11, Stop 12
IID_PEER_STATICS = "081f6fbe-6500-528a-a506-f5a4d41ddf6c" # CreatePeerForElement 7
IID_AUTOMATION_PEER = "e51d3e4e-34f0-568c-999f-6277e2afe6d7" # GetPattern 8
IID_INVOKE_PROVIDER = "02481105-3378-544d-b4e1-a1b368afbc02" # Invoke 6
IID_PROPERTY_VALUE_STATICS = "629bdbc8-d932-4ff4-96b9-8d96c5c1e858" # CreateString 18
# Windows.Foundation's IVector<Object>, from its template's IID and the rule
# of "Parameterized types": get_Size 7, RemoveAt 12, Append 13.
IID_VECTOR_OBJECT = "b32bdca4-5e52-5b27-bc5d-d66a1a268c2a"
# EventHandler<Object>, the type of DispatcherTimer.Tick, by the same rule.
IID_EVENT_HANDLER_OBJECT = "c50898f6-c536-5f47-8583-8b2c2438a13b"
# IVector<UIElement>, the type of Panel.Children, by the same rule.
IID_VECTOR_UIELEMENT = "ea4a1af0-4286-5f11-8142-6b0169f4e9de"

# ---- 3. The screen ------------------------------------------------------------

class Screen
  VK_RETURN = 13

  def initialize
    @window = activate("Microsoft.UI.Xaml.Window").qi(IID_WINDOW)
    @handlers = []
    @plain = "" if ENV["NO_TEXTBOX"]
    @root = stack(8.0, 0)
    row = stack(8.0, 1)
    unless @plain
      @entry = activate("Microsoft.UI.Xaml.Controls.TextBox")
      @text = @entry.qi(IID_TEXTBOX)
      @text.hr(35, [P], hs("Add an item"), what: "put_PlaceholderText")
    end
    @add = button("Add")
    @rows = activate("Microsoft.UI.Xaml.Controls.ListView")
    @remove = button("Remove selected")
    adopt(row, *[@entry, @add].compact)
    adopt(@root, row, @rows, @remove)
    @vector = @rows.qi(IID_ITEMS_CONTROL).out_itf(8, what: "get_Items").qi(IID_VECTOR_OBJECT)
    @selector = @rows.qi(IID_SELECTOR)
    click(@add) { add }
    click(@remove) { remove }
    key_down(@entry) { |key| add if key == VK_RETURN } if @entry
    @window.hr(9, [P], @root.qi(IID_UIELEMENT).ptr, what: "put_Content")
    @window.hr(15, [P], hs("Basket"), what: "put_Title")
    @window.hr(26, [], what: "Activate")
    say "window activated"
  end

  def count = @vector.out(7, what: "get_Size") & 0xffffffff

  # The rows below are what a person would do; UI Automation does it for the
  # probe, through the toolkit's own event queue.
  def type_and_add(text)
    self.text = text
    invoke(@add)
  end

  def remove_first
    @selector.hr(7, [I], 0, what: "put_SelectedIndex")
    invoke(@remove)
  end

  def report
    root = @root.qi(IID_FRAMEWORK_ELEMENT)
    say "layout: the content is #{root.out_double(13)} by #{root.out_double(14)}"
  end

  private def stack(spacing, orientation)
    panel = activate("Microsoft.UI.Xaml.Controls.StackPanel")
    properties = panel.qi(IID_STACK_PANEL)
    properties.hr(9, [I], orientation, what: "put_Orientation")
    properties.hr(21, [D], spacing, what: "put_Spacing")
    panel
  end

  private def adopt(panel, *children)
    list = panel.qi(IID_PANEL).out_itf(6, what: "get_Children").qi(IID_VECTOR_UIELEMENT)
    children.each { |child| list.hr(13, [P], child.qi(IID_UIELEMENT).ptr, what: "Children.Append") }
  end

  private def button(label)
    button = activate("Microsoft.UI.Xaml.Controls.Button")
    button.qi(IID_CONTENT_CONTROL).hr(7, [P], boxed(label), what: "put_Content")
    button
  end

  # A string as an Object, which is what a ListView's Items and a button's
  # Content take.
  private def boxed(text)
    factory("Windows.Foundation.PropertyValue", IID_PROPERTY_VALUE_STATICS).out(18, [P], hs(text), what: "CreateString")
  end

  private def click(button, &body)
    handler = delegate(IID_ROUTED_HANDLER) { |_sender, _args| body.call }
    @handlers << handler
    button.qi(IID_BUTTON_BASE).hr(14, [P, P], handler.ptr, Fiddle::Pointer.malloc(8), what: "add_Click")
  end

  private def key_down(element, &body)
    handler = delegate(IID_KEY_HANDLER) { |_sender, args| body.call(Itf.new(args.to_i).qi(IID_KEY_ARGS).out(6, what: "get_Key") & 0xffffffff) }
    @handlers << handler
    element.qi(IID_UIELEMENT).hr(132, [P, P], handler.ptr, Fiddle::Pointer.malloc(8), what: "add_KeyDown")
  end

  private def text = @plain || Win.hstring_to_s(@text.out(6, what: "get_Text"))

  private def text=(value)
    return @plain = value if @plain
    @text.hr(7, [P], hs(value), what: "put_Text")
  end

  private def add
    item = text.strip
    return if item.empty?
    @vector.hr(13, [P], boxed(item), what: "Append")
    self.text = ""
    say "added #{item.inspect}; the list has #{count} rows"
  end

  private def remove
    index = @selector.out(6, what: "get_SelectedIndex") & 0xffffffff
    return say("nothing selected") if index == 0xffffffff
    @vector.hr(12, [I], index, what: "RemoveAt")
    say "removed row #{index}; the list has #{count} rows"
  end

  # Clicks a button as UI Automation would, which raises its Click event.
  private def invoke(button)
    peers = factory("Microsoft.UI.Xaml.Automation.Peers.FrameworkElementAutomationPeer", IID_PEER_STATICS)
    peer = peers.out_itf(7, [P], button.qi(IID_UIELEMENT).ptr, what: "CreatePeerForElement")
    peer.qi(IID_AUTOMATION_PEER).out_itf(8, [I], 0, what: "GetPattern(Invoke)").qi(IID_INVOKE_PROVIDER).hr(6, [], what: "Invoke")
  end
end

# ---- 4. Application.Start, and the Application subclass ---------------------

$exit_code = 1
$keep = []

# Called on the UI thread, which is Ruby's main thread, once the window exists.
launched = lambda do
  $screen = Screen.new
  timer = activate("Microsoft.UI.Xaml.DispatcherTimer").qi(IID_DISPATCHER_TIMER)
  timer.hr(7, [L], 5_000_000, what: "put_Interval") # a TimeSpan, in 100 ns ticks
  steps = [
    -> { $screen.report },
    -> { $screen.type_and_add("Milk") },
    -> { $screen.type_and_add("Eggs") },
    -> { $screen.remove_first },
    -> { $screen.report },
  ]
  tick = delegate(IID_EVENT_HANDLER_OBJECT) do |_sender, _args|
    next steps.shift.call unless steps.empty?
    timer.hr(12, [], what: "Stop")
    $exit_code = ($screen.count == 1) ? 0 : 3
    say "the list ends with #{$screen.count} rows"
    modules = loaded_modules
    say "#{modules.size} DLLs are loaded; Visual C++ runtime among them: #{modules.grep(/\A(vcruntime|msvcp|vccorlib|concrt)/i).inspect}; WinUI's: #{modules.grep(/\AMicrosoft\.(ui|WindowsApp)/i).size}"
    factory("Microsoft.UI.Xaml.Application", IID_APPLICATION_STATICS).out_itf(6, what: "Application.Current").qi(IID_APPLICATION).hr(17, [], what: "Exit")
  end
  $keep << tick << timer
  timer.hr(9, [P, P], tick.ptr, Fiddle::Pointer.malloc(8), what: "add_Tick")
  timer.hr(11, [], what: "Start")
end

# Application.Start makes a message loop on this thread and calls this back.
# The callback makes the Application, a subclass of WinUI's by aggregation: the
# outer object answers IApplicationOverrides, so that WinUI calls OnLaunched,
# and hands every other interface to the inner object WinUI made.
callback = delegate(IID_INIT_CALLBACK, [P]) do |_params|
  overrides = Impl.new("Probe.App", {IID_APPLICATION_OVERRIDES => [[[P], ->(_this, _args) { launched.call; 0 }]]})
  inner_cell = Fiddle::Pointer.malloc(8)
  instance_cell = Fiddle::Pointer.malloc(8)
  Win.check(factory("Microsoft.UI.Xaml.Application", IID_APPLICATION_FACTORY).call(6, [P, P, P], overrides.ptr, inner_cell, instance_cell), "Application.CreateInstance")
  overrides.forward = Itf.new(inner_cell[0, 8].unpack1("Q"))
  $keep << overrides << instance_cell
end

Thread.new do
  sleep Integer(ENV.fetch("PROBE_TIMEOUT", "120"))
  warn "[probe] timed out"
  exit!(5)
end

say "calling Application.Start on thread #{Win.fn('kernel32.dll', 'GetCurrentThreadId', [], UINT).call}"
Win.check(factory("Microsoft.UI.Xaml.Application", IID_APPLICATION_STATICS).call(7, [P], callback.ptr), "Application.Start")
say "Application.Start returned; exiting with #{$exit_code}"
exit($exit_code)
```

The bootstrapper run replaced the steps of section 1 (loading the DLLs, the manifest, the activation context) with this, where `ARGV[2]` held the folder of `Microsoft.WindowsAppRuntime.Bootstrap.dll` from the Foundation package's `runtimes/win-x64/native`:

```ruby
dll = Fiddle::Handle.new(File.join(ARGV.fetch(2), "Microsoft.WindowsAppRuntime.Bootstrap.dll").tr("/", "\\"))
init = Fiddle::Function.new(dll["MddBootstrapInitialize2"], [UINT, P, L, I], I)
Win.check(init.call(0x00020007, Win.wide(""), 0, 0), "MddBootstrapInitialize2") # 2.7, no version tag, any version, no options
```

## Appendix B: the setup script

What each run did, in MSYS2's bash. `WORK` is a temporary folder that the run made and removed. The script for the 1.8 packages differs in the versions and SHA-256 only. Its last line runs the probe, which the run had written to `$WORK/probe.rb`.

```sh
set -eu
# Pinned inputs: Microsoft's NuGet packages of the Windows App SDK 2.7.0.
BASE=https://api.nuget.org/v3-flatcontainer
CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/winui-probe"
mkdir -p "$CACHE"
WORK=$(mktemp -d)
fetch() { # name sha
  local name="$1" sha="$2" id
  id=$(echo "$name" | tr 'A-Z' 'a-z')
  local file="$CACHE/$name.2.7.0.nupkg"
  if [ -f "$file" ] && echo "$sha  $file" | sha256sum -c - >/dev/null 2>&1; then
    echo "cached $name"
  else
    curl -fsSL --retry 3 -o "$file" "$BASE/$id/2.7.0/$id.2.7.0.nupkg"
    echo "$sha  $file" | sha256sum -c -
  fi
}
fetch Microsoft.WindowsAppSDK.Foundation 4131660bda7476eef751ce134c9847b5a79e4051809bffbf9dd171f4246afdf8
fetch Microsoft.WindowsAppSDK.WinUI 027ecdc0c51a2d31fd25985616ef2e9438f02ee3e7b6e72fd0601ddb119688b4
fetch Microsoft.WindowsAppSDK.InteractiveExperiences 5df51fd9e30a6093f737698ae8ad4e8d62d87f7081b00aa6a4ea0b893f03e1c2
fetch Microsoft.WindowsAppSDK.DWrite d9ea79e67c2379d100a51a8ea681d1fb21af211c1a6676fd60ecf7795ac46a44
APP="$WORK/app"
SRC="$WORK/src"
mkdir -p "$APP" "$SRC"
FRAGS=""
for name in Foundation WinUI InteractiveExperiences DWrite; do
  mkdir -p "$SRC/$name"
  /c/Windows/System32/tar.exe -xf "$(cygpath -w "$CACHE/Microsoft.WindowsAppSDK.$name.2.7.0.nupkg")" -C "$(cygpath -w "$SRC/$name")" runtimes-framework
  cp -r "$SRC/$name/runtimes-framework/win-x64/native/." "$APP/"
  if [ -f "$SRC/$name/runtimes-framework/package.appxfragment" ]; then
    FRAGS="$FRAGS$(cygpath -m "$SRC/$name/runtimes-framework/package.appxfragment");"
  fi
done
FRAGS="${FRAGS%;}"
echo "app dir holds $(find "$APP" -type f | wc -l) files, $(du -sm "$APP" | cut -f1) MB"

mise x http:rubyinstaller-head http:msys2-zlib http:msys2-libgcc -- ruby "$WORK/probe.rb" "$APP" "$FRAGS"
```

## 2026-11-25: the text box on the signed-in desktop

The note above ran each probe on a desktop made for the run and guessed that this desktop caused the text box's failure (section 5). Three more runs, on the same Windows 11 computer (build 10.0.26300), ran on its signed-in desktop. Run 1 and run 2 printed the name of their desktop (`GetThreadDesktop`, `GetUserObjectInformationW`), which was `Default`. Each used the probe of Appendix A with the text box in the window, with the bootstrapper in place of the packages' DLLs (the last form of Appendix A), so the process loaded `Microsoft.UI.Xaml.dll` from the Windows App Runtime 2.7.0 framework package that Windows had registered. No run injected input, and none installed anything.

Basket does not take the self-contained route of section 1. It would use the framework package that Microsoft provides: the bootstrapper for a program that runs unpackaged, and an MSIX package that depends on the framework for an app that ships. The runs below therefore used the bootstrapper, and the self-contained route stands only as a comparison, from the earlier runs' crash records.

**Run 1, the failing case on the signed-in desktop.** `MddBootstrapInitialize2` returned 0, the probe printed "window activated", and the process ended. Its exit status was 123, the low byte of 0xC000027B. The text box still ends the process.

**Run 2, the fault's message and record.** The probe now had a handler for `Application.UnhandledException`. It printed `0x80040111: Windows.ApplicationModel.LimitedAccessFeatures`, the same text as on the private desktop, and `cmd.exe` reported the exit code -1073741189, which is 0xC000027B. Windows' Application log recorded an Application Error with faulting module `Microsoft.UI.Xaml.dll` 3.3.0.0 (the file in `C:\Program Files\WindowsApps\Microsoft.WindowsAppRuntime.2_2.7.0.0_x64__8wekyb3d8bbwe`), exception code 0xc000027b, fault offset 0x3d1a49. The earlier self-contained run on the private desktop left an event with the same module version, code, and offset, with the module in the probe's folder. So the fault is at one place in `Microsoft.UI.Xaml.dll` on both routes and both desktops, and the private desktop is not its cause. The same run read `ruby.exe`'s embedded manifest: 377 bytes that set only `longPathAware`, with no `supportedOS` entry.

**Run 3, the manifest.** Hypothesis, stated before the run: Windows treats a process whose manifest lists no Windows 10 `supportedOS` as an older program, and WinUI's call into `LimitedAccessFeatures` fails for that reason. The run copied the Ruby installation into the run's temporary folder, wrote a manifest into the copy's `ruby.exe` with `UpdateResourceW` that adds the Windows 10 and 11 `supportedOS` GUID, read it back, and ran the same probe under the copy. The result was the same: "window activated", the same `0x80040111` message, and the exit code -1073741189. The manifest is not the cause.

**What stays open.** The cause is not found. The runs rule out the private desktop and, for Windows 10 compatibility, the host's manifest, on this computer and this build of Windows. Two hypotheses are left, and each needs something the runs here could not do:

- `Windows.ApplicationModel.LimitedAccessFeatures` needs the caller to have a package identity, which a process that `ruby.exe` starts lacks and a packaged app has. Testing it takes a package installed on the computer, which no run may do. The same package would test whether a packaged Basket has the problem at all.
- The build of Windows, 10.0.26300, differs from the one Microsoft tests WinUI 3 on. Testing it takes a computer of another build.

A working screen with a text box, and the Fluent styles, were not reached: the probe never got a text box that lived. The screen of section 4 with its text box left out is still the most that the note proves. WinUI 3 from pure Ruby cannot carry Basket's screen on this computer until a text box starts.

### What an MSIX package that depends on the framework needs from `fledge build`

This comes from Microsoft's pages and from the packages, and no run built or installed such a package. `Fledge::Msix#manifest` writes one `PackageDependency`, on the Visual C++ runtime's framework package, only when the app's gems need it (`lib/fledge/msix.rb`, lines 183 to 186). A package for a WinUI 3 app would add a second `PackageDependency` element, as the generated manifest of Microsoft's WinUI 3 templates has ("Deploy packaged apps", section "Stable version", lines 34 to 46):

- `Name` is `Microsoft.WindowsAppRuntime.2`, the package name in the Runtime package's `Microsoft.WindowsAppSDK.AppXReference.props` (`WinAppSDKPackageName`).
- `Publisher` is `CN=Microsoft Corporation, O=Microsoft Corporation, L=Redmond, S=Washington, C=US`, from the same file, and the same publisher as the Visual C++ dependency's.
- `MinVersion` is `2.7.0.0` for this release, the Foundation version that the Runtime package's `MicrosoftWindowsAppSDKFoundationAppXVersion.props` and `WindowsAppSDK-VersionInfo.json` give.
- The VCLibs framework dependency that the same page lists as a prerequisite for a packaged app is already one of Fledge's two cases (`visual_c_runtime: central`).

The package then carries no file of Microsoft's, and `fledge build` downloads nothing: a package the Store installs gets the framework with it, and a package installed by hand needs the framework already registered or given to `Add-AppxPackage` with `-DependencyPath`, as for the Visual C++ runtime ("Deploy packaged apps", line 61). The page says the Main and Singleton packages cannot be declared as dependencies, and gives the Deployment API as the way to deploy them, which an app needs only for features outside the framework package, push notifications among them. The process of such a package has a package graph made from its manifest, so it does not call the bootstrapper, which is for unpackaged programs. Whether a Ruby process in that package finds `Microsoft.UI.Xaml.*` through the package graph with no activation context was not tried. The same computer had the framework package 2.7.0 registered for its account, in the folder the Application log shows above.

## 2026-11-25: the text box in a process with package identity

The section above left one hypothesis that a run could test: `Windows.ApplicationModel.LimitedAccessFeatures` needs the caller to have package identity, which a process started from `ruby.exe` lacks. One test package gave a Ruby process that identity, on the same Windows 11 computer (build 10.0.26300), on its signed-in desktop. The text box still ends the process. Each run checked, before it touched anything, that it ran as the Windows account set aside for these runs (`whoami` and `USERNAME` both named it), and would have exited without touching anything otherwise; each run passed that check.

**Run 1, what the computer allowed (read only).** Developer Mode was already on (`AllowDevelopmentWithoutDevLicense` was 1 under `HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock`), so a package registered from loose files needed no certificate and no setting changed. `Add-AppxPackage` has `-AllowUnsigned`, `Microsoft.WindowsAppRuntime.2` 2.7.0.0 (x64 and x86) and `Microsoft.VCLibs.140.00.UWPDesktop` 14.0.33728.0 were registered for the account, and no package named `Setdef.FledgeWinUIProbe` existed.

**The package.** `Setdef.FledgeWinUIProbe` 1.0.0.0 for x64, with the manifest that `Fledge::Msix#manifest` writes for a desktop app (`runFullTrust`, `Windows.FullTrustApplication`, `Windows.Desktop` 10.0.17763.0), the VCLibs `PackageDependency` of `lib/fledge/msix.rb` (lines 183 to 186), and a second one on `Microsoft.WindowsAppRuntime.2`, `MinVersion` 2.7.0.0, with Microsoft's publisher, as the last section's MSIX subsection says. Its one application's `Executable` was `ruby\bin\ruby.exe`. The package held a copy of the Ruby installation of Appendix A (18,619 files, 334 MB) with `zlib1.dll` and `libgcc_s_seh-1.dll` beside `ruby.exe`, the probe of Appendix A, and a one-pixel logo. It carried no file of the Windows App SDK. `Add-AppxPackage -Register` registered it from the folder of loose files (`IsDevelopmentMode` True), and `Invoke-CommandInDesktopPackage` started `cmd.exe` in the package, which ran Ruby and the probe, with the probe's output sent to a file.

**Run 2, the probe in the package.** The probe was Appendix A's, with the section 1 steps replaced by `RoInitialize` alone: it loaded no DLL, made no activation context, and called no bootstrapper. It also printed `GetCurrentPackageFullName` and tried to activate `XamlControlsResources` first. The run printed:

```
[probe] GetCurrentPackageFullName returned 0: Setdef.FledgeWinUIProbe_1.0.0.0_x64__j2n0ph6rme2fj
[probe] calling Application.Start on thread 59684
[probe] XamlControlsResources: RoActivateInstance Microsoft.UI.Xaml.Controls.XamlControlsResources failed: 0x80004005
[probe] window activated
[probe] UnhandledException 0x80040111: Windows.ApplicationModel.LimitedAccessFeatures
```

The process exit code was -1073741189, which is 0xC000027B, as in every earlier run.

- **A packaged Ruby process starts WinUI.** `Application.Start` and `OnLaunched` ran, and WinUI's classes activated through the package graph that Windows builds from the manifest's dependencies, with no manifest of Ruby's and no bootstrapper. The window with the text box activated, and the failure came afterward, as it did without identity.
- **Package identity does not fix the text box.** The process had an identity, and WinUI still raised `0x80040111` from `LimitedAccessFeatures` and ended the process. The hypothesis about package identity is ruled out on this computer. The runs do not show whether the feature needs more than an identity, and the other hypothesis, the build of Windows, stays open.
- **`XamlControlsResources` fails in the package** with the same 0x80004005 as outside it, so the Fluent styles stay out of reach.
- **Not run.** The list with Add and Remove buttons, the Return key, and the Application log's record of this fault were not tried, since the text box ended the process first. A run without the text box, which would show whether the rest of the screen works in a package, was not made either.

**Removal.** The script ran `Get-AppxPackage -Name Setdef.FledgeWinUIProbe | Remove-AppxPackage` in a handler that runs when the script ends, whether or not the probe passed. Afterward `@(Get-AppxPackage -Name Setdef.FledgeWinUIProbe).Count` printed 0 and `Get-AppxPackage -Name Setdef.FledgeWinUIProbe` printed nothing. The run changed no setting and installed no certificate.

WinUI 3 from pure Ruby still cannot carry Basket's screen on this computer, packaged or not: a text box ends the process in both.

## 2026-11-26: why the text box ends the process, and the fix

The text box fails because the probe's `Application` does not answer `IXamlMetadataProvider`. A WinUI 3 app's `Application` answers it, through code the XAML compiler generates, and hands each call to `XamlControlsXamlMetaDataProvider`, which describes the types of `Microsoft.UI.Xaml.Controls.dll`. Without it, WinUI cannot make an object of those types, and the default styles of `TextBox`, `PasswordBox`, and `RichEditBox` set two such objects. With it, the text box works, `XamlControlsResources` activates, and the screen of section 4 runs with its text box: typed text becomes a row on Add and on Return. The cause is in how the probe set WinUI up, not in Windows, the desktop, package identity, or Microsoft's code. The `LimitedAccessFeatures` message that every earlier run printed has nothing to do with the text box.

Each run below ran on the same Windows 11 computer (version 26H2, build 26300.9974), on a desktop made for the run, through the bootstrapper with the Windows App Runtime 2.7.0 framework package that Windows had registered (the last form of Appendix A), as the Windows account set aside for these runs. Each checked the account first. No run installed anything. The first run printed the SHA-256 of the framework package's `Microsoft.ui.xaml.dll` and `WinUIEdit.dll`, and each matched the file in the `Microsoft.WindowsAppSDK.WinUI` 2.7.0 package, so the frames below are named from Microsoft's public symbols for those files (from `msdl.microsoft.com`, by each file's CodeView GUID and age). Source lines are cited at tag `winui3/release/2.7.0` of microsoft/microsoft-ui-xaml (commit 1b5b1a0).

**Run 1. Hypothesis: the text box fails because of focus (the Text Services Framework starting when the box takes focus), spell checking, or text prediction.** The probe set, in turn, `IsSpellCheckEnabled` false, `IsTextPredictionEnabled` false, both, `IsTabStop` false, and `IsEnabled` false, each before the box joined the window. Every variant ended the process with 0xC000027B and the same message, so the hypothesis is ruled out. The same run read the thread's error information at two points, with `GetRestrictedErrorInfo` and `RoInspectCapturedStackBackTrace`. Right after `Window.Activate`, before anything failed, the thread already held an error of 0x80040111 ("ClassFactory cannot supply requested class") with the text `Windows.ApplicationModel.LimitedAccessFeatures`. The stack combase captured when that error was raised runs from `Microsoft.UI.Xaml.dll`, during window creation, through `dcompi.dll` and Windows' `dcomp.dll`, to combase's activation of a class in `Windows.ApplicationModel.dll`. DirectComposition asked for a limited access feature, got that error, and went on. A scan of `C:\Windows\System32` found the string in 18 files, `dcomp.dll` among them, and in no file of the framework package.

**Run 2. Hypothesis: the `LimitedAccessFeatures` error is left over on the thread, and WinUI reports it in place of the text box's error.** WinUI's `ErrorHelper::ReportUnhandledError` takes whatever error is on the thread (`ErrorHelper.cpp`, line 459; `ErrorInfo::GetFromThread`, `ErrorInfo.cpp`, lines 52 to 78), with no check that it matches the failure being reported, and `ProcessUnhandledError` raises `UnhandledException` with that error's code and message (`ErrorHelper.cpp`, lines 545 to 552). The run made two checks:

- Without a text box, the same `LimitedAccessFeatures` error was on the thread after `Activate`, and the probe ran to its end with status 0.
- With a text box, the probe cleared the thread's error (`SetErrorInfo(0, NULL)`) after `Activate`. The process still ended, and `UnhandledException` then reported 0x80004005, "Unspecified error", which is what the 1.8.260921001 runs of section 5 printed.

The hypothesis holds: the text box's error is E_FAIL, and it carries no message.

**Run 3. Where E_FAIL comes from.** WinUI records each failure its code returns in "error contexts" for the thread: up to five, each with up to 512 frames and the HRESULT at each frame (`ErrorContextStructure.h`, lines 37 to 100). They are kept in a TLS slot whose index is the static `g_dwErrorContextTlsIndex` (`errorcontext.cpp`, lines 54 and 250), at RVA 0xd33204 in this `Microsoft.ui.xaml.dll` by its public symbols. The probe's `UnhandledException` handler read the list from that slot. The newest context, of 157 frames, read from the failure outward (frame numbers in parentheses):

- `CXcpDispatcher::Tick` (115) ran a frame, whose `CLayoutManager::UpdateLayout` (110) measured the window's content. That applied the content presenter's template, which added the panels, and the text box entered the tree (`CTextBoxBase::EnterImpl`, 43).
- On entering, the text box applied its default style (`CControl::EnsureBuiltInStyleApplied`, 41, then `DefaultStyles::GetDefaultStyleByKey`, 37). A setter of that style has a `StaticResource` value (`OptimizedStyle::EnsureValueRealized`, 18; `BinaryFormatObjectWriter::ProvideStaticResourceReference`, 16), which WinUI looked up in the global theme resources and made from its deferred markup (`CResourceDictionary::GetKeyFromGlobalThemeResourceNoRef`, 12; `CResourceDictionary::TryLoadDeferredResource`, 9).
- Making that object failed in `ObjectWriterCommonRuntime::CreateType` (3), under `XamlType::get_FullName` (1), with E_FAIL at frame 0.

In WinUI's default styles (`dxaml/xcp/dxaml/themes/generic.xaml`), `TextBox`'s `ContextFlyout` and `SelectionFlyout` are set to `{StaticResource TextControlCommandBarContextFlyout}` and `{StaticResource TextControlCommandBarSelectionFlyout}` (lines 21358, 21373, and 21374), and so are those of `RichEditBox` (lines 20047, 20063, and 20064) and `PasswordBox` (lines 20267, 20282, and 20283). Both resources are a `TextCommandBarFlyout` (lines 7167 and 7168). An `AutoSuggestBox` holds a `TextBox`. Those are the four controls that failed, and the styles of the controls that worked have no such setter. `TextCommandBarFlyout` is a class of `Microsoft.UI.Xaml.Controls.dll`, not of `Microsoft.UI.Xaml.dll` (the WinUI package's `package.appxfragment` lists it at line 713, under the `Path` of line 517). WinUI finds types outside `Microsoft.UI.Xaml.dll` by asking the `Application` object for `IXamlMetadataProvider` (`MetadataAPI::TryGetMetadataProvider`, `MetadataAPI.cpp`, lines 326 to 375), and adds only `Microsoft.UI.Xaml.Phone.dll` by itself (line 32). The XAML compiler puts `XamlControlsXamlMetaDataProvider` first among the providers an app's generated code consults (`TypeInfoCollector.cs`, lines 180 to 199). The probe's `Application` answered `IApplicationOverrides` and handed every other interface to WinUI's inner object, which does not answer `IXamlMetadataProvider`, so WinUI had no description of `TextCommandBarFlyout` and could not make one.

**Run 4. Hypothesis: if the probe's `Application` answers `IXamlMetadataProvider` by handing each of its three methods to a `XamlControlsXamlMetaDataProvider`, the text box and `XamlControlsResources` start.** The probe gave its outer `Application` object one more interface, whose three methods call the same slots of a `Microsoft.UI.Xaml.XamlTypeInfo.XamlControlsXamlMetaDataProvider`, made on the first call:

```ruby
IID_XAML_METADATA_PROVIDER = "a96251f0-2214-5d53-8746-ce99a2593cd7" # GetXamlType 6 and 7, GetXmlnsDefinitions 8

provider = nil
forward = lambda do |slot|
  [[P, P], lambda do |_this, a, b|
    provider ||= activate("Microsoft.UI.Xaml.XamlTypeInfo.XamlControlsXamlMetaDataProvider").qi(IID_XAML_METADATA_PROVIDER)
    provider.call(slot, [P, P], a, b)
  end]
end
overrides = Impl.new("Probe.App", {
  IID_APPLICATION_OVERRIDES => [[[P], ->(_this, _args) { launched.call; 0 }]],
  IID_XAML_METADATA_PROVIDER => [forward.(6), forward.(7), forward.(8)],
})
```

Each method takes two pointers on x64 (the 16-byte `TypeName` of the first `GetXamlType` goes by reference), so the Ruby passes them on as they came. In `OnLaunched` the probe then activated `XamlControlsResources` and set it as `Application.Resources` (`IApplication`, slot 7), as a WinUI app merges it in its `App.xaml`. The screen was section 4's, with the text box. The timer's steps set the text box's text and clicked Add through UI Automation twice, removed the first row, focused the text box (`UIElement.Focus`, slot 226, with `FocusState.Keyboard`), posted `WM_CHAR` for each letter of "Bread" to the window that `GetGUIThreadInfo` gave as having keyboard focus, and posted the Return key's `WM_KEYDOWN` and `WM_KEYUP` there. The text box's `KeyDown` handler adds the text as a row on Return. The run printed:

```
[probe] the Application answers IXamlMetadataProvider: true
[probe] XamlControlsResources: activated
[probe] Application.Resources is the XamlControlsResources
[probe] window activated
[probe] layout: the content is 1424.0 by 734.0
[probe] added "Milk"; the list has 1 rows
[probe] added "Eggs"; the list has 2 rows
[probe] removed row 0; the list has 1 rows
[probe] Focus returned 1; focused window 0x1310498
[probe] posted "Bread" as WM_CHAR to 0x1310498
[probe] posted Return to 0x1310498; the text box holds "Bread"
[probe] KeyDown 13
[probe] added "Bread"; the list has 2 rows
[probe] layout: the content is 1424.0 by 734.0
[probe] the list ends with 2 rows: ["Eggs", "Bread"]
[probe] Application.Start returned; exiting with 0
```

The same probe without the interface, in the same run, ended with 0xC000027B as before, and `XamlControlsResources` failed with 0x80004005 again. The hypothesis holds. The characters reached the text box through its input path, since `get_Text` returned "Bread" after the posts, and Return raised `KeyDown` with key 13, which added the row.

**What this changes in the note above.** These runs used the bootstrapper route only; nobody ran the self-contained route of section 1, or a package with identity, again with the fix. Section 5's text box, its `PasswordBox`, `RichEditBox`, and `AutoSuggestBox`, and its failing `XamlControlsResources` share the one cause found here. The failure of `XamlReader.Load` on `<TextBox/>` (0x802B000A) fits the same cause, and no run tried it with the fix. The `LimitedAccessFeatures` error that DirectComposition leaves on the thread does no harm, but WinUI reports it in place of any later unhandled error that carries no message, so a Ruby `UnhandledException` handler prints a misleading message unless the Ruby clears that error after `Activate`. Basket's Windows bridge needs the interface above, about ten lines. With it, WinUI 3 from pure Ruby carries Basket's screen on this computer: the list, the text box, Add, Remove, and Return. How the Fluent styles look is not known, since no run read a pixel.
