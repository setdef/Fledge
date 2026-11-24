<!--
  SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
  SPDX-License-Identifier: CC-BY-SA-4.0
-->
# Markdown to HTML

A droplet: drop Markdown files on the app, or open them with it, and it writes each file's HTML beside it, as `notes.md` becomes `notes.html`. It opens no window and no browser. It also shows an app with two programs, the droplet and `md2html`, which share `lib/` and one copy of [kramdown](https://kramdown.gettalong.org/).

## What it shows

- **Files dropped on an app, or opened with it.** `fledge.yml` lists Markdown under `file_associations`, and each system hands the program the paths in `ARGV`. See [Desktop apps](../../doc/desktop_apps.md).
- **An app with no window.** A success shows nothing but the new file. A failure is a notification on macOS and Linux and a message box on Windows, as [Desktop apps](../../doc/desktop_apps.md#tell-the-person-without-a-window) explains.
- **Two programs in one app.** `markdown_to_html.rb` is the windowed program and takes the app's name. `bin/md2html` is a console program that prints the HTML of the files it is given, or of standard input, with `--page` as a whole page.
- **Pure Ruby only.** kramdown and its GitHub-Flavored Markdown parser need no compiler, so one `Gemfile.lock` serves every platform.

## Run it from source

```console
$ bundle install
$ bundle exec ruby markdown_to_html.rb sample.md
$ bundle exec ruby bin/md2html sample.md
```

## Build the app

On each computer you ship to, from a folder with Fledge in its `Gemfile`:

```console
$ bundle exec fledge build examples/markdown_to_html
```

This makes the app and its installers for that computer's system: a `.app` and `.dmg` on macOS, a setup program on Windows, and an AppImage, `.deb`, and `.tar.gz` on Linux.
