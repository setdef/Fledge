<!--
SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>

SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Draft: a Ruby feature proposal, for the maintainer to file

Not filed. For the maintainer to file, if he chooses, at https://bugs.ruby-lang.org/projects/ruby-master/issues/new as a **Feature**, with the subject below, and everything after the line as the description (the tracker takes Markdown).

Ruby's contributing guide (`doc/contributing/reporting_issues.md` at ruby/ruby master 88ea6fd282) asks a feature proposal to check for earlier discussion, to give a solid use case, and to consider compatibility, and offers a template (Abstract, Background, Proposal, Use cases, Discussion, See also), which the description follows; it says nothing about AI-assisted reports either way. Before filing: search the tracker for "C locale", "POSIX locale", "UTF-8 mode", and "default_external", since someone may have proposed it after 2026-11-14 (on that day no issue subject did; the related tickets are under See also); file the bug report beside this one ([ruby-c-locale-paths.md](ruby-c-locale-paths.md)) first and put its number where the description says "the bug report", and do the same for the Bundler and Thor pull requests once they are open ([bundler-c-locale-paths.md](bundler-c-locale-paths.md), [thor-c-locale-paths.md](thor-c-locale-paths.md)); and read the description start to finish as your own words, since you are the one filing it.

This is the research's option D (`doc/contributors/research/2026-11-13-c-locale.md`), the only change that would make stock `ruby main.rb` give, with no locale, what an app Fledge builds gives. If Ruby takes it, Fledge's coercion (`doc/contributors/design/launcher.md`, "The locale") becomes Ruby's own behavior.

- **Tracker:** Feature
- **Subject:** Treat the C and POSIX locales as UTF-8

---

# Abstract

When the `LC_CTYPE` locale is `C` or `POSIX`, the locale a process has when nothing set one, use UTF-8 as the locale encoding, and so as `Encoding.default_external` and the filesystem encoding, as Python does in that locale since 3.7 (PEP 540) and as Ruby 3.0 did for `Encoding.default_external` on Windows (#16604).

# Background

In the C locale, `nl_langinfo(CODESET)` is `ANSI_X3.4-1968` on glibc and `US-ASCII` on macOS (`localeinit.c`, line 56), so `Encoding.find("locale")`, `Encoding.default_external`, and `Encoding.find("filesystem")`, which follows `default_external` on Unix (`localeinit.c`, line 134), are all US-ASCII. A path whose name is not ASCII then reaches Ruby code as a string that is BINARY, or US-ASCII and invalid, depending on where Ruby made it (the bug report). In a folder named `café`, on ruby 4.1.0preview1 (2026-10-11 master 2d08b5f42f) +PRISM [arm64-darwin27], `ruby -I "$PWD/lib" "$PWD/t.rb"`, with `t.rb` as in the bug report:

```
$ LC_ALL=C ruby -I "$PWD/lib" "$PWD/t.rb"
Dir.pwd                  ASCII-8BIT
ENV["PWD"]               ASCII-8BIT
__dir__                  US-ASCII (invalid)
$0                       US-ASCII (invalid)
$LOAD_PATH[0] (-I)       US-ASCII (invalid)
File.expand_path("x")    UTF-8
__dir__ =~ /lib/                 ArgumentError: invalid byte sequence in US-ASCII
__dir__.split("/")               ArgumentError: invalid byte sequence in US-ASCII
$LOAD_PATH[0].sub(/lib$/, "man") ArgumentError: invalid byte sequence in US-ASCII
File.expand_path("café")         Encoding::CompatibilityError: incompatible character encodings: UTF-8 and US-ASCII
```

With `LANG=en_US.UTF-8` every line is UTF-8 and every call succeeds. Linux (Ubuntu 26.04, glibc 2.43, Ruby 4.1.0-preview1 for x86_64-linux) printed the same lines, run with `ENV["HOME"]` in place of `ENV["PWD"]`.

Fixing where those strings are made, as the bug report proposes, turns the invalid US-ASCII strings into BINARY ones, and the first three calls then work. But a path outside ASCII stays BINARY, and joining it with a UTF-8 string, such as a literal in the program, still raises; `File.expand_path("café")` does so in Ruby itself, and Bundler and Thor do in seven and three places (the Bundler and Thor pull requests). Every one of those is code that works in the terminal where its author ran it.

# Proposal

In `rb_locale_charmap_index` (`localeinit.c`), when `setlocale(LC_CTYPE, NULL)` names `C` or `POSIX`, answer UTF-8. Everything that follows the locale encoding follows: `Encoding.find("locale")`, `Encoding.default_external` unless `-E` or `-U` sets it, the filesystem encoding, and `ENV`'s strings. `Encoding.locale_charmap` keeps reporting what `nl_langinfo(CODESET)` says. `ruby -E US-ASCII` (or `RUBYOPT=-EUS-ASCII`) keeps today's `default_external`. Windows, where Ruby takes the code page and not the locale, is unchanged.

A patch against 4.1.0-preview1, which applies unchanged to master 88ea6fd282:

<!--
SPDX-SnippetBegin
SPDX-SnippetCopyrightText: 2013 Yukihiro Matsumoto
SPDX-License-Identifier: Ruby OR BSD-2-Clause
SPDX-SnippetComment: A patch to localeinit.c of ruby/ruby at v4_1_0_preview1 (2d08b5f42f)
-->

```diff
diff -u a/localeinit.c b/localeinit.c
--- a/localeinit.c
+++ b/localeinit.c
@@ -104,12 +104,30 @@
 }
 #endif
 
+#if !NO_LOCALE_CHARMAP && !defined _WIN32 && !defined __CYGWIN__ && defined HAVE_LOCALE_H
+#include <locale.h>
+#include <string.h>
+
+/* The C and POSIX locales are the ones a process has when its environment
+ * names none.  Their character set is ASCII, but the text and file names a
+ * process meets there are as likely as anywhere to be UTF-8. */
+static int
+c_locale_p(void)
+{
+    const char *name = setlocale(LC_CTYPE, NULL);
+    return name && (strcmp(name, "C") == 0 || strcmp(name, "POSIX") == 0);
+}
+#endif
+
 int
 rb_locale_charmap_index(void)
 {
 #if NO_LOCALE_CHARMAP
     return ENCINDEX_US_ASCII;
 #else
+# if !defined _WIN32 && !defined __CYGWIN__ && defined HAVE_LOCALE_H
+    if (c_locale_p()) return ENCINDEX_UTF_8;
+# endif
     return (int)locale_charmap(enc_find_index);
 #endif
 }
```

<!--
SPDX-SnippetEnd
-->

Built from the 4.1.0-preview1 release tarball with this patch and installed with `--prefix` under a folder named `josé`, on Ubuntu 26.04 (glibc 2.43), with no locale variable at all:

```
$ ruby -e 'p [Encoding.default_external, Encoding.find("locale"), Encoding.find("filesystem"), Encoding.locale_charmap, ENV["HOME"].encoding]'
[#<Encoding:UTF-8>, #<Encoding:UTF-8>, #<Encoding:UTF-8>, "ANSI_X3.4-1968", #<Encoding:UTF-8>]
$ ruby -EUS-ASCII -e 'p [Encoding.default_external, Encoding.find("locale"), Encoding.find("filesystem")]'
[#<Encoding:US-ASCII>, #<Encoding:UTF-8>, #<Encoding:US-ASCII>]
```

`LC_ALL=C` printed three UTF-8s, as no locale did. `t.rb` printed UTF-8 on every line and `ok` for every call, `File.expand_path("café")` included; every loaded feature was valid UTF-8; `require "bundler/setup"` and `ruby -rbundler/setup` set up a bundle with no change to Bundler, and a Thor CLI ran with no change to Thor. `bundle exec` still failed, inside Bundler's error report, as it does with stock Ruby in such a folder under `LANG=C.UTF-8` (the Bundler pull request fixes that case). The same build without the patch printed US-ASCII for all three encodings. Ruby's own test suite was not run with the patch.

# Use cases

The C locale is the one a program meets wherever nothing set a locale:

- every macOS app LaunchServices starts, and every launchd job: `launchctl getenv LANG` prints nothing (macOS 27.2.1), while Terminal sets `LANG` for its own shells;
- cron jobs, and systemd services, which get `$LANG` only from `locale.conf` or the kernel command line (systemd.exec(5)), on a system that sets neither;
- minimal container images (PEP 538's motivation names Fedora's and Debian's) and `env -i`;
- an SSH session that forwards a locale the server lacks;
- Android, where passing `""` to `setlocale` is the same as passing `"C"` (PEP 538, "Changes to locale settings on Android").

There a program written and tested in a UTF-8 terminal fails on the first path outside ASCII, such as a user's home folder named `José`, with an error that names an encoding.

# Discussion

- Users cannot fix it from inside the program: by the time Ruby code runs, the load path, `__dir__`, and `$0` are made. `-E UTF-8` changes `default_external` and the filesystem encoding, but not `Encoding.find("locale")`, nor the features and paths `process_options` re-tags with it (`ruby.c`, lines 2546 to 2589), so `require "bundler/setup"` still fails in the same place under `ruby -E UTF-8` (measured on macOS).
- Compatibility: a program run in the C locale would read files and `ENV` as UTF-8 instead of US-ASCII. Bytes that are not UTF-8 would make an invalid UTF-8 string where they make an invalid US-ASCII one today, as they already do under a UTF-8 locale. A test that runs under `LANG=C` to get ASCII-only behavior would pass `-E US-ASCII` instead. An embedder that never calls `setlocale` is in the C locale too, and would get UTF-8.
- #18495 found `LC_ALL=C.UTF-8` giving US-ASCII on a system that lacked that locale, and was closed as "it's up to the system to properly define locales". This proposal is about the processes for which the system defined no locale at all, which on macOS is every app.
- #15044 was told that `ENV`'s encoding follows the locale on purpose. It still would; the locale's encoding would be UTF-8.

# See also

- PEP 538, "Coercing the legacy C locale to a UTF-8 based locale" (Python 3.7).
- PEP 540, "Add a new UTF-8 Mode" (Python 3.7): "This mode is off by default, but is automatically activated when using the 'POSIX' locale." Its rationale: "Many users inherit the ASCII encoding from the POSIX locale, aka the 'C' locale, but are unable change the locale for various reasons."
- PEP 686, "Make UTF-8 mode default" (Python 3.15).
- #16604, "Set default for Encoding.default_external to UTF-8 on Windows" (Ruby 3.0): "UTF-8 as the default external encoding is the expected encoding for most of the people on Windows, now."
- #18191, "All loaded feature filenames should be in the file system encoding" (fixed in 60d0421ca8), #18495, #15044, #22194.

---

This report was produced entirely by Claude (Anthropic) via Claude Code. [https://declare-ai.org/1.0.0/total.html](https://declare-ai.org/1.0.0/total.html)
