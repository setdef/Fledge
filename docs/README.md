# Fledge's documentation

Fledge builds a Ruby program into an app that people without Ruby can run, for macOS, Windows, Linux, iOS, and Android. These pages are for developers who ship apps with it. They describe Fledge 0.17.0.

## Start here

New to Fledge? Work through [the tutorial](tutorial.md). It takes a two-line program to an app you can hand to someone, and shows what's in it.

## The four kinds of page

| Kind | For when you want to | Pages |
| - | - | - |
| [Tutorial](tutorial.md) | learn Fledge by building something, from the start | [Ship a command-line tool](tutorial.md) |
| [How-to guides](how-to/README.md) | get one task done, such as signing an app or adding an icon | [Make a windowed app](how-to/windowed-app.md), [Ship gems with C extensions](how-to/native-gems.md), [Sign and notarize an app](how-to/signing.md), [Build for iPhone and Android](how-to/phones.md), and [more](how-to/README.md) |
| [Reference](reference/README.md) | look up a command, a `fledge.yml` key, a platform, what a built app holds, or where its Ruby differs from `ruby main.rb` | [The `fledge` command](reference/fledge.usage.kdl), [fledge.yml](reference/fledge-yml.md), [Platforms](reference/platforms.md), [What a built app holds](reference/built-app.md), [Differences from `ruby main.rb`](reference/differences.md) |
| Explanation | understand how Fledge works, and why it works that way | [How Fledge works](explanation/how-fledge-works.md), [Ruby on a phone](explanation/phones.md) |

The tutorial assumes you know Ruby and Bundler, and nothing of Fledge. The guides assume you have built an app once. The reference assumes nothing, and is the complete word on every command, key, and file.

## The command-line reference

`fledge`'s commands, flags, environment variables, and exit statuses are specified in [`fledge.usage.kdl`](reference/fledge.usage.kdl), a [Usage](https://usage.jdx.dev) spec. Read it as it is, or turn it into the form you like with the `usage` command:

<!-- SPDX-SnippetBegin -->
<!--
  SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
  SPDX-License-Identifier: MIT-0
-->
```console
$ usage generate markdown -f docs/reference/fledge.usage.kdl --out-file fledge.md
$ usage generate manpage -f docs/reference/fledge.usage.kdl > fledge.1
$ usage generate completion zsh fledge -f docs/reference/fledge.usage.kdl > _fledge
```
<!-- SPDX-SnippetEnd -->

A completion script asks `usage` for its answers on each Tab, so `usage` must be installed where you use it.

## Get help

Ask on [the Fledge forum](https://forum.setdef.com/c/fledge), with the command you ran and everything it printed. Report a mistake in these pages there too. Report a security problem privately, as [the security policy](../SECURITY.md) says.
