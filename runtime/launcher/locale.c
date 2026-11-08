/*
 * SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
 * SPDX-License-Identifier: MIT
 */

/*
 * The locale an app's Ruby starts in, on macOS and Linux, and in the
 * mobile runtimes (runtime/mobile/fledge_ruby.c), whose apps the system
 * starts with no LANG at all. The runtime's bin/ruby (ruby_main.c) calls
 * it too, so a Ruby the app starts is in the app's locale (ADR 026).
 */

#include "launcher.h"

#include <langinfo.h>
#include <locale.h>
#include <stddef.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>

static int
codeset_is_utf8(void)
{
    const char *codeset = nl_langinfo(CODESET);

    return codeset != NULL && (strcasecmp(codeset, "UTF-8") == 0 || strcasecmp(codeset, "utf8") == 0);
}

/* Whether the environment gives the variable +name+ a value. */
static int
names_locale(const char *name)
{
    const char *value = getenv(name);

    return value != NULL && *value != '\0';
}

/*
 * Sets LC_CTYPE from the environment, as Ruby's main.c does, so the
 * person's locale decides Encoding.default_external. When there is no
 * locale at all (LANG unset, as for an app started by a desktop, a
 * service manager, env -i, or a phone), that locale is C, whose
 * character set is ASCII, and a folder name such as "Ünïcödé" in the
 * app's path makes Ruby fail with "invalid byte sequence in US-ASCII" as
 * it builds its load path. As Python does (PEP 538), a C or POSIX locale
 * is then replaced by the first UTF-8 locale the system has.
 *
 * A character set the person chose stays theirs, C included. PEP 538
 * never coerces when LC_ALL is set (CPython v3.13.0,
 * Python/pylifecycle.c, lines 189 to 194 and 293 to 294). Fledge also
 * leaves an explicit LC_CTYPE alone, where PEP 538 coerces it: LC_CTYPE
 * is the category Encoding.default_external comes from, and ruby
 * honours it (ADR 026, section 1). So only a C locale that comes from
 * LANG, or from no variable at all, is replaced.
 */
void
fledge_coerce_locale(void)
{
    static const char *const utf8_locales[] = {"C.UTF-8", "C.utf8", "UTF-8", "en_US.UTF-8", NULL};
    const char *chosen = setlocale(LC_CTYPE, "");

    if (names_locale("LC_ALL") || names_locale("LC_CTYPE")) return;
    if (chosen != NULL && strcmp(chosen, "C") != 0 && strcmp(chosen, "POSIX") != 0) return;
    for (const char *const *locale = utf8_locales; *locale != NULL; locale++) {
        if (setlocale(LC_CTYPE, *locale) != NULL && codeset_is_utf8()) return;
    }
    setlocale(LC_CTYPE, "C");
}
