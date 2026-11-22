<!--
  SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
  SPDX-License-Identifier: MIT-0
-->
# Markdown Preview

Open a Markdown file with Markdown Preview, and it shows here, read as GitHub-Flavored Markdown, with its fenced code, tables, ~~strikethrough~~, and task lists:

- **Windows:** right-click the file in Explorer, then choose Open with > Markdown Preview.
- **Linux:** right-click the file in your file manager, then choose Open With > Markdown Preview.

To have Markdown Preview open every Markdown file you double-click, choose it as the default there.

The preview opens in your browser, or in the one the `BROWSER` environment variable names.

## In a terminal

Markdown Preview comes with `md2html`, which prints a Markdown file's HTML:

```sh
md2html notes.md > notes.html
md2html --page notes.md > notes.html   # the whole page, as the preview shows it
```

It is beside Markdown Preview: in `Markdown Preview.app/Contents/MacOS` on macOS, in the folder Markdown Preview is installed in on Windows, and in the app's folder on Linux.
