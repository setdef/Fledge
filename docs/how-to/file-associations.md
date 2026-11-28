# Open files and folders

A windowed app can tell each system which files and folders it opens, so that people can open them with it from their file manager, or drop them on it. Your program gets their paths in `ARGV`, as it would from `ruby main.rb PATH`.

## Say what the app opens

Add an entry to `file_associations` in `fledge.yml` for each kind of document:

<!-- SPDX-SnippetBegin -->
<!--
  SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
  SPDX-License-Identifier: MIT-0
-->
```yaml
name: Cool App
kind: windowed
identifier: com.example.CoolApp

file_associations:
  - name: Markdown note
    role: editor
    extensions: [md, markdown]
    mime_types: [text/markdown]
  - name: Notes folder
    folders: true
```
<!-- SPDX-SnippetEnd -->

Name each kind as people would, since each system shows the name. Give each by its extensions (for macOS and Windows) and MIME types (for Linux desktops). `role: editor` says the app writes these files too; the default, `viewer`, says it only reads them.

## Read the paths

Each system starts the program with the paths in `ARGV`, so read them as any Ruby program reads its arguments:

<!-- SPDX-SnippetBegin -->
<!--
  SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
  SPDX-License-Identifier: MIT-0
-->
```ruby
ARGV.each do |path|
  if File.directory?(path)
    open_folder(path)
  else
    open_note(path)
  end
end
```
<!-- SPDX-SnippetEnd -->

On macOS, Finder sends the paths in an Apple event, not on the command line. Fledge's launcher waits for that event when the app starts, up to 15 seconds, and passes its paths to Ruby in `ARGV` after any on the command line. A program that is already running gets no new `ARGV`: what happens when a person opens a second file depends on your GUI toolkit.

## What each system does

- **macOS** lists each kind as one of the bundle's document types, ranked Alternate: Finder offers the app in Open With, and never makes it the default app for the type.
- **Windows** gets the associations from the setup program, which adds the app to each extension's Open with list, without taking the default, and, for folders, adds "Open with Cool App" to every folder's menu. Uninstalling removes them. An MSIX package declares the extensions too.
- **Linux** desktops read the app's desktop entry, which lists the MIME types, and `inode/directory` for folders.

To make the app the default for a type, a person chooses it, as each system lets them.

## A file type the app defines

When the app's files are of a type no other program uses, such as a game's save files, say that it defines the type:

<!-- SPDX-SnippetBegin -->
<!--
  SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
  SPDX-License-Identifier: MIT-0
-->
```yaml
file_associations:
  - name: Rocket Run save
    defines_type: true
    extensions: [rrsave]
    mime_types: [application/x-rocket-run-save]
```
<!-- SPDX-SnippetEnd -->

Give it its extensions and exactly one MIME type. On Linux, the app then carries the type's definition, which a `.deb` installs where shared-mime-info finds it, so a desktop knows a `.rrsave` file by its name even though no other program defines it.

## Types macOS defines

macOS identifies many types by a uniform type identifier, and goes by it before extensions. For a type macOS defines, such as plain text, give it too:

<!-- SPDX-SnippetBegin -->
<!--
  SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
  SPDX-License-Identifier: MIT-0
-->
```yaml
file_associations:
  - name: Plain text
    extensions: [txt]
    mime_types: [text/plain]
    content_types: [public.plain-text]
```
<!-- SPDX-SnippetEnd -->

With `content_types`, macOS goes by them and ignores the extensions and MIME types.

The full list of what an entry of `file_associations` takes is in [the fledge.yml reference](../reference/fledge-yml.md#file_associations).
