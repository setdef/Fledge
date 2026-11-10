/*
 * SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
 * SPDX-License-Identifier: MIT
 */

/*
 * Finds the launcher on Linux.
 *
 * The kernel keeps /proc/self/exe as a link to the file the process
 * runs (proc(5)), whatever argv[0] says, whether the launcher was found
 * on PATH, run through a symlink, or run by a relative path. realpath
 * reads that link, so the result is the runtime folder the file really
 * lives in. Ruby's own ruby.c reads the same link to find its prefix
 * (runtime_libruby_path, ruby.c lines 648 to 651 at Ruby
 * 4.1.0-preview1).
 *
 * It also answers one question only Linux asks: whether this computer
 * has the libraries the app's gems load from the distribution, which
 * fledge.cfg lists (ADR 030). A gem's extension that needs one that is
 * missing fails when Ruby requires it, with a LoadError that names the
 * gem, so the launcher asks the loader first and names the library
 * instead. It asks in a child process, which dlopen(3)s each library and
 * exits, so that the app's own process loads nothing early and runs as
 * it would under ruby: a library's constructors run when the gem loads
 * it, as they would without Fledge.
 */

#include "launcher.h"

#include <dlfcn.h>
#include <errno.h>
#include <limits.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>

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

/*
 * In the child: dlopens each library names lists, and at the first that
 * fails writes its name, a newline, and dlerror's reason to out, then
 * exits 1; exits 0 when every one loads.
 */
static void load_each(const char *names, int out) __attribute__((noreturn));

static void
load_each(const char *names, int out)
{
    char name[NAME_MAX + 1];
    const char *start = names;

    while (*start != '\0') {
        const char *space = strchr(start, ' ');
        size_t length = space != NULL ? (size_t)(space - start) : strlen(start);

        if (length > NAME_MAX) length = NAME_MAX;
        memcpy(name, start, length);
        name[length] = '\0';
        if (dlopen(name, RTLD_LAZY | RTLD_LOCAL) == NULL) {
            const char *reason = dlerror();
            if (reason == NULL) reason = "it could not be loaded";
            if (write(out, name, length) < 0 || write(out, "\n", 1) < 0 || write(out, reason, strlen(reason)) < 0)
                _exit(1);
            _exit(1);
        }
        start = space != NULL ? space + 1 : start + length;
    }
    _exit(0);
}

/*
 * Copies text, up to its first newline or end, into out, which holds
 * size bytes, and returns what follows the newline.
 */
static const char *
copy_line(const char *text, char *out, size_t size)
{
    const char *newline = strchr(text, '\n');
    size_t length = newline != NULL ? (size_t)(newline - text) : strlen(text);

    if (length >= size) length = size - 1;
    memcpy(out, text, length);
    out[length] = '\0';
    return newline != NULL ? newline + 1 : text + strlen(text);
}

int
fledge_find_system_libraries(const char *names, char *library, char *reason, size_t size)
{
    int ends[2];
    char said[PATH_MAX * 2];
    size_t length = 0;
    int status = 0;

    /* A computer that cannot start the check is not refused: the app's
     * gems load their libraries as they would have. */
    if (pipe(ends) != 0) return 0;
    pid_t child = fork();
    if (child < 0) {
        close(ends[0]);
        close(ends[1]);
        return 0;
    }
    if (child == 0) {
        close(ends[0]);
        load_each(names, ends[1]);
    }
    close(ends[1]);
    for (;;) {
        ssize_t got = read(ends[0], said + length, sizeof said - 1 - length);
        if (got < 0 && errno == EINTR) continue;
        if (got <= 0) break;
        length += (size_t)got;
        if (length == sizeof said - 1) break;
    }
    close(ends[0]);
    said[length] = '\0';
    while (waitpid(child, &status, 0) < 0) {
        if (errno != EINTR) return 0;
    }
    if (WIFEXITED(status) && WEXITSTATUS(status) == 0) return 0;
    if (length == 0) return 0;

    copy_line(copy_line(said, library, size), reason, size);
    return -1;
}
