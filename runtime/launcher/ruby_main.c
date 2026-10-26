/*
 * SPDX-FileCopyrightText: 1993-2007 Yukihiro Matsumoto
 * SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
 * SPDX-License-Identifier: Ruby OR BSD-2-Clause
 * SPDX-FileComment: Adapted from Ruby's main.c at Ruby v4.0.9
 *   (3e93b23afcec3433f6aecc34b5d832799d754238), without its developer-only
 *   RUBY_DEBUG_ENV and sanitizer hooks, whose headers Ruby does not install.
 */

/*
 * Ruby's own program, bin/ruby, in a macOS or Linux runtime.
 *
 * An app that starts Ruby again, to run a script in a child process or
 * to restart itself, finds it the way any Ruby program does: through
 * RbConfig.ruby or Gem.ruby, which name PREFIX/bin/ruby. rv-ruby ships
 * that program, but the runtime builds its own from the same static
 * libruby the launcher links, with the same link line, so the two
 * programs carry exactly the same Ruby and the same libraries. This is
 * Ruby's main.c, unchanged in what it does: it is the ruby a person
 * runs, not an app's launcher, so it neither scrubs the environment nor
 * runs app/main.rb. Built with --enable-load-relative, it finds its
 * standard library from its own folder, bin, whose parent is the
 * runtime (ruby.c, ruby_init_loadpath).
 *
 * Its license is Ruby's, like the rest of what it is made of; the
 * runtime's notices/ruby/ covers it.
 */

#include <ruby.h>

#include <locale.h>

RUBY_GLOBAL_SETUP

static int
rb_main(int argc, char **argv)
{
    RUBY_INIT_STACK;
    ruby_init();
    return ruby_run_node(ruby_options(argc, argv));
}

int
main(int argc, char **argv)
{
    setlocale(LC_CTYPE, "");

    ruby_sysinit(&argc, &argv);
    return ruby_start_main(rb_main, argc, argv);
}
