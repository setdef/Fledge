<!--
SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>

SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Draft: a Ruby bug report, for the maintainer to file

Not filed. For the maintainer to file, if he chooses, at https://bugs.ruby-lang.org/projects/ruby-master/issues/new as a **Bug**, with the subject and the Ruby version below, and everything after the line as the description (the tracker takes Markdown).

Ruby's contributing guide (`doc/contributing/reporting_issues.md` at ruby/ruby master) asks a reporter to search for an existing ticket first, to show the bug on master, to give `ruby -v`, and to keep any reproduction small; it says nothing about AI-assisted reports either way. A search of the tracker for "umask" and for "android" on 2026-11-12 found no report of this. Before filing: search again, since someone may have reported it since; and read the description start to finish as your own words, since you are the one filing it. Found by ruby/spec in Fledge's Android app, where Fledge mends it with scripted edits (`RuntimeBuilder::RubySource.process_c_umask` and `.file_c_umask`).

- **Tracker:** Bug
- **Subject:** `umask: -1` and `File.umask(-1)` abort the process on Android (bionic's fortified umask)
- **Ruby version:** ruby 4.1.0preview1 (2026-10-11 master 2d08b5f42f); still present at master acc624e47b
- **Backport:** the same lines are in 3.4 and 4.0.

---

On Android, `Process.exec(..., umask: -1)`, and the same option of `spawn` and `system`, end the process with SIGABRT, from bionic's fortify check (`umask: called with invalid mask ...`). `File.umask(-1)` passes the same mask to the same call. ruby/spec expects `umask: -1` to work: `core/process/exec_spec.rb`, "masks all permission bits when given umask: -1", which passes on Linux and macOS. On an Android emulator (API 36, x86_64), Ruby 4.1.0-preview1 built with the NDK fails it:

```
Expected exit status is 0 but actual is :SIGABRT for command ruby_exe(...)
```

## Cause

Ruby passes the mask it is given to `umask` unchanged: `rb_execarg_run_options` in `process.c` (line 3446 at master, 3441 at 4.1.0-preview1):

```c
        mode_t oldmask = umask(mask); /* never fail */ /* async-signal-safe */
```

and `rb_file_s_umask` in `file.c` (line 4598 at master, 4486 at 4.1.0-preview1):

```c
        omask = umask(NUM2MODET(argv[0]));
```

On Linux the kernel keeps only the permission bits (`kernel/sys.c`, `SYSCALL_DEFINE1(umask)`, lines 1906 to 1910 at v6.12, `mask & S_IRWXUGO`), and glibc's `umask` is the system call, so -1 sets 0777. macOS does the same. Ruby's `configure.ac` compiles with `-D_FORTIFY_SOURCE=2` where the compiler takes it (`hardenflags`, lines 882 to 899 at master), and with it bionic's `<sys/stat.h>` turns a `umask` whose argument is not a constant into `__umask_chk` (`libc/include/bits/fortify/stat.h`, lines 36 to 47 at bionic 731631f), which aborts on any bit beyond 0777 (`libc/bionic/fortify.cpp`, lines 400 to 406):

```c
mode_t __umask_chk(mode_t mode) {
  if (__predict_false((mode & 0777) != mode)) {
    __fortify_fatal("umask: called with invalid mask %o", mode);
  }

  return umask(mode);
}
```

## Reproduction

Ruby built for Android with the NDK (API 26 or later) as `configure` builds it, run on a device or an emulator:

```
ruby -e 'Process.exec("true", umask: -1)'
ruby -e 'File.umask(-1)'
```

The first ends with SIGABRT, as ruby/spec's example did, where Linux sets the mask to 0777; the second reaches the same fortified `umask` with the same mask.

## Suggested fix

Keep the permission bits before the call, as the kernel would, so the result is the same everywhere:

```diff
--- a/process.c
+++ b/process.c
@@ rb_execarg_run_options
-        mode_t oldmask = umask(mask); /* never fail */ /* async-signal-safe */
+        mode_t oldmask = umask(mask & 0777); /* never fail */ /* async-signal-safe */
--- a/file.c
+++ b/file.c
@@ rb_file_s_umask
-        omask = umask(NUM2MODET(argv[0]));
+        omask = umask(NUM2MODET(argv[0]) & 0777);
```

Masking where the option is parsed (`rb_execarg_addopt`, `eargp->umask_mask = cmask`) would do as well for `exec`. Fledge's Android runtime carries the edit above, and ruby/spec's example passes there.

---

This report was produced entirely by Claude (Anthropic) via Claude Code. [https://declare-ai.org/1.0.0/total.html](https://declare-ai.org/1.0.0/total.html)
