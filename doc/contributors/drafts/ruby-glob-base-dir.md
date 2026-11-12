<!--
SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>

SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Draft: a Ruby bug report, for the maintainer to file

Not filed. For the maintainer to file, if he chooses, at https://bugs.ruby-lang.org/projects/ruby-master/issues/new as a **Bug**, with the subject and the Ruby version below, and everything after the line as the description (the tracker takes Markdown).

Ruby's contributing guide (`doc/contributing/reporting_issues.md` at ruby/ruby master) asks a reporter to search for an existing ticket first, to show the bug on master, to give `ruby -v`, and to keep any reproduction small; it says nothing about AI-assisted reports either way. Before filing: search the tracker for "glob base Dir relative", since someone may have reported it after 2026-11-12; and read the description start to finish as your own words, since you are the one filing it. Found by ruby/spec in Fledge's Android app, where Fledge sidesteps it by defining the `IFTODT` bionic lacks (`RuntimeBuilder::RubySource.dir_c`), which makes Android's Ruby take Linux's path through `glob_helper`; the bug itself is on Linux too, as below.

- **Tracker:** Bug
- **Subject:** Dir.glob with base: a Dir opened by a relative path misses entries it stats
- **Ruby version:** ruby 4.1.0preview1 (2026-10-11 master 2d08b5f42f) [x86_64-linux]; the lines are the same at master ee74a10ca9
- **Backport:** none checked.

---

`Dir.glob(pattern, base: dir)`, where `dir` is a `Dir` opened by a relative path, finds nothing for a pattern whose match `glob_helper` has to stat:

```
$ mkdir -p a/b/c
$ ruby -e 'p Dir.glob("b", base: "a"); Dir.open("a") { |d| p Dir.glob("b", base: d) }; Dir.open(File.expand_path("a")) { |d| p Dir.glob("b", base: d) }'
["b"]
[]
["b"]
```

## Cause

With a `Dir` for `base:`, `push_glob` passes `glob_helper` the `Dir`'s descriptor and its path (`dir.c`, lines 3525 to 3535 at 4.1.0-preview1), and `ruby_glob0` starts every path `glob_helper` builds with that base path (lines 3335 to 3343). Where `glob_helper` stats a path relative to the descriptor it must first take the base off with `at_subpath`, as it does for a symbolic link's target (lines 3030 and 3135, `do_stat(fd, at_subpath(fd, baselen, ...))`) and `do_opendir` does. Three calls do not (lines 2996, 3004, and 3127 at 4.1.0-preview1; 2989, 2997, and 3120 at master):

```c
            if (do_lstat(fd, path, &st, flags, enc) == 0) {
...
            if (do_stat(fd, path, &st, flags, enc) == 0) {
...
                if (do_lstat(fd, buf, &st, flags, enc) == 0)
```

So `fstatat(fd, "a/b", ...)` looks for `a/a/b`. An absolute base hides it, since `fstatat` ignores the descriptor for an absolute path, and so does a string base, for which the descriptor is `AT_FDCWD`.

The first two are the literal match above. The third stats each directory entry whose type `readdir` did not give, which is every entry where the C library defines no `IFTODT` (lines 229 to 233, `EMULATE_IFTODT`): Android's bionic defines `DT_UNKNOWN` but not `IFTODT` ([`libc/include/dirent.h` at 731631f](https://android.googlesource.com/platform/bionic/+/731631f300090436d7f5df80d50b6275c8c60a93/libc/include/dirent.h)), so there ruby/spec's "follows directory symlinks relative to a Dir opened with a relative path" (`core/dir/shared/glob.rb`, line 558) finds nothing. On glibc it shows on a file system whose `readdir` returns `DT_UNKNOWN`.

## Suggested fix

Take the base off in the three calls too:

```diff
-            if (do_lstat(fd, path, &st, flags, enc) == 0) {
+            if (do_lstat(fd, at_subpath(fd, baselen, path), &st, flags, enc) == 0) {
...
-            if (do_stat(fd, path, &st, flags, enc) == 0) {
+            if (do_stat(fd, at_subpath(fd, baselen, path), &st, flags, enc) == 0) {
...
-                if (do_lstat(fd, buf, &st, flags, enc) == 0)
+                if (do_lstat(fd, at_subpath(fd, baselen, buf), &st, flags, enc) == 0)
```

`sys_warning` in `do_stat` and `do_lstat` would then name the path without its base; passing the full path for the warning separately keeps it as it is.

---

This report was produced entirely by Claude (Anthropic) via Claude Code. [https://declare-ai.org/1.0.0/total.html](https://declare-ai.org/1.0.0/total.html)
