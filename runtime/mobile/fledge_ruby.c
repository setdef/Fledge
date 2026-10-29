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
 *     section 6), and so nothing to pin RubyGems' paths against or to
 *     put back once Bundler is set up.
 *
 * fledge_ruby_run_app reads the fledge.cfg fledge build writes into an
 * app's root with the launcher's own reader (config.c), and for an app
 * with a Gemfile has Bundler set up its gems between ruby_options and
 * ruby_run_node, as the desktop launcher's setup_bundler does
 * (runtime/launcher/unix.c): BUNDLE_GEMFILE names the app's Gemfile, so
 * Bundler reads its settings from the app's .bundle/config beside it, and
 * bundler/setup, from Ruby's own library, sets ENV as bundle exec would
 * (Bundler::Runtime#setup, set_bundle_environment, at Bundler 4.0.20).
 */

#include "fledge_ruby.h"
#include "launcher.h"
#include "mobile.h"

#include <ruby.h>

#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

/* The runtimes' edit to ruby.c (RubySource.ruby_c). */
extern const char *ruby_embed_libruby_path;

static int started;
static const char *found_certificates;

/* The app's Gemfile, for fledge_ruby_run_app, or NULL. */
static const char *bundle_gemfile;

static const char require_bundler[] = "require File.join(RbConfig::CONFIG['rubylibdir'], 'bundler')";
static const char bundler_setup[] = "begin\n"
                                    "  require File.join(RbConfig::CONFIG['rubylibdir'], 'bundler/setup')\n"
                                    "rescue StandardError => e\n"
                                    "  $stderr.puts(e.message)\n"
                                    "  raise\n"
                                    "end\n";

const char *
fledge_ruby_certificates(void)
{
    return found_certificates;
}

/*
 * Has Bundler set up the gems of bundle_gemfile, and returns 0, or prints
 * why it could not and returns -1.
 */
static int
setup_bundler(void)
{
    int state = 0;

    rb_eval_string_protect(require_bundler, &state);
    if (state == 0 && setenv("BUNDLE_GEMFILE", bundle_gemfile, 1) != 0) state = -1;
    if (state == 0) rb_eval_string_protect(bundler_setup, &state);
    if (state == 0) return 0;
    rb_set_errinfo(Qnil);
    fputs("fledge_ruby_run_app: could not set up this app's gems\n", stderr);
    return -1;
}

/*
 * SPDX-SnippetBegin
 * SPDX-License-Identifier: Ruby OR BSD-2-Clause
 * SPDX-SnippetCopyrightText: 1993-2007 Yukihiro Matsumoto
 * SPDX-SnippetComment: rb_main, from Ruby's main.c (lines 37 to 43) at
 *   Ruby v4.0.9 (3e93b23afc), with setup_bundler between ruby_options and
 *   ruby_run_node, as in the desktop launcher's run_ruby.
 */
static int
run_ruby(int argc, char **argv)
{
    RUBY_INIT_STACK;
    ruby_init();
    void *node = ruby_options(argc, argv);
    if (bundle_gemfile != NULL && ruby_executable_node(node, NULL) && setup_bundler() != 0) {
        return ruby_cleanup(FLEDGE_RUBY_SOFTWARE);
    }
    return ruby_run_node(node);
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

/*
 * Reads root/fledge.cfg into config, whose strings point into text, a
 * buffer of size bytes. Returns 0, or prints why it could not and returns
 * the status fledge_ruby_run_app should.
 */
static int
read_config(const char *root, char *text, size_t size, struct fledge_config *config)
{
    char path[PATH_MAX];
    const char *problem = NULL;

    if (join(path, root, "/" FLEDGE_CONFIG) != 0) {
        fputs("fledge_ruby_run_app: the path to the app is too long\n", stderr);
        return FLEDGE_RUBY_SOFTWARE;
    }
    FILE *file = fopen(path, "rb");
    if (file == NULL) {
        fprintf(stderr, "fledge_ruby_run_app: this app is incomplete: %s is missing\n", path);
        return FLEDGE_RUBY_NO_APP;
    }
    size_t length = fread(text, 1, size - 1, file);
    int unreadable = ferror(file);
    fclose(file);
    if (unreadable || length == size - 1 || memchr(text, '\0', length) != NULL) {
        fprintf(stderr, "fledge_ruby_run_app: this app is damaged: %s is not a fledge.cfg\n", path);
        return FLEDGE_RUBY_SOFTWARE;
    }
    text[length] = '\0';
    if (fledge_parse_config(text, config, &problem) != 0) {
        fprintf(stderr, "fledge_ruby_run_app: this app is damaged: %s %s\n", path, problem);
        return FLEDGE_RUBY_SOFTWARE;
    }
    return 0;
}

int
fledge_ruby_run_app(const char *root, int argc, char *const *argv)
{
    static char text[4096];
    static char script[PATH_MAX];
    static char gemfile[PATH_MAX];
    struct fledge_config config;
    struct stat status;

    int problem = read_config(root, text, sizeof text, &config);
    if (problem != 0) return problem;
    if (snprintf(script, sizeof script, "%s/app/%s", root, config.entry) >= (int)sizeof script ||
        (config.gemfile != NULL &&
         snprintf(gemfile, sizeof gemfile, "%s/app/%s", root, config.gemfile) >= (int)sizeof gemfile)) {
        fputs("fledge_ruby_run_app: the path to the app is too long\n", stderr);
        return FLEDGE_RUBY_SOFTWARE;
    }
    if (stat(script, &status) != 0 || !S_ISREG(status.st_mode)) {
        fprintf(stderr, "fledge_ruby_run_app: this app is incomplete: %s is missing\n", script);
        return FLEDGE_RUBY_NO_APP;
    }
    if (config.gemfile != NULL) bundle_gemfile = gemfile;
    return fledge_ruby_run(root, script, argc, argv);
}
