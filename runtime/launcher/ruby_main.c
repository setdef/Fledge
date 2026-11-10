/*
 * SPDX-FileCopyrightText: 1993-2007 Yukihiro Matsumoto
 * SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
 * SPDX-License-Identifier: Ruby OR BSD-2-Clause
 * SPDX-FileComment: Adapted from Ruby's main.c at Ruby v4.1.0-preview1
 *   (2d08b5f42f2cbed4a4e6ecf8d62987a4f21f98c1), without its developer-only
 *   RUBY_DEBUG_ENV and sanitizer hooks, whose headers Ruby does not install,
 *   with Fledge's fledge_relaunch (relaunch.c) first, and with Fledge's
 *   fledge_coerce_locale (locale.c) in place of its setlocale.
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
 * Ruby's main.c, and it is the ruby a person runs, not an app's
 * launcher: it neither scrubs the environment nor runs app/main.rb on
 * its own.
 * Built with --enable-load-relative, it finds its standard library from
 * its own folder, bin, whose parent is the runtime (ruby.c,
 * ruby_init_loadpath).
 *
 * It differs from main.c in two calls. First, when its first argument is
 * the program a launcher of this app runs, as in a restart with exec
 * RbConfig.ruby, $0, *ARGV, it runs that launcher in its place
 * (fledge_relaunch, ADR 026), so the restarted app boots as
 * it booted the first time. Second, where main.c sets LC_CTYPE from
 * the environment, it calls the launcher's fledge_coerce_locale, which
 * does the same and then turns a bare C or POSIX locale into a UTF-8
 * one, as Python does (PEP 538). The launcher sets the locale only in
 * its own process and exports nothing, so a Ruby the app starts, a
 * restart of the app, and a gem's executable start from the locale the
 * person has, which for an app a desktop started is C; with main.c's
 * setlocale they would read the app's folder, whose name need not be
 * ASCII, as US-ASCII, and Bundler would fail to set up the app's gems
 * (ADR 041).
 *
 * Its license is Ruby's, like the rest of what it is made of; the
 * runtime's notices/ruby/ covers it. relaunch.c, config.c, locale.c, and
 * the file that finds this program (darwin.c or linux.c) are Fledge's
 * own.
 */

#include "launcher.h"

#include <ruby.h>

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
    fledge_relaunch(argc, argv);
    fledge_coerce_locale();

    ruby_sysinit(&argc, &argv);
    return ruby_start_main(rb_main, argc, argv);
}
