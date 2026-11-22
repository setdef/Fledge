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
 * fledge.cfg lists. A gem's extension that needs one that is
 * missing fails when Ruby requires it, with a LoadError that names the
 * gem, so the launcher asks the loader first and names the library
 * instead. It asks in a child process, which dlopen(3)s each library and
 * exits, so that the app's own process loads nothing early and runs as
 * it would under ruby: a library's constructors run when the gem loads
 * it, as they would without Fledge.
 *
 * It asks the same of the typelibs the app's gems load from the
 * distribution, which fledge.cfg also lists: the files of GObject
 * introspection data that a gem over libgirepository, as each of
 * ruby-gnome's is, opens by namespace and version while the app runs.
 * No compiled file names them, and Debian and Ubuntu package them apart
 * from the libraries they describe (gir1.2-gtk-4.0 beside libgtk-4-1), so
 * a computer can have GTK and not its typelib, and the gem then fails
 * with Ruby's GObjectIntrospection::RepositoryError. The child loads
 * libgirepository-1.0, the one ruby-gnome links, and requires each as the
 * gem will, through g_irepository_require, which searches GI_TYPELIB_PATH
 * and the library's own folder and requires each typelib's own
 * dependencies too (girepository.c, init_globals and
 * load_dependencies_recurse, at gobject-introspection c6c7e781).
 */

#include "launcher.h"

#include <dlfcn.h>
#include <errno.h>
#include <limits.h>
#include <stdint.h>
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
 * In the child: writes name, a newline, and reason to out, and exits with
 * status.
 */
static void say(int out, const char *name, size_t length, const char *reason, int status) __attribute__((noreturn));

static void
say(int out, const char *name, size_t length, const char *reason, int status)
{
    if (write(out, name, length) < 0 || write(out, "\n", 1) < 0 || write(out, reason, strlen(reason)) < 0)
        _exit(status);
    _exit(status);
}

/*
 * Copies the word of names that starts at start, up to a space or the
 * end, into name, which holds NAME_MAX + 1 bytes, and returns where the
 * next word starts.
 */
static const char *
next_word(const char *start, char *name, size_t *length)
{
    const char *space = strchr(start, ' ');

    *length = space != NULL ? (size_t)(space - start) : strlen(start);
    if (*length > NAME_MAX) *length = NAME_MAX;
    memcpy(name, start, *length);
    name[*length] = '\0';
    return space != NULL ? space + 1 : start + strlen(start);
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
        size_t length;
        start = next_word(start, name, &length);
        if (dlopen(name, RTLD_LAZY | RTLD_LOCAL) == NULL) {
            const char *reason = dlerror();
            say(out, name, length, reason != NULL ? reason : "it could not be loaded", 1);
        }
    }
    _exit(0);
}

/*
 * The library through which ruby-gnome's gems load typelibs: its
 * gobject-introspection gem links libgirepository-1.0, not GLib 2.80's
 * libgirepository-2.0, whose gi_repository_require this does not call.
 */
#define GIREPOSITORY "libgirepository-1.0.so.1"

/*
 * The launcher includes no header of GLib's or GObject introspection's,
 * and links neither: it declares the two parts of their interfaces it
 * uses. This is GError, whose fields GLib's reference documentation
 * gives (GLib, "GError" struct: domain, a GQuark, which is a guint32;
 * code, a gint; message, a gchar pointer).
 */
struct gerror {
    uint32_t domain;
    int code;
    char *message;
};

/*
 * And this is g_irepository_require, whose parameters GObject
 * Introspection's reference documentation for libgirepository-1.0 gives
 * (GIRepository, g_irepository_require: the repository, or NULL for the
 * default one; the namespace; the version, or NULL for the latest; the
 * GIRepositoryLoadFlags; a GError out-parameter), returning the
 * GITypelib, or NULL on failure.
 */
typedef void *(*require_function)(void *repository, const char *namespace_, const char *version, int flags,
                                  struct gerror **error);

/*
 * In the child: loads GIREPOSITORY and requires each typelib names lists,
 * NAMESPACE-VERSION, from the default repository. At the first that
 * fails it writes the typelib's name, a newline, and libgirepository's
 * reason to out, and exits 1; when the library itself does not load it
 * writes the library's name and dlerror's reason, and exits 2; it exits
 * 0 when every one loads.
 */
static void require_each(const char *names, int out) __attribute__((noreturn));

static void
require_each(const char *names, int out)
{
    char name[NAME_MAX + 1];
    const char *start = names;
    void *library = dlopen(GIREPOSITORY, RTLD_LAZY | RTLD_LOCAL);
    void *symbol = library != NULL ? dlsym(library, "g_irepository_require") : NULL;
    require_function require;

    if (symbol == NULL) {
        const char *reason = dlerror();
        say(out, GIREPOSITORY, strlen(GIREPOSITORY), reason != NULL ? reason : "it could not be loaded", 2);
    }
    memcpy(&require, &symbol, sizeof require);
    while (*start != '\0') {
        size_t length;
        struct gerror *error = NULL;
        start = next_word(start, name, &length);
        char *dash = strrchr(name, '-');
        if (dash == NULL) say(out, name, length, "it names no version", 1);
        *dash = '\0';
        if (require(NULL, name, dash + 1, 0, &error) == NULL) {
            *dash = '-';
            say(out, name, length, error != NULL && error->message != NULL ? error->message : "it could not be loaded",
                1);
        }
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

/*
 * Runs check over names in a child, and reads what it says. Returns 0
 * when the child exits 0, or cannot be started, or says nothing; else
 * the child's exit status, or 1 when a signal ended it, with the first
 * line it said in first and the second in reason, each NUL-terminated
 * within size bytes.
 */
static int
ask_child(void (*check)(const char *, int), const char *names, char *first, char *reason, size_t size)
{
    int ends[2];
    char said[PATH_MAX * 2];
    size_t length = 0;
    int status = 0;

    /* A computer that cannot start the check is not refused: the app's
     * gems load what they need as they would have. */
    if (pipe(ends) != 0) return 0;
    pid_t child = fork();
    if (child < 0) {
        close(ends[0]);
        close(ends[1]);
        return 0;
    }
    if (child == 0) {
        close(ends[0]);
        check(names, ends[1]);
        _exit(0);
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

    copy_line(copy_line(said, first, size), reason, size);
    return WIFEXITED(status) ? WEXITSTATUS(status) : 1;
}

int
fledge_find_system_libraries(const char *names, char *library, char *reason, size_t size)
{
    return ask_child(load_each, names, library, reason, size) == 0 ? 0 : -1;
}

int
fledge_find_system_typelibs(const char *names, char *typelib, char *reason, size_t size)
{
    switch (ask_child(require_each, names, typelib, reason, size)) {
    case 0:
        return 0;
    case 2:
        return -2;
    default:
        return -1;
    }
}
