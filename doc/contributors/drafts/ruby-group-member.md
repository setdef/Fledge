<!--
SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>

SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Draft: a Ruby bug report, for the maintainer to file

Not filed. For the maintainer to file, if he chooses, at https://bugs.ruby-lang.org/projects/ruby-master/issues/new as a **Bug**, with the subject and the Ruby version below, and everything after the line as the description (the tracker takes Markdown).

Ruby's contributing guide (`doc/contributing/reporting_issues.md` at ruby/ruby master) asks a reporter to search for an existing ticket first, to show the bug on master, to give `ruby -v`, and to keep any reproduction small; it says nothing about AI-assisted reports either way. Before filing: search the tracker for "rb_group_member" and "getgroups", since someone may have reported it after 2026-11-12; and read the description start to finish as your own words, since you are the one filing it. Found by ruby/spec in Fledge's iOS app, where Fledge mends it with a scripted edit (`RuntimeBuilder::RubySource.file_c`).

- **Tracker:** Bug
- **Subject:** File::Stat#readable? raises "malloc: possible integer overflow" when getgroups(2) fails
- **Ruby version:** ruby 4.1.0preview1 (2026-10-11 master 2d08b5f42f); still present at master ee74a10ca9
- **Backport:** the same lines are in 3.4 and 4.0.

---

`rb_group_member` in `file.c` passes the result of `getgroups(0, NULL)` to `ALLOCV_N` without checking for -1. Where `getgroups` fails, `File::Stat#readable?`, `#writable?`, `#executable?`, and `#grpowned?`, and `File.readable?` and friends where Ruby has no `eaccess`, raise for any file whose group is not the process's own:

```
ArgumentError: malloc: possible integer overflow (18446744073709551615*4)
```

## Cause

`file.c`, lines 1956 to 1958 at master (1849 to 1851 at 4.1.0-preview1):

```c
    groups = getgroups(0, NULL);
    gary = ALLOCV_N(GETGROUPS_T, v, groups);
    anum = getgroups(groups, gary);
```

`process.c`'s `proc_getgroups` checks the same call and raises the error (`Process.groups`), but `rb_group_member` takes -1 for a count.

Where it happens: in an iOS app. Ruby is built on Darwin with `_DARWIN_C_SOURCE` (`configure.ac`, line 1154), so `getgroups` is Libc's `getgroups$DARWIN_EXTSN`, not the kernel's, and that one looks the process's user up with `getpwuid(getuid())` and returns -1 with `EINVAL` when it finds none ([Libc-1752.120.2, `sys/getgroups.c`, lines 35 to 58](https://github.com/apple-oss-distributions/Libc/blob/Libc-1752.120.2/sys/getgroups.c#L35-L58)). Inside an iOS app, in the Simulator at least, `getpwuid` finds no user for the app's own ID (`Etc.getpwuid(Process.uid)` raises "can't find user for 501"), so `Process.groups` raises `Errno::EINVAL` and `File::Stat.new("/etc/passwd").readable?` raises the `ArgumentError` above. A macOS process whose user the directory service cannot find would do the same.

## Reproduction

Without an iOS app, a stand-in for `getgroups` that fails shows it. Save as `member.c`:

```c
#include <ruby.h>
#include <errno.h>
#include <unistd.h>
#define GETGROUPS_T gid_t
static int fails(int size, GETGROUPS_T *list) { (void)size; (void)list; errno = EINVAL; return -1; }
#define getgroups fails
static int
member(GETGROUPS_T gid)
{
    int rv = FALSE;
    int groups;
    VALUE v = 0;
    GETGROUPS_T *gary;
    int anum = -1;

    groups = getgroups(0, NULL);
    gary = ALLOCV_N(GETGROUPS_T, v, groups);
    anum = getgroups(groups, gary);
    while (--anum >= 0) if (gary[anum] == gid) rv = TRUE;
    if (v) ALLOCV_END(v);
    return rv;
}
static VALUE member_p(VALUE self, VALUE gid) { (void)self; return member((GETGROUPS_T)NUM2INT(gid)) ? Qtrue : Qfalse; }
void Init_member(void) { rb_define_global_function("member?", member_p, 1); }
```

```
$ ruby -rmkmf -e 'create_makefile("member")' && make
$ ruby -I. -rmember -e 'p member?(12345)'
-e:1:in 'Object#member?': malloc: possible integer overflow (18446744073709551615*4) (ArgumentError)
```

## Suggested fix

Answer that the process is in no other group, as `rb_group_member` answers where there is no `getgroups`, so the caller goes on to the permission bits for others:

```diff
     groups = getgroups(0, NULL);
+    if (groups == -1) return FALSE;
     gary = ALLOCV_N(GETGROUPS_T, v, groups);
```

With it, the stand-in above prints `false`, and in an iOS app `File::Stat#readable?`, `#writable?`, and `#executable?` give what `File.readable?` and the others give.

---

This report was produced entirely by Claude (Anthropic) via Claude Code. [https://declare-ai.org/1.0.0/total.html](https://declare-ai.org/1.0.0/total.html)
