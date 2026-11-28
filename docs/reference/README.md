# Reference

The complete description of what Fledge reads, writes, and runs, for looking things up. Each page defines every entry fully; examples only illustrate.

- [The `fledge` command](fledge.usage.kdl): every command, argument, flag, environment variable, and exit status, as a [Usage](https://usage.jdx.dev) spec. `usage generate markdown -f fledge.usage.kdl` renders it as a page, and `usage generate manpage` as a man page.
- [fledge.kdl](fledge-kdl.md): every node of the file that says how an app presents itself, its defaults, and what each system does with it.
- [Platforms](platforms.md): the platforms Fledge builds for, the oldest system each app runs on, and what the computer that builds needs.
- [What a built app holds, and how it starts](built-app.md): the files of an app, its `fledge.cfg`, what its launcher does before your program runs, and its exit statuses.
- [What ships inside an app, and what its licenses ask of you](licensing.md): every component of each platform's runtime, its license, and what that license asks of you when you give the app to other people. It is written from the license audit every runtime passes.
- [Differences from `ruby main.rb`](differences.md): every difference your program's code can observe between the app and `ruby main.rb` or `bundle exec`, on each platform, and what to do about each.
