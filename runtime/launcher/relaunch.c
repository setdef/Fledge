/*
 * SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
 * SPDX-License-Identifier: MIT
 */

/*
 * Hands an app's own program, run through the runtime's bin/ruby, back
 * to the app's launcher, on macOS and Linux (ADR 089;
 * doc/contributors/design/launcher.md, "bin/ruby and restarts").
 *
 * A Ruby program restarts itself with exec RbConfig.ruby, $0, *ARGV, as
 * Puma's hot restart does. In a built app RbConfig.ruby is bin/ruby, and
 * $0 is the program fledge.cfg names, ROOT/app/ENTRY. Ruby's own main.c
 * would run it as plain Ruby: with the person's RUBYOPT, RUBYLIB, and
 * GEM_HOME, which the launcher put back before the app ran, and without
 * Bundler set up as the launcher sets it up. So bin/ruby asks one
 * question first: is the script it was given, as its first argument,
 * the program a launcher of this app runs? If so, it runs that launcher
 * in its place, with execv, and the same arguments after the script.
 * The launcher then hides the person's Ruby settings from Ruby's boot,
 * sets up the app's gems, and puts the settings back, as it did the
 * first time, in the same process: execv keeps the PID, and on macOS,
 * the launcher being the bundle's own program, the app's bundle.
 *
 * A launcher of this app is a regular, executable file, not a link, in a
 * folder whose fledge.cfg is this runtime's: the runtime's own folder,
 * or, in a macOS .app, Contents/MacOS, which links fledge.cfg from
 * Contents/Resources (Fledge::MacBundle). Its section of fledge.cfg, the one with its own
 * file name (ADR 024), or the whole file when it has no sections, must
 * name the script as its entry. Files are compared as the operating
 * system sees them, by device and inode, so a relative path, a symlink,
 * or the link through Contents/MacOS/app all name the same entry.
 *
 * Anything else stays Ruby's: a first argument that is an option, as in
 * ruby --yjit ROOT/app/main.rb or the -x a gem's executable is run with;
 * a script that is not an entry; a runtime with no fledge.cfg, or one
 * this cannot read. In an app without sections, the first executable
 * file in the folder is its launcher; fledge build puts no other there.
 * A launcher found but not started is a damaged app: bin/ruby says so
 * and exits with EX_SOFTWARE, as the launcher would, rather than run the
 * app as plain Ruby.
 */

#include "launcher.h"

#include <dirent.h>
#include <errno.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

/* fledge.cfg is at most this long, as unix.c reads it. */
#define CONFIG_SIZE 65536

static int
same_file(const struct stat *one, const struct stat *other)
{
    return one->st_dev == other->st_dev && one->st_ino == other->st_ino;
}

/* Writes "first/second" into out, which holds PATH_MAX bytes. Returns 0,
 * or -1 when the path is too long. */
static int
join(char *out, const char *first, const char *second)
{
    int length = snprintf(out, PATH_MAX, "%s/%s", first, second);

    return length < 0 || length >= PATH_MAX ? -1 : 0;
}

/* Reads the file at path into text, of CONFIG_SIZE bytes, as one
 * NUL-terminated string. Returns 0, or -1. */
static int
read_config(const char *path, char *text)
{
    FILE *file = fopen(path, "rb");

    if (file == NULL) return -1;
    size_t length = fread(text, 1, CONFIG_SIZE - 1, file);
    int failed = ferror(file);
    fclose(file);
    if (failed || length == CONFIG_SIZE - 1 || memchr(text, '\0', length) != NULL) return -1;
    text[length] = '\0';
    return 0;
}

/* Whether the program named name runs script: whether its part of the
 * fledge.cfg text config names an entry in prefix/app that is script. */
static int
runs_script(const char *prefix, const char *name, const char *config, const struct stat *script)
{
    static char text[CONFIG_SIZE];
    char app[PATH_MAX];
    char entry_path[PATH_MAX];
    struct fledge_config program;
    const char *problem = NULL;
    struct stat entry;

    memcpy(text, config, strlen(config) + 1);
    if (fledge_parse_config(text, name, fledge_same_ascii_name, &program, &problem) != 0) return 0;
    if (join(app, prefix, "app") != 0 || join(entry_path, app, program.entry) != 0) return 0;
    return stat(entry_path, &entry) == 0 && same_file(&entry, script);
}

/* Finds, in folder, the launcher that runs script, and writes its path
 * into out, which holds PATH_MAX bytes. Returns 1 when it finds one. */
static int
find_launcher(const char *folder, const char *prefix, const char *config, const struct stat *config_file,
              const struct stat *script, char *out)
{
    char path[PATH_MAX];
    struct stat status;
    int found = 0;

    if (join(path, folder, FLEDGE_CONFIG) != 0 || stat(path, &status) != 0 || !same_file(&status, config_file)) {
        return 0;
    }

    DIR *entries = opendir(folder);
    if (entries == NULL) return 0;
    for (struct dirent *item = readdir(entries); item != NULL && !found; item = readdir(entries)) {
        if (item->d_name[0] == '.' || join(out, folder, item->d_name) != 0) continue;
        if (lstat(out, &status) != 0 || !S_ISREG(status.st_mode) || access(out, X_OK) != 0) continue;
        found = runs_script(prefix, item->d_name, config, script);
    }
    closedir(entries);
    return found;
}

void
fledge_relaunch(int argc, char **argv)
{
    static char config[CONFIG_SIZE];
    char prefix[PATH_MAX];
    char path[PATH_MAX];
    char bundle_programs[PATH_MAX];
    char launcher[PATH_MAX];
    struct stat script;
    struct stat config_file;

    if (argc < 2 || argv[1][0] == '-' || argv[1][0] == '\0') return;
    if (stat(argv[1], &script) != 0 || !S_ISREG(script.st_mode)) return;

    /* bin/ruby is PREFIX/bin/ruby. */
    if (fledge_executable_path(prefix, sizeof prefix) != 0) return;
    for (int level = 0; level < 2; level++) {
        char *slash = strrchr(prefix, '/');
        if (slash == NULL || slash == prefix) return;
        *slash = '\0';
    }
    if (join(path, prefix, FLEDGE_CONFIG) != 0 || stat(path, &config_file) != 0 || read_config(path, config) != 0) {
        return;
    }

    /* In a .app, PREFIX is Contents/Resources, and the launchers are in
     * Contents/MacOS, named by its real path, as dyld will report it. */
    const char *folders[] = {prefix, bundle_programs};
    size_t count = 1;
    if (join(path, prefix, "../MacOS") == 0 && realpath(path, bundle_programs) != NULL) count = 2;
    for (size_t index = 0; index < count; index++) {
        if (!find_launcher(folders[index], prefix, config, &config_file, &script, launcher)) continue;

        char **arguments = calloc((size_t)argc, sizeof *arguments);
        if (arguments == NULL) return;
        arguments[0] = launcher;
        for (int argument = 2; argument < argc; argument++) arguments[argument - 1] = argv[argument];
        execv(launcher, arguments);
        fprintf(stderr, "ruby: could not run %s: %s\n", launcher, strerror(errno));
        exit(FLEDGE_EXIT_SOFTWARE);
    }
}
