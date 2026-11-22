/*
 * SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
 * SPDX-License-Identifier: MIT
 */
#include <stdio.h>
#include "greet.h"

/* libgreet: a greeting that libpunct finishes. */
const char *
greet_hello(void)
{
    static char line[64];
    snprintf(line, sizeof line, "hello from libgreet%s", punct_mark());
    return line;
}
