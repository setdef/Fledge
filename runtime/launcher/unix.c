/*
 * SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */

/*
 * Fledge's launcher for macOS and Linux: the program a person runs.
 *
 * A built app is a folder. The launcher sits at its top, renamed to the
 * app's name, beside the Ruby it embeds and the app it runs:
 *
 *   NAME                       this program
 *   lib/ruby/4.0.0/            Ruby's standard library
 *   lib/ruby/gems/4.0.0/       Ruby's default gems
 *   lib/libcrypt.so.N          libxcrypt, on Linux only (see below)
 *   libexec/cert.pem           certificate authorities for HTTPS
 *   notices/                   the licenses of everything above
 *   app/main.rb                the app
 *
 * libruby is linked into this program statically, so the program is the
 * Ruby interpreter. It starts Ruby the way Ruby's own main.c does
 * (main.c lines 37 to 63 at Ruby 4.0.9): setlocale, ruby_sysinit, then
 * ruby_start_main, whose callback runs RUBY_INIT_STACK, ruby_init, and
 * ruby_run_node(ruby_options(...)). Ruby runs on the process's main
 * thread, where macOS wants windows and events. Before that it does four
 * things Ruby's main.c does not:
 *
 *   1. It finds the folder it lives in (fledge_executable_path, one file
 *      per operating system).
 *   2. It removes every environment variable through which a Ruby that
 *      happens to be installed on the computer could change what runs:
 *      RUBYOPT, RUBYLIB, GEM_HOME, BUNDLE_GEMFILE, and the rest (see
 *      scrub_environment). The runtime's own
 *      lib/ruby/4.0.0/rubygems/defaults/operating_system.rb then keeps
 *      RubyGems to the runtime's gems, away from ~/.gem.
 *   3. It turns a bare C locale into a UTF-8 one (see coerce_locale).
 *   4. It runs the app with arguments equivalent to
 *        NAME --disable=rubyopt --yjit -I ROOT/app -- ROOT/app/main.rb ARGS
 *      and exits with the app's exit status.
 *
 * Ruby finds its standard library on its own. rv-ruby builds Ruby with
 * --enable-load-relative, so ruby_init_loadpath derives the install
 * prefix at run time from the file that holds libruby (ruby.c lines 591
 * to 735 at Ruby 4.0.9). Here that file is this program, so the prefix is
 * the folder this program sits in, and Ruby looks for ROOT/lib/ruby/4.0.0
 * as rv-ruby's own bin/ruby does. One wrinkle: when that folder is named
 * bin (in any case) or lib, ruby.c takes its parent as the prefix
 * instead. The launcher refuses to run from such a folder rather than
 * run with a standard library from somewhere else.
 *
 * On Linux, libruby calls crypt(3) from libxcrypt, which is LGPL. The
 * launcher links it dynamically, from ROOT/lib, through an RPATH of
 * $ORIGIN/lib set when it is built, so that whoever receives an app can
 * replace that library. A DT_RPATH, unlike a DT_RUNPATH, is searched
 * before LD_LIBRARY_PATH, so the computer's libraries cannot stand in
 * for it either.
 */

#include "launcher.h"

#include <ruby.h>

#include <errno.h>
#include <langinfo.h>
#include <limits.h>
#include <locale.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <sys/stat.h>

/* As in Ruby's main.c: lets the VM declare any globals it needs. */
RUBY_GLOBAL_SETUP

extern char **environ;

/*
 * The exit status for a runtime folder that cannot run, as sysexits(3)'s
 * EX_SOFTWARE. An app's own failures exit with the app's status instead.
 */
enum { EXIT_BROKEN_RUNTIME = 70 };

/* The launcher's file name, for messages. Set once in main. */
static const char *program_name = "launcher";

/*
 * Prints "NAME: message" to standard error and exits. A person who runs
 * an app never asked for Ruby, so messages name the app, not Ruby.
 */
static void fail(const char *format, ...) __attribute__((format(printf, 1, 2), noreturn));

static void
fail(const char *format, ...)
{
    va_list arguments;

    fprintf(stderr, "%s: ", program_name);
    va_start(arguments, format);
    vfprintf(stderr, format, arguments);
    va_end(arguments);
    fputc('\n', stderr);
    exit(EXIT_BROKEN_RUNTIME);
}

/*
 * Prefixes of environment variables that change what Ruby, RubyGems, or
 * Bundler load or do. Prefixes, not a list of names, so a variable a
 * later Ruby adds is removed too. Read at Ruby 4.0.9:
 *
 *   RUBY      ruby.c: RUBYOPT, RUBYLIB, RUBYPATH, RUBYSHELL,
 *             RUBY_YJIT_ENABLE, RUBY_ZJIT_ENABLE; gc.c, vm.c, thread.c:
 *             RUBY_GC_*, RUBY_THREAD_*, RUBY_FIBER_*, RUBY_MN_THREADS,
 *             RUBY_MAX_CPU, RUBY_CRASH_REPORT, RUBY_DEBUG,
 *             RUBY_FREE_AT_EXIT; RubyGems: RUBYGEMS_GEMDEPS.
 *   GEM_      RubyGems: GEM_HOME, GEM_PATH, GEM_SPEC_CACHE, GEM_VENDOR,
 *             GEM_REQUIREMENT_<NAME>.
 *   GEMRC     RubyGems' configuration file.
 *   BUNDLE_   Bundler's settings: BUNDLE_GEMFILE, BUNDLE_PATH, ...
 *   BUNDLER_  Bundler: BUNDLER_VERSION, and BUNDLER_SETUP, a file that
 *             rubygems.rb requires as it loads (its last lines), which
 *             would run any code it names.
 *
 * Variables outside these, such as SSL_CERT_FILE, HOME, and the XDG_
 * directories, describe the person's computer, not their Ruby, and stay.
 */
static const char *const scrubbed_prefixes[] = {
    "RUBY", "GEM_", "GEMRC", "BUNDLE_", "BUNDLER_", NULL,
};

static int
is_scrubbed(const char *entry)
{
    for (const char *const *prefix = scrubbed_prefixes; *prefix != NULL; prefix++) {
        if (strncmp(entry, *prefix, strlen(*prefix)) == 0) return 1;
    }
    return 0;
}

/*
 * Removes every scrubbed variable. unsetenv rearranges environ, so the
 * scan starts over after each removal; environments are small.
 */
static void
scrub_environment(void)
{
    int removed;

    do {
        removed = 0;
        for (char **entry = environ; entry != NULL && *entry != NULL; entry++) {
            if (!is_scrubbed(*entry)) continue;

            const char *equals = strchr(*entry, '=');
            size_t length = equals != NULL ? (size_t)(equals - *entry) : strlen(*entry);
            char *name = strndup(*entry, length);
            if (name == NULL) fail("out of memory");
            int status = unsetenv(name);
            free(name);
            if (status != 0) fail("could not clear the environment: %s", strerror(errno));
            removed = 1;
            break;
        }
    } while (removed);
}

static int
codeset_is_utf8(void)
{
    const char *codeset = nl_langinfo(CODESET);

    return codeset != NULL && (strcasecmp(codeset, "UTF-8") == 0 || strcasecmp(codeset, "utf8") == 0);
}

/*
 * Sets LC_CTYPE from the environment, as Ruby's main.c does, so the
 * person's locale decides Encoding.default_external. When there is no
 * locale at all (LANG unset, as for an app started by a desktop, a
 * service manager, or env -i), that locale is C, whose character set is
 * ASCII, and a folder name such as "Ünïcödé" in the app's path makes
 * Ruby fail with "invalid byte sequence in US-ASCII" as it builds its
 * load path. As Python does (PEP 538), a C or POSIX locale is replaced
 * by the first UTF-8 locale the system has; a locale the person chose
 * is left alone.
 */
static void
coerce_locale(void)
{
    static const char *const utf8_locales[] = {"C.UTF-8", "C.utf8", "UTF-8", "en_US.UTF-8", NULL};
    const char *chosen = setlocale(LC_CTYPE, "");

    if (chosen != NULL && strcmp(chosen, "C") != 0 && strcmp(chosen, "POSIX") != 0) return;
    for (const char *const *locale = utf8_locales; *locale != NULL; locale++) {
        if (setlocale(LC_CTYPE, *locale) != NULL && codeset_is_utf8()) return;
    }
    setlocale(LC_CTYPE, "C");
}

/*
 * The folder the launcher sits in, refusing one that ruby.c would read
 * as a bin or lib folder (ruby.c lines 710 to 720 at Ruby 4.0.9: "/bin"
 * matched in any case, "/lib" exactly).
 */
static void
find_root(char *root, size_t size)
{
    if (fledge_executable_path(root, size) != 0) {
        fail("could not find where this app is: %s", strerror(errno));
    }

    char *slash = strrchr(root, '/');
    if (slash == NULL) fail("could not find where this app is: %s", root);
    program_name = slash + 1;
    *slash = '\0';

    const char *folder = strrchr(root, '/');
    folder = folder != NULL ? folder + 1 : root;
    if (strcasecmp(folder, "bin") == 0 || strcmp(folder, "lib") == 0) {
        fail("this app cannot run from a folder named \"%s\"; rename the folder or move the app out of it", folder);
    }
}

/* Ruby's argument vector, built in main and handed to ruby_options. */
static char **ruby_argv;
static int ruby_argc;

/* As rb_main in Ruby's main.c, with the launcher's arguments. */
static int
run_ruby(int argc, char **argv)
{
    RUBY_INIT_STACK;
    ruby_init();
    return ruby_run_node(ruby_options(argc, argv));
}

/*
 * Builds the arguments Ruby sees. argv[0] stays the very pointer
 * ruby_sysinit recorded: on Linux, ruby.c recognizes the program that
 * holds libruby by comparing dladdr's file name with that pointer
 * (ruby.c line 647 at Ruby 4.0.9), and only then reads /proc/self/exe,
 * so a launcher found on PATH by its bare name still finds its root.
 */
static void
build_ruby_arguments(int argc, char **argv, const char *root)
{
    static char app[PATH_MAX];
    static char main_rb[PATH_MAX];
    int app_length = snprintf(app, sizeof app, "%s/app", root);
    int main_length = snprintf(main_rb, sizeof main_rb, "%s/app/main.rb", root);

    if (app_length < 0 || (size_t)app_length >= sizeof app || main_length < 0 ||
        (size_t)main_length >= sizeof main_rb) {
        fail("the path to this app is too long");
    }

    struct stat status;
    if (stat(main_rb, &status) != 0 || !S_ISREG(status.st_mode)) {
        fail("this app is incomplete: %s is missing", main_rb);
    }

    static char disable_rubyopt[] = "--disable=rubyopt";
    static char yjit[] = "--yjit";
    static char include[] = "-I";
    static char end_of_options[] = "--";
    char *before_app_arguments[] = {argv[0], disable_rubyopt, yjit, include, app, end_of_options, main_rb};
    size_t fixed = sizeof before_app_arguments / sizeof before_app_arguments[0];
    size_t count = fixed + (size_t)(argc > 1 ? argc - 1 : 0);

    ruby_argv = calloc(count + 1, sizeof *ruby_argv);
    if (ruby_argv == NULL) fail("out of memory");
    memcpy(ruby_argv, before_app_arguments, sizeof before_app_arguments);
    for (int index = 1; index < argc; index++) ruby_argv[fixed + (size_t)index - 1] = argv[index];
    ruby_argc = (int)count;
}

int
main(int argc, char **argv)
{
    static char root[PATH_MAX];

    find_root(root, sizeof root);
    scrub_environment();
    coerce_locale();

    ruby_sysinit(&argc, &argv);
    build_ruby_arguments(argc, argv, root);
    return ruby_start_main(run_ruby, ruby_argc, ruby_argv);
}
