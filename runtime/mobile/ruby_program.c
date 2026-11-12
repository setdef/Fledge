/*
 * SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
 * SPDX-License-Identifier: MIT
 */

/*
 * The runtime's ruby program on Android, libfledgerubyexe.so in each
 * ABI's folder of the AAR, which an app's package installer extracts
 * beside libfledgeruby.so, and to which ROOT/bin/ruby, RbConfig.ruby,
 * links (ADR 069). It is linked against libfledgeruby.so, which it finds
 * beside itself through its run path, $ORIGIN, so it carries no second
 * copy of Ruby: its work is fledge_ruby_program_main's (android.c), and
 * Ruby's main.c is in fledge_ruby.c (fledge_ruby_main).
 */

#include "mobile.h"

int
main(int argc, char **argv)
{
    return fledge_ruby_program_main(argc, argv);
}
