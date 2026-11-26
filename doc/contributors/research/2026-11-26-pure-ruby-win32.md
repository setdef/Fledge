<!--
SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>

SPDX-License-Identifier: CC-BY-SA-4.0
-->

> Findings of 2026-11-26 for the Windows half of issue #139, on whether an app's Ruby can draw a list, a text field, and buttons with Win32's common controls on Windows 11, with nothing of Fledge's, and what the app has to do to make them look like the system's controls. Requested: written by an agent and not reviewed line by line. They decide nothing: Basket, `doc/contributors/design/phone-widgets.md`, and the launcher change with the code. WinUI 3 is the subject of another note.

# Pure Ruby and Win32 common controls on Windows 11

`examples/basket` has no screen on a desktop (#139). On Windows, the controls to draw it with are Win32's: `user32` makes the window and the buttons and the text field, and `comctl32` makes the list. Every Windows 11 has both. This note asks whether Basket's Ruby, with Fiddle and nothing else, opens such a window and takes a click; what it takes for the controls to look like Windows 11's and not like the classic Windows controls; what a fresh Windows 11 needs; and how many lines Basket's bridge to all of it would be.

## How the experiments ran

Every answer below that an experiment could settle was settled by one, on a Windows 11 computer, `Microsoft Windows [Version 10.0.26300.9974]` from `ver`, which ran each program as a standard user. The Ruby was `ruby 4.1.0dev (2026-11-10 master 0e25874222) +PRISM [x64-mingw-ucrt]` with fiddle 1.1.8: the RubyInstaller archive that `runtime/sources.yml` pins for the Windows runtimes, which `mise.toml` installs for a contributor on Windows. It was not a built app: no Windows runtime existed on the computer, and building one there takes far longer than this note's questions did, so the launcher's start-up is unproven (section 7).

Each program ran on a desktop of its own, where `SendInput`, the cursor, and screenshots through GDI fail, so the experiment drove the program's window with posted messages: `WM_CHAR` for typing, `WM_LBUTTONDOWN` and `WM_LBUTTONUP` at a button's center for a click, `WM_KEYDOWN` for Return and Delete. It read pixels by sending the top-level window `WM_PRINT`, with `PRF_CLIENT | PRF_ERASEBKGND | PRF_CHILDREN`, into a device-independent bitmap in memory that Ruby allocated, and wrote a PNG from the bits. Those pictures show the client area only, with no title bar, no frame, and no DWM backdrop.

The program is one Ruby file of 427 lines that are not blank or comments, about 120 of them diagnostics, which `require`s `fiddle`, `zlib` (for the PNG), and `tmpdir`. It ran in three modes: `classic`, with nothing added; `actctx`, which activates Common Controls 6 first (section 2); and `dark`, which adds the dark-mode calls of section 5. Five runs of it exited 0, and the scenario of seven checks (section 3) passed in every mode, `actctx` under `rubyw.exe` as well as `ruby.exe`. The program and the pictures are not kept; a reader who needs them writes the program again from section 3's list and the excerpts below, which are the same calls in the same order, and this note describes each picture in words.

References to Microsoft's documentation are to the repositories that publish learn.microsoft.com, cloned at the commits `MicrosoftDocs/win32` bc82a65f, `MicrosoftDocs/sdk-api` 656e9656, and `MicrosoftDocs/windows-dev-docs` a3812316, by the file's path and the heading or line. Constants and structure layouts come from mingw-w64's headers at f0f3907625e5 (`mingw-w64-headers/include/commctrl.h` and `winuser.h`), since Microsoft's SDK headers are not published in a repository; each constant is one the experiment used.

## 1. Which controls: Microsoft recommends WinUI, and Win32's common controls follow Windows 11's geometry

**Finding.** Microsoft's guidance for a new Windows app is WinUI. `windows-dev-docs`, `hub/apps/get-started/windows-developer-faq.md`, line 78, "Which framework should I use to leverage Microsoft's latest investments in Windows app development?", answers on line 80: "If you're building a new Windows-only app, we recommend using WinUI." `hub/apps/get-started/best-practices.md`, lines 39 and 104, add: "If you can't use WinUI, consider emulating the styles demonstrated in our design toolkits and WinUI 3 Gallery." Microsoft also publishes guidance for a Win32 app on Windows 11: the pages "Support Dark and Light themes in Win32 apps" and "Apply rounded corners in desktop apps for Windows 11" under `hub/apps/desktop/modernize/ui/`, which the sections below cite.

What a Win32 app's controls look like on Windows 11 is a smaller question than which framework Microsoft recommends. `hub/apps/design/signature-experiences/geometry.md`, line 26, "Rounded corners": "Windows 11 applies rounded corners to all top-level app windows. The same applies to most common controls such as Button and ListView," with a 4 px radius for "in-page elements such as buttons and list backplates". The experiment's pictures show that this holds for Win32 controls once Common Controls 6 is active, and not before (section 2).

**What this note covers and what it does not.** Issue #139 asks for "the controls Microsoft's guidance recommends for a desktop app". The guidance recommends WinUI, so a Basket screen built on Win32's common controls departs from the recommendation, and the departure is a decision for the issue to record, not something this note settles (decisions needed, 1). This note answers what Win32 costs and how close it comes.

## 2. Common Controls 6 is off in a process whose manifest does not turn it on, and Ruby can turn it on itself

**Finding.** A process gets version 5.82 of `comctl32.dll`, which draws Windows 2000's controls, unless its manifest lists a dependency on version 6.0. Microsoft says so: `win32`, `desktop-src/Controls/cookbook-overview.md`, "Using Manifests or Directives to Ensure That Visual Styles Can Be Applied to Applications", line 29: "If you want your application to use visual styles, you must add an application manifest or compiler directive that indicates that ComCtl32.dll version 6 should be used if it is available." `desktop-src/Controls/em-setcuebanner.md`, line 52, says the same for the text field's placeholder: "To use this API, you must provide a manifest specifying Comclt32.dll version 6.0."

Neither RubyInstaller's `ruby.exe` nor Fledge's launcher has that manifest. The `classic` run, under RubyInstaller's `ruby.exe`, loaded `comctl32` from `C:\WINDOWS\WinSxS\amd64_microsoft.windows.common-controls_6595b64144ccf1df_5.82.26100.8328_none_87eede957a2ccddd\comctl32.dll`, and `InitCommonControlsEx` with `ICC_STANDARD_CLASSES` (0x4000, `commctrl.h` line 71) returned 0. The launcher's manifest, `runtime/launcher/windows.manifest`, lines 24 to 42, declares `requestedExecutionLevel`, `supportedOS`, `longPathAware`, and `activeCodePage`, and no `Microsoft.Windows.Common-Controls` dependency; `runtime/launcher/windows.rc` embeds it as the process's manifest, and `tasks/runtime_builder/windows.rb` links the resulting object into `launcher.exe` and `launcherw.exe` (lines 245 to 248) and into the runtime's `ruby.exe` and `rubyw.exe` (lines 258 and 278). So a Fledge app, and the runtime's Ruby under `ruby main.rb`, start with the controls of version 5.82, as RubyInstaller's `ruby.exe` does.

**What Ruby can do about it.** Windows can activate a manifest for a thread at run time. `CreateActCtxW` takes an `ACTCTXW` whose `lpSource` is the path of a manifest file ("Null-terminated string specifying the path of the manifest file or PE image", `sdk-api`, `sdk-api-src/content/winbase/ns-winbase-actctxw.md`, line 162), and `ActivateActCtx` makes it the thread's. The experiment wrote Microsoft's own dependency to a file:

```xml
<assembly xmlns="urn:schemas-microsoft-com:asm.v1" manifestVersion="1.0">
  <dependency><dependentAssembly>
    <assemblyIdentity type="win32" name="Microsoft.Windows.Common-Controls"
      version="6.0.0.0" processorArchitecture="*" publicKeyToken="6595b64144ccf1df" language="*"/>
  </dependentAssembly></dependency>
</assembly>
```

and ran, with the structure packed as `[56, 0, source_address].pack("LLQ")` into a 56-byte buffer:

```
CreateActCtxW(...common-controls.manifest) -> 1503927072632 (-1 is failure; last error 0)
ActivateActCtx -> 1 (last error 0)
InitCommonControlsEx -> 1
comctl32 modules after: [".../amd64_microsoft.windows.common-controls_6595b64144ccf1df_6.0.26100.9818_none_3e071914e3359bdd/comctl32.dll"]
```

The same process, with nothing else changed, then had the controls of version 6.0. Four readings differ between the modes:

| Reading | `classic` | `actctx` |
|---|---|---|
| `comctl32.dll` loaded | 5.82.26100.8328 | 6.0.26100.9818 |
| `EM_SETCUEBANNER` on the text field | 0 | 1 |
| `BCM_GETIDEALSIZE` on a button | 0 | 1 (ideal size 51 by 40 px at 192 dpi) |
| `GetWindowTheme` of the text field and the Add button | 0 and 0 | 65537 and 131075 |

The pictures differ the same way. With version 5.82, Add and Remove are gray rectangles with a raised bevel, the text field is empty, and the list's selected row is a flat light gray. With version 6.0, Add has a 4 px-rounded outline with the accent color on the default button, the text field shows "Add an item", and the list has Windows 11's selection color and thin border. Both pictures came from the same Ruby calls in the same order, with the manifest the only difference. The `rubyw.exe` run, a GUI-subsystem program with no standard output, passed the same seven checks with the output sent to a file.

**Where the manifest file lives.** `lpSource` is a path, so the manifest has to be a file when Ruby calls `CreateActCtxW`. The experiment wrote it to a temporary folder. Basket can carry it as a file in `lib/`, found with `__dir__`, which Fledge copies with the rest of the project, so Basket writes no file at run time. Microsoft's other way, a manifest in the program or beside it (`cookbook-overview.md`, line 162, "The file system version takes precedence"), would be the launcher's job and would give every Fledge app Common Controls 6 where `ruby.exe` has none. That is a difference from `ruby main.rb`, and a bug unless `Parity::JUSTIFIED` says why it is right (AGENTS.md, design precedence 2; decisions needed, 2).

## 3. What Ruby needs over Fiddle

Everything below ran. Each is a plain C call to `user32`, `gdi32`, `kernel32`, `comctl32`, `uxtheme`, or `dwmapi`, or the window procedure as a closure; none needed COM.

- **The window procedure is a `Fiddle::Closure::BlockCaller`** of type `LRESULT (HWND, UINT, WPARAM, LPARAM)`, made with `BlockCaller.new(TYPE_INTPTR_T, [TYPE_INTPTR_T, -TYPE_INT, TYPE_UINTPTR_T, TYPE_INTPTR_T]) { |hwnd, msg, wp, lp| ... }`, its address in the `WNDCLASSEXW`'s `lpfnWndProc`. It is called from `DispatchMessageW` and from `CreateWindowExW` (for `WM_CREATE`, which runs before the call returns), always on Ruby's main thread, the one that called `GetMessageW`. An exception raised inside the procedure came out of the `DispatchMessageW` call in the message loop with its backtrace (`RangeError: bignum too big to convert into 'long long'`, from an HDC passed as a signed type), and ended the process there, so a loop can `rescue` around `DispatchMessageW`. Keep the closure in a constant, or the garbage collector frees it.
- **Windows' integers are 64 bits where a handle is, and 32 where `LONG` is.** Fiddle's `TYPE_LONG` is 32 bits on Windows (LLP64), so handles, `WPARAM`, `LPARAM`, and `LRESULT` need `TYPE_INTPTR_T` or `TYPE_UINTPTR_T`. A handle the system gives out can be a sign-extended 32-bit value, such as an HDC; as an unsigned `WPARAM` it is a bignum above 2^63, which does not fit `TYPE_INTPTR_T`. Declare a function that takes it as `TYPE_UINTPTR_T`.
- **Structures are buffers packed by hand,** with `Fiddle::Pointer.malloc` and `Array#pack`; fiddle's struct classes (`Fiddle::Importer`) were not tried. The sizes the experiment used, computed for x64 from the structures' fields and confirmed by the calls succeeding: `WNDCLASSEXW` 80 bytes, `MSG` 48, `LVITEMW` 88, `LVCOLUMNW` 56, `ACTCTXW` 56, `NONCLIENTMETRICSW` 504, `OSVERSIONINFOW` 276.
- **The list is `SysListView32`** with `LVS_REPORT | LVS_SINGLESEL | LVS_SHOWSELALWAYS | LVS_NOCOLUMNHEADER`, one column, and messages `LVM_INSERTCOLUMNW`, `LVM_INSERTITEMW`, `LVM_GETITEMTEXTW`, `LVM_DELETEITEM`, `LVM_GETNEXTITEM`, `LVM_SETITEMSTATE`, `LVM_SETEXTENDEDLISTVIEWSTYLE` (`commctrl.h`, lines 2274 to 2750). Its Delete key arrives as `WM_NOTIFY` with `LVN_KEYDOWN` (line 3302) and a two-byte virtual-key code at offset 24 of the notification.
- **Tab and Return come from `IsDialogMessageW(main_window, msg)` in the message loop,** called before `TranslateMessage`. For a window that is not a dialog, `IsDialogMessageW` asks the window which button is the default with `DM_GETDEFID` (`winuser.h`, line 4659), and the procedure answers `(0x534B << 16) | ID_ADD` (`DC_HASDEFID`, `winuser.h`, line 4663, in the high word). With that answer, a `WM_KEYDOWN` of Return posted to the text field added the item, which a procedure that ignores `DM_GETDEFID` would not.
- **Typing, a click, and the Delete key** all reached Ruby as the messages above and changed the list: the list held `Milk` after a click on Add, held `Milk` and `Eggs` after Return, held `Eggs` after Remove on the selected `Milk`, and held nothing after Delete on `Eggs`.

The scenario's seven checks, each printed `PASS`: typing reaches the field, a click on Add puts the item in the list, the field empties, Return presses the default button, the first row can be selected, a click on Remove deletes it, and Delete in the list removes the row.

## 4. A window that is crisp, in the system's font

**Process DPI awareness.** A process with no `dpiAwareness` in its manifest is DPI-unaware, and Windows scales its window as a bitmap. The experiment read it: `GetAwarenessFromDpiAwarenessContext(GetThreadDpiAwarenessContext())` was 0 before Ruby did anything, the same under `ruby.exe` as the launcher's manifest gives. `SetProcessDpiAwarenessContext(-4)`, `DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2`, returned 1 and the awareness was 2 afterward, and `GetDpiForWindow` then said 192 on the computer's display. Microsoft recommends a manifest, and allows the call: `win32`, `desktop-src/HiDPI/setting-the-default-dpi-awareness-for-a-process.md`, line 23, "We recommended that you specify the default process DPI awareness via a manifest setting. While specifying the default via API is supported, it is not recommended", and line 58, "If you are setting the process-default DPI awareness mode programmatically, you must call the corresponding API before any HWNDs have been created." Basket calls it first. A manifest in the launcher would be the same departure from `ruby main.rb` as section 2's.

**Font.** A Win32 window draws in the stock font until a control is sent `WM_SETFONT`. `SystemParametersInfoForDpi(SPI_GETNONCLIENTMETRICS, ...)` gave `lfMessageFont` as `"Segoe UI"`, height -24 px at 192 dpi (9 pt), and `CreateFontIndirectW` made the font each control took. Windows 11's apps use Segoe UI Variable for text drawn by XAML controls ("When using XAML common controls, the Segoe UI Variable font will be selected by default", `hub/apps/design/signature-experiences/typography.md`, line 29); Win32 controls take the message font, which is Segoe UI. That is a difference between WinUI's controls and these, which no picture of the experiment shows.

**Layout.** A window sized in pixels at 96 dpi is half the size at 192, so each size is multiplied by `dpi / 96`, and `MoveWindow` places each control on every `WM_SIZE`. The experiment's layout clipped the Remove button at the bottom of its pictures: that is the experiment's arithmetic, not a fact about Win32.

## 5. Light and dark: Microsoft documents the title bar, and the controls need undocumented calls

**Finding.** A Win32 app is light, whatever the person chose, until it opts in. The experiment's `AppsUseLightTheme` (read from `HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize` with `RegGetValueW`, a read) was 0, dark, and every picture of the `actctx` mode is light. `hub/apps/desktop/modernize/ui/apply-windows-themes.md`, "Enable a Dark mode title bar for Win32 applications", line 168, says that "Windows doesn't know if an application can support Dark mode, so it assumes that it can't", and gives `DwmSetWindowAttribute` with `DWMWA_USE_IMMERSIVE_DARK_MODE` (20, `dwmapi.h`, line 49; "supported starting with Windows 11 Build 22000", `sdk-api`, `sdk-api-src/content/dwmapi/ne-dwmapi-dwmwindowattribute.md`, line 154) as the way to a dark title bar. The call returned `S_OK`; the frame is outside what `WM_PRINT` draws, so no picture shows it. The same page, line 54, says what it leaves out: "It does not cover specifics of how to repaint and render your app UI using a Dark mode color set." For Win32's common controls, Microsoft documents nothing more.

**What works, and what it rests on.** The `dark` mode did three things, none documented by Microsoft. It called `uxtheme.dll`'s unnamed exports by ordinal: 135 (`SetPreferredAppMode`, given 2, `ForceDark`), 104 (`RefreshImmersiveColorPolicyState`), and 136 (`FlushMenuThemes`), all present on this build. The numbers and meanings are those of the example program `ysc3839/win32-darkmode`, "undocumented dark mode API introduced in Windows 10 1809" (commit cc26549b, `README.md`, line 2; `win32-darkmode/DarkMode.h`, lines 10 to 17, 63 to 72, and 201 to 212). It gave the list and both buttons the visual style `DarkMode_Explorer` and the text field `DarkMode_CFD` through `SetWindowTheme`; those two names are the experimenter's, from no source this note read, and the run did not isolate which call darkened which control. And it set the list's colors with `LVM_SETBKCOLOR`, `LVM_SETTEXTBKCOLOR`, and `LVM_SETTEXTCOLOR`, and answered `WM_CTLCOLOREDIT` with a dark brush and white text.

The picture shows both buttons and the list with dark backgrounds and light text, and the text field dark with a dim placeholder. With no `WM_CTLCOLOREDIT` handler, the text field stayed white, the one control the other calls did not darken. An app that depends on the ordinals depends on what `uxtheme.dll` exports in each Windows build.

**Mica.** `DwmSetWindowAttribute(DWMWA_SYSTEMBACKDROP_TYPE, DWMSBT_MAINWINDOW)` (38 and 2, by the order in `dwmapi.h`, lines 49 to 74) returned `S_OK`. Microsoft's page for Mica in a Win32 app says "you need to use the Windows App SDK" (`hub/apps/desktop/modernize/ui/apply-mica-win32.md`, line 17). Whether the call alone draws Mica could not be seen, since `WM_PRINT` does not draw the backdrop; it is unproven.

## 6. What a fresh Windows 11 needs, and what Basket's bridge costs

**Nothing is installed.** The window, the controls, the visual styles, and the dark-mode and DWM calls are in the operating system: `user32`, `gdi32`, `kernel32`, `uxtheme`, and `dwmapi` by their names, and Common Controls 6.0 in `WinSxS`, where the `actctx` run loaded it from. No Windows App SDK runtime, no MSIX identity, no manifest in the executable, and no admin rights are involved; the run's account was a standard user. This is a statement about this Windows build. A Windows 10 build older than 1703 lacks `SetProcessDpiAwarenessContext`'s per-monitor v2 context (the call returns 0, and Basket continues unaware), and one older than Windows 11 build 22000 has no dark title-bar attribute; each is a call whose failure Basket ignores.

**The bridge, estimated.** What a Basket screen on Win32 needs is these, with line counts that are estimates, not measurements, made from the experiment's program and from `ios.rb`'s (185 lines) and the 200 to 300 lines the iOS note estimated for Basket's Objective-C bridge (`2026-11-25-pure-ruby-uikit.md`, section 3):

| Part | Estimated lines |
|---|---|
| Function declarations (about 35 of the experiment's 51) and constants (about 30 of its 42) | 70 |
| Buffers, wide strings, structure packing and reading | 30 |
| Activation context and its manifest | 15 |
| DPI awareness and the message font | 15 |
| Window class, window procedure, message loop with `IsDialogMessageW` | 40 |
| Making the controls and laying them out | 50 |
| List, text field, and button helpers (add, remove, read text) | 30 |
| Basket's screen: what Add, Return, Remove, and Delete do with `Basket::List` | 30 |
| Dark mode: the calls of section 5 | 25 |

That is 305 lines, in a range of 250 to 350, beside Basket's `list.rb` (45 lines) and its other screens. It is Ruby only, plus one XML file of 8 lines. The iOS bridge is longer because Objective-C's runtime needs classes made at run time; Win32's window class is a table and a closure.

## 7. Recommendation

For Basket's Windows screen on Win32:

1. **Activate Common Controls 6 from Basket's Ruby** with `CreateActCtxW` and `ActivateActCtx`, before any control exists, with a manifest file in `lib/`. It needs nothing from Fledge, runs under `ruby.exe`, `rubyw.exe`, and (by the source of the launcher's manifest) `launcherw.exe` alike, and is the step that makes the controls look like Windows 11's.
2. **Call `SetProcessDpiAwarenessContext(-4)` first,** and size and place every control by `GetDpiForWindow`.
3. **Use the message font** from `SystemParametersInfoForDpi`, and `WM_SETFONT` on every control.
4. **Run the message loop with `IsDialogMessageW`,** and answer `DM_GETDEFID`, so that Tab and Return work as in a dialog.
5. **Follow light and dark, or stay light.** The title bar's calls are documented and number two. Dark controls need ordinals that Microsoft does not document. Decide before the screen (decisions needed, 3).

The reasons: each step is a documented Win32 call or message except dark controls; each ran on Windows 11 under the same Ruby as a Fledge runtime; the result has Windows 11's rounded buttons, placeholder text, selection color, and keyboard behavior; and none of it needs a file in a language but Ruby.

## 8. What stays unproven

- **A built Basket.** No Windows runtime was on the computer, so the experiment ran under RubyInstaller's `ruby.exe` and `rubyw.exe`, not `launcherw.exe`. The launcher's manifest has no Common Controls dependency and no DPI setting (section 2), as `ruby.exe`'s `classic` run shows for it, so nothing in the sources says the activation context differs there; a built app run on a fresh computer is Delivery's proof.
- **Windows on ARM.** The structure sizes are those of any 64-bit Windows (LLP64 pointers), so the code is the same; it ran on x64 only.
- **Windows 10 and other Windows 11 builds.** One build, 26300, ran.
- **How it looks to a person.** The pictures are the client area drawn by `WM_PRINT` at 192 dpi, from a private desktop; the frame, the title bar, Mica, the focus ring, and animation were not captured. The note's claims about look are those of the pictures.
- **Dark mode's calls one by one.** The pictures show the effect of the calls together; which call darkens which control, what the two visual-style names are, and whether the ordinals keep their numbers in later builds, were not settled.
- **Accessibility, input method editors, and high contrast.** Win32's controls carry Windows' accessibility interfaces; a Basket on Win32 was not run under Narrator, an IME, or a high-contrast theme.
- **A screen on a moved window.** `WM_DPICHANGED`, when a window moves between displays of different scale, was not handled or run.
- **Threads beside the message loop.** One window procedure ran on Ruby's main thread; another Ruby thread that posts messages to the window while the loop runs was not tried.

## Decisions needed

1. **Win32 or WinUI.** #139 says Basket's Windows screen uses "the controls Microsoft's guidance recommends", and that guidance is WinUI (section 1). Options: Win32's common controls, which this note proves with Fiddle alone and which need nothing installed; or WinUI, which the other note covers and which needs the Windows App SDK and COM or WinRT calls. Recommendation: choose from the two notes together, and edit the issue's wording to name whichever is chosen.
2. **Who turns on Common Controls 6 and per-monitor DPI.** Options: Basket's Ruby, as section 7 says; or Fledge's launcher manifest. Recommendation: Basket's Ruby, since `ruby.exe` has neither, so an app that depends on them runs under `ruby main.rb` as under Fledge.
3. **Dark mode.** Options: light only, with the documented dark title bar; or dark controls through the undocumented calls of section 5. Recommendation: follow the person's setting for the title bar and the controls once a maintained project or a Microsoft source confirms the ordinals, and until then stay light, which Microsoft documents.
