/*
 * SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
 * SPDX-License-Identifier: MIT
 */

/*
 * What the launcher's files share.
 *
 * The launcher is one program per platform family. unix.c holds what
 * macOS and Linux share: the locale, and the hand-off to a Ruby linked
 * into the launcher. Each of them answers the one question POSIX
 * cannot: "where is the file I am running from?" darwin.c answers it
 * with _NSGetExecutablePath, linux.c with /proc/self/exe. windows.c is
 * the whole launcher on Windows, where everything else differs too: a
 * wide-character entry point, Ruby in a DLL loaded at run time, and an
 * environment kept in two copies. scrub.c holds one rule every
 * operating system shares: which variables a person's own Ruby may not
 * pass to an app. config.c holds another: how to read fledge.cfg, which
 * says what the app runs. bundler.c holds a third: how an app with a
 * Gemfile gets the Bundler and the environment bundle exec would give
 * it. locale.c holds
 * how macOS, Linux, and the mobile runtimes choose a UTF-8 locale, for
 * the launcher and for the runtime's bin/ruby (ruby_main.c) alike.
 * relaunch.c holds how bin/ruby hands an app's own program back to the
 * app's launcher.
 */

#ifndef FLEDGE_LAUNCHER_H
#define FLEDGE_LAUNCHER_H

#include <stddef.h>

/*
 * The exit statuses of a launcher that cannot start its app, from
 * sysexits(3) (ADR 002): EX_NOINPUT when the program the app runs, or the
 * fledge.cfg that names it, is missing, EX_OSFILE when a library the app's
 * gems load from the Linux distribution is not on the computer (ADR 030),
 * and EX_SOFTWARE when anything else about the app or its runtime is
 * broken. An app's own failures exit with
 * the app's status instead, as under ruby.
 */
enum { FLEDGE_EXIT_NO_APP = 66, FLEDGE_EXIT_SOFTWARE = 70, FLEDGE_EXIT_OSFILE = 72 };

/*
 * Whether the environment variable name (or "NAME=value" entry) is one
 * the launcher removes before Ruby starts (scrub.c). ignore_case is
 * nonzero on Windows, whose variable names ignore ASCII case.
 */
int fledge_is_scrubbed(const char *name, int ignore_case);

/*
 * The Ruby code that gives an app with a Gemfile bundle exec's
 * environment, built over the person's own (bundler.c), as a new
 * NUL-terminated string for rb_eval_string_protect. variables holds the
 * length bytes of the variables the launcher set aside, each "NAME=value"
 * followed by a NUL. Returns NULL when out of memory.
 */
char *fledge_bundle_environment_code(const char *variables, size_t length);

/*
 * Writes into code, which holds size bytes, the Ruby that requires
 * Bundler, when setup is 0, or that has it set up the app's gems, when
 * setup is 1, by their paths, as bundle exec's RUBYOPT requires
 * bundler/setup (bundler.c): the runtime's own Bundler when version is
 * NULL, and otherwise the Bundler of that version that fledge build
 * installed in the runtime's gem folder (ADR 063). Returns 0, or -1 when
 * the code does not fit.
 */
int fledge_bundler_code(char *code, size_t size, const char *version, int setup);

/* Room enough for the code fledge_bundler_code writes. */
#define FLEDGE_BUNDLER_CODE_MAX 2048

/* The file beside the launcher that says what the app runs (config.c). */
#define FLEDGE_CONFIG "fledge.cfg"

/* The longest identifier fledge.cfg may name: an AppUserModelID's limit. */
#define FLEDGE_IDENTIFIER_MAX 128

/*
 * What fledge.cfg says: the program to run, and the Gemfile to set up
 * first, or NULL for none, each relative to the app folder with / between
 * folders, the version of the Bundler that sets it up, or NULL for the
 * runtime's own, the app's reverse-DNS identifier, or NULL for none, and the
 * libraries its gems load from the Linux distribution, between spaces, or
 * NULL for none.
 */
struct fledge_config {
    const char *entry;
    const char *gemfile;
    const char *bundler;
    const char *identifier;
    const char *system_libraries;
};

/*
 * What fledge_parse_config returns when fledge.cfg holds a section for
 * each of several programs, and none for this one (ADR 024).
 */
enum { FLEDGE_CONFIG_NO_PROGRAM = 1 };

/*
 * Whether two program names are the same, as same_name compares them:
 * ignoring case, as the file systems of Windows and macOS do.
 */
typedef int (*fledge_same_name)(const char *one, const char *other);

/* The names compared byte by byte, ignoring ASCII case (config.c). */
int fledge_same_ascii_name(const char *one, const char *other);

/*
 * Reads fledge.cfg's NUL-terminated text, changing it in place, into
 * config, whose strings point into text. A file of several programs has
 * a section for each, headed [NAME]; this reads the one whose NAME is
 * program, as same_name compares them, or none when program is NULL.
 * Returns 0; FLEDGE_CONFIG_NO_PROGRAM when the file has sections and
 * none is program's; or -1 with problem set to what is wrong, as words
 * that follow "fledge.cfg ".
 */
int fledge_parse_config(char *text, const char *program, fledge_same_name same_name, struct fledge_config *config,
                        const char **problem);

#ifndef _WIN32
/*
 * Sets LC_CTYPE from the environment, as Ruby's main.c does, and turns a
 * bare C or POSIX locale into a UTF-8 one (locale.c).
 */
void fledge_coerce_locale(void);

/*
 * Writes the absolute, symlink-free path of the running executable into
 * out, which holds size bytes. Returns 0, or -1 with errno set.
 */
int fledge_executable_path(char *out, size_t size);

#ifdef __linux__
/*
 * Whether this computer's loader loads each of the libraries names lists,
 * between spaces, as it would for a gem's extension (linux.c). Returns 0,
 * or -1 with the first it could not load in library and the loader's
 * reason in reason, each NUL-terminated within size bytes.
 */
int fledge_find_system_libraries(const char *names, char *library, char *reason, size_t size);
#endif

/*
 * In the runtime's bin/ruby: when argv[1] is the program a launcher of
 * this app runs, runs that launcher in this process with the arguments
 * after it, and does not return; otherwise returns, and bin/ruby is
 * plain Ruby (relaunch.c).
 */
void fledge_relaunch(int argc, char **argv);
#endif

#endif
