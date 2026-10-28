/*
 * SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later
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
 *   identifier = com.example.MyCoolApp
 *
 * entry is the program to run and gemfile the project's Gemfile, which
 * the launcher has Bundler set up first; both are relative to the app's
 * app folder, with / between folders. identifier is the app's reverse-DNS
 * name, which the Windows launcher makes its AppUserModelID (ADR 008):
 * letters, digits, hyphens, and dots, at most FLEDGE_IDENTIFIER_MAX
 * characters. Blank lines and lines that begin
 * with # say nothing. fledge build and the launcher come from the same
 * Fledge, so a key this launcher does not know means the file is
 * damaged, and it is refused, as is a path that leaves the app folder
 * and an identifier with any other character.
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
fledge_parse_config(char *text, struct fledge_config *config, const char **problem)
{
    config->entry = NULL;
    config->gemfile = NULL;
    config->identifier = NULL;

    char *line = text;
    while (line != NULL) {
        char *newline = strchr(line, '\n');
        if (newline != NULL) *newline = '\0';

        char *content = trim(line);
        line = newline != NULL ? newline + 1 : NULL;
        if (*content == '\0' || *content == '#') continue;

        char *equals = strchr(content, '=');
        if (equals == NULL) {
            *problem = "has a line that is not key = value";
            return -1;
        }
        *equals = '\0';

        const char *key = trim(content);
        const char *value = trim(equals + 1);
        const char **slot;
        int is_path = 1;
        if (strcmp(key, "entry") == 0) {
            slot = &config->entry;
        } else if (strcmp(key, "gemfile") == 0) {
            slot = &config->gemfile;
        } else if (strcmp(key, "identifier") == 0) {
            slot = &config->identifier;
            is_path = 0;
        } else {
            *problem = "has a key this app's program does not know";
            return -1;
        }
        if (*slot != NULL) {
            *problem = "names the same key twice";
            return -1;
        }
        if (is_path && !safe_path(value)) {
            *problem = "names a path outside the app folder";
            return -1;
        }
        if (!is_path && !safe_identifier(value)) {
            *problem = "has an identifier that is not reverse-DNS";
            return -1;
        }
        *slot = value;
    }

    if (config->entry == NULL) {
        *problem = "names no entry";
        return -1;
    }
    return 0;
}
