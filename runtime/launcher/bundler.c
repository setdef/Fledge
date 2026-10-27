/*
 * SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */

/*
 * The environment an app with a Gemfile runs in, on every operating
 * system (ADR 005, section 5).
 *
 * Under bundle exec, a program's ENV is the person's, with Bundler's
 * own settings over it: BUNDLE_GEMFILE, GEM_HOME, PATH with the bundle's
 * bin folder first, RUBYOPT with -r.../bundler/setup before the
 * person's own RUBYOPT, and BUNDLER_ORIG_* recording what each was
 * before (bundler/shared_helpers.rb, set_bundle_environment, and
 * bundler/environment_preserver.rb, at Bundler 4.0.20). And
 * Bundler.original_env, which Bundler.with_original_env and
 * with_unbundled_env start from, is the person's environment, so a
 * Bundler app that starts a person's own tools, such as bundle exec
 * rspec in the person's project, starts them as the person would.
 *
 * The launcher has Bundler set up the app's gems while the person's
 * Ruby settings are still set aside, so they cannot change which gems
 * load (unix.c and windows.c, setup_bundler). Then it hands Ruby what it
 * set aside, and the code below, run once, rebuilds the environment as
 * bundle exec would have built it from the person's: it records the
 * person's environment as the one Bundler started from, lets Bundler's
 * own EnvironmentPreserver and set_bundle_environment compose Bundler's
 * settings over the person's, and keeps the values that name the app's
 * own bundle (its Gemfile, its lockfile, and the runtime's gem folder as
 * GEM_HOME) as the protected setup found them. RubyGems' paths were
 * fixed before (pin_rubygems), and Bundler's settings were read then, so
 * nothing here changes which gems the app loads.
 *
 * The variables travel as hexadecimal inside the code itself, so the
 * launcher needs no Ruby function but rb_eval_string_protect, and the
 * code leaves no global, constant, or loaded feature behind.
 */

#include "launcher.h"

#include <stdint.h>
#include <stdlib.h>
#include <string.h>

static const char code_before_variables[] = "set_aside = [\"";
static const char code_after_variables[] =
    "\"].pack(\"H*\").split(\"\\0\").to_h do |entry|\n"
    "  entry.force_encoding(Gem.win_platform? ? Encoding::UTF_8 : Encoding.find(\"locale\")).split(\"=\", 2)\n"
    "end\n"
    "bundled = ENV.to_hash\n"
    "booted = Bundler::ORIGINAL_ENV.dup\n"
    "preserver = Bundler::EnvironmentPreserver.new(booted.merge(set_aside), "
    "Bundler::EnvironmentPreserver::BUNDLER_KEYS)\n"
    "Bundler::ORIGINAL_ENV.replace(preserver.restore)\n"
    "ENV.replace(preserver.backup)\n"
    "ENV.update(bundled.slice(\"BUNDLE_GEMFILE\", \"BUNDLE_LOCKFILE\"))\n"
    "Bundler::SharedHelpers.set_bundle_environment\n"
    "ENV.update(bundled.slice(\"GEM_HOME\", \"GEM_PATH\"))\n"
    "Bundler.load.send(:setup_manpath) unless bundled[\"MANPATH\"] == booted[\"MANPATH\"]\n"
    "nil\n";

char *
fledge_bundle_environment_code(const char *variables, size_t length)
{
    static const char digits[] = "0123456789abcdef";
    size_t fixed = sizeof code_before_variables - 1 + sizeof code_after_variables;

    if (length > (SIZE_MAX - fixed) / 2) return NULL;

    char *code = malloc(fixed + 2 * length);
    if (code == NULL) return NULL;

    char *next = code;
    memcpy(next, code_before_variables, sizeof code_before_variables - 1);
    next += sizeof code_before_variables - 1;
    for (size_t index = 0; index < length; index++) {
        unsigned char byte = (unsigned char)variables[index];
        *next++ = digits[byte >> 4];
        *next++ = digits[byte & 0xF];
    }
    memcpy(next, code_after_variables, sizeof code_after_variables);
    return code;
}
