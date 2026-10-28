/*
 * SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */

/*
 * The locale an app's Ruby starts in, on macOS and Linux, and in the
 * mobile runtimes (runtime/mobile/fledge_ruby.c), whose apps the system
 * starts with no LANG at all.
 */

#include "launcher.h"

#include <langinfo.h>
#include <locale.h>
#include <stddef.h>
#include <string.h>
#include <strings.h>

static int
codeset_is_utf8(void)
{
    const char *codeset = nl_langinfo(CODESET);

    return codeset != NULL && (strcasecmp(codeset, "UTF-8") == 0 || strcasecmp(codeset, "utf8") == 0);
}

/*
 * Sets LC_CTYPE from the environment, as Ruby's main.c does, so the
 * person's locale decides Encoding.default_external. When there is no
 * locale at all (LANG unset, as for an app started by a desktop, a
 * service manager, env -i, or a phone), that locale is C, whose
 * character set is ASCII, and a folder name such as "Ünïcödé" in the
 * app's path makes Ruby fail with "invalid byte sequence in US-ASCII" as
 * it builds its load path. As Python does (PEP 538), a C or POSIX locale
 * is replaced by the first UTF-8 locale the system has; a locale the
 * person chose is left alone.
 */
void
fledge_coerce_locale(void)
{
    static const char *const utf8_locales[] = {"C.UTF-8", "C.utf8", "UTF-8", "en_US.UTF-8", NULL};
    const char *chosen = setlocale(LC_CTYPE, "");

    if (chosen != NULL && strcmp(chosen, "C") != 0 && strcmp(chosen, "POSIX") != 0) return;
    for (const char *const *locale = utf8_locales; *locale != NULL; locale++) {
        if (setlocale(LC_CTYPE, *locale) != NULL && codeset_is_utf8()) return;
    }
    setlocale(LC_CTYPE, "C");
}
