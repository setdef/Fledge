/*
 * SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
 * SPDX-License-Identifier: MIT
 */

/*
 * Reads fledge.cfg, the file fledge build writes beside the launcher to
 * say what the app runs (ADR 005), on every operating system.
 *
 * The launcher is the same program for every app, and on macOS it is
 * signed, so nothing about one app can be written into it. Instead, as
 * Python's interpreter reads the pyvenv.cfg beside it (PEP 405), the
 * launcher reads a small text file of "key = value" lines beside itself:
 *
 *   # Written by fledge build: what this app's program runs (ADR 005).
 *   entry = exe/my_cool_app
 *   gemfile = Gemfile
 *   bundler = 4.0.19
 *   identifier = com.example.MyCoolApp
 *
 * entry is the program to run and gemfile the project's Gemfile, which
 * the launcher has Bundler set up first; both are relative to the app's
 * app folder, with / between folders. bundler, beside gemfile, is the
 * version of the Bundler that sets it up when that is not the runtime's
 * own (ADR 063), whose gem fledge build installed: letters, digits, and
 * dots, as a gem's version is written. identifier is the app's reverse-DNS
 * name, which the Windows launcher makes its AppUserModelID (ADR 008):
 * letters, digits, hyphens, and dots, at most FLEDGE_IDENTIFIER_MAX
 * characters. system_libraries, on Linux, names the libraries the app's
 * gems load from the distribution, between spaces, which the launcher
 * looks for before Ruby starts (ADR 030): letters, digits, and . _ + -,
 * with no folder. Blank lines and lines that begin
 * with # say nothing. fledge build and the launcher come from the same
 * Fledge, so a key this launcher does not know means the file is
 * damaged, and it is refused, as is a path that leaves the app folder
 * and an identifier with any other character.
 *
 * An app of several programs (ADR 024) is several copies of the
 * launcher, each renamed to its program's name, sharing one fledge.cfg.
 * Its Gemfile stays at the top, and each program has a section, headed
 * by its name, as an INI file heads one:
 *
 *   # Written by fledge build: what this app's programs run (ADR 024).
 *   gemfile = Gemfile
 *
 *   [MyGame]
 *   entry = gui/main.rb
 *   identifier = com.example.MyGame
 *
 *   [my-game-cli]
 *   entry = bin/cli
 *
 * Each copy reads the section whose name is its own file's name. A
 * section holds only entry and identifier, and a file with sections
 * holds neither outside them. gemfile, bundler, and system_libraries are
 * the whole app's, so they stay outside the sections. A copy renamed by hand finds no section,
 * which is a missing input, as a missing entry is.
 */

#include "launcher.h"

#include <string.h>

/* Removes spaces and tabs from both ends of text, in place. */
static char *
trim(char *text)
{
    while (*text == ' ' || *text == '\t') text++;

    size_t length = strlen(text);
    while (length > 0 && (text[length - 1] == ' ' || text[length - 1] == '\t' || text[length - 1] == '\r')) {
        text[--length] = '\0';
    }
    return text;
}

/* Whether path stays inside the app folder: relative, with / between
 * names, and no empty, ".", or ".." name. */
static int
safe_path(const char *path)
{
    if (*path == '\0' || strchr(path, '\\') != NULL || strchr(path, ':') != NULL) return 0;

    const char *name = path;
    for (;;) {
        const char *slash = strchr(name, '/');
        size_t length = slash != NULL ? (size_t)(slash - name) : strlen(name);

        if (length == 0) return 0;
        if (length == 1 && name[0] == '.') return 0;
        if (length == 2 && name[0] == '.' && name[1] == '.') return 0;
        if (slash == NULL) return 1;
        name = slash + 1;
    }
}

/* Whether names is a list fledge build writes of system libraries: file
 * names of letters, digits, and . _ + -, between single spaces. */
static int
safe_libraries(const char *names)
{
    if (*names == '\0') return 0;
    for (const char *letter = names; *letter != '\0'; letter++) {
        int allowed = (*letter >= 'a' && *letter <= 'z') || (*letter >= 'A' && *letter <= 'Z') ||
                      (*letter >= '0' && *letter <= '9') || *letter == '.' || *letter == '_' || *letter == '+' ||
                      *letter == '-' || (*letter == ' ' && letter[1] != ' ' && letter[1] != '\0');
        if (!allowed) return 0;
    }
    return 1;
}

/* Whether version is one fledge build writes of a Bundler: 1 to 32
 * letters, digits, and dots, as Gem::Version writes one, so that it
 * can name a gem's folder and stand in the launcher's Ruby. */
static int
safe_version(const char *version)
{
    size_t length = strlen(version);

    if (length == 0 || length > 32) return 0;
    for (const char *letter = version; *letter != '\0'; letter++) {
        int allowed = (*letter >= 'a' && *letter <= 'z') || (*letter >= 'A' && *letter <= 'Z') ||
                      (*letter >= '0' && *letter <= '9') || *letter == '.';
        if (!allowed) return 0;
    }
    return 1;
}

/* Whether identifier is one fledge build writes: 1 to FLEDGE_IDENTIFIER_MAX
 * letters, digits, hyphens, and dots. */
static int
safe_identifier(const char *identifier)
{
    size_t length = strlen(identifier);

    if (length == 0 || length > FLEDGE_IDENTIFIER_MAX) return 0;
    for (const char *letter = identifier; *letter != '\0'; letter++) {
        int allowed = (*letter >= 'a' && *letter <= 'z') || (*letter >= 'A' && *letter <= 'Z') ||
                      (*letter >= '0' && *letter <= '9') || *letter == '-' || *letter == '.';
        if (!allowed) return 0;
    }
    return 1;
}

int
fledge_same_ascii_name(const char *one, const char *other)
{
    for (;; one++, other++) {
        char a = *one >= 'A' && *one <= 'Z' ? (char)(*one - 'A' + 'a') : *one;
        char b = *other >= 'A' && *other <= 'Z' ? (char)(*other - 'A' + 'a') : *other;
        if (a != b) return 0;
        if (a == '\0') return 1;
    }
}

int
fledge_parse_config(char *text, const char *program, fledge_same_name same_name, struct fledge_config *config,
                    const char **problem)
{
    /* Whether the file has sections, whether the last heading was this
     * program's, and whether any was. */
    int sectioned = 0;
    int mine = 0;
    int found = 0;

    config->entry = NULL;
    config->gemfile = NULL;
    config->bundler = NULL;
    config->identifier = NULL;
    config->system_libraries = NULL;

    char *line = text;
    while (line != NULL) {
        char *newline = strchr(line, '\n');
        if (newline != NULL) *newline = '\0';

        char *content = trim(line);
        line = newline != NULL ? newline + 1 : NULL;
        if (*content == '\0' || *content == '#') continue;

        if (*content == '[') {
            size_t length = strlen(content);
            if (length < 3 || content[length - 1] != ']') {
                *problem = "has a section heading that is not [NAME]";
                return -1;
            }
            if (!sectioned && (config->entry != NULL || config->identifier != NULL)) {
                *problem = "names an entry or identifier outside its programs' sections";
                return -1;
            }
            content[length - 1] = '\0';
            sectioned = 1;
            mine = program != NULL && same_name(content + 1, program);
            found = found || mine;
            continue;
        }

        char *equals = strchr(content, '=');
        if (equals == NULL) {
            *problem = "has a line that is not key = value";
            return -1;
        }
        *equals = '\0';

        const char *key = trim(content);
        const char *value = trim(equals + 1);
        const char **slot;
        enum { PATH, IDENTIFIER, LIBRARIES, VERSION } kind = PATH;
        if (strcmp(key, "entry") == 0) {
            slot = &config->entry;
        } else if (strcmp(key, "gemfile") == 0) {
            if (sectioned) {
                *problem = "names a gemfile inside a program's section";
                return -1;
            }
            slot = &config->gemfile;
        } else if (strcmp(key, "bundler") == 0) {
            if (sectioned) {
                *problem = "names bundler inside a program's section";
                return -1;
            }
            slot = &config->bundler;
            kind = VERSION;
        } else if (strcmp(key, "identifier") == 0) {
            slot = &config->identifier;
            kind = IDENTIFIER;
        } else if (strcmp(key, "system_libraries") == 0) {
            if (sectioned) {
                *problem = "names system_libraries inside a program's section";
                return -1;
            }
            slot = &config->system_libraries;
            kind = LIBRARIES;
        } else {
            *problem = "has a key this app's program does not know";
            return -1;
        }
        if (kind == PATH && !safe_path(value)) {
            *problem = "names a path outside the app folder";
            return -1;
        }
        if (kind == LIBRARIES && !safe_libraries(value)) {
            *problem = "names a system library that is not a file name";
            return -1;
        }
        if (kind == VERSION && !safe_version(value)) {
            *problem = "names a Bundler that is not a version";
            return -1;
        }
        if (kind == IDENTIFIER && !safe_identifier(value)) {
            *problem = "has an identifier that is not reverse-DNS";
            return -1;
        }
        if (sectioned && !mine) continue;
        if (*slot != NULL) {
            *problem = "names the same key twice";
            return -1;
        }
        *slot = value;
    }

    if (sectioned && !found) return FLEDGE_CONFIG_NO_PROGRAM;
    if (config->entry == NULL) {
        *problem = "names no entry";
        return -1;
    }
    return 0;
}
