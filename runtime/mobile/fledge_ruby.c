/*
 * SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */

/*
 * fledge_ruby_run (fledge_ruby.h): Ruby started in a phone app as
 * Fledge's desktop launcher starts it (runtime/launcher/unix.c), which
 * follows Ruby's own main.c at 4.0.9: the locale, ruby_sysinit, then
 * ruby_start_main, whose callback runs RUBY_INIT_STACK, ruby_init, and
 * ruby_run_node(ruby_options(...)), with the arguments
 *
 *   ruby --disable=rubyopt -- SCRIPT ARGS
 *
 * which is what ruby SCRIPT ARGS does with no RUBYOPT (ADR 003): no -I,
 * so the app loads its own files with require_relative, and no --yjit.
 *
 * What differs from the desktop launcher is what a phone needs:
 *
 *   - Ruby's prefix is the root the host names. The runtimes build Ruby
 *     with --enable-load-relative, and Ruby derives its prefix from the
 *     path of the file that holds libruby, which on Android is a folder
 *     of native libraries alone; the runtimes' Ruby has
 *     ruby_embed_libruby_path for an embedder to name that path instead
 *     (tasks/runtime_builder/ruby_source.rb, RubySource.ruby_c). Ruby
 *     strips the file's name and a lib folder from it, so ROOT/lib/libruby
 *     makes ROOT the prefix.
 *   - OpenSSL is told where the runtime's CA certificates are, through
 *     the SSL_CERT_FILE it reads itself, since its compiled-in folder is
 *     the build machine's; desktop runtimes get the same file from
 *     rv-ruby, whose OpenSSL finds it beside Ruby. On Android, OpenSSL
 *     reads no environment variable in an app, so android.c answers for
 *     its default file instead (fledge_ruby_certificates).
 *   - Nothing is set aside from the environment: iOS and Android start
 *     an app with their own environment, which no person sets, so there
 *     is no RUBYOPT or GEM_HOME of a person's own to hide (ADR 011,
 *     section 6).
 */

#include "fledge_ruby.h"
#include "launcher.h"
#include "mobile.h"

#include <ruby.h>

#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

/* The runtimes' edit to ruby.c (RubySource.ruby_c). */
extern const char *ruby_embed_libruby_path;

static int started;
static const char *found_certificates;

const char *
fledge_ruby_certificates(void)
{
    return found_certificates;
}

/*
 * SPDX-SnippetBegin
 * SPDX-License-Identifier: Ruby OR BSD-2-Clause
 * SPDX-SnippetCopyrightText: 1993-2007 Yukihiro Matsumoto
 * SPDX-SnippetComment: rb_main, from Ruby's main.c (lines 37 to 43) at
 *   Ruby v4.0.9 (3e93b23afc).
 */
static int
run_ruby(int argc, char **argv)
{
    RUBY_INIT_STACK;
    ruby_init();
    return ruby_run_node(ruby_options(argc, argv));
}
/* SPDX-SnippetEnd */

/* Writes root and then suffix into path, which holds PATH_MAX bytes. */
static int
join(char *path, const char *root, const char *suffix)
{
    int length = snprintf(path, PATH_MAX, "%s%s", root, suffix);

    return length >= 0 && length < PATH_MAX ? 0 : -1;
}

int
fledge_ruby_run(const char *root, const char *script, int argc, char *const *argv)
{
    static char libruby[PATH_MAX];
    static char certificates[PATH_MAX];
    static char disable_rubyopt[] = "--disable=rubyopt";
    static char end_of_options[] = "--";
    static char program[] = "ruby";

    if (started) {
        fputs("fledge_ruby_run: Ruby has already run in this process, and runs only once\n", stderr);
        return FLEDGE_RUBY_SOFTWARE;
    }
    started = 1;
    if (join(libruby, root, "/lib/libruby") != 0 || join(certificates, root, "/libexec/cert.pem") != 0) {
        fputs("fledge_ruby_run: the path to Ruby is too long\n", stderr);
        return FLEDGE_RUBY_SOFTWARE;
    }
    if (access(certificates, R_OK) == 0) {
        found_certificates = certificates;
        setenv("SSL_CERT_FILE", certificates, 0);
    }
    fledge_coerce_locale();
    ruby_embed_libruby_path = libruby;

    size_t count = 4 + (size_t)(argc > 0 ? argc : 0);
    char **ruby_argv = calloc(count + 1, sizeof *ruby_argv);
    char *entry = strdup(script);
    if (ruby_argv == NULL || entry == NULL) {
        fputs("fledge_ruby_run: out of memory\n", stderr);
        free(ruby_argv);
        free(entry);
        return FLEDGE_RUBY_SOFTWARE;
    }
    ruby_argv[0] = program;
    ruby_argv[1] = disable_rubyopt;
    ruby_argv[2] = end_of_options;
    ruby_argv[3] = entry;
    for (size_t index = 4; index < count; index++) ruby_argv[index] = argv[index - 4];

    /*
     * SPDX-SnippetBegin
     * SPDX-License-Identifier: Ruby OR BSD-2-Clause
     * SPDX-SnippetCopyrightText: 1993-2007 Yukihiro Matsumoto
     * SPDX-SnippetComment: The end of main, from Ruby's main.c (lines 61
     *   to 62) at Ruby v4.0.9 (3e93b23afc).
     */
    int ruby_argc = (int)count;
    ruby_sysinit(&ruby_argc, &ruby_argv);
    return ruby_start_main(run_ruby, ruby_argc, ruby_argv);
    /* SPDX-SnippetEnd */
}
