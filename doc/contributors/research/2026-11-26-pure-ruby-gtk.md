<!--
SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>

SPDX-License-Identifier: CC-BY-SA-4.0
-->

> Findings of 2026-11-26 for the Linux half of issue #139, on whether Basket's Ruby can draw its shopping list with GTK 4 by GNOME's Human Interface Guidelines with nothing of Fledge's, and on what that needs from the Linux that people run. Requested: written by an agent and not reviewed line by line. They decide nothing: Basket, `doc/contributors/design/desktop-apps.md`, and `doc/contributors/design/gems.md` change with the code.

# Pure Ruby and GTK 4 on Linux

Basket has no screen on Linux. Issue #139 asks whether GTK 4's C API, called through Fiddle with signals connected to closures, draws it; which GTK 4 a fresh Ubuntu, Debian, and Fedora have; how a built app finds `libgtk-4.so.1`; and whether anything needs GObject introspection. The answers below come from a probe: one Ruby file that requires `fiddle` and Basket's unchanged `examples/basket/lib/basket/list.rb`, and draws a window with a header bar, an entry, an Add button, and a list whose rows each have a button that removes them.

## How the experiments ran

The probe is 168 lines that are neither comments nor blank, kept outside the repository. It calls GTK 4's functions through `Fiddle::Function`, connects each signal to a `Fiddle::Closure::BlockCaller`, and ends in `g_application_run`. An environment variable switches on each thing the questions below ask about: a Ruby thread that counts while the window is open, `need_gvl: true` on every function, and a handler for SIGINT and SIGTERM.

Each run took place in a rootless Podman container of one distribution's image, pulled by digest, with the distribution's GTK 4 installed by its package manager and nothing of Ruby in the image. The Ruby was the one Fledge runs on, 4.1.0-preview1 from jdx/ruby (`mise.toml`, `runtime/sources.yml`), whose Linux builds are linked against glibc 2.17, with fiddle 1.1.8; the container reached it through a bind mount. Inside, Xvfb (800 by 640, 24 bits) and Openbox gave the window a display. The input was real: `xdotool` typed `Milk` and pressed Return, clicked the entry and typed `Eggs` and clicked Add, typed `Bread` and pressed Return, clicked the trash button of `Eggs`, and clicked the header bar's close button. A Ruby script of about 30 lines turned Xvfb's framebuffer file into a PNG with `zlib`, and each PNG was read at full size.

A second kind of run built the probe with `fledge build` (`kind: windowed`, on the x86_64-linux runtime of release 0.17.0, from the checkout at c281a19c) and ran the built program in containers of Ubuntu 24.04, Debian 12, and Fedora 44, with the launcher in front and no Ruby but the one inside the app. It ran and gave the same output on Ubuntu 24.04 and Fedora 44; on Debian 12 it did not start (section 4).

| Distribution (image digest) | GTK 4 | GLib | libadwaita |
| --- | --- | --- | --- |
| Ubuntu 24.04.5 (`sha256:562111b8…`) | 4.14.5 | 2.80.0 | 1.5.0 |
| Ubuntu 26.04.1 (`sha256:d66b366d…`) | 4.22.4 | 2.88.0 | 1.9.1 |
| Debian 12 (`sha256:e67eeead…`, slim) | 4.8.3 | 2.74.6 | 1.2.2 |
| Debian 13 (`sha256:8aa5a7bf…`, slim) | 4.18.6 | 2.84.4 | 1.7.6 |
| Fedora 43 (`sha256:f01112b9…`) | 4.20.4 | 2.86.5 | 1.8.8 |
| Fedora 44 (`sha256:15da97ed…`) | 4.22.5 | 2.88.4 | 1.9.4 |

The versions are what each distribution's package manager installed in the image (`apt-cache policy libgtk-4-1`, `rpm -q gtk4`), and are the newest versions each distribution's archive had on 2026-11-26, security updates included.

## 1. GTK 4's C API, called through Fiddle, draws Basket's screen

**Finding.** On every distribution in the table the probe's window came up, took the typed input, added three rows, removed the middle one, saved `["Milk","Bread"]` through `Basket::List`, and ended with exit status 0 when the header bar's close button was clicked. Basket's output, the same on every distribution:

```
Basket shows 0 items
Basket added Milk
Basket added Eggs
Basket added Bread
Basket removed Eggs
Basket exited 0
```

Fedora 43 needed one more package than the other five (section 6). The screenshots show a GTK 4 window in GTK's default theme: a header bar with the title `Basket` and the window's minimize, maximize, and close buttons; a text entry with the placeholder `Add an item…` and a blue `Add` button; a bordered, scrolling list; and, in each row, the item's name and a flat button with GNOME's trash icon. With no rows the list shows the placeholder `Nothing in the basket` in dimmed text. Removing `Eggs` left `Milk` and `Bread`, with the pointer's hover state on the second row's button.

**The calls are plain C.** Every function the probe binds is a public function of GTK 4, GLib, or GObject. The 35 of GTK's are declared `GDK_AVAILABLE_IN_ALL` in the headers at 4.8.3, 4.14.5, and 4.22.5 (`gtk/*.h`), and none is deprecated at 4.22.5. So the same file ran on GTK 4.8.3 and on 4.22.5, with GLib 2.74.6 and 2.88.4. The probe opens one library, with `Fiddle.dlopen("libgtk-4.so.1")`, and its handle finds the GLib, GObject, and GIO functions too (`g_application_run`, `g_signal_connect_data`, `g_object_set`, `g_unix_signal_add`), since `dlsym` on a handle searches the library's dependencies. Fiddle opens the library with `RTLD_LAZY | RTLD_GLOBAL` (`ext/fiddle/handle.c`, line 149, at fiddle v1.1.8).

**Nothing needs GObject introspection.** Introspection exists so that a language can generate its calls to a library from a typelib, the way ruby-gnome's gems do (`gems.md`, "Typelibs from the Linux distribution"). A program that writes its calls itself needs neither libgirepository nor a typelib. The difference shows in what a desktop installs: dry runs of each distribution's desktop (section 5) put `libgtk-4-1` in each of the five Ubuntu desktops tried and `gir1.2-gtk-4.0`, the typelib, in only some of them: Kubuntu, Lubuntu, and Xubuntu 24.04 have the library without it. A Basket that asked for the typelib would fail on those desktops, which have GTK 4.

**Signals take Fiddle's closures.** `g_signal_connect` is a macro over a function of six arguments, `g_signal_connect_data (instance, detailed_signal, c_handler, data, destroy_data, connect_flags)` (`gobject/gsignal.h`, lines 409 to 414 and 518 to 519, at GLib 2.80.0), so nothing about it is variadic. The probe passes a `Fiddle::Closure::BlockCaller` as `c_handler`, a closure of two pointers (the emitting object and the data), for `"clicked"` on a button and `"activate"` on the entry and on the application. It keeps each closure in an array, since Ruby's garbage collector would free a closure that only GLib refers to. One closure serves every row's trash button: each button is connected with its row's address as `data`, and the closure removes whatever row it is given.

**The main loop runs on the main thread.** `g_application_run` takes the default main context for the calling thread with `g_main_context_acquire` (`gio/gapplication.c`, line 2673, at GLib 2.80.0), and GTK needs every call of its API from the thread that created the application, which it calls the main thread (`docs/reference/gtk/question_index.md`, lines 85 to 88, at GTK 4.14.5). The launcher runs the app's Ruby on the process's main thread (`launcher.md`, line 77), and the probe printed `thread main: true` under `ruby` and in the built app. So the problem of ADR 104, a toolkit that owns the main thread while Ruby runs on a second one, does not arise on Linux. `g_application_run (app, 0, NULL)` is valid: GLib checks `argc == 0 || argv != NULL` (`gapplication.c`, line 2598), so the probe passes no arguments.

**Fiddle's lock handling lets other Ruby threads run.** Fiddle releases Ruby's lock around a call unless the function was made with `need_gvl: true` (`function.c`, lines 381 to 386), and a closure that GTK calls on that same thread takes the lock back for its Ruby code (`closure.c`, lines 220 to 233). So with the default, a Ruby thread keeps running while the main loop sits in `g_application_run`. The probe's counting thread, one tick per 0.05 s of `sleep`, showed it, on Ubuntu 24.04:

```
Basket added Milk (background thread ticks: 75)
Basket added Eggs (background thread ticks: 100)
Basket added Bread (background thread ticks: 128)
```

With `need_gvl: true` on every function, the same sequence read 0, 1, and 2: the main loop held the lock, and the thread barely ran. A Basket that does background work, such as saving the list, should keep Fiddle's default.

## 2. Varargs and reference counts

**Variadic functions.** Fiddle 1.1.8 calls a variadic function when its argument types end in `Fiddle::TYPE_VARIADIC` and each extra argument is passed as a type and a value (`function.c`, lines 95 to 115, 242 to 260, and 300 to 312, which call `ffi_prep_cif_var`). The probe sets the entry's placeholder with `g_object_set (entry, "placeholder-text", "Add an item…", NULL)`, a function declared `(gpointer object, const gchar *first_property_name, ...)` (`gobject/gobject.c`, lines 3304 to 3306), written as `OBJECT_SET.call(entry, "placeholder-text", P, "Add an item…", P, nil)`; the screenshots show the text. Nothing else in the screen is variadic, since GTK has a setter for each property the screen sets. In a variadic call a wrong type in a pair is the caller's error, which C does not check.

**Reference counts.** `GtkWidget` is a `GInitiallyUnowned`: a new widget starts with a floating reference (`gtk/gtkwidget.c`, line 700, at GTK 4.14.5), which the first container to take it turns into an ordinary one with `g_object_ref_sink` (line 6009). So the probe never calls `g_object_ref` or `g_object_unref` on a widget: `gtk_box_append`, `gtk_list_box_append`, `gtk_list_box_row_set_child`, `gtk_scrolled_window_set_child`, and `gtk_window_set_child` each take the reference, and `gtk_list_box_remove` gives it up. The one object the probe owns is the `GtkApplication`, whose `gtk_application_new` returns a new instance (`gtk/gtkapplication.c`, lines 660 to 672); it calls `g_object_unref` on it after `g_application_run` returns. A `Fiddle::Pointer` is only an address with no reference behind it, so the probe keeps an address only while the widget it points to is in a container, which holds for the row address that travels as a handler's data: the row's button is the only caller, and the button goes with the row.

Neither was checked for leaks or for a pointer used after its widget died; a long-running screen that adds and removes many rows would want a run under Valgrind first.

## 3. What GNOME's guidelines ask, and what GTK 4 alone gives

The guidelines (developer.gnome.org/hig, read at hig-www 97028eac) describe their patterns with libadwaita's widgets, and Basket's screen has five of them:

| Pattern | What the guidelines say | The probe, with GTK 4 alone |
| --- | --- | --- |
| Header bar | Holds the main actions, "such as *new*, *add*, *open* and *back*", at the start (`header-bars.rst`, line 13). | `GtkHeaderBar` with the title. Basket's Add button sits beside the entry, as on iOS, and not in the bar. |
| Text field | Placeholder text, phrased as an instruction followed by an ellipsis (`text-fields.rst`, lines 21 and 23). | `Add an item…`, set with `g_object_set`. |
| Suggested action | One button per view with the suggested style (`buttons.rst`, line 57). | `suggested-action` on Add, which GTK's theme draws (`gtk/theme/Default/_common.scss`, line 722, at 4.14.5). |
| List | A boxed list is "appropriate for relatively small static lists" (`boxed-lists.rst`, line 11). | `GtkListBox` in a scrolling frame. The `boxed-list` style class is in GTK's theme at 4.14.5 (`_common.scss`, line 3429) and 4.22.5, and not at 4.8.3. |
| Removing a row | "Destructive actions should always be accompanied by either a confirmation dialog or an offer to undo the action (typically using a toast)" (`dialogs.rst`, line 23). | None. The row goes at once. GTK 4 has no toast, and its `GtkAlertDialog` came in 4.10 (`gtk/gtkalertdialog.h` is absent at 4.8.3 and says `GDK_AVAILABLE_IN_4_10` at 4.14.5). |

**libadwaita.** The pages the table cites link libadwaita's widgets (`AdwHeaderBar`, `AdwToast`, `AdwStatusPage`, the rows of a boxed list), and libadwaita is also a C library, so Fiddle reaches it the same way. A second probe, 29 lines longer, opens `libadwaita-1.so.0` beside `libgtk-4.so.1`; makes an `AdwApplication` and an `AdwApplicationWindow`; puts an `AdwHeaderBar` above an `AdwToastOverlay` that holds the same column; gives the list the `boxed-list` style; and, when a row goes, shows an `AdwToast` titled `Removed Eggs` with an `Undo` button whose `button-clicked` signal puts the item back. It ran on Ubuntu 24.04 (libadwaita 1.5.0) and Debian 12 (1.2.2). The screenshots show libadwaita's look: round window buttons in the header bar, a filled entry, the list as one white rounded card with separators, and, at the bottom of the window after a removal, a dark rounded toast with the text, `Undo`, and a close button. Clicking `Undo` printed `Basket restored Eggs` and the row came back, at the end of the list because `Basket::List` has no insert. So undo after a removal, which GTK 4 alone lacks, is in reach of Fiddle through libadwaita, at the price of a second library on the computer (section 5).

## 4. How the probe reaches GTK 4 in a built app

`Fiddle.dlopen("libgtk-4.so.1")` is a `dlopen` of the soname (`ext/fiddle/handle.c`, line 183, at fiddle v1.1.8). On all six distributions with GTK 4 installed, `ldconfig -p` listed `libgtk-4.so.1`, and the probe found it from `ruby`, and from the built app on the two distributions where that started, with no setting.

**In a built app** the search starts in the app's `lib` folder. With `LD_DEBUG=libs`, the built app on Ubuntu 24.04 looked for `libgtk-4.so.1` first in `ROOT/lib`, which the loader's log labels "RPATH from file .../Basket": the launcher's `DT_RPATH` of `$ORIGIN/lib` (`launcher.md`, line 93). It found nothing there, searched `/etc/ld.so.cache`, and found `/lib/x86_64-linux-gnu/libgtk-4.so.1`. It looked up the library GTK needs next, `libgmodule-2.0.so.0`, in the same order. A shared library in `ROOT/lib` with the soname of one that GTK's chain needs would therefore be loaded in the computer's place. In the built app the only shared library of the runtime that the loader initialized from `ROOT/lib` was `libcrypt.so.2` (the others were Ruby's extensions, under `lib/ruby`), which nothing of GTK's asks for, so nothing of GTK's came from the app.

**On Debian 12 the built app did not start**, for a reason that has nothing to do with GTK. The loader stopped the launcher before Ruby ran:

```
Basket: /lib/x86_64-linux-gnu/libm.so.6: version `GLIBC_2.38' not found (required by Basket)
Basket: /lib/x86_64-linux-gnu/libc.so.6: version `GLIBC_2.38' not found (required by Basket)
Basket: /lib/x86_64-linux-gnu/libc.so.6: version `GLIBC_2.38' not found (required by lib/libcrypt.so.2)
```

`objdump -T` on the built `Basket` lists `GLIBC_2.38` for `__isoc23_strtol`, `__isoc23_strtoll`, `__isoc23_strtoul`, `fmod`, `strlcat`, and `strlcpy`, and on `lib/libcrypt.so.2` for `__isoc23_strtoul`, while the app's `fledge.cfg` says "Needs glibc 2.28 or newer". Debian 12 has glibc 2.36. This is issue #142. The probe under `ruby` ran on Debian 12, since Ruby there is the jdx/ruby build, and a Delivery job for a built Basket on Debian 12 cannot pass until the launcher holds to the runtime's floor.

## 5. Which GTK 4 a desktop has

A dry run of each distribution's desktop (`apt-get -s install TASK` in the Debian and Ubuntu images, with recommended packages, and `dnf install --assumeno @GROUP` in Fedora's) says whether that desktop would install the library (`libgtk-4-1`, `gtk4`), libadwaita, and, on Debian and Ubuntu, the typelib package `gir1.2-gtk-4.0`:

| Desktop | GTK 4 | libadwaita | typelib |
| --- | --- | --- | --- |
| Ubuntu 24.04: GNOME (`ubuntu-desktop-minimal`) | yes | yes | yes |
| Ubuntu 24.04: Kubuntu, Xubuntu | yes | yes | no |
| Ubuntu 24.04: Lubuntu | yes | no | no |
| Ubuntu 24.04: MATE | yes | yes | yes |
| Ubuntu 26.04: GNOME, Xubuntu, MATE | yes | yes | yes |
| Ubuntu 26.04: Kubuntu, Lubuntu | yes | no | no |
| Debian 12: GNOME (`task-gnome-desktop`) | yes | yes | yes |
| Debian 12: KDE, Xfce, MATE | no | no | no |
| Debian 13: GNOME | yes | yes | yes |
| Debian 13: KDE, Xfce | yes | no | no |
| Debian 13: MATE | yes | yes | no |
| Fedora 43 and 44: GNOME (`@gnome-desktop`) | yes | yes | |
| Fedora 43 and 44: Xfce | yes | yes | |
| Fedora 43 and 44: KDE | no | no | |

So every GNOME desktop in the table has GTK 4 and libadwaita, and a KDE or Lubuntu desktop is the case where an app that asks for either may find it missing: GTK 4 is absent from Fedora's KDE and from Debian 12's KDE, Xfce, and MATE, and libadwaita from Lubuntu, Kubuntu on 26.04, and Debian 13's KDE and Xfce. A dry run says what the desktop's packages pull in, and not what a person who chose the desktop has since removed or added.

## 6. When GTK 4 is not there

**No library.** A container with no GTK 4 raised `Fiddle::DLError` with the loader's message, `libgtk-4.so.1: cannot open shared object file: No such file or directory`. The probe rescued it, wrote `Basket needs GTK 4, which this computer does not have (…)` and exited 72, the status the launcher uses for a library the computer lacks (`launcher.md`, line 214). This ran in the built app, on Ubuntu 24.04.

**No display.** With GTK 4 and neither `DISPLAY` nor `WAYLAND_DISPLAY`, the app printed `Gtk-WARNING **: Failed to open display` and exited 1. The exit is GTK's: `gtk_application_startup` calls `gtk_init` (`gtk/gtkapplication.c`, line 259), which calls `exit (1)` when the display will not open (`gtk/gtkmain.c`, lines 650 to 657). It runs from inside `g_application_run`, so Ruby gets no chance to handle it (not run to see).

**A missing library GTK loads itself.** On Fedora 43, where the image held `gtk4` and Mesa's drivers and not `mesa-libGLES`, the first run aborted:

```
Couldn't open libGLESv2.so.2: libGLESv2.so.2: cannot open shared object file: No such file or directory
basket_gtk.rb:113: [BUG] Aborted at 0x00000000000000e8
```

libepoxy, which GTK uses for OpenGL, opens `libGLESv2.so.2` and calls `abort ()` when it cannot (`src/dispatch_common.c`, lines 312 to 316, at libepoxy 1.5.10). The same file ran once `mesa-libGLES` was installed. Ubuntu 24.04's and Debian 13's `libgtk-4-1` depend on `libgles2`, and a desktop install has `mesa-libGLES`; Fedora 43's `gtk4` did not pull it into the image, and Fedora 44's image, given the same packages, ran without being given it. A Ruby program cannot catch the abort, and a person on such a computer sees Ruby's crash report. This is GTK's and the distribution's, and the same for a C program, but it is the one way the probe failed on a distribution that has GTK 4.

## 7. A `.deb` and GTK 4

Fledge already has a way for a gem's compiled file to say what it needs from the distribution (`gems.md`, "Libraries from the Linux distribution", and `desktop-apps.md`, "Depends"): `linux: system_libraries` lists sonames, the launcher tries to `dlopen` each before Ruby starts and exits 72 with the name of the one that fails, and a `.deb` depends on the packages `dpkg-shlibdeps` finds for the compiled files that need them. Two rules keep Basket from using it. A listed library that no gem's compiled file needs fails the build, so "the list cannot name what a gem opens with `dlopen`, which no compiled file names" (`gems.md`, "Refused when unused"), and `dpkg-shlibdeps` reads ELF files, of which a pure-Ruby app has none that needs `libgtk-4.so.1`.

`linux: system_typelibs` is the other list, and a `.deb` does depend on `gir1.2-gtk-4.0` for `Gtk-4.0` (`desktop-apps.md`, "Depends on typelibs"). Used for Basket it would be wrong in the way section 1 shows: Basket needs no typelib, `gir1.2-gtk-4.0` is not in Kubuntu's, Lubuntu's, or Xubuntu 24.04's desktop, and the launcher would fail an app on a computer where GTK 4 runs it.

What a `.deb` for Basket could name is the same on every Debian-family target here: the policy output of section 5 gives `libgtk-4-1` as the package on Ubuntu 24.04 and 26.04 and on Debian 12 and 13, and `libadwaita-1-0` for libadwaita, and Fedora's are `gtk4` and `libadwaita`. Whether Fledge writes that dependency, and from what, is a decision (section 10). Until then the `.deb`, the AppImage, and the archive of a Basket on Linux say nothing about GTK 4, and the person who lacks it meets the message of section 6, on a terminal if they started the app from one.

## 8. SIGINT and SIGTERM do not reach Ruby inside the main loop

**Finding.** On Ubuntu 24.04, the probe under `ruby` ignored a SIGTERM sent to it while the window was open: it was still running 3 seconds later, and 2 seconds after a second SIGTERM; only SIGKILL ended it (exit status 137).

**Why.** Ruby's handler for SIGINT and SIGTERM only queues the signal and wakes a timer thread (`signal.c`, lines 697 to 709 and 1585 to 1593, at Ruby 4.1.0-preview1); the Ruby code that handles it runs when the main thread next checks for interrupts. A thread inside `rb_thread_call_without_gvl` checks "pending interrupts" before it releases the lock and "interrupts that happened between 2 to 4" after it takes the lock back (`include/ruby/thread.h`, lines 118 to 130), and the function the caller passes to cancel the call is what interrupts `func` in between. Fiddle passes none (`function.c`, line 385: `rb_thread_call_without_gvl (nogvl_ffi_call, &args, 0, 0)`). So until `g_application_run` returns or a closure runs, the signal waits. SIGINT takes the same path in `signal.c`; only SIGTERM was sent.

**What fixes it.** GLib can take the signal in its main loop: `g_unix_signal_add (signum, handler, data)` attaches a handler for the signal to the default main context (`glib/glib-unix.c`, lines 265 to 285, at GLib 2.80.0). The probe's handler is a closure that calls `g_application_quit` and returns 0, and the handler is attached for signals 2 and 15 before `g_application_run`. With it, a SIGTERM ended the app within 3 seconds, with `Basket exited 0` and status 0, under `ruby` and in the built app. It is a few lines: one function bound, one closure, and a loop over the two signal numbers.

## 9. What Basket's screen and bridge would cost

The probe is 168 lines that are neither comments nor blank. By part, as estimates: the table of bound functions and the helpers around it come to about 70 lines; `Screen`, which builds the widgets and handles Add and remove, to about 75; and a start of 15 that creates the application, connects `activate`, and runs. Without the lines that only serve the experiments (the thread, `need_gvl`, the environment switches) that is about 155 lines for Basket's Linux screen in all, the signal handler included, against 117 lines of screen and 400 of `objc.rb` for iOS, and 90 of `android.rb`, besides the files under `android/`, for Android. The libadwaita screen of section 3 is 29 lines more: its library and six more bound functions, the header bar and the overlay, and the toast with its Undo.

The bridge is shorter than `objc.rb` because GTK's C API is the API: there is no message to type by a runtime's encoding, no class to register, and no protocol to answer. A call is a function, a closure, and a pointer.

An estimate of the lines is not a measurement of the work: the probe has no code for a list longer than the window, for keyboard navigation in the list beyond what GTK gives, or for a menu.

## 10. Decisions the implementation needs

**1. Which libraries Basket's Linux screen asks for.** GTK 4 alone runs wherever `libgtk-4.so.1` does, from Debian 12's 4.8.3, and meets the guidelines' header bar, text field, suggested action, and, where GTK's theme has the `boxed-list` class (4.14.5 and 4.22.5 do, 4.8.3 does not), boxed list; it lacks the undo after a removal that `dialogs.rst` says a destructive action needs. GTK 4 with libadwaita is the guidelines' widgets, for 29 more lines and a second library (`libadwaita-1.so.0`, which 1.2.2 and 1.5.0 served), absent from the Lubuntu and Kubuntu 26.04 desktops and from Debian 13's KDE and Xfce. Basket could also use libadwaita when it is there and GTK 4 alone when it is not, which is two screens. Recommendation: GTK 4 with libadwaita. The issue says Basket follows the guidelines, the guidelines' patterns are libadwaita's, and every GNOME desktop in section 5 has it. The message for a missing library says which one is missing.

**2. Whether Fledge states what an app needs when the app's Ruby opens it.** Section 7 has the evidence. (a) Nothing: Basket reports a missing library as section 6 shows, a `.deb` installs on a computer without GTK 4, and a person who runs the AppImage sees the message only on a terminal. (b) A listed soname that no compiled file needs is allowed, on a key that says the app opens it: the launcher's check works unchanged, and a `.deb` needs the package that provides the soname, which `dpkg-shlibdeps` finds only for an ELF file that needs it. (c) A list of package names for the `.deb`, which is Debian-family already: the policy output gives the same packages on all four targets (`libgtk-4-1`, `libadwaita-1-0`), and Tauri's `deb > depends` and Briefcase's `system_runtime_requires` are prior art (`gems.md`, "Libraries from the Linux distribution", weighs both). (b) and (c) add a key to `fledge.yml`, which is public interface. Recommendation: (a) for Basket, since `deb` is never a default installer (`desktop-apps.md`), and an issue for the key if the maintainer asks for one.

**3. Signals.** Basket attaches `g_unix_signal_add` for SIGINT and SIGTERM, 5 lines, or a Ctrl-C and a `kill` do nothing while its window is open (section 8). The runtime has nothing to fix: the same Fiddle calls under `ruby main.rb` behave the same, so parity holds. Recommendation: Basket's code, with a comment that says why.

**4. What a Delivery job for Basket on Linux runs.** A container of the distribution with GTK 4 and libadwaita, Xvfb, `xdotool`, Mesa's software drivers (`mesa-libGLES` on Fedora), and a font (`fonts-dejavu-core`, `dejavu-sans-fonts`), as the runs here had; Openbox ran in every run, and none was tried without a window manager. Real input through `xdotool` drove every run and exercised the entry's Return, the button, and the removal through GTK's event path, where a self-test hook in Basket would not; the cost is one more package and the window's pixel positions. Recommendation: real input.

**5. The launcher's glibc floor.** Not a decision: issue #142, which Delivery on Debian 12 would hit first.

## 11. What stays unproven

- **A Wayland session.** Every run used the X11 backend under Xvfb. GDK chooses the backend itself and the program's calls are the same, but no run drew a window under a Wayland compositor, which is what GNOME runs.
- **A real desktop.** No run had GNOME Shell, a settings daemon, a session bus (the probe printed GTK's warning `Unable to acquire session bus` in every container), the accessibility bus (`NO_AT_BRIDGE=1` was set), a dark color scheme, or a display scale above 1. No run drove the window with a keyboard layout other than the container's or an input method.
- **Rendering on a GPU.** Mesa's software renderer drew every frame. On Ubuntu 26.04 (GTK 4.22.4) a short row of dots showed under the third row in the three-row screenshot, where the empty-list placeholder would be, and it is not explained.
- **Other processors and libcs.** Every run was x86_64 on glibc. An aarch64 Linux was not tried, nor Alpine (musl).
- **The other installers.** The built app that ran was the folder of `fledge build`'s archive; its AppImage and `.deb` were not started. A `.deb` installs only where glibc is 2.39 or newer (`desktop-apps.md`, "The .deb"), which leaves Debian 12 to the AppImage and the archive.
- **Leaks and dangling pointers** (section 2), and **the cost of a closure per signal connection** for a list of thousands of rows.
- **Releases older than the six in the table.**
