/*
 * SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later
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
 * Gemfile gets the environment bundle exec would give it.
 */

#ifndef FLEDGE_LAUNCHER_H
#define FLEDGE_LAUNCHER_H

#include <stddef.h>

/*
 * The exit statuses of a launcher that cannot start its app, from
 * sysexits(3) (ADR 002): EX_NOINPUT when the program the app runs, or the
 * fledge.cfg that names it, is missing, and EX_SOFTWARE when anything else
 * about the app or its runtime is broken. An app's own failures exit with
 * the app's status instead, as under ruby.
 */
enum { FLEDGE_EXIT_NO_APP = 66, FLEDGE_EXIT_SOFTWARE = 70 };

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

/* The file beside the launcher that says what the app runs (config.c). */
#define FLEDGE_CONFIG "fledge.cfg"

/*
 * What fledge.cfg says: the program to run, and the Gemfile to set up
 * first, or NULL for none, each relative to the app folder with / between
 * folders.
 */
struct fledge_config {
    const char *entry;
    const char *gemfile;
};

/*
 * Reads fledge.cfg's NUL-terminated text, changing it in place, into
 * config, whose strings point into text. Returns 0, or -1 with problem
 * set to what is wrong, as words that follow "fledge.cfg ".
 */
int fledge_parse_config(char *text, struct fledge_config *config, const char **problem);

#ifndef _WIN32
/*
 * Writes the absolute, symlink-free path of the running executable into
 * out, which holds size bytes. Returns 0, or -1 with errno set.
 */
int fledge_executable_path(char *out, size_t size);
#endif

#endif
