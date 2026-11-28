/*
 * SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
 * SPDX-License-Identifier: MIT
 */

/*
 * The gems' commands of an Android app's Ruby (mobile.h,
 * fledge_ruby_read_commands). Android lets an app run only the files its
 * package installer extracts, its native libraries, so each command,
 * ROOT/bin/NAME, is a link to the runtime's ruby program, which fledge
 * build lists in ROOT/fledge.links (fledge_link_libraries), and RubyGems'
 * wrapper for it, the script a desktop has at that path, is kept in
 * ROOT/libexec/commands (FLEDGE_COMMANDS). The runtime's Ruby asks
 * ruby_embed_source_path, wherever it reads a Ruby file
 * (RubySource.prism_compile_c and ruby_c_source), for a file to read in
 * that file's place, so ruby -S NAME, ruby ROOT/bin/NAME, load, and the
 * program run as NAME (fledge_ruby_program_main, android.c) all read
 * the wrapper, while $0, __FILE__, and every message name ROOT/bin/NAME,
 * as on a desktop. Every other path reads as it would without it.
 */

#include "mobile.h"

#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>

/* The runtime's edit to prism_compile.c (RubySource.prism_compile_c). */
extern int (*ruby_embed_source_path)(const char *, char *, size_t);

/* ROOT/bin, as Ruby's prefix spells it and resolved, and ROOT's FLEDGE_COMMANDS folder. */
static char command_bin[PATH_MAX];
static char command_bin_resolved[PATH_MAX];
static char command_folder[PATH_MAX];

/*
 * Writes into buffer, of size bytes, the wrapper Ruby reads in place
 * of path, and returns 1, when path names a file NAME in ROOT/bin whose
 * wrapper FLEDGE_COMMANDS holds; returns 0 otherwise, when Ruby reads
 * path itself. A name is looked up among the wrappers before the folder
 * is resolved, so that a file Ruby requires, whose name no command has,
 * costs one failed stat.
 */
static int
command_source(const char *path, char *buffer, size_t size)
{
    char folder[PATH_MAX];
    char resolved[PATH_MAX];
    struct stat status;
    const char *slash = strrchr(path, '/');
    const char *name = slash != NULL ? slash + 1 : path;
    size_t length = slash == NULL ? 0 : slash == path ? 1 : (size_t)(slash - path);

    if (name[0] == '\0' || name[0] == '.' || strcmp(name, "ruby") == 0 || length >= sizeof folder) return 0;
    if (snprintf(buffer, size, "%s/%s", command_folder, name) >= (int)size || stat(buffer, &status) != 0 ||
        !S_ISREG(status.st_mode)) {
        return 0;
    }
    if (length == 0) {
        folder[length++] = '.';
    } else {
        memcpy(folder, path, length);
    }
    folder[length] = '\0';
    if (strcmp(folder, command_bin) == 0) return 1;
    /* Resolved once it exists: fledge_ruby_link_program makes it after this is set up. */
    if (command_bin_resolved[0] == '\0' && realpath(command_bin, command_bin_resolved) == NULL) return 0;
    return realpath(folder, resolved) != NULL && strcmp(resolved, command_bin_resolved) == 0;
}

void
fledge_ruby_read_commands(const char *root)
{
    struct stat status;

    if (snprintf(command_bin, sizeof command_bin, "%s/bin", root) >= (int)sizeof command_bin ||
        snprintf(command_folder, sizeof command_folder, "%s" FLEDGE_COMMANDS, root) >= (int)sizeof command_folder ||
        stat(command_folder, &status) != 0 || !S_ISDIR(status.st_mode)) {
        return;
    }
    ruby_embed_source_path = command_source;
}
