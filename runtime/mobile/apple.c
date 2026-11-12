/*
 * SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
 * SPDX-License-Identifier: MIT
 */

/*
 * The system log on iOS and iPadOS: os_log, which Xcode's console,
 * Console.app, and log stream show, with the app's tag as the log's
 * subsystem and "ruby" as its category. Lines are marked public, since
 * an app's own output is not private data the system should hide.
 *
 * The unified log copies each entry to standard error as well when the
 * process's environment holds OS_ACTIVITY_DT_MODE, as Xcode's console
 * set it for the app it ran, and as a developer tool still may (Apple's
 * DTS, developer.apple.com/forums/thread/705868). macOS 27 and the iOS
 * 26 Simulator copy it whatever the variable's value, NO and an empty
 * one included, so what counts is that it is there
 * (doc/contributors/design/phone-runtimes.md, "Output to the system log").
 */

#include "mobile.h"

#include <os/log.h>
#include <stdlib.h>

static os_log_t ruby_log;

int
fledge_log_echoes(void)
{
    return getenv("OS_ACTIVITY_DT_MODE") != NULL;
}

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
