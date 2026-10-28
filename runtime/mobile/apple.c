/*
 * SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */

/*
 * The system log on iOS and iPadOS: os_log, which Xcode's console,
 * Console.app, and log stream show, with the app's tag as the log's
 * subsystem and "ruby" as its category. Lines are marked public, since
 * an app's own output is not private data the system should hide.
 */

#include "mobile.h"

#include <os/log.h>

static os_log_t ruby_log;

int
fledge_log_open(const char *tag)
{
    ruby_log = os_log_create(tag, "ruby");
    return 0;
}

void
fledge_log_write(int error, const char *text, size_t length)
{
    os_log_with_type(ruby_log, error ? OS_LOG_TYPE_ERROR : OS_LOG_TYPE_DEFAULT, "%{public}.*s", (int)length, text);
}
