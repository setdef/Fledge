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
 *   fledge.cfg                 what it runs (config.c)
 *   bin/ruby                   Ruby's own program, for RbConfig.ruby
 *   lib/ruby/4.0.0/            Ruby's standard library
 *   lib/ruby/gems/4.0.0/       Ruby's default and bundled gems, and the
 *                              app's own
 *   lib/libcrypt.so.N          libxcrypt, on Linux only (see below)
 *   libexec/cert.pem           certificate authorities for HTTPS
 *   notices/                   the licenses of everything above
 *   app/                       the app's project, such as app/main.rb, or
 *                              app/exe/my_cool_app beside its Gemfile
 *
 * libruby is linked into this program statically, so the program is the
 * Ruby interpreter. It starts Ruby the way Ruby's own main.c does
 * (main.c lines 37 to 63 at Ruby 4.0.9): setlocale, ruby_sysinit, then
 * ruby_start_main, whose callback runs RUBY_INIT_STACK, ruby_init, and
 * ruby_run_node(ruby_options(...)). Ruby runs on the process's main
 * thread, where macOS wants windows and events. Beyond that it does six
 * things Ruby's main.c does not:
 *
 *   1. It finds the folder it lives in (fledge_executable_path, one file
 *      per operating system), and reads fledge.cfg there, which names the
 *      program in app/ to run, ENTRY, and the app's Gemfile, if it has one.
 *   2. It sets aside every environment variable through which a Ruby
 *      that happens to be installed on the computer could change how
 *      Ruby boots: RUBYOPT, RUBYLIB, GEM_HOME, BUNDLE_GEMFILE, and the
 *      rest (see scrub.c, which windows.c shares). The runtime's own
 *      lib/ruby/4.0.0/rubygems/defaults/operating_system.rb then keeps
 *      RubyGems to the runtime's gems, away from ~/.gem.
 *   3. It turns a bare C locale into a UTF-8 one (see coerce_locale).
 *   4. It runs the app with arguments equivalent to
 *        NAME --disable=rubyopt -- ROOT/app/ENTRY ARGS
 *      which is what ruby ROOT/app/ENTRY ARGS does with no RUBYOPT
 *      (ADR 003): no -I, so the app loads its own files with
 *      require_relative, and no --yjit, so RubyVM::YJIT.enabled? is
 *      false until the app enables it, as under ruby.
 *   5. Once Ruby has booted and before ENTRY runs, it fixes RubyGems'
 *      paths, and for an app with a Gemfile has Bundler set up the app's
 *      gems, as bundle exec would (setup_bundler, ADR 005).
 *   6. Then it puts the variables of step 2 back, so ENV and the app's
 *      child processes see what they would see without Fledge: as they
 *      were (restore_environment), or for an app with a Gemfile beneath
 *      Bundler's own settings, as bundle exec composes them
 *      (bundle_environment, bundler.c).
 *
 * It exits with the app's exit status, or, when it cannot start the app,
 * with a status from sysexits(3) (launcher.h).
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

/* As in Ruby's main.c (line 35 at v4.0.9): lets the VM declare any
 * globals it needs. */
RUBY_GLOBAL_SETUP

extern char **environ;

/* The launcher's file name, for messages. Set once in main. */
static const char *program_name = "launcher";

/*
 * Prints "NAME: message" to standard error and exits with status, as
 * Ruby's own "ruby: message" does. A person who runs an app never asked
 * for Ruby, so messages name the app, not Ruby (ADR 002).
 */
static void fail_with(int status, const char *format, ...) __attribute__((format(printf, 2, 3), noreturn));

static void
fail_with(int status, const char *format, ...)
{
    va_list arguments;

    fprintf(stderr, "%s: ", program_name);
    va_start(arguments, format);
    vfprintf(stderr, format, arguments);
    va_end(arguments);
    fputc('\n', stderr);
    exit(status);
}

#define fail(...) fail_with(FLEDGE_EXIT_SOFTWARE, __VA_ARGS__)

/*
 * The variables scrub_environment set aside, as "NAME=value" copies, for
 * restore_environment to put back.
 */
static char **set_aside;
static size_t set_aside_count;

/*
 * Removes every variable scrub.c names (RUBYOPT, RUBYLIB, GEM_HOME,
 * BUNDLE_GEMFILE, and the rest), keeping a copy of each. unsetenv
 * rearranges environ, so the scan starts over after each removal;
 * environments are small.
 */
static void
scrub_environment(void)
{
    int removed;

    do {
        removed = 0;
        for (char **entry = environ; entry != NULL && *entry != NULL; entry++) {
            if (!fledge_is_scrubbed(*entry, 0)) continue;

            char **grown = realloc(set_aside, (set_aside_count + 1) * sizeof *set_aside);
            if (grown == NULL) fail("out of memory");
            set_aside = grown;
            set_aside[set_aside_count] = strdup(*entry);
            if (set_aside[set_aside_count] == NULL) fail("out of memory");
            set_aside_count++;

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

/*
 * Forgets the variables scrub_environment set aside, once they are back.
 */
static void
forget_set_aside(void)
{
    for (size_t index = 0; index < set_aside_count; index++) free(set_aside[index]);
    free(set_aside);
    set_aside = NULL;
    set_aside_count = 0;
}

/*
 * Puts back every variable scrub_environment set aside, with its
 * original value, for an app without a Gemfile, whose boot sets none of
 * them. Ruby's ENV reads the process's environment on every access
 * (hash.c, env_fetch and getenv), so the app's ENV, and every process it
 * starts, see them. Ruby's own gem_prelude.rb does the same with
 * BUNDLER_SETUP: it removes the variable while RubyGems loads and puts
 * it back afterwards.
 */
static void
restore_environment(void)
{
    for (size_t index = 0; index < set_aside_count; index++) {
        char *entry = set_aside[index];
        char *equals = strchr(entry, '=');

        if (equals != NULL) {
            *equals = '\0';
            if (getenv(entry) == NULL && setenv(entry, equals + 1, 1) != 0) {
                fail("could not restore %s: %s", entry, strerror(errno));
            }
            *equals = '=';
        }
    }
    forget_set_aside();
}

/*
 * Puts back every variable scrub_environment set aside for an app with a
 * Gemfile, once Bundler has set up its gems, beneath Bundler's own
 * settings, as bundle exec would have composed them over the person's
 * environment, and records the person's environment as the one Bundler
 * started from (bundler.c; ADR 005, section 5).
 */
static void
bundle_environment(void)
{
    size_t length = 0;

    for (size_t index = 0; index < set_aside_count; index++) length += strlen(set_aside[index]) + 1;

    char *variables = malloc(length + 1);
    if (variables == NULL) fail("out of memory");
    char *next = variables;
    for (size_t index = 0; index < set_aside_count; index++) {
        size_t size = strlen(set_aside[index]) + 1;
        memcpy(next, set_aside[index], size);
        next += size;
    }

    char *code = fledge_bundle_environment_code(variables, length);
    free(variables);
    if (code == NULL) fail("out of memory");

    int state = 0;
    rb_eval_string_protect(code, &state);
    free(code);
    if (state != 0) fail("could not set up this app's environment");
    forget_set_aside();
}

/*
 * Has RubyGems work out its gem paths now, from the environment Ruby
 * booted with, before restore_environment puts GEM_HOME and GEM_PATH
 * back. Gem.paths reads them once and keeps the answer (rubygems.rb,
 * Gem.paths, at Ruby 4.0.9), so the app's gems stay the runtime's even
 * when the person has GEM_HOME set; a child Ruby the app starts still
 * reads the person's own.
 */
static void
pin_rubygems(void)
{
    int state = 0;

    rb_eval_string_protect("Gem.paths if defined?(Gem.paths)", &state);
    if (state != 0) fail("could not start RubyGems");
}

/* The folder this program lives in, and what its fledge.cfg says. */
static char root[PATH_MAX];
static struct fledge_config app_config;

/*
 * The Ruby that loads Bundler, and that has Bundler set up the app's
 * gems, by their paths in Ruby's own library, as bundle exec's
 * RUBYOPT=-r.../bundler/setup does (bundler/shared_helpers.rb,
 * set_rubyopt): required by name, RubyGems would activate the bundler gem
 * first, loading what bundle exec does not. The second prints what went
 * wrong when it cannot. bundler/setup prints its
 * own message and exits when standard output is a terminal; otherwise it
 * raises, quietly.
 */
static const char require_bundler[] = "require File.join(RbConfig::CONFIG['rubylibdir'], 'bundler')";
static const char bundler_setup[] = "begin\n"
                                    "  require File.join(RbConfig::CONFIG['rubylibdir'], 'bundler/setup')\n"
                                    "rescue StandardError => e\n"
                                    "  $stderr.puts(e.message)\n"
                                    "  raise\n"
                                    "end\n";

/*
 * Has Bundler set up the gems of the app's Gemfile, which fledge build
 * installed into the runtime's gem folder, as bundle exec would before
 * running ENTRY (ADR 005). The person's own Bundler settings are still
 * set aside: BUNDLE_GEMFILE names the app's Gemfile, and
 * BUNDLE_USER_CONFIG names the app's own .bundle/config, which fledge
 * build wrote, in place of ~/.bundle/config, so nothing of the person's
 * changes which gems load. Bundler is required first, so the environment
 * it records as the one it started from (Bundler.original_env) is the one
 * Ruby booted with, without the launcher's two variables, which
 * bundle_environment then completes with the person's own.
 */
static void
setup_bundler(void)
{
    static char gemfile[PATH_MAX];
    static char settings[PATH_MAX];
    int gemfile_length = snprintf(gemfile, sizeof gemfile, "%s/app/%s", root, app_config.gemfile);
    int settings_length = snprintf(settings, sizeof settings, "%s/app/.bundle/config", root);
    int state = 0;

    if (gemfile_length < 0 || (size_t)gemfile_length >= sizeof gemfile || settings_length < 0 ||
        (size_t)settings_length >= sizeof settings) {
        fail("the path to this app is too long");
    }
    rb_eval_string_protect(require_bundler, &state);
    if (state != 0) fail("could not start Bundler");
    if (setenv("BUNDLE_GEMFILE", gemfile, 1) != 0 || setenv("BUNDLE_USER_CONFIG", settings, 1) != 0) {
        fail("could not set up Bundler: %s", strerror(errno));
    }
    rb_eval_string_protect(bundler_setup, &state);
    if (state != 0) fail("could not set up this app's gems");
    if (unsetenv("BUNDLE_USER_CONFIG") != 0) fail("could not clear the environment: %s", strerror(errno));
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
 * as a bin or lib folder.
 */
static void
find_root(size_t size)
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
    /*
     * SPDX-SnippetBegin
     * SPDX-License-Identifier: Ruby OR BSD-2-Clause
     * SPDX-SnippetCopyrightText: 1993-2007 Yukihiro Matsumoto
     * SPDX-SnippetComment: The test of ruby_init_loadpath in ruby.c
     *   (lines 710 to 720) at Ruby v4.0.9 (3e93b23afc): "/bin" matched in
     *   any case, "/lib" exactly.
     */
    if (strcasecmp(folder, "bin") == 0 || strcmp(folder, "lib") == 0) {
        fail("this app cannot run from a folder named \"%s\"; rename the folder or move the app out of it", folder);
    }
    /* SPDX-SnippetEnd */
}

/*
 * Reads ROOT/fledge.cfg into app_config (config.c). A missing file is a
 * missing input, as a missing ENTRY is (EX_NOINPUT); one that cannot be
 * read or says something wrong is a damaged app.
 */
static void
read_config(void)
{
    static char path[PATH_MAX];
    static char text[65536];
    int length = snprintf(path, sizeof path, "%s/%s", root, FLEDGE_CONFIG);
    const char *problem = "is unreadable";

    if (length < 0 || (size_t)length >= sizeof path) fail("the path to this app is too long");

    FILE *file = fopen(path, "rb");
    if (file == NULL) {
        if (errno == ENOENT) fail_with(FLEDGE_EXIT_NO_APP, "this app is incomplete: %s is missing", path);
        fail("could not read %s: %s", path, strerror(errno));
    }
    size_t size = fread(text, 1, sizeof text - 1, file);
    int unreadable = ferror(file);
    fclose(file);
    if (unreadable) fail("could not read %s", path);
    if (size == sizeof text - 1 || memchr(text, '\0', size) != NULL)
        fail("this app is damaged: %s is not a fledge.cfg", path);
    text[size] = '\0';
    if (fledge_parse_config(text, &app_config, &problem) != 0) fail("this app is damaged: %s %s", path, problem);
}

/* Ruby's argument vector, built in main and handed to ruby_options. */
static char **ruby_argv;
static int ruby_argc;

/*
 * SPDX-SnippetBegin
 * SPDX-License-Identifier: Ruby OR BSD-2-Clause
 * SPDX-SnippetCopyrightText: 1993-2007 Yukihiro Matsumoto
 * SPDX-SnippetComment: rb_main, adapted from Ruby's main.c (lines 37 to
 *   43) at Ruby v4.0.9 (3e93b23afc), as Lota's launcher spike first did
 *   (setdef/lota, ADR 002), with pin_rubygems, setup_bundler,
 *   bundle_environment, and restore_environment between ruby_options and
 *   ruby_run_node.
 */
static int
run_ruby(int argc, char **argv)
{
    RUBY_INIT_STACK;
    ruby_init();
    void *node = ruby_options(argc, argv);
    if (ruby_executable_node(node, NULL)) {
        pin_rubygems();
        if (app_config.gemfile != NULL) {
            setup_bundler();
            pin_rubygems();
            bundle_environment();
        }
    }
    restore_environment();
    return ruby_run_node(node);
}
/* SPDX-SnippetEnd */

/*
 * Builds the arguments Ruby sees. argv[0] stays the very pointer
 * ruby_sysinit recorded: on Linux, ruby.c recognizes the program that
 * holds libruby by comparing dladdr's file name with that pointer
 * (ruby.c line 647 at Ruby 4.0.9), and only then reads /proc/self/exe,
 * so a launcher found on PATH by its bare name still finds its root.
 */
static void
build_ruby_arguments(int argc, char **argv)
{
    static char entry[PATH_MAX];
    int entry_length = snprintf(entry, sizeof entry, "%s/app/%s", root, app_config.entry);

    if (entry_length < 0 || (size_t)entry_length >= sizeof entry) fail("the path to this app is too long");

    struct stat status;
    if (stat(entry, &status) != 0 || !S_ISREG(status.st_mode)) {
        fail_with(FLEDGE_EXIT_NO_APP, "this app is incomplete: %s is missing", entry);
    }

    static char disable_rubyopt[] = "--disable=rubyopt";
    static char end_of_options[] = "--";
    char *before_app_arguments[] = {argv[0], disable_rubyopt, end_of_options, entry};
    size_t fixed = sizeof before_app_arguments / sizeof before_app_arguments[0];
    size_t count = fixed + (size_t)(argc > 1 ? argc - 1 : 0);

    ruby_argv = calloc(count + 1, sizeof *ruby_argv);
    if (ruby_argv == NULL) fail("out of memory");
    memcpy(ruby_argv, before_app_arguments, sizeof before_app_arguments);
    for (int index = 1; index < argc; index++) ruby_argv[fixed + (size_t)index - 1] = argv[index];
    ruby_argc = (int)count;
}

/*
 * SPDX-SnippetBegin
 * SPDX-License-Identifier: Ruby OR BSD-2-Clause
 * SPDX-SnippetCopyrightText: 1993-2007 Yukihiro Matsumoto
 * SPDX-SnippetComment: main, adapted from Ruby's main.c (lines 51 to 63)
 *   at Ruby v4.0.9 (3e93b23afc), with the launcher's own steps before
 *   ruby_sysinit.
 */
int
main(int argc, char **argv)
{
    find_root(sizeof root);
    read_config();
    scrub_environment();
    coerce_locale();

    ruby_sysinit(&argc, &argv);
    build_ruby_arguments(argc, argv);
    return ruby_start_main(run_ruby, ruby_argc, ruby_argv);
}
/* SPDX-SnippetEnd */
