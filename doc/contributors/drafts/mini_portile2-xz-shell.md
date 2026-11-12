<!--
SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>

SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Draft: a mini_portile2 bug report, for the maintainer to file

Not filed. For the maintainer to file, if he chooses, at https://github.com/flavorjones/mini_portile/issues/new, with the title below, and everything after the line as the body (GitHub takes Markdown).

mini_portile2 has no contributing guide or issue template (its repository holds a README, a CHANGELOG, and a SECURITY.md). Before filing: search its issues for "xz", "shellescape", and "Windows", since someone may have reported it after 2026-11-12 (nothing matched then); check that `lib/mini_portile2/mini_portile.rb` still builds the `.xz` command as a string (it did at main 2dd8c949fa); and read the body start to finish as your own words, since you are the one filing it. Found when CI built nokogiri from source with `fledge build` on GitHub's Windows runner, whose `TMP` is `C:\Users\RUNNER~1\AppData\Local\Temp` (CI run 43186780019, Build (x64-mingw-ucrt)). The reproduction below is reduced from that build and has not been run on its own as written.

- **Title:** On Windows, a `.tar.xz` whose path needs escaping unpacks nothing, and extract says OK
- **Version:** mini_portile2 2.8.9; still present at main 2dd8c949fa

---

On Windows, `MiniPortile#extract` unpacks nothing from a `.tar.xz` whose path has a character `Shellwords` escapes, such as the `~` of an 8.3 short name (`C:\Users\RUNNER~1\...`, which `TMP` is for any user whose folder name is no 8.3 name) or a space (`C:\Users\John Smith\...`), and still prints "OK". The next step then fails far from the cause. nokogiri's `extconf.rb`, building libxml2 2.13.9 in such a folder:

```
Extracting libxml2-2.13.9.tar.xz into tmp/x86_64-w64-mingw32/ports/libxml2/2.13.9... OK
...
.../mini_portile2-2.8.9/lib/mini_portile2/mini_portile.rb:594:in 'Dir.chdir': no implicit conversion of nil into String (TypeError)
```

## Cause

`#tar_command` (`lib/mini_portile2/mini_portile.rb`, lines 561 to 573 at v2.8.9) returns an array of arguments for every archive but `.xz`, which it returns as one string for a shell, because OpenBSD's tar has no `-J`:

<!--
SPDX-SnippetBegin
SPDX-SnippetCopyrightText: 2011-2016 Luis Lavena and Mike Dalessio
SPDX-License-Identifier: MIT
SPDX-SnippetComment: lib/mini_portile2/mini_portile.rb, lines 567 to 569, mini_portile2 v2.8.9
-->

```ruby
      when '.xz'
        # NOTE: OpenBSD's tar command does not support the -J option
        "#{xzcat_exe.shellescape} #{file.shellescape} | #{tar_exe.shellescape} xf - -C #{target.shellescape}"
```

<!--
SPDX-SnippetEnd
-->

`Shellwords` escapes for a POSIX shell, with backslashes, but on Windows `#execute` (line 603) hands the string to `spawn`, and Ruby runs a command line with a pipe through cmd.exe, which takes a backslash as part of a name. `RUNNER~1` becomes `RUNNER\~1`, which names no folder, and `John\ Smith` becomes two arguments. So `xzcat` finds no file and writes nothing; `tar` reads an empty archive and exits 0; and the pipeline's status is `tar`'s, so `#execute` prints "OK" (lines 617 and 618). Nothing was unpacked, so `#work_path` (lines 411 to 413) finds no folder and returns `nil`, and the patch step's `Dir.chdir(nil)` (line 594) raises.

A `.tar.gz` in the same folder unpacks: its command is an array, which reaches `tar` without a shell.

## Reproduction

On Windows, with RubyInstaller's Ruby and its MSYS2 on `PATH` (`ridk enable`, which puts MSYS2's `xzcat` and `tar` there), in a folder whose path has a space, or an 8.3 name:

```
ridk enable
mkdir "C:\mp test"
cd /d "C:\mp test"
mkdir src
echo hello> src\hello.txt
tar -cJf src.tar.xz src
gem install mini_portile2 -v 2.8.9
ruby -rmini_portile2 -e "r = MiniPortile.new('src', '1'); r.send(:extract_file, File.expand_path('src.tar.xz'), 'out'); p Dir.children('out')"
```

It prints `Extracting src.tar.xz into out... OK` and then `[]`; with `src.tar.gz` made by `tar -czf` in place of the `.xz`, it prints `["src"]`. For an 8.3 path, use a folder under `%TMP%` on an account whose user name is longer than eight characters, as GitHub's `windows-latest` runner is (`runneradmin`, so `C:\Users\RUNNER~1`).

## Suggested fix

Run the two programs without a shell, as the other branches run `tar`, so no path is escaped at all. `Open3.pipeline` takes each command as an array, and its statuses show when `xzcat` fails:

```ruby
statuses = Open3.pipeline([xzcat_exe, file], [tar_exe, "xf", "-", "-C", target])
```

That would need `#execute` to take a pipeline, or `#extract_file` to run it itself. Where tar has `-J` (GNU tar, as MSYS2 ships it, and bsdtar), `[tar_exe, "xJf", file, "-C", target]` is enough, keeping the pipeline for OpenBSD. Either way, checking `xzcat`'s status as well as `tar`'s would turn the next failure of this kind into an error at the step that failed.

---

This report was produced entirely by Claude (Anthropic) via Claude Code. [https://declare-ai.org/1.0.0/total.html](https://declare-ai.org/1.0.0/total.html)
