/*
 * SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
 * SPDX-License-Identifier: MIT-0
 */

#include <ruby.h>
#include <stdint.h>

/* Rakesum.adler32(string): the Adler-32 checksum of the string's bytes. */
static VALUE
adler32(VALUE self, VALUE string)
{
    const unsigned char *bytes = (const unsigned char *)RSTRING_PTR(string);
    long length = RSTRING_LEN(string);
    uint32_t a = 1, b = 0;
    for (long i = 0; i < length; i++) {
        a = (a + bytes[i]) % 65521;
        b = (b + a) % 65521;
    }
    return UINT2NUM((b << 16) | a);
}

void
Init_adler_ext(void)
{
    rb_define_module_function(rb_define_module("Rakesum"), "adler32", adler32, 1);
}
