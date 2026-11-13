/*
 * SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
 * SPDX-License-Identifier: MIT
 */

/*
 * The links from where an Android app's Ruby looks for a file to the
 * native library the package installer extracted for it (mobile.h,
 * fledge_link_libraries). The installer extracts only lib/ABI/lib*.so
 * entries, into a folder whose name changes with each install, so a
 * library cannot sit at the path Ruby looks for it: a link there,
 * remade whenever the folder moves, as fledge_ruby_link_program makes
 * ROOT/bin/ruby, takes its place. ROOT/fledge.links, which fledge build
 * writes, lists them, a line each: the ABI, the library's file name, and
 * the path under ROOT, separated by tabs.
 */

#include "mobile.h"

#include <errno.h>
#include <limits.h>
#include <stdio.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

#define FLEDGE_LINKS "fledge.links"

/* Nonzero when the length bytes at name are a file's name: not empty, ".", or "..". */
static int
named(const char *name, size_t length)
{
    return length != 0 && !(length == 1 && name[0] == '.') && !(length == 2 && strncmp(name, "..", 2) == 0);
}

/* Nonzero when path stays below ROOT: relative, with no empty, ".", or ".." part. */
static int
inside(const char *path)
{
    if (path[0] == '/') return 0;
    for (const char *part = path;; part++) {
        size_t length = strcspn(part, "/");
        if (!named(part, length)) return 0;
        part += length;
        if (*part == '\0') return 1;
    }
}

/* Makes each folder above the file at path, below its first skip bytes, which exist. */
static int
make_parents(char *path, size_t skip)
{
    for (char *slash = strchr(path + skip, '/'); slash != NULL; slash = strchr(slash + 1, '/')) {
        *slash = '\0';
        int made = mkdir(path, 0755) == 0 || errno == EEXIST;
        *slash = '/';
        if (!made) return -1;
    }
    return 0;
}

/* Links root/path to folder/library, through a fresh link renamed into place; 0 when it is, -1 when not. */
static int
link_one(const char *root, const char *folder, const char *library, const char *path)
{
    char link[PATH_MAX];
    char fresh[PATH_MAX];
    char target[PATH_MAX];
    char current[PATH_MAX];
    struct stat status;

    if (!inside(path) || strchr(library, '/') != NULL || !named(library, strlen(library))) {
        fprintf(
            stderr,
            "fledge_ruby_run: %s names %s for %s, which is not a library in the app's native library folder and a path "
            "inside its Ruby\n",
            FLEDGE_LINKS, library, path);
        return -1;
    }
    if (snprintf(link, sizeof link, "%s/%s", root, path) >= (int)sizeof link ||
        snprintf(fresh, sizeof fresh, "%s.fledge-%d", link, (int)getpid()) >= (int)sizeof fresh ||
        snprintf(target, sizeof target, "%s/%s", folder, library) >= (int)sizeof target) {
        fprintf(stderr, "fledge_ruby_run: the path to %s is too long\n", path);
        return -1;
    }
    if (access(target, R_OK) != 0) {
        if (lstat(link, &status) == 0 && S_ISLNK(status.st_mode)) unlink(link);
        fprintf(
            stderr,
            "fledge_ruby_run: %s is not in the app's native library folder, %s, so %s cannot load: the package must "
            "be installed with its native libraries extracted\n",
            library, folder, path);
        return -1;
    }
    ssize_t length = readlink(link, current, sizeof current - 1);
    if (length >= 0) {
        current[length] = '\0';
        if (strcmp(current, target) == 0) return 0;
    }
    if (make_parents(link, strlen(root) + 1) != 0 || symlink(target, fresh) != 0 || rename(fresh, link) != 0) {
        fprintf(stderr, "fledge_ruby_run: could not link %s to %s: %s\n", link, target, strerror(errno));
        unlink(fresh);
        return -1;
    }
    return 0;
}

int
fledge_link_libraries(const char *root, const char *folder, const char *abi)
{
    char list[PATH_MAX];
    char line[3 * PATH_MAX];
    int failures = 0;

    if (snprintf(list, sizeof list, "%s/" FLEDGE_LINKS, root) >= (int)sizeof list) return 1;
    FILE *file = fopen(list, "r");
    if (file == NULL) return 0;
    while (fgets(line, sizeof line, file) != NULL) {
        line[strcspn(line, "\r\n")] = '\0';
        char *library = strchr(line, '\t');
        char *path = library != NULL ? strchr(library + 1, '\t') : NULL;
        if (path == NULL) {
            if (line[0] != '\0') failures++;
            continue;
        }
        *library++ = '\0';
        *path++ = '\0';
        if (strcmp(line, abi) == 0 && link_one(root, folder, library, path) != 0) failures++;
    }
    fclose(file);
    return failures;
}
