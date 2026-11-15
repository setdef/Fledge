<!--
SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>

SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Draft: a Ruby bug report, for the maintainer to file

Not filed. For the maintainer to file, if he chooses, at https://bugs.ruby-lang.org/projects/ruby-master/issues/new as a **Bug**, with the subject and the Ruby version below, and everything after the line as the description (the tracker takes Markdown).

Ruby's contributing guide (`doc/contributing/reporting_issues.md` at ruby/ruby master 88ea6fd282) asks a reporter to search for an existing ticket first, to show the bug on master, to give `ruby -v`, and to keep any reproduction small; it says nothing about AI-assisted reports either way. The reproduction below ran on 4.1.0-preview1, not on a build of master; the lines it names are the same at master 88ea6fd282 (2026-11-14), but shifted, as given. Before filing: search the tracker for "US-ASCII", "invalid byte sequence", "LOADED_FEATURES", and "filesystem encoding", since someone may have reported it after 2026-11-14 (on that day no issue subject matched this case; the related tickets are at the end); file it before or with the feature proposal beside it ([ruby-c-locale-utf8.md](ruby-c-locale-utf8.md)), which names it; and read the description start to finish as your own words, since you are the one filing it.

Found when Fledge, which runs Ruby with no locale, measured what stock Ruby does there (`doc/contributors/research/2026-11-13-c-locale.md`). Fledge sidesteps it by giving Ruby a UTF-8 locale (`doc/contributors/design/launcher.md`, "The locale"), and keeps doing so if this is fixed: the fix makes these strings BINARY, not UTF-8.

- **Tracker:** Bug
- **Subject:** Under the C locale, `__dir__`, `$0`, `-I` entries, and boot features are US-ASCII strings with invalid bytes
- **Ruby version:** ruby 4.1.0preview1 (2026-10-11 master 2d08b5f42f) +PRISM [arm64-darwin27]; also on x86_64-linux; the lines are the same at master 88ea6fd282
- **Backport:** not checked.

---

Under the C locale, whose character set is ASCII, Ruby gives a path whose name is not ASCII as a BINARY string where it reads it from the system (`Dir.pwd`, `ENV`, the default `$LOAD_PATH`), following `rb_external_str_new_with_enc` (`string.c`, lines 1395 to 1398; 1409 to 1412), but as a US-ASCII string whose bytes are not valid US-ASCII in four other places. Matching, splitting, or substituting in those strings raises. Save as `t.rb` in a folder named `café`:

```ruby
def show(label, s)
  puts "#{label.ljust(24)} #{s.encoding}#{" (invalid)" unless s.valid_encoding?}"
end

show "Dir.pwd", Dir.pwd
show "ENV[\"PWD\"]", ENV["PWD"]
show "__dir__", __dir__
show "$0", $0
show "$LOAD_PATH[0] (-I)", $LOAD_PATH[0]
show "File.expand_path(\"x\")", File.expand_path("x")

{
  '__dir__ =~ /lib/' => -> { __dir__ =~ /lib/ },
  '__dir__.split("/")' => -> { __dir__.split("/") },
  '$LOAD_PATH[0].sub(/lib$/, "man")' => -> { $LOAD_PATH[0].sub(/lib$/, "man") },
  'File.expand_path("café")' => -> { File.expand_path("café") },
}.each do |code, call|
  call.call
  puts "#{code.ljust(32)} ok"
rescue => e
  puts "#{code.ljust(32)} #{e.class}: #{e.message}"
end
```

```
$ cd café && mkdir -p lib
$ ruby -v
ruby 4.1.0preview1 (2026-10-11 master 2d08b5f42f) +PRISM [arm64-darwin27]
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

That Ruby was built from the 4.1.0-preview1 tarball by mise, at an ASCII path, on macOS 27.2.1. Ruby 4.1.0-preview1 for x86_64-linux on Ubuntu 26.04 (glibc 2.43), run with `ENV["HOME"]` in place of `ENV["PWD"]` and a home folder in the same folder, printed the same lines.

With a UTF-8 locale every line is UTF-8 and every call is `ok`. With Ruby installed under a folder named outside ASCII, the features Ruby loads before encodings exist (`enc/encdb.so`, `enc/trans/transdb.so`) are US-ASCII with invalid bytes too, while the default `$LOAD_PATH` entries they came from are BINARY, so `$LOADED_FEATURES.any? { |f| f.start_with?($LOAD_PATH.last) }` raises "incompatible character encodings: US-ASCII and BINARY (ASCII-8BIT)". Bundler's `clean_load_path` makes that comparison, and fails there on macOS.

## Cause

Each of the four tags a path with the locale or filesystem encoding without checking that its bytes are valid there (line numbers at 4.1.0-preview1, then at master 88ea6fd282):

1. `copy_str` (`ruby.c`, lines 2051 to 2059; 2052 to 2060) checks validity only when `intern` is false. `process_options` calls it with `intern` true for every `$LOAD_PATH` entry not marked as a default one, which are the `-I` and `RUBYLIB` entries (`copy_str(path, lenc, !mark)`, line 2561; 2565), and for every feature loaded before `Init_enc` (line 2579; 2583), the re-tagging #18191 added.
2. `rb_progname` gets the locale encoding unchecked (line 2511; 2515), and so does the script name (line 2538; 2542), from which `$0` and `__FILE__` come.
3. `__dir__` comes from the script's real path. `rb_check_realpath_internal` already makes that BINARY when it is not valid in the filesystem encoding (`file.c`, lines 5717 to 5722; 5830 to 5835), but `process_options` then copies the script name's encoding onto any BINARY result (`ruby.c`, lines 2695 to 2697; 2699 to 2701):

   ```c
               if (!ENCODING_GET(path)) { /* ASCII-8BIT */
                   rb_enc_copy(path, opt->script_name);
               }
   ```

   so `__dir__` is invalid US-ASCII even for a script named by a relative path (`ruby t.rb`), whose `$0` is then ASCII and valid.
4. `File.expand_path` tags the current directory with the filesystem encoding unchecked when it is not ASCII (`file.c`, `append_fspath`, lines 4946 to 4949; 5058 to 5061), so a relative name outside ASCII raises "UTF-8 and US-ASCII".

## Suggested fix

Do what `rb_external_str_new_with_enc` does: leave a path that is not valid in the encoding BINARY, in `ruby.c` for the first three.

The patch also gives `copy_path_class` (`file.c`, lines 7996 to 8006; 8111 to 8121) the same check. Without it, fixing the first three only moves the problem: `require_relative` from a script whose path is now BINARY goes through `copy_path_class`, which replaces BINARY and US-ASCII with the filesystem encoding unchecked, and the required file's `__FILE__` became US-ASCII and invalid where it had been UTF-8. The patch is against 4.1.0-preview1, and applies unchanged to master 88ea6fd282:

<!--
SPDX-SnippetBegin
SPDX-SnippetCopyrightText: 1993-2007 Yukihiro Matsumoto; 2000 Network Applied Communication Laboratory, Inc.; 2000 Information-technology Promotion Agency, Japan
SPDX-License-Identifier: Ruby OR BSD-2-Clause
SPDX-SnippetComment: A patch to file.c and ruby.c of ruby/ruby at v4_1_0_preview1 (2d08b5f42f)
-->

```diff
diff -u a/file.c b/file.c
--- a/file.c
+++ b/file.c
@@ -7996,9 +7996,12 @@
 copy_path_class(VALUE path, VALUE orig)
 {
     int encidx = rb_enc_get_index(orig);
-    if (encidx == ENCINDEX_ASCII_8BIT || encidx == ENCINDEX_US_ASCII)
+    int fallback = encidx == ENCINDEX_ASCII_8BIT || encidx == ENCINDEX_US_ASCII;
+    if (fallback)
         encidx = rb_filesystem_encindex();
     rb_enc_associate_index(path, encidx);
+    if (fallback && rb_enc_str_coderange(path) == ENC_CODERANGE_BROKEN)
+        rb_enc_associate_index(path, ENCINDEX_ASCII_8BIT);
     str_shrink(path);
     RBASIC_SET_CLASS(path, rb_obj_class(orig));
     OBJ_FREEZE(path);
diff -u a/ruby.c b/ruby.c
--- a/ruby.c
+++ b/ruby.c
@@ -2050,9 +2050,9 @@
 static VALUE
 copy_str(VALUE str, rb_encoding *enc, bool intern)
 {
+    if (rb_enc_str_coderange_scan(str, enc) == ENC_CODERANGE_BROKEN)
+        return 0;
     if (!intern) {
-        if (rb_enc_str_coderange_scan(str, enc) == ENC_CODERANGE_BROKEN)
-            return 0;
         return rb_enc_associate(rb_str_dup(str), enc);
     }
     return rb_enc_interned_str(RSTRING_PTR(str), RSTRING_LEN(str), enc);
@@ -2508,7 +2508,8 @@
 
     Init_enc();
     lenc = rb_locale_encoding();
-    rb_enc_associate(rb_progname, lenc);
+    if (rb_enc_str_coderange_scan(rb_progname, lenc) != ENC_CODERANGE_BROKEN)
+        rb_enc_associate(rb_progname, lenc);
     rb_obj_freeze(rb_progname);
     if (opt->ext.enc.name != 0) {
         opt->ext.enc.index = opt_enc_index(opt->ext.enc.name);
@@ -2535,7 +2536,8 @@
         ienc = enc;
 #endif
     }
-    rb_enc_associate(opt->script_name, IF_UTF8_PATH(uenc, lenc));
+    if (rb_enc_str_coderange_scan(opt->script_name, IF_UTF8_PATH(uenc, lenc)) != ENC_CODERANGE_BROKEN)
+        rb_enc_associate(opt->script_name, IF_UTF8_PATH(uenc, lenc));
 #if UTF8_PATH
     if (uenc != lenc) {
         opt->script_name = str_conv_enc(opt->script_name, uenc, lenc);
@@ -2692,7 +2694,8 @@
                 path = str_conv_enc(path, uenc, lenc);
             }
 #endif
-            if (!ENCODING_GET(path)) { /* ASCII-8BIT */
+            if (!ENCODING_GET(path) && /* ASCII-8BIT */
+                rb_enc_str_coderange_scan(path, rb_enc_get(opt->script_name)) != ENC_CODERANGE_BROKEN) {
                 rb_enc_copy(path, opt->script_name);
             }
         }
```

<!--
SPDX-SnippetEnd
-->

Built from the 4.1.0-preview1 release tarball with this patch and installed with `--prefix` under a folder named `josé`, on Ubuntu 26.04 (glibc 2.43), with `LC_ALL=C`, `t.rb` printed (it ran with `ENV["HOME"]`, in the same folder, in place of `ENV["PWD"]`):

```
Dir.pwd                  ASCII-8BIT
ENV["HOME"]              ASCII-8BIT
__dir__                  ASCII-8BIT
$0                       ASCII-8BIT
$LOAD_PATH[0] (-I)       ASCII-8BIT
File.expand_path("x")    UTF-8
__dir__ =~ /lib/                 ok
__dir__.split("/")               ok
$LOAD_PATH[0].sub(/lib$/, "man") ok
File.expand_path("café")         Encoding::CompatibilityError: incompatible character encodings: UTF-8 and US-ASCII
```

and with no locale variable, the boot features (`encdb.so` and four others), a file loaded by `require_relative`, and `$0` were all valid BINARY, and `$LOADED_FEATURES.any? { |f| f.start_with?($LOAD_PATH.last) }` returned `true`. The same build without the patch printed, under `LC_ALL=C`, what the macOS run above printed. Ruby's own test suite was not run with the patch.

The fourth would raise "incompatible character encodings: UTF-8 and BINARY (ASCII-8BIT)" instead with the same treatment, which is no better; joining a UTF-8 name with a directory whose bytes are not ASCII has no right answer while the filesystem encoding is US-ASCII. The feature proposal (#FEATURE) addresses that, and the rest of this case, by treating the C locale as UTF-8.

Related: #18191 (fixed in 60d0421ca8) gave the boot features the filesystem encoding, which on Windows is UTF-8 and under the C locale is US-ASCII. #22194 (open) reports `File.realpath` and `File.realdirpath` disagreeing on a path that is not valid in the filesystem's encoding. #9737 and #1614 (closed) fixed Ruby failing to boot under a non-ASCII prefix.

---

This report was produced entirely by Claude (Anthropic) via Claude Code. [https://declare-ai.org/1.0.0/total.html](https://declare-ai.org/1.0.0/total.html)
