/*
 * SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */

/*
 * Finds the launcher on macOS.
 *
 * dyld records the path the executable was loaded from, which
 * _NSGetExecutablePath returns (dyld(3)). That path may still go
 * through symlinks, such as a link someone put on their PATH, so
 * realpath resolves it to the runtime folder the file really lives in.
 */

#include "launcher.h"

#include <errno.h>
#include <limits.h>
#include <mach-o/dyld.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

int
fledge_executable_path(char *out, size_t size)
{
    char loaded[PATH_MAX];
    uint32_t loaded_size = sizeof loaded;
    char resolved[PATH_MAX];

    if (_NSGetExecutablePath(loaded, &loaded_size) != 0) {
        errno = ENAMETOOLONG;
        return -1;
    }
    if (realpath(loaded, resolved) == NULL) return -1;
    if (strlen(resolved) >= size) {
        errno = ENAMETOOLONG;
        return -1;
    }
    strcpy(out, resolved);
    return 0;
}
