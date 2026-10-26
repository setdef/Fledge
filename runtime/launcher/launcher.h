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
 * environment kept in two copies. scrub.c holds the one rule every
 * operating system shares: which variables a person's own Ruby may not
 * pass to an app.
 */

#ifndef FLEDGE_LAUNCHER_H
#define FLEDGE_LAUNCHER_H

#include <stddef.h>

/*
 * The exit status for a runtime folder that cannot run, as sysexits(3)'s
 * EX_SOFTWARE. An app's own failures exit with the app's status instead.
 */
enum { FLEDGE_EXIT_BROKEN_RUNTIME = 70 };

/*
 * Whether the environment variable name (or "NAME=value" entry) is one
 * the launcher removes before Ruby starts (scrub.c). ignore_case is
 * nonzero on Windows, whose variable names ignore ASCII case.
 */
int fledge_is_scrubbed(const char *name, int ignore_case);

#ifndef _WIN32
/*
 * Writes the absolute, symlink-free path of the running executable into
 * out, which holds size bytes. Returns 0, or -1 with errno set.
 */
int fledge_executable_path(char *out, size_t size);
#endif

#endif
