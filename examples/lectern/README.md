<!--
  SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
  SPDX-License-Identifier: CC-BY-SA-4.0
-->
# Lectern Example

A Markdown reader for the terminal: it draws headings, *emphasis*, lists, block quotes, tables, and code blocks with highlighting, wrapped to the width of the terminal, and pages what is longer than the screen.

A program for the command line is the easiest kind to hand to someone, and the one that most often needs a runtime they do not have. Lectern is that program as an app: one download, no Ruby, and one name to type. It is written in Ruby, with [kramdown](https://kramdown.gettalong.org/) to read the Markdown, and [Rouge](https://rouge.jneen.net/) to color the code.

## What it shows

- **A tool for a terminal.** `kind: console` makes Lectern a program that runs in the terminal that starts it, with its standard input, output, and error, and the exit status of `ruby main.rb`.
- **Pure-Ruby gems, on every platform.** kramdown, its GitHub-Flavored Markdown parser, and Rouge compile nothing, so one `Gemfile.lock`, with every gem's checksum, builds Lectern on macOS, on Linux with glibc or musl, and on Windows on x64 or ARM64.
- **Output that fits where it goes.** On a terminal Lectern wraps to its width (at most 100 columns) and draws in color. Off a terminal, into a file or a pipe, it writes plain text, 80 columns wide, with no escape sequence. `NO_COLOR` keeps the colors out and leaves bold, italic, and underline ([no-color.org](https://no-color.org/)), and `--color=always` or `--color=never` decides without asking.
- **A pager of its own.** Output taller than the screen opens in a pager written in Ruby, which needs no `less` and works on a computer with nothing installed: space and `b` page, `j` and `k` scroll by a line, `g` and `G` go to the ends, and `q` quits.

## Run it with Ruby

With Ruby 4.1, in this folder:

<!-- SPDX-SnippetBegin -->
<!--
  SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
  SPDX-License-Identifier: MIT-0
-->
```console
$ bundle install
$ bundle exec ruby main.rb README.md
$ bundle exec ruby main.rb --width=60 README.md
$ bundle exec ruby main.rb README.md | cat
```
<!-- SPDX-SnippetEnd -->

With no file, or with `-`, it reads the standard input. `--help` lists every option.

| Option | What it does |
|:-------|:-------------|
| `-w`, `--width=COLUMNS` | Wraps at COLUMNS. |
| `--color=WHEN` | Colors the output: `auto`, `always`, or `never`. |
| `-p`, `--pager` | Pages on a terminal, even when the text is short. |
| `-P`, `--no-pager` | Never pages. |

A file it cannot read ends it with exit status 66, and an option it does not know with 64, as [sysexits.h](https://man.freebsd.org/cgi/man.cgi?query=sysexits) names them.

## Build it with Fledge

Install Fledge as the README's [Installation](../../README.md#installation) says, in a `Gemfile` of a folder of its own outside this one, such as `~/fledge`, and run `bundle install` there. Then, from that folder, build Lectern by its path:

<!-- SPDX-SnippetBegin -->
<!--
  SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
  SPDX-License-Identifier: MIT-0
-->
```console
$ bundle exec fledge build ~/path/to/Fledge/examples/lectern
```
<!-- SPDX-SnippetEnd -->

That writes `dist/Lectern-PLATFORM.tar.gz`, or `.zip` on Windows. Unpack it, and run `Lectern` in the folder it makes, on any computer of that platform.

> [!NOTE]
> Fledge builds each platform's app on a computer of that platform. A Mac builds Lectern for macOS, and a Windows computer for Windows.

## Read the code

- [`main.rb`](main.rb): the start, which sets the output to UTF-8 and runs the command.
- [`lib/lectern/cli.rb`](lib/lectern/cli.rb): the options, the width, what is read, and when to page.
- [`lib/lectern/renderer.rb`](lib/lectern/renderer.rb): kramdown's tree, turned into lines: each block takes the width it has left, and each paragraph is words and spaces that [`text.rb`](lib/lectern/text.rb) wraps by the width a terminal draws them in, two columns for a Japanese character.
- [`lib/lectern/table_layout.rb`](lib/lectern/table_layout.rb): a table's columns, narrowed from the widest first, and never below a word that would then be cut.
- [`lib/lectern/highlight.rb`](lib/lectern/highlight.rb): Rouge's tokens, in the sixteen colors every terminal has, so that a person's palette decides how they look.
- [`lib/lectern/pager.rb`](lib/lectern/pager.rb): the pager, on the terminal's alternate screen.
- [`fledge.yml`](fledge.yml): why Lectern is a console app.

```ruby
# The sample code block of this page, which Lectern draws in color.
Lectern::Cli.new(ARGV).run
```

## Use this example if you need to

- Ship a command-line tool to people who have no Ruby.
- Ship pure-Ruby gems, and one lockfile for every platform.
- Write for a terminal: read the standard input, honor `NO_COLOR`, draw only where there is a terminal, and page what is long.

- [x] Run `bundle exec ruby main.rb README.md` to see this page.
- [ ] Copy this folder to start a tool of your own.

[Read the source code →](main.rb)
