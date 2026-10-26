/*
 * SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */

/*
 * What the launcher asks of each operating system.
 *
 * The launcher is one program per platform family. unix.c holds what
 * macOS and Linux share: the environment scrub, the locale, and the
 * hand-off to Ruby. Each operating system answers the one question
 * POSIX cannot: "where is the file I am running from?" darwin.c answers
 * it with _NSGetExecutablePath, linux.c with /proc/self/exe. A Windows
 * launcher will need its own entry point (wmain, wide-character paths,
 * GetModuleFileNameW), so it gets a file of its own rather than a branch
 * here.
 */

#ifndef FLEDGE_LAUNCHER_H
#define FLEDGE_LAUNCHER_H

#include <stddef.h>

/*
 * Writes the absolute, symlink-free path of the running executable into
 * out, which holds size bytes. Returns 0, or -1 with errno set.
 */
int fledge_executable_path(char *out, size_t size);

#endif
