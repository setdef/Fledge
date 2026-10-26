/*
 * SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */

/*
 * Which environment variables the launcher hides from Ruby's boot, on
 * every operating system. It removes them before Ruby starts and puts
 * them back, with their values, before the app's main.rb runs (unix.c
 * and windows.c, restore_environment; ADR 003).
 *
 * A person who runs an app never asked for Ruby, so nothing of a Ruby
 * they happen to have may change how the app starts (ADR 001, section
 * 1). Ruby, RubyGems, and Bundler read their settings from environment
 * variables, so the launcher hides every variable whose name starts
 * with one of these prefixes. Prefixes, not a list of names, so a
 * variable a later Ruby adds is removed too. Read at Ruby 4.0.9:
 *
 *   RUBY      ruby.c: RUBYOPT, RUBYLIB, RUBYPATH, RUBYSHELL,
 *             RUBY_YJIT_ENABLE, RUBY_ZJIT_ENABLE; gc.c, vm.c, thread.c:
 *             RUBY_GC_*, RUBY_THREAD_*, RUBY_FIBER_*, RUBY_MN_THREADS,
 *             RUBY_MAX_CPU, RUBY_CRASH_REPORT, RUBY_DEBUG,
 *             RUBY_FREE_AT_EXIT; RubyGems: RUBYGEMS_GEMDEPS. On Windows,
 *             RubyInstaller's runtime also reads RUBY_DLL_PATH, a list of
 *             folders to load DLLs from.
 *   GEM_      RubyGems: GEM_HOME, GEM_PATH, GEM_SPEC_CACHE, GEM_VENDOR,
 *             GEM_REQUIREMENT_<NAME>.
 *   GEMRC     RubyGems' configuration file.
 *   BUNDLE_   Bundler's settings: BUNDLE_GEMFILE, BUNDLE_PATH, ...
 *   BUNDLER_  Bundler: BUNDLER_VERSION, and BUNDLER_SETUP, a file that
 *             rubygems.rb requires as it loads (its last lines), which
 *             would run any code it names.
 *   RI_FORCE_PATH_FOR_DLL
 *             RubyInstaller's runtime: puts RUBY_DLL_PATH's folders on
 *             PATH. Only RubyInstaller reads it, and a Windows runtime
 *             replaces the file that would load RubyInstaller's runtime,
 *             but an app that loads that runtime itself still finds the
 *             variable gone.
 *
 * Variables outside these, such as SSL_CERT_FILE, HOME, and the XDG_
 * directories, describe the person's computer, not their Ruby, and stay.
 */

#include "launcher.h"

#include <string.h>

static const char *const scrubbed_prefixes[] = {
    "RUBY", "GEM_", "GEMRC", "BUNDLE_", "BUNDLER_", "RI_FORCE_PATH_FOR_DLL", NULL,
};

/* ASCII only: variable names are compared as Windows compares them,
 * whatever the C locale says about other letters. */
static char
ascii_upper(char letter)
{
    return (letter >= 'a' && letter <= 'z') ? (char)(letter - 'a' + 'A') : letter;
}

static int
starts_with(const char *name, const char *prefix, int ignore_case)
{
    for (; *prefix != '\0'; name++, prefix++) {
        char actual = ignore_case ? ascii_upper(*name) : *name;
        if (actual != *prefix) return 0;
    }
    return 1;
}

int
fledge_is_scrubbed(const char *name, int ignore_case)
{
    for (const char *const *prefix = scrubbed_prefixes; *prefix != NULL; prefix++) {
        if (starts_with(name, *prefix, ignore_case)) return 1;
    }
    return 0;
}
