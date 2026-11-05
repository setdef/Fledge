<!--
SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>

SPDX-License-Identifier: CC-BY-SA-4.0
-->

> Trial by an agent session on 2026-11-04, on the branch `experiment/lota-windows-trial`, of a small Lota 0.1.2 game built with `fledge build` and run on GitHub's `windows-latest` (x64) and `windows-11-arm` (ARM64) runners. Requested: written by an agent and not reviewed line by line. The workflow is `.github/workflows/lota-windows-trial.yml`, the game and the scripts are in `trial/`. One Fledge defect turned up, and its fix is on the branch `fix/windows-system-dlls`; nothing here changes `trunk`.

# A Lota game as a Fledge app on Windows

## Short answer

Fledge at `trunk` (054fd66) refuses to build the game on either Windows: its check of a gem's compiled files does not count four DLLs that every Windows has in System32, and Lota's engine and its OpenAL Soft import them. With that fixed (`fix/windows-system-dlls`, c20a629, whose full CI run 41931558728 passed all 74 jobs), `fledge build` writes the `.zip` and the NSIS setup program for both platforms in about a minute each, and the app runs on a fresh runner with no Ruby on its `PATH`.

What runs, on both platforms, unpacked and installed: the game with no window, which plays a sound through OpenAL Soft's null backend and exits 3; and the windowed game, which opens its window, draws, reads back two pixels of its own frame in the colours it drew, plays a tone, and quits by itself with 0, when the runner has a software renderer. A runner has no GPU and no audio device, so drawing needs Mesa beside the program, and sound needs OpenAL Soft's null backend. On x64 the game draws with Mesa's llvmpipe (OpenGL 4.6) or lavapipe (Vulkan 1.4); on ARM64 only with lavapipe, because Lota's ARM64 build has no OpenGL at all.

Every failure but Fledge's own traces to Lota's ARM64 build, to how Lota reports a missing renderer, or to the runners. The same game under `bundle exec` on the build runner, with no Fledge in the way, behaves the same in every case.

## What ran

The game (`trial/game/`) opens a 320x240 window on a blue background, draws an orange square in its middle and a line of text, plays half a second of a 440 Hz tone, captures frame 30 with `Lota::Graphics.capture_screenshot` and reads two of its pixels, writes it to the save folder as `frame.png`, and quits after four seconds with `Lota::Event.quit(0)`. With the argument `quiet`, `trial/main.rb` runs `trial/quiet/` instead, Lota's own Windows check: no window, graphics, or input modules, one sound source playing, exit status 3. `trial/main.rb` starts either as a fused game, with `Lota::Boot.new(folder, ARGV, fused: true).call`. `fledge.yml` asks for a windowed app named LotaTrial with an NSIS installer.

The build job, on each runner, downloads Lota 0.1.2's two Windows gems from its GitHub release, checks them against the release's `SHA256SUMS` and against SHA-256s pinned in the workflow, puts them in `vendor/cache`, locks both Windows platforms, fills in the checksum Bundler leaves empty for the platform it is not running on (as the Linux trial did), and runs `bundle exec fledge build` with Fledge from git, once at `trunk` and once at the fix. Ruby is 4.0.9, `mise.toml`'s pin, from setup-ruby. It then runs the game under `bundle exec` with the same stages as below (`trial/reference.ps1`).

The run job, on a fresh runner of each kind, unpacks the `.zip` with `Expand-Archive` under `Lota trial\jögo`, cuts `PATH` to Windows' own folders and checks that no Ruby is on it, and runs the program with exactly the environment a desktop gives one, through .NET's `Process` with both streams captured (`trial/run-on-windows.ps1`). Each stage takes a screenshot of the desktop 2.5 seconds in, saves the text of every window the game has open and the graphics DLLs it loaded, and kills it after 60 or 90 seconds. Then it installs the setup program silently, runs the game with no window from the installed folder, starts the windowed game from its Start menu shortcut, and uninstalls it.

Mesa 26.2.6 comes from MSYS2's UCRT64 and CLANGARM64 packages, 14 and 12 of them, each pinned by SHA-256 in `trial/mesa.sha256`, unpacked by a Linux job: `opengl32.dll`, `libgallium_wgl.dll`, `vulkan_lvp.dll`, and the DLLs they import, with a lavapipe driver manifest that names `vulkan_lvp.dll` beside it. The run copies them beside `LotaTrial.exe`, where the launcher's `SetDefaultDllDirectories(LOAD_LIBRARY_SEARCH_DEFAULT_DIRS)` lets SDL's `LoadLibrary("OPENGL32.DLL")` find them before System32's, and removes them after.

## Results

CI runs, all on `experiment/lota-windows-trial`: 41931892403 (4f30553, the first), 41933736621 (fc1c795, window texts and null audio), 41935758507 (9cbec30, `bundle exec` on the build runner), 41937280415 (14ae300, lavapipe tried, cancelled), 41938769900 (3791a89, a registry key the script could not make), 41940014221 (db09be8, cancelled), 41941237248 (56f3a3d, lavapipe drawing), and 41943599334 (367dce7, lavapipe from an ASCII path). In the last two, the x64 run job passed, and the ARM64 one failed only on its checks of the lavapipe stages under `jögo` (see Runner limits). The table's lavapipe rows come from 41941237248 and 41943599334, the rest from every run that reached the run jobs.

| Stage | x64-mingw-ucrt | aarch64-mingw-ucrt |
| --- | --- | --- |
| `fledge build`, Fledge at `trunk` | refused, exit 1 | refused, exit 1 |
| `fledge build`, Fledge at the fix | `.zip` 46.0 MB, setup 36.3 MB, 54 s | `.zip` 39.0 MB, setup 30.0 MB, 64 s |
| no window, the runner's audio | exit 3, `Could not open device.`, 0 sources | the same |
| no window, `ALSOFT_DRIVERS=null` | exit 3, `Windows: 1 source playing` | the same |
| window, Windows' own OpenGL | message box: OpenGL 1.1.0 GDI Generic | message box: no OpenGL / GLES library |
| window, llvmpipe | draws, exit 0, 264 to 270 frames in 4 s | message box: no OpenGL / GLES library |
| window, lavapipe, under `bundle exec` | draws, 1976 frames in 4 s | draws, 2372 frames in 4 s |
| window, lavapipe, the app under an ASCII path | draws, exit 0, 1957 frames in 4 s | draws, exit 0, 2339 frames in 4 s |
| window, lavapipe, the app under `jögo` | could not find Vulkan | could not find Vulkan |
| window, through the shell | draws with llvmpipe, exit 0 | could not find Vulkan (under `jögo`) |
| setup program, silent install and uninstall | exit 0, Start menu shortcut, folder removed | the same |
| installed, no window | exit 3, 1 source playing | the same |
| installed, from the Start menu shortcut | draws with llvmpipe, exit 0 | draws with lavapipe, exit 0 |

In every stage that draws, the frame the game read back has `[1.0, 0.5, 0.0, 1.0]` at the centre and `[0.1, 0.2, 0.6, 1.0]` near a corner, the colours it drew, and `frame.png` shows the square and the text. The renderer lines read `OpenGL 4.6 (Core Profile) Mesa 26.2.6 / Mesa / llvmpipe (LLVM 23.1.4, 256 bits)` and `Vulkan 1.4.354 / Mesa / llvmpipe (LLVM 23.1.4, 256 bits)` on x64, `128 bits` on ARM64. The process's loaded modules confirm the game's own `OpenAL32.dll` came from `ruby\lib\ruby\gems\4.0.0\gems\lota-0.1.2-PLATFORM\lib\lota\libraries`, and Mesa's DLLs from the app's folder.

Artifacts of each run: `lota-trial-PLATFORM` (the `.zip`, the setup program, the build's output, the lockfile, and `reference/`, the `bundle exec` stages), `results-PLATFORM` (each stage's output, its window texts in `LABEL-windows.txt`, the desktop's screenshot in `LABEL.png`, and the game's own frame in `LABEL-frame.png`), and `mesa-PLATFORM`. The x64 screenshots of run 41941237248 show the game's window over the runner's console; the ARM64 ones show Windows' first sign-in screen, which covers that runner's desktop (see Runner limits).

## Defects, by owner

### Fledge

**`fledge build` refuses a gem that imports `avrt.dll`, `dwmapi.dll`, `imm32.dll`, or `setupapi.dll`.** At `trunk`, on both runners:

```
fledge build: LotaTrial can't ship for x64-mingw-ucrt:
fledge build:   lota 0.1.2 (x64-mingw-ucrt)'s lib/lota/libraries/OpenAL32.dll needs AVRT.dll, which neither windows, nor Fledge's runtime, nor the gem itself provides, so the app could not load it on another computer. Build the gem so that it carries the library, or links it statically.
fledge build:   lota 0.1.2 (x64-mingw-ucrt)'s lib/lota/native.so needs dwmapi.dll, ...
fledge build:   lota 0.1.2 (x64-mingw-ucrt)'s lib/lota/native.so needs IMM32.dll, ...
fledge build:   lota 0.1.2 (x64-mingw-ucrt)'s lib/lota/native.so needs SETUPAPI.dll, ...
```

The root cause is `Fledge::Linkage::SYSTEM_LIBRARIES["windows"]`, which came from what Ruby and the runtime import and so names none of the DLLs a windowed program's libraries link for windows, input, and sound. Each of the four is in System32 on both runners (`System32\avrt.dll` 10.0.26100.32860 on x64, for one) and on every x64 Windows from 7 SP1 and every ARM64 Windows from 10, as delvewheel 1.13.2's `ignore_names_x64` and `ignore_names_arm64` list them. The fix, c20a629 on `fix/windows-system-dlls`, adds those and the others such libraries link (`cfgmgr32`, `comctl32`, `d3d9`, `d3d11`, `dinput8`, `dsound`, `dxgi`, `hid`), with a test of a game-shaped gem and two new PE fixtures, a CHANGELOG line, and ADR 006's sentence. Its gate passed locally and its CI run, 41931558728, passed every job. It is not merged into `trunk`.

Nothing else in this trial is Fledge's. The app found the game's DLLs, kept the person's Ruby out, wrote nothing into its folder that the uninstaller did not remove, and behaved as `bundle exec` did on the build runner in every stage.

### Lota

These are for Lota's maintainers, with what to look at.

1. **The ARM64 build cannot use OpenGL, though ARM64 Windows has it.** `tasks/windows_build.rb` at v0.1.2 (lines 237 to 251) builds SDL with `-DSDL_OPENGL=OFF` on ARM64, since "Windows on ARM64 has no opengl32.dll". The `windows-11-arm` runner (Windows 11 Enterprise 10.0.26200) has `System32\opengl32.dll` 10.0.26100.9549, and both it and Mesa's ARM64 `opengl32.dll` load into an ARM64 process (`LoadLibraryExW`, run 41941237248). The game still cannot open a window with either, under `bundle exec` and in the app alike: `SDL window creation error: Could not initialize OpenGL / GLES library`. So on ARM64 Lota draws only with Vulkan, which this trial saw work with lavapipe. An ARM64 PC whose only working graphics API is OpenGL would not run a Lota game; none was tried. Whether SDL built with OpenGL fails on a Windows on ARM that lacks `opengl32.dll` was not tried either.
2. **With no usable renderer, a player meets a Ruby backtrace and a silent wait.** The game shows a modal message box titled "Initialization error" whose text starts with a path into the installed gem and a Ruby exception class, then the engine's advice:

   ```
   D:/Lota trial/jögo/LotaTrial-x64-mingw-ucrt/ruby/lib/ruby/gems/4.0.0/gems/lota-0.1.2-x64-mingw-ucrt/lib/lota/window.rb:105:in 'Lota::Native::Window.set_mode': Unable to create renderer. (RuntimeError)
   This program requires a graphics card and video drivers which support Vulkan, OpenGL 3.3, or OpenGL ES 3.0.

   Detected OpenGL version:
   1.1.0 - GDI Generic (Microsoft Corporation)
   ```

   Until someone presses OK, nothing reaches standard output or standard error, and the process stays alive: every such stage here ran into its 60 or 90 second limit with only the game's first line printed. What it prints after OK was not seen. For a game shipped to people without Ruby, the first line names Ruby internals; the engine's advice and the detected version are what a player can act on.
3. **On ARM64 the message names the wrong library.** The box reports only the last error the engine met, from its OpenGL ES fallback, `Could not initialize OpenGL / GLES library`. It does not say that this build has no OpenGL, so a player or a developer reads it as a driver problem.
4. **Drawing on Windows can be tested in CI.** Lota's README says nothing has tested drawing on Windows, since a runner has no GPU. This trial drew on both runners with Mesa's lavapipe, and on x64 with llvmpipe too, from MSYS2's packages pinned by SHA-256. Two settings matter. The engine's Vulkan renderer scores a CPU device zero unless the hint `LOVE_GRAPHICS_VULKAN_ALLOW_SOFTWARE` is set (its `src/modules/graphics/vulkan/Graphics.cpp`, `rateDeviceSuitability`), which SDL also reads from the environment. And a runner's processes are elevated, so the Vulkan loader ignores `VK_DRIVER_FILES`; the driver's manifest goes under `HKLM\SOFTWARE\Khronos\Vulkan\Drivers` instead.
5. **No audio device means silence and one line on standard output.** With no audio endpoint, the engine prints `Could not open device.` to standard output and plays nothing (`Lota::Audio.active_source_count` is 0). That is the engine's behaviour, not new in Lota; it is here because a game's own output gets that line first.

### Runner limits

- **No GPU.** The display adapter is `Microsoft Hyper-V Video`. Windows' own OpenGL is 1.1, `GDI Generic`, on x64. `System32\vulkan-1.dll` 1.3.300 is there, with no Vulkan device behind it.
- **No audio endpoint.** OpenAL Soft opens no device, though the Windows Audio service runs. `ALSOFT_DRIVERS=null`, OpenAL Soft's own setting, makes it open its null backend, as Lota's CI does with its `alsoft.conf`.
- **Elevated processes.** The Vulkan loader ignores `VK_DRIVER_FILES` and `VK_ICD_FILENAMES` in an elevated process, and the runner's are (`elevated: True`), so lavapipe had to be registered under HKLM.
- **The ARM64 runner's desktop is covered.** Its interactive session shows Windows' "Choose privacy settings for your device" page over everything, so a screenshot shows only that. The game's windows are there underneath: their text was read with `EnumWindows`, and the game's own frame capture shows what it drew.
- **lavapipe under a folder with a letter outside ASCII.** The same files that drew from `%LOCALAPPDATA%\Programs\LotaTrial` and from Ruby's folder found no Vulkan device from `Lota trial\jögo`, on both runners: `Cannot create Vulkan renderer: could not find vulkan`. The same app unpacked under `%RUNNER_TEMP%\ascii` drew with lavapipe on both (run 41943599334). llvmpipe drew from `jögo` on x64, and so did the app itself, so the folder's name matters only to how the Vulkan loader reads a driver manifest's path, not to Fledge's launcher or to Lota.
- **Mesa's Direct3D 12 driver on WARP** created an OpenGL 4.6 context on x64 (`D3D12 (Microsoft Basic Render Driver)`) and then the game exited with 0x80070057 after 2.5 seconds. This was not looked into.

## What was not verified

- A Windows computer with a GPU, a real audio device, or a person at it. Everything here is a CI runner.
- That a player can dismiss Lota's message box and what the game prints after.
- An ARM64 PC with OpenGL but no Vulkan, and a Windows on ARM without `opengl32.dll`.
- What happens to an app with Mesa's DLLs shipped beside its program. They were copied there by the trial after the build; `fledge.yml` has no way to put a file beside the program, and none is proposed here.
- The license notices the app carries for Lota's gem, including the OpenAL Soft source archive the gem ships in `sources/`, which went into the app with the rest of the gem. The trial did not read `notices\NOTICES.txt`.
- Whether `fledge build` refuses anything else a game gem might import from System32. The fix adds the names Lota imports and the ones SDL, OpenAL Soft, and a Direct3D or DirectInput game library commonly link; a gem that imports another System32 DLL would be refused the same way, and would need its name added.
