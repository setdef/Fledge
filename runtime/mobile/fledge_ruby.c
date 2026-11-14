/*
 * SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
 * SPDX-License-Identifier: MIT
 */

/*
 * fledge_ruby_run (fledge_ruby.h): Ruby started in a phone app as
 * Fledge's desktop launcher starts it (runtime/launcher/unix.c), which
 * follows Ruby's own main.c at 4.1.0-preview1: the locale, ruby_sysinit,
 * then ruby_start_main, whose callback runs RUBY_INIT_STACK, ruby_init,
 * and ruby_run_node(ruby_options(...)), with the arguments
 *
 *   ruby --disable=rubyopt -- SCRIPT ARGS
 *
 * which is what ruby SCRIPT ARGS does with no RUBYOPT (ADR 081): no -I,
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
 *   - Nothing is added to the environment. OpenSSL finds the runtime's
 *     CA certificates as rv-ruby's, the desktops', finds them: openssl.rb
 *     names them in PORTABLE_RUBY_SSL_CERT_FILE as openssl loads, which
 *     the runtime's OpenSSL reads (tasks/runtime_builder/certificates.rb).
 *     On Android, OpenSSL reads no environment variable in an app, so
 *     android.c answers for its default file instead
 *     (fledge_ruby_certificates).
 *   - Nothing is set aside from the environment: iOS and Android start
 *     an app with their own environment, which no person sets, so there
 *     is no RUBYOPT or GEM_HOME of a person's own to hide (ADR 061),
 *     and so nothing to pin RubyGems' paths against or to
 *     put back once Bundler is set up.
 *   - On Android, bionic's fdsan warns once in logcat where it would
 *     end the process, so that Ruby's descriptors fail as on Linux
 *     (soften_fdsan).
 *
 * fledge_ruby_run_app reads the fledge.cfg fledge build writes into an
 * app's root with the launcher's own reader (config.c), and for an app
 * with a Gemfile has Bundler set up its gems between ruby_options and
 * ruby_run_node, as the desktop launcher's setup_bundler does
 * (runtime/launcher/unix.c): BUNDLE_GEMFILE names the app's Gemfile, so
 * Bundler takes its settings from the app's .bundle/config beside it,
 * through the environment (the launcher's bundler.c), and
 * bundler/setup, from Ruby's own library or from the gem of the Bundler
 * fledge.cfg names (the launcher's bundler.c; ADR 063), sets ENV as
 * bundle exec would (Bundler::Runtime#setup, set_bundle_environment, at
 * Bundler 4.0.20).
 *
 * fledge_ruby_main is the main function of the Android runtime's ruby
 * program, which RbConfig.ruby names in an app (ADR 083). It is what the
 * desktop's bin/ruby is (runtime/launcher/ruby_main.c): Ruby's main.c,
 * with the launcher's locale, and with the app's own program handed to
 * the app's way of starting, as fledge_relaunch hands it to the launcher
 * (ADR 096), here fledge_ruby_run_app in the program's own process. It
 * takes Ruby's arguments as they come, RUBYOPT included, as ruby does,
 * and leaves $stdout as Ruby sets it: a Ruby the app starts writes to
 * the standard output the app gives it, by default the app's own, the
 * log's pipe, and buffers a pipe as ruby does on a desktop.
 */

#include "fledge_ruby.h"
#include "launcher.h"
#include "mobile.h"

#include <ruby.h>
#include <ruby/io.h>

#include <errno.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

#ifdef __ANDROID__
#include <android/fdsan.h>
#include <dlfcn.h>
#endif

/* The runtimes' edit to ruby.c (RubySource.ruby_c). */
extern const char *ruby_embed_libruby_path;

/*
 * Ruby's registry of statically linked extensions, load.c at
 * 4.1.0-preview1 (line 1553): the one extinit.c fills for Ruby's own, by
 * the feature with its ".so", which require looks a name up in when it
 * finds no file (search_required, lines 1199 to 1218).
 */
void ruby_init_ext(const char *name, void (*init)(void));

/* An extension fledge_ruby_add_extension was told of. */
struct extension {
    char *feature;
    void (*init)(void);
};

static struct extension *extensions;
static size_t extension_count;
static int started;
static const char *found_certificates;

/* The app's Gemfile, for fledge_ruby_run_app, or NULL. */
static const char *bundle_gemfile;

/* The version of the Bundler fledge.cfg names, for fledge_ruby_run_app,
 * or NULL for the runtime's own (ADR 063). */
static const char *bundle_bundler;

const char *
fledge_ruby_certificates(void)
{
    return found_certificates;
}

/*
 * Has Bundler, bundle_bundler's or the runtime's own, set up the gems of
 * bundle_gemfile (the launcher's bundler.c), and returns 0, or prints why
 * it could not and returns -1.
 */
static int
setup_bundler(void)
{
    static char require_bundler[FLEDGE_BUNDLER_CODE_MAX];
    static char bundler_setup[FLEDGE_BUNDLER_CODE_MAX];
    int state = 0;

    if (fledge_bundler_code(require_bundler, sizeof require_bundler, bundle_bundler, 0) != 0 ||
        fledge_bundler_code(bundler_setup, sizeof bundler_setup, bundle_bundler, 1) != 0) {
        state = -1;
    }
    if (state == 0) rb_eval_string_protect(require_bundler, &state);
    if (state == 0 && setenv("BUNDLE_GEMFILE", bundle_gemfile, 1) != 0) state = -1;
    if (state == 0) rb_eval_string_protect(bundler_setup, &state);
    if (state == 0) return 0;
    rb_set_errinfo(Qnil);
    fputs("fledge_ruby_run_app: could not set up this app's gems\n", stderr);
    return -1;
}

int
fledge_ruby_add_extension(const char *feature, void (*init)(void))
{
    if (feature == NULL || feature[0] == '\0' || init == NULL) {
        errno = EINVAL;
        return -1;
    }
    if (started) {
        errno = EALREADY;
        return -1;
    }
    struct extension *grown = realloc(extensions, (extension_count + 1) * sizeof *extensions);
    if (grown == NULL) return -1;
    extensions = grown;
    /* Ruby keeps the name it is given, so it is never freed; ".so" as extinit.c writes it. */
    size_t length = strlen(feature);
    char *name = malloc(length + sizeof ".so");
    if (name == NULL) return -1;
    memcpy(name, feature, length);
    memcpy(name + length, ".so", sizeof ".so");
    extensions[extension_count].feature = name;
    extensions[extension_count].init = init;
    extension_count++;
    return 0;
}

/*
 * Hands Ruby every extension fledge_ruby_add_extension was told of, as
 * Init_ext hands it Ruby's own (Ruby's ruby_opt_init calls Init_ext once
 * the VM is up, ruby.c line 1824 at 4.1.0-preview1): after ruby_options,
 * so that the main namespace they register in exists, and before the
 * program or Bundler's setup requires any of them.
 */
static void
register_extensions(void)
{
    for (size_t index = 0; index < extension_count; index++) {
        ruby_init_ext(extensions[index].feature, extensions[index].init);
    }
}

/*
 * Has Ruby write each line to standard output as it is printed, as it
 * does on a terminal, when standard output is not one: on a phone it is
 * the pipe fledge_ruby_forward_output reads into the system log, or a
 * developer tool's, and whoever reads it is watching the app run. Ruby
 * writes through to a terminal but buffers a pipe until its buffer fills
 * or the program ends (io.c, io_binwrite_requires_flush_write, lines
 * 1941 to 1954 at 4.1.0-preview1), so without this an app's lines
 * reached the log only when it ended. Briefcase's iOS host unbuffers
 * Python's streams so that "output appears in the log immediately"
 * (config.buffered_stdio = 0); standard error is in sync mode already
 * (rb_io_prep_stderr).
 *
 * It is done as a terminal does it: $stdout's IO gets the FMODE_TTY
 * that io_check_tty gives an IO on a terminal (io.c, line 7386), which
 * every write reads (lines 1945 and 2326), and which nothing else reads
 * for a descriptor other than standard input. So $stdout.sync stays
 * false, as under ruby main.rb, and $stdout.tty?, which asks isatty of
 * the descriptor itself (rb_io_isatty, line 5547), stays false, so no
 * library sends a terminal's escape codes into the log. Ruby's header
 * deprecates the field, with no other way to set it, and says of
 * FMODE_TTY "You cannot change this" (include/ruby/io.h, lines 188 to
 * 191), since Ruby sets it once, as it opens the IO: it is set once
 * here too, before the program has written anything. On a terminal it
 * is left as it is.
 */
static void
write_lines_as_printed(void)
{
    rb_io_t *stdout_io;

    if (isatty(STDOUT_FILENO)) return;
    GetOpenFile(rb_stdout, stdout_io);
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wdeprecated-declarations"
    stdout_io->mode |= FMODE_TTY;
#pragma GCC diagnostic pop
}

/*
 * SPDX-SnippetBegin
 * SPDX-License-Identifier: Ruby OR BSD-2-Clause
 * SPDX-SnippetCopyrightText: 1993-2007 Yukihiro Matsumoto
 * SPDX-SnippetComment: rb_main, from Ruby's main.c (lines 37 to 43) at
 *   Ruby v4.1.0-preview1 (2d08b5f42f), with setup_bundler between
 *   ruby_options and ruby_run_node, as in the desktop launcher's
 *   run_ruby, and standard output written through before either.
 */
static int
run_ruby(int argc, char **argv)
{
    RUBY_INIT_STACK;
    ruby_init();
    void *node = ruby_options(argc, argv);
    write_lines_as_printed();
    register_extensions();
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

/*
 * On Android from API 30, lowers fdsan, bionic's file descriptor
 * sanitizer, from ending the process to warning once in logcat, the
 * level API 29 had (bionic's docs/fdsan.md, lines 5 to 7 and 56 to 66,
 * at 731631f). fdsan ends the process when a descriptor one owner has
 * tagged is tagged or closed as another's (libc/bionic/fdsan.cpp, lines
 * 134 to 177 and 299 to 330), which Ruby does with no bug of the app's:
 * Dir.for_fd hands a Dir's descriptor to fdopendir, which tags it as its
 * own DIR's (libc/bionic/dirent.cpp, lines 69 to 99), so a second Dir on
 * one descriptor, which glibc and every desktop allow, ended the app
 * where ruby main.rb raises Errno::EBADF at the second close. A level
 * the host or debug.fdsan set lower stays. The functions are looked up,
 * since they are API 29's and the runtime runs from API 26, where
 * nothing checks descriptors.
 */
static void
soften_fdsan(void)
{
#ifdef __ANDROID__
    enum android_fdsan_error_level (*get_level)(void) =
        (enum android_fdsan_error_level (*)(void))dlsym(RTLD_DEFAULT, "android_fdsan_get_error_level");
    enum android_fdsan_error_level (*set_level)(enum android_fdsan_error_level) =
        (enum android_fdsan_error_level (*)(enum android_fdsan_error_level))dlsym(RTLD_DEFAULT,
                                                                                  "android_fdsan_set_error_level");

    if (get_level != NULL && set_level != NULL && get_level() == ANDROID_FDSAN_ERROR_LEVEL_FATAL) {
        set_level(ANDROID_FDSAN_ERROR_LEVEL_WARN_ONCE);
    }
#endif
}

/*
 * Readies this process for Ruby with its prefix at root: where the
 * runtime's CA certificates are, for android.c, the locale, and the path
 * Ruby derives its prefix from. Returns 0, or prints why it could not,
 * after caller's name, and returns FLEDGE_RUBY_SOFTWARE.
 */
static int
prepare(const char *root, const char *caller)
{
    static char libruby[PATH_MAX];
    static char certificates[PATH_MAX];

    if (started) {
        fprintf(stderr, "%s: Ruby has already run in this process, and runs only once\n", caller);
        return FLEDGE_RUBY_SOFTWARE;
    }
    started = 1;
    if (join(libruby, root, "/lib/libruby") != 0 || join(certificates, root, "/libexec/cert.pem") != 0) {
        fprintf(stderr, "%s: the path to Ruby is too long\n", caller);
        return FLEDGE_RUBY_SOFTWARE;
    }
    if (access(certificates, R_OK) == 0) found_certificates = certificates;
    soften_fdsan();
    fledge_coerce_locale();
    ruby_embed_libruby_path = libruby;
    return 0;
}

int
fledge_ruby_run(const char *root, const char *script, int argc, char *const *argv)
{
    static char disable_rubyopt[] = "--disable=rubyopt";
    static char end_of_options[] = "--";
    static char program[] = "ruby";

    if (prepare(root, "fledge_ruby_run") != 0) return FLEDGE_RUBY_SOFTWARE;
    fledge_ruby_link_program(root);

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
     *   to 62) at Ruby v4.1.0-preview1 (2d08b5f42f).
     */
    int ruby_argc = (int)count;
    ruby_sysinit(&ruby_argc, &ruby_argv);
    return ruby_start_main(run_ruby, ruby_argc, ruby_argv);
    /* SPDX-SnippetEnd */
}

/*
 * Reads root/fledge.cfg into config, whose strings point into text, a
 * buffer of size bytes. Returns 0, or the status fledge_ruby_run_app
 * should, after printing why unless quiet is nonzero.
 */
static int
read_config(const char *root, char *text, size_t size, struct fledge_config *config, int quiet)
{
    char path[PATH_MAX];
    const char *problem = NULL;

    if (join(path, root, "/" FLEDGE_CONFIG) != 0) {
        if (!quiet) fputs("fledge_ruby_run_app: the path to the app is too long\n", stderr);
        return FLEDGE_RUBY_SOFTWARE;
    }
    FILE *file = fopen(path, "rb");
    if (file == NULL) {
        if (!quiet) fprintf(stderr, "fledge_ruby_run_app: this app is incomplete: %s is missing\n", path);
        return FLEDGE_RUBY_NO_APP;
    }
    size_t length = fread(text, 1, size - 1, file);
    int unreadable = ferror(file);
    fclose(file);
    if (unreadable || length == size - 1 || memchr(text, '\0', length) != NULL) {
        if (!quiet) fprintf(stderr, "fledge_ruby_run_app: this app is damaged: %s is not a fledge.cfg\n", path);
        return FLEDGE_RUBY_SOFTWARE;
    }
    text[length] = '\0';
    /* fledge build gives a phone one program, so a file of several
     * programs' sections (ADR 024) is one this app was not built with. */
    int parsed = fledge_parse_config(text, NULL, fledge_same_ascii_name, config, &problem);
    if (parsed == FLEDGE_CONFIG_NO_PROGRAM) problem = "has several programs' sections, and a phone's app runs one";
    if (parsed != 0) {
        if (!quiet) fprintf(stderr, "fledge_ruby_run_app: this app is damaged: %s %s\n", path, problem);
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

    int problem = read_config(root, text, sizeof text, &config, 0);
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
    bundle_bundler = config.bundler;
    return fledge_ruby_run(root, script, argc, argv);
}

/*
 * SPDX-SnippetBegin
 * SPDX-License-Identifier: Ruby OR BSD-2-Clause
 * SPDX-SnippetCopyrightText: 1993-2007 Yukihiro Matsumoto
 * SPDX-SnippetComment: rb_main, from Ruby's main.c (lines 37 to 43) at
 *   Ruby v4.1.0-preview1 (2d08b5f42f), with the extensions an app links
 *   registered between ruby_options and ruby_run_node.
 */
static int
run_program(int argc, char **argv)
{
    RUBY_INIT_STACK;
    ruby_init();
    void *node = ruby_options(argc, argv);
    register_extensions();
    return ruby_run_node(node);
}
/* SPDX-SnippetEnd */

/*
 * Whether script, the first argument of the runtime's ruby program, is
 * the program root/fledge.cfg names, the one the host runs. Files are
 * compared as the system sees them, by device and inode, as the
 * desktop's fledge_relaunch compares them (runtime/launcher/relaunch.c),
 * so a relative path or a link names the same program. An option, a
 * file that is not the app's program, and an app whose fledge.cfg is
 * missing or damaged are not.
 */
static int
runs_app(const char *root, const char *script)
{
    static char text[4096];
    char entry_path[PATH_MAX];
    struct fledge_config config;
    struct stat given;
    struct stat entry;

    if (script[0] == '-' || script[0] == '\0' || stat(script, &given) != 0 || !S_ISREG(given.st_mode)) return 0;
    if (read_config(root, text, sizeof text, &config, 1) != 0) return 0;
    if (snprintf(entry_path, sizeof entry_path, "%s/app/%s", root, config.entry) >= (int)sizeof entry_path) return 0;
    return stat(entry_path, &entry) == 0 && entry.st_dev == given.st_dev && entry.st_ino == given.st_ino;
}

int
fledge_ruby_main(const char *root, int argc, char **argv)
{
    if (argc >= 2 && runs_app(root, argv[1])) return fledge_ruby_run_app(root, argc - 2, argv + 2);
    if (prepare(root, "ruby") != 0) return FLEDGE_RUBY_SOFTWARE;

    /*
     * SPDX-SnippetBegin
     * SPDX-License-Identifier: Ruby OR BSD-2-Clause
     * SPDX-SnippetCopyrightText: 1993-2007 Yukihiro Matsumoto
     * SPDX-SnippetComment: The end of main, from Ruby's main.c (lines 61
     *   to 62) at Ruby v4.1.0-preview1 (2d08b5f42f).
     */
    ruby_sysinit(&argc, &argv);
    return ruby_start_main(run_program, argc, argv);
    /* SPDX-SnippetEnd */
}
