/*
 * SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */

/*
 * Finds the launcher on Linux.
 *
 * The kernel keeps /proc/self/exe as a link to the file the process
 * runs (proc(5)), whatever argv[0] says, whether the launcher was found
 * on PATH, run through a symlink, or run by a relative path. realpath
 * reads that link, so the result is the runtime folder the file really
 * lives in. Ruby's own ruby.c reads the same link to find its prefix
 * (runtime_libruby_path, ruby.c lines 646 to 649 at Ruby 4.0.9).
 */

#include "launcher.h"

#include <errno.h>
#include <limits.h>
#include <stdlib.h>
#include <string.h>

int
fledge_executable_path(char *out, size_t size)
{
    char resolved[PATH_MAX];

    if (realpath("/proc/self/exe", resolved) == NULL) return -1;
    if (strlen(resolved) >= size) {
        errno = ENAMETOOLONG;
        return -1;
    }
    strcpy(out, resolved);
    return 0;
}
